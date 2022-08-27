#!/usr/bin/env perl

use Mojolicious::Lite -signatures;
use Mojo::SQLite;
use Mojo::Pg;

use lib qw(./lib);
use Service::User;
use Service::Proxy;
use Controller::Admin;
use Controller::User;

my $config = plugin 'JSONConfig';
app->secrets( [ $config->{secret} ] );

# db connection
helper db_conn => sub {

  # config var 'test' will be defined if we're running unit tests,
  # otherwise see what type of DB we defined in the ENV VARs
  if ( !$ENV{test} && defined($config->{db_type}) && $config->{db_type} eq 'sqlite' ) {
    state $path      = app->home->child('data.db');
    state $db_handle = Mojo::SQLite->new( 'sqlite:' . $path );
    return $db_handle;
  }
  elsif ( !defined( $config->{test} ) && $config->{db_type} eq 'pg' ) {
    state $db_handle = Mojo::Pg->new( $config->{db_uri} );
    return $db_handle;
  }
  else {
    # for tests and future tests...
    state $db_handle = Mojo::SQLite->new(':temp:');
    return $db_handle;
  }
};

# do migrations (see bottom of file __DATA__ section)
app->db_conn->auto_migrate(1)->migrations->from_data;

my $user_service = Service::User->new(db => app->db_conn->db, config => $config);
my $proxy_service = Service::Proxy->new(config => $config, ua => Mojo::UserAgent->new);
my $admin_controller = Controller::Admin->new(user_service => $user_service);
my $user_controller = Controller::User->new(user_service => $user_service);

# create the admin user if it doesn't exist
$user_service->create_admin_user;


############################
#### BEGIN ROUTING DEFS ####
############################

# login/logout shortcut - always reachable
get '/logout' => sub ($c) { $user_controller->logout_get($c) };
get '/login' => sub ($c) { $user_controller->login_page_get($c) };
post '/auth/login' => sub ($c) { $user_controller->login_post($c) };

# all routes from here-on require authentication
under '/' => sub ($c) { $user_service->check_user_status($c) };

get '/admin' => sub ($c) { $admin_controller->admin_page_get($c) };
post '/admin/users' => sub ($c) { $admin_controller->add_user_post($c) };
put '/admin/users' => sub ($c) { $admin_controller->update_user_put($c) };
get '/users' => sub ($c) { $admin_controller->all_users_get($c) };

# show the password change form
get '/auth/password/change' => sub ($c) { $user_controller->password_change_form_get($c) };
post '/auth/password/change' => sub ($c) { $user_controller->password_change_post($c) };

# add our proxy routes requiring authentication
for my $route_spec ( keys %{ $config->{routes} } ) {
  any $route_spec => sub ($c) {
    $proxy_service->proxy( $c, $route_spec );
  };
}

# catch-all/default routes - just proxy to the front-end service
any '/**' => sub ($c) {
  proxy( $c, 'default_route' );
};
any '*' => sub ($c) {
  proxy( $c, 'default_route' );
};

# Remove the default 'Server' header
app->hook(after_dispatch => sub ($c) {
    $c->res->headers->remove('Server');
});

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
ALTER TABLE users ADD COLUMN last_reset TIMESTAMP;
-- 4 up
ALTER TABLE users ADD COLUMN last_login TIMESTAMP;