#!/usr/bin/env perl

use Mojolicious::Lite -signatures;
use Mojo::SQLite;
use Mojo::Pg;
use Mojo::JWT;
use Time::Piece;
use Date::Parse;

use lib '.';
use Password::Complexity;

my $config = plugin 'JSONConfig';
my $ua     = Mojo::UserAgent->new;
app->secrets( [ $config->{secret} ] );

# db connection
helper db_conn => sub {

    # config var 'test' will be defined if we're running unit tests,
    # otherwise see what type of DB we defined in the ENV VARs
    if ( !defined( $config->{test} ) && $config->{db_type} eq 'sqlite' ) {
        state $path      = app->home->child('data.db');
        state $db_handle = Mojo::SQLite->new( 'sqlite:' . $path );
        return $db_handle;
    } elsif ( !defined( $config->{test} ) && $config->{db_type} eq 'pg' ) {
        state $db_handle = Mojo::Pg->new( $config->{db_uri} );
        return $db_handle;
    } else {
        # for tests and future tests...
        state $db_handle = Mojo::SQLite->new(':temp:');
        return $db_handle;
    }
};

# do migrations (see bottom of file __DATA__ section)
app->db_conn->auto_migrate(1)->migrations->from_data;

# initialize Yancy, editor enabled (requiring admin field True)
plugin Yancy => {
    backend => $config->{db_type} eq 'pg'
    ? { Pg     => app->db_conn }
    : { Sqlite => app->db_conn },
    editor => {
        require_user => { is_admin => 1 },
    },
    read_schema => 0,
    schema      => {
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
                reset_password => {
                    type    => 'boolean',
                    default => 0,
                },
                last_reset => {
                    type    => [ 'string' ],
                    format  => 'date-time',
                    default => 'now',  # default to now for when new user accounts made
                }
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
        email    => "$config->{admin_user}",
        password => "$config->{admin_pass}",
        dod_id   => 123456789,
        is_admin => 1
    }
) unless app->yancy->get( 'users', "$config->{admin_user}" )->{email};

# proxy method - takes the request object ($c) and the URL ($uri)
#   makes sure the $uri has no backslash on it
sub proxy ( $c, $name, $uri ) {
    my $request = $c->req->clone;

    # remove the trailing slash if present
    $uri =~ s!/$!!;
    $request->url( Mojo::URL->new( $uri . $c->req->url ) );

    # see if we wanna use JWT for this proxy route
    if ($config->{routes}->{$name}->{enable_jwt}) {
        my $claims = {};
        for my $claim (keys %{$config->{routes}->{$name}->{jwt_claims}}) {
            $claims->{$claim} = eval $config->{routes}->{$name}->{jwt_claims}->{$claim};
        }
        my $jwt = Mojo::JWT->new(
            claims => $claims,
            secret => $config->{jwt_secret}
        );

        $request->headers->add( 'Authorization', 'Bearer ' . $jwt->encode );
    }

    # add any other static-text headers
    for my $header (keys %{$config->{routes}->{$name}->{other_headers}}) {
        $request->headers->add($header, $config->{routes}->{$name}->{other_headers}->{$header});
    }

    my $tx = $ua->start( Mojo::Transaction::HTTP->new( req => $request ) );

    if (defined($tx->res->code)) {
        $c->res($tx->res);
        $c->res->code($tx->res->code);
        $c->res->headers->location($tx->res->headers->location) if $tx->res->code;
        $c->res->headers($tx->res->headers->clone);
        $c->res->headers->content_type($tx->res->headers->content_type);

        my $body = $tx->res->body;

        # replace the api base url if to a relative one if requesting the environment.js file
        if ($c->req->url->path =~ m/environment\.js/) {
            $body =~ s!http://localhost:8080/puckboard-api/v1!/puckboard-api/v1!;
        }

        $c->res->body($body);
        $c->rendered;
    } else {
        # something went wrong and we didnt get a response from the proxy target
        $c->render("no_response");
    }
}

# password must be at least 8 characters
# must have letters, numbers, and at least one special character
sub do_password_change($c) {
    my $existing_password = $c->req->param('current-password');
    my $new_password = $c->req->param('new-password');
    my $retyped_password = $c->req->param('retyped-new-password');
    my $checker = Password::Complexity->new;

    my ($obj) = app->yancy->auth->plugins;
    if (!$existing_password || !$obj->_check_pass( $c, $c->yancy->auth->current_user->{email}, $existing_password )) {
        $c->flash({ return_to => $c->flash('return_to'), error_msg => 'Existing Password Incorrect'});
        $c->redirect_to('/yancy/auth/password/change',  );
    } elsif ($new_password eq $existing_password) {
        $c->flash({ return_to => $c->flash('return_to'), error_msg => 'New Password cannot equal the existing password' });
        $c->redirect_to('/yancy/auth/password/change',  );
    } elsif ($new_password ne $retyped_password) {
        $c->flash({ return_to => $c->flash('return_to'), error_msg => 'New Password does not equal Retyped New Password' });
        $c->redirect_to('/yancy/auth/password/change',  );
    } elsif (!$checker->check_complexity(new_password => $new_password, $config->{password_complexity} )) {
        $c->flash({ return_to => $c->flash('return_to'), error_msg => 'New Password does not meet complexity requirements... No whitespace, at least 8 characters, combination of letters/digits and special characters.' });
        $c->redirect_to('/yancy/auth/password/change', );
    } else {
        # guess we're good
        app->yancy->set("users", $c->yancy->auth->current_user->{email}, { "password" => $new_password, reset_password => 0, last_reset => 'now' } );
        $c->redirect_to($c->flash('return_to'));
    }
}

############################
#### BEGIN ROUTING DEFS ####
############################

# logout shortcut - always reachable
get '/logout' => sub ($c) {
    $c->session( expires => 1 );
    $c->redirect_to('yancy.auth.password.login');
};

# all routes from here-on require authentication
under '/' => sub ($c) {

    # if there's no current_user populated in the session cookie,
    # then we're not authenticated, so re-direct to the sign-in page...
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

    # if user record shows we need to reset-password, and we're not already at the password path,
    #  then re-direct to that page
    if ( $c->yancy->auth->current_user->{reset_password} && $c->req->url !~ /\/yancy\/auth\/password\/change/ ) {
        $c->flash( { return_to => $c->req->url } );
        $c->redirect_to('/yancy/auth/password/change');
        return undef;
    }

    # user authenticated OK or already-authenticated, check password expiry if we've defined
    #  that setting and its more than 0 days
    if ($c->yancy->auth->current_user->{reset_password} || ($config->{password_valid_days} && $config->{password_valid_days} > 0)
        && $c->req->url !~ /\/yancy\/auth\/password\/change/) {

        # because we said so
        if ($c->yancy->auth->current_user->{reset_password}) {
            $c->flash( { return_to => $c->req->url, expired => 0, mandated => 1 });
            $c->redirect_to('/yancy/auth/password/change');
        }

        # if last_reset is undef, then set it to now, not sure how'd that be though, should default to current date time
        if (!defined($c->yancy->auth->current_user->{last_reset})) {
            app->yancy->set("users", $c->yancy->auth->current_user->{email}, { last_reset => 'now' } );
        } else {
            # check days delta between NOW and last_reset
            my $last_reset = str2time($c->yancy->auth->current_user->{last_reset});
            my $reset_timestamp = Time::Piece->new($last_reset);
            my $now = Time::Piece->new();
            if (Time::Seconds->new($now - $reset_timestamp)->days >= $config->{password_valid_days}) {
                $c->flash( { return_to => $c->req->url, expired => 1, mandated => 0 });
                $c->redirect_to('/yancy/auth/password/change');
                return undef;
            }
        }
    }

    # continue on to the routes below
    return 1;
};

# show the password change form
get '/yancy/auth/password/change' => sub ($c) {
    # preserve the flash value
    $c->flash( { return_to => $c->flash('return_to') // '/' });
    # render the change_password form
    $c->render('yancy/auth/password/password_change');
};

# change the password for current user
post '/yancy/auth/password/change' => sub ($c) {    
    do_password_change($c);
};

# add our proxy routes requiring authentication
for my $route_spec (keys %{$config->{routes}}) {
    any $route_spec => sub ($c) {
        proxy( $c, $route_spec, $config->{routes}->{$route_spec}->{uri});
    };
}


# catch-all/default routes - just proxy to the front-end service
any '/**' => sub ($c) {
    proxy( $c, 'default_route', $config->{default_route}->{uri} );
};
any '*' => sub ($c) {
    proxy( $c, 'default_route', $config->{default_route}->{uri} );
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
-- 2 up
ALTER TABLE users ADD COLUMN reset_password BOOLEAN DEFAULT FALSE;
-- 3 up
ALTER TABLE users ADD COLUMN last_reset TIMESTAMP
