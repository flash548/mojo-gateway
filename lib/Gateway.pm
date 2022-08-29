package Gateway;
use Mojo::Base 'Mojolicious', -signatures;
use Mojo::Pg;
use Mojo::SQLite;

use lib qw(./lib);
use Service::User;
use Service::Proxy;
use Controller::Admin;
use Controller::User;

has 'user_service';
has 'proxy_service';
has 'admin_controller';
has 'user_controller';

# This method will run once at server start
sub startup ($self) {
  my $config = $self->plugin('JSONConfig');
  $self->secrets([$config->{secret}]);

  $self->hook(
    after_dispatch => sub ($c) {
      $c->res->headers->remove('Server');
    }
  );

  $self->helper(
    db_conn => sub {

      # config var 'test' will be defined if we're running unit tests,
      # otherwise see what type of DB we defined in the ENV VARs
      if (!$ENV{test} && defined($config->{db_type}) && $config->{db_type} eq 'sqlite') {
        state $path      = $self->app->home->child('data.db');
        state $db_handle = Mojo::SQLite->new('sqlite:' . $path);
        return $db_handle;
      } elsif (!defined($config->{test}) && $config->{db_type} eq 'pg') {
        state $db_handle = Mojo::Pg->new($config->{db_uri});
        return $db_handle;
      } else {

        # for tests and future tests...
        state $db_handle = Mojo::SQLite->new(':temp:');
        return $db_handle;
      }
    }
  );

  $self->db_conn->auto_migrate(1)->migrations->from_file('./migrations/data.sql');

  $self->user_service(Service::User->new(db => $self->db_conn->db, config => $config));
  $self->proxy_service(Service::Proxy->new(config => $config, ua => Mojo::UserAgent->new));
  $self->admin_controller(Controller::Admin->new(user_service => $self->user_service));
  $self->user_controller(Controller::User->new(user_service => $self->user_service));

  # create the admin user if it doesn't exist
  $self->user_service->create_admin_user;

  # login/logout shortcut - always reachable
  $self->routes->get('/logout' => sub ($c) { $self->user_controller->logout_get($c) });
  $self->routes->get('/login'  => sub ($c) { $self->user_controller->login_page_get($c) });
  $self->routes->post('/auth/login' => sub ($c) { $self->user_controller->login_post($c) });

  # all routes from here-on require authentication
  my $authorized_routes = $self->routes->under('/' => sub ($c) { $self->user_service->check_user_status($c) });
  $authorized_routes->get('/admin' => sub ($c) { $self->admin_controller->admin_page_get($c) });
  $authorized_routes->post('/admin/users' => sub ($c) { $self->admin_controller->add_user_post($c) });
  $authorized_routes->put('/admin/users' => sub ($c) { $self->admin_controller->update_user_put($c) });
  $authorized_routes->get('/users' => sub ($c) { $self->admin_controller->all_users_get($c) });

  # show the password change form
  $authorized_routes->get('/auth/password/change' => sub ($c) { $self->user_controller->password_change_form_get($c) });
  $authorized_routes->post('/auth/password/change' => sub ($c) { $self->user_controller->password_change_post($c) });

  # add our proxy routes requiring authentication
  for my $route_spec (keys %{$config->{routes}}) {
    $authorized_routes->any(
      $route_spec => sub ($c) {
        $self->proxy_service->proxy($c, $route_spec);
      }
    );
  }

  # catch-all/default routes - routes to the default_routes specified in the config json
  $authorized_routes->any(
    '/**' => sub ($c) {
      $self->proxy_service->proxy($c, 'default_route');
    }
  );
  $authorized_routes->any(
    '*' => sub ($c) {
      $self->proxy_service->proxy($c, 'default_route');
    }
  );
}

1;

