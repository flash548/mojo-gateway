#!/usr/bin/env perl
use Mojolicious::Lite -signatures;
use Mojo::SQLite;
use Mojo::JWT;
use constant SECRET => 'secret';

my $ua = Mojo::UserAgent->new;

helper sqlite => sub {
	state $path   = app->home->child('data.db');
	state $sqlite = Mojo::SQLite->new( 'sqlite:' . $path );
	return $sqlite;
};

app->sqlite->auto_migrate(1)->migrations->from_data;

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

app->yancy->plugin(
	'Auth' => {
		schema         => 'users',
		allow_register => 1,
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

get '/logout' => sub ($c) {
	$c->session( expires => 1 );
	$c->redirect_to('yancy.auth.password.login');
};

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

sub proxy ($c, $uri) {
    my $request = $c->req->clone;
    $request->url(Mojo::URL->new($uri . $c->req->url));
    my $tx = $ua->start(Mojo::Transaction::HTTP->new(req => $request));

    $c->res($tx->res);
    $c->res->code($tx->res->code);
    $c->res->headers->location($tx->res->headers->location) if $tx->res->code;
    $c->res->headers($tx->res->headers->clone);
    $c->res->body($tx->res->body);
    $c->res->fix_headers;
    $c->rendered;
}

any '/puckboard-api' => sub ($c) {
    proxy($c, $ENV{BACKEND_URI});
};

any '/puckboard-api/**' => sub ($c) {
    proxy($c, $ENV{BACKEND_URI});
};

any '*' => sub ($c) {
	proxy($c, $ENV{FRONTEND_URI});
};

# Remove a default header
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
    email VARCHAR UNIQUE,
    is_admin BOOLEAN DEFAULT FALSE,
    password VARCHAR
);

-- 2 up
ALTER TABLE users ADD COLUMN dod_id integer;
update users set dod_id = 123456789 where email = 'czell@revacomm.com';