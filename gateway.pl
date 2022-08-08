#!/usr/bin/env perl

use Mojolicious::Lite -signatures;
use Mojo::SQLite;
use Mojo::Pg;
use Mojo::JWT;
use Time::Piece;
use Crypt::Bcrypt qw/bcrypt bcrypt_check/;
use Data::Entropy::Algorithms qw(rand_bits);
use lib qw(./lib);
use Password::Complexity;

my $config = plugin 'JSONConfig';
my $ua     = Mojo::UserAgent->new;
app->secrets( [ $config->{secret} ] );

# db connection
helper db_conn => sub {

    # config var 'test' will be defined if we're running unit tests,
    # otherwise see what type of DB we defined in the ENV VARs
    if ( !$ENV{test} && $config->{db_type} eq 'sqlite' ) {
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

# create the admin user if it doesn't exist
app->db_conn->db->insert(
    users => {
        email    => "$config->{admin_user}",
        password => encode_password($config->{admin_pass}),
        dod_id   => 123456789,
        is_admin => 1
    }
) unless defined(app->db_conn->db->select( 'users', undef, { email => $config->{admin_user}} )->hash);

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

# compares the database-stored hash to the hashed version of $password
# returns 1 if they match (aka user gave the correct password)
sub check_pass($db_password, $password) {
    return bcrypt_check($password, $db_password);
}

sub do_login($c) {
    my $username = $c->req->param('username');
    my $password = $c->req->param('password');

    my $record = get_user($username);
    if ($record && check_pass($record->{password}, $password)) {
        delete $record->{password};

        # fix an undef 'last_reset' to now
        if ($record->{last_reset} == undef) {
            app->db_conn->db->update("users", { last_reset => get_gmstamp() }, { email => $username });
            $record = get_user($username);
            delete $record->{password};
        }
            
        # update person's last login time, set the session to the user's record
        # and return them to where they were trying to go to (or default to /)
        app->db_conn->db->update("users", { last_login => get_gmstamp() }, { email => $username });
        $c->session->{user} = $record;
        $c->redirect_to($c->flash('return_to') // '/');
    } else {
        $c->render( 'login_page', login_failed => 1 );
    }
}

sub get_user($username) {
    my $record = app->db_conn->db->select("users", undef, { email => $username })->hash;
    return $record if defined($record);
}

sub encode_password($password) {
    return bcrypt($password, "2b", 12, rand_bits(16*8));
}

# password must be at least 8 characters
# must have letters, numbers, and at least one special character
sub do_password_change($c) {
    my $existing_password = $c->req->param('current-password');
    my $new_password = $c->req->param('new-password');
    my $retyped_password = $c->req->param('retyped-new-password');
    my $checker = Password::Complexity->new;

    # see if the existing password was correct
    if (!$existing_password || !check_pass( get_user($c->session->{user}->{email})->{password}, $existing_password )) {
        $c->flash({ return_to => $c->flash('return_to'), error_msg => 'Existing Password Incorrect'});
        $c->redirect_to('/auth/password/change',  );
    } 
    # see if the new password doesn't equal the existing password
    elsif ($new_password eq $existing_password) {
        $c->flash({ return_to => $c->flash('return_to'), error_msg => 'New Password cannot equal the existing password' });
        $c->redirect_to('/auth/password/change',  );
    } 
    # make sure the retyped password equals the new password
    elsif ($new_password ne $retyped_password) {
        $c->flash({ return_to => $c->flash('return_to'), error_msg => 'New Password does not equal Retyped New Password' });
        $c->redirect_to('/auth/password/change',  );
    } 
    # make sure we pass the complexity checks
    elsif (!$checker->check_complexity($new_password, $config->{password_complexity} )) {
        $c->flash({ return_to => $c->flash('return_to'), error_msg => 'New Password does not meet complexity requirements... No whitespace, at least 8 characters, combination of letters/digits and special characters.' });
        $c->redirect_to('/auth/password/change', );
    } 
    # if we make it here, then change the password in the database
    else {
        app->db_conn->db->update("users", { "password" => encode_password($new_password), reset_password => 0, last_reset => get_gmstamp() }, { email => $c->session->{user}->{email} } );
        $c->redirect_to($c->flash('return_to') // '/');
    }
}

# returns 'now' as a ISO8601 UTC string (with no 'Z')
sub get_gmstamp() {
    return gmtime()->datetime;
}

# returns time since given date stamp (in ISO 8601 format) in days
sub get_days_since_gmstamp($time) {
    return (gmtime() - Time::Piece->strptime($time, "%Y-%m-%dT%H:%M:%S"))->days;
}

sub check_user_admin($c) {
    return $c->session->{user}->{is_admin};
}

############################
#### BEGIN ROUTING DEFS ####
############################

# login/logout shortcut - always reachable
get '/logout' => sub ($c) {
    $c->session( expires => 1 );
    $c->redirect_to('/login');
};

get '/login' => sub ($c) {
    $c->render('login_page');
};

post '/auth/login' => sub ($c) {
    do_login($c);
};

# all routes from here-on require authentication
under '/' => sub ($c) {

    # if there's no current_user populated in the session cookie,
    # then we're not authenticated, so re-direct to the sign-in page...
    unless ( $c->session->{user}->{email} ) {

        # set return_to value to go back to initially requested url
        # dont allow redirect back to itself - default to /
        if ( $c->req->url =~ m/auth\/login/ || !defined( $c->req->url ) ) {
            $c->req->url('/');
        }
        $c->flash( { return_to => $c->req->url } );
        $c->redirect_to('/login');
        return undef;
    }

    # if user record shows we need to reset-password, and we're not already at the password path,
    #  then re-direct to that page
    if ( $c->session->{user}->{reset_password} && $c->req->url !~ /auth\/password\/change/ ) {
        $c->flash( { return_to => $c->req->url } );
        $c->redirect_to('/auth/password/change');
        return undef;
    }

    # user authenticated OK or already-authenticated, check password expiry if we've defined
    #  that setting and its more than 0 days
    if (($c->session->{user}->{reset_password} || (defined($config->{password_valid_days}) && $config->{password_valid_days} > 0))
        && $c->req->url !~ /auth\/password\/change/) {
        # because we said so
        if ($c->session->{user}->{reset_password}) {
            $c->flash( { return_to => $c->req->url, expired => 0, mandated => 1 });
            $c->redirect_to('/auth/password/change');
            return undef;
        }

        # ok didnt blatantly say we need to change the password, so
        # if last_reset is undef, then set it to now, not sure how'd that be though, should default to current date time
        # otherwise check the age of the password
        if (!defined($c->session->{user}->{last_reset})) {
            app->db_conn->db->update("users", { last_reset => get_gmstamp() }, { email => $c->session->{user}->{email}} );
        } else {
            # check days delta between NOW and last_reset
            my $last_reset = $c->session->{user}->{last_reset};
            if (get_days_since_gmstamp($last_reset) >= $config->{password_valid_days}) {
                $c->flash( { return_to => $c->req->url, expired => 1, mandated => 0 } );
                $c->redirect_to('/auth/password/change');
                return undef;
            }
        }
    }

    # continue on to the routes below
    return 1;
};

get '/admin' => sub ($c) {
    $c->render('no_response') if !check_user_admin($c);
    $c->render('admin');
};

get '/users' => sub ($c) {
    $c->render('no_response') if !check_user_admin($c);
    my $users = app->db_conn->db->select('users', [ 'email', 'reset_password', 'last_reset', 'last_login', 'is_admin' ])->hashes;
    $c->render(json => $users);
};

# show the password change form
get '/auth/password/change' => sub ($c) {
    # preserve the flash value
    $c->flash( { return_to => $c->flash('return_to') // '/' });
    # render the change_password form
    $c->render('password_change');
};

# change the password for current user
post '/auth/password/change' => sub ($c) {    
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
-- 4 up
ALTER TABLE users ADD COLUMN last_login TIMESTAMP
