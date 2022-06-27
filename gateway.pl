#!/usr/bin/env perl
use Mojolicious::Lite -signatures;
use Mojo::SQLite;
use Mojo::JWT;

use constant SECRET => 'secret';

my $ua = Mojo::UserAgent->new;

# sqlite3 db connection
helper sqlite => sub {
	state $path   = app->home->child('data.db');
	state $sqlite = Mojo::SQLite->new( 'sqlite:' . $path );
	return $sqlite;
};

# do migrations (see bottom of file __DATA__) section
app->sqlite->auto_migrate(1)->migrations->from_data;

# initialize Yancy using sqlite3, editor enabled (requiring admin field True)
plugin Yancy => {
	backend => { Sqlite => app->sqlite },
	editor  => {
		require_user => { is_admin => 1 },
	},
	schema => {
		users => {
			'x-id-field' => 'email',
			properties   => {
				email => {
					type   => [ 'string', 'null' ],
					format => 'email',
				},
				dod_id => {
					type   => [ 'integer', 'null' ],
					format => 'number',
				},
				password => {
					type   => [ 'string', 'null' ],
					format => 'password',
				},
				is_admin => {
					type    => 'boolean',
					default => 0,
				},
			},
		},
	},
};

# load the Yancy authN plugin, uses the 'users' table and email/password
# as the username/password fields.  New user registration disabled.
app->yancy->plugin(
	'Auth' => {
		schema         => 'users',
		allow_register => 0,
		plugins        => [
			[
				Password => {
					username_field  => 'email',
					password_field  => 'password',
					password_digest => {
						type => 'SHA-1',
					},
				}
			],
		]
	}
);

# create the admin user if it doesn't exist
app->yancy->create(
	users => {
		email    => 'admin@revacomm.com',
		password => "$ENV{ADMIN_PASS}",
		dod_id   => 123456789,
		is_admin => 1
	}
) unless app->yancy->get( 'users', 'admin@revacomm.com' )->{email};

# proxy method - takes the request object ($c) and the URL ($uri)
#   makes sure the $uri has no backslash on it
sub proxy ( $c, $uri ) {
	my $request = $c->req->clone;

    # remove the trailing slash if present
    $uri =~ s!/$!!;  
	$request->url( Mojo::URL->new( $uri . $c->req->url ) );

	my $jwt = Mojo::JWT->new(
		claims => {
			email           => $c->yancy->auth->current_user->{email},
			usercertificate => "Tron.Developer."
				. $c->yancy->auth->current_user->{dod_id}
		},
		secret => 'secret'
	);

	$request->headers->add( 'Authorization', 'Bearer ' . $jwt->encode );
	my $tx = $ua->start( Mojo::Transaction::HTTP->new( req => $request ) );

	$c->res( $tx->res );
	$c->res->code( $tx->res->code );
	$c->res->headers->location( $tx->res->headers->location ) if $tx->res->code;
	$c->res->headers( $tx->res->headers->clone );
    $c->res->headers->content_type( $tx->res->headers->content_type );
	$c->res->body( $tx->res->body );
	$c->rendered;
}

# logout shortcut
get '/logout' => sub ($c) {
	$c->session( expires => 1 );
	$c->redirect_to('yancy.auth.password.login');
};

# all routes from here on require authentication
under '/' => sub ($c) {
	unless ( $c->yancy->auth->current_user ) {

		# set return_to value to go back to initially requested url
		# dont allow redirect back to itself - default to /
		if ( $c->req->url =~ m/auth\/password/ || !defined( $c->req->url ) ) {
			$c->req->url = '/';
		}
		$c->flash( { return_to => $c->req->url } );
		$c->redirect_to('yancy.auth.password.login');
		return undef;
	}
	return 1;
};

any '/' => sub ($c) {
    proxy( $c, $ENV{FRONTEND_URI} );
};

any '/puckboard-api' => sub ($c) {
	proxy( $c, $ENV{BACKEND_URI} );
};

any '/puckboard-api/**' => sub ($c) {
	proxy( $c, $ENV{BACKEND_URI} );
};

any '/**' => sub ($c) {
	proxy( $c, $ENV{FRONTEND_URI} );
};

any '*' => sub ($c) {
	proxy( $c, $ENV{FRONTEND_URI} );
};

# Remove the default 'Server' header
app->hook(
	after_dispatch => sub ($c) {
		$c->res->headers->remove('Server');
	}
);

app->start;

__DATA__
@@ migrations
-- 1 up
CREATE TABLE users (
    email VARCHAR UNIQUE PRIMARY KEY,
    dod_id INTEGER,
    is_admin BOOLEAN DEFAULT FALSE,
    password VARCHAR
);

