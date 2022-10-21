package Gateway;
use Mojo::Base 'Mojolicious', -signatures;
use Mojo::Pg;
use Mojo::SQLite;

use lib qw(./lib);
use Service::UserService;
use Service::Proxy;
use Controller::AdminController;
use Controller::UserController;
use Constants;

has 'user_service';
has 'proxy_service';
has 'admin_controller';
has 'user_controller';

sub startup ($self) {
  my $config = $self->plugin('JSONConfig');
  $self->secrets([$config->{secret}]);
  $self->sessions->cookie_name($config->{cookie_name} // 'mojolicious');

  # remove any headers we never want going back to the client
  $self->hook(
    after_dispatch => sub ($c) {
      if ($config->{strip_headers_to_client}) {
        $c->res->headers->remove(lc $_) for (@{$config->{strip_headers_to_client}});
      }
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

  $self->user_service(Service::UserService->new(db => $self->db_conn->db, config => $config));
  $self->proxy_service(Service::Proxy->new(config => $config, ua => Mojo::UserAgent->new));
  $self->admin_controller(Controller::AdminController->new(user_service => $self->user_service));
  $self->user_controller(Controller::UserController->new(user_service => $self->user_service));

  # create the admin user if it doesn't exist
  $self->user_service->create_admin_user;

  # login/logout shortcut - always reachable
  $self->routes->get('/logout' => sub ($c) { $self->user_controller->logout_get($c) });
  $self->routes->get('/login'  => sub ($c) { $self->user_controller->login_page_get($c) });
  $self->routes->post('/auth/login' => sub ($c) { $self->user_controller->login_post($c) });

  # add any config-file-defined proxy routes that do not require authentication
  for my $route_spec (keys %{$config->{routes}}) {
    next if !defined($config->{routes}->{$route_spec}->{requires_login}) || $config->{routes}->{$route_spec}->{requires_login};
    $self->routes->any(
      $route_spec => sub ($c) {
        $self->proxy_service->proxy($c, $route_spec);
      }
    );
  }

  # all routes from here-on require authentication
  my $authorized_routes = $self->routes->under('/' => sub ($c) { $self->user_service->check_user_status($c) });

  # the routes under '/admin/**' requires admin-blessed, authenticated users
  my $admin_routes = $authorized_routes->under('/admin' => sub ($c) { 
    if (!$self->user_service->check_user_admin($c)) {
      $c->rendered(Constants::HTTP_FORBIDDEN);
      return;
    }

    return 1;
  });
  $admin_routes->get('/' => sub ($c) { $self->admin_controller->admin_page_get($c) });
  $admin_routes->post('/users' => sub ($c) { $self->admin_controller->add_user_post($c) });
  $admin_routes->put('/users' => sub ($c) { $self->admin_controller->update_user_put($c) });
  $admin_routes->get('/users' => sub ($c) { $self->admin_controller->users_get($c) });
  $admin_routes->get('/users' => sub ($c) { $self->admin_controller->users_get($c) });
  $admin_routes->delete('/users' => sub ($c) { $self->admin_controller->users_delete($c) });

  # the password change form - that only existing (auth'd) users can get to that is
  $authorized_routes->get('/auth/password/change' => sub ($c) { $self->user_controller->password_change_form_get($c) });
  $authorized_routes->post('/auth/password/change' => sub ($c) { $self->user_controller->password_change_post($c) });

  # add any config-file-defined proxy routes requiring authentication
  for my $route_spec (keys %{$config->{routes}}) {
    next if defined($config->{routes}->{$route_spec}->{requires_login}) && !$config->{routes}->{$route_spec}->{requires_login};
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

