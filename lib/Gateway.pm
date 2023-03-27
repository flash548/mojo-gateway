package Gateway;
use Mojo::Base 'Mojolicious', -signatures;
use Mojo::Pg;
use Mojo::SQLite;
use JSON::Validator::Joi qw(joi);

use lib qw(./lib);
use Service::UserService;
use Service::Proxy;
use Service::HttpLogService;
use Controller::AdminController;
use Controller::UserController;
use Constants;

binmode STDOUT, ":encoding(UTF-8)";

has 'user_service';
has 'proxy_service';
has 'http_log_service';
has 'admin_controller';
has 'user_controller';

# we'll check the config file routes do not match these as we do not
# want these to get overriden - ever
my $reserved_routes = ['/admin', '/auth', '/login', '/logout'];

sub startup ($self) {
  my $config = $self->plugin('JSONConfig');

  # validate our config before doing anything
  $self->validate_config();
  
  $self->secrets([$config->{secret}]);
  $self->sessions->cookie_name($config->{cookie_name} // 'mojolicious');
  $self->hook(
    before_dispatch => sub ($c) {

      # start the http trace
      $self->http_log_service->start_trace($c);
    }
  );

  $self->hook(
    after_dispatch => sub ($c) {

      # remove any headers we never want going back to the client
      if ($config->{strip_headers_to_client}) {
        $c->res->headers->remove(lc $_) for (@{$config->{strip_headers_to_client}});
      }

      # log the http trace
      $self->http_log_service->end_trace($c);
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

        # turn off pg-server-side prepares since in prod we're running this
        # thing in prefork mode.  If not pre-fork, shouldn't matter as to this
        # setting's value, otherwise we get multiple Mojo::Gateway instances telling Postgres to
        # prepare identical, already stored statements causing exceptions...
        $db_handle->db->dbh->{pg_server_prepare} = 0;
        return $db_handle;
      } else {

        # in-mem, volatile database
        # for tests and future tests...
        state $db_handle = Mojo::SQLite->new(':temp:');
        return $db_handle;
      }
    }
  );

  if (!$ENV{test} && defined($config->{db_type}) && $config->{db_type} eq 'sqlite') {
    $self->db_conn->auto_migrate(1)->migrations->from_file('./migrations/data.sql');
  } elsif (!defined($config->{test}) && $config->{db_type} eq 'pg') {
    $self->db_conn->auto_migrate(1)->migrations->from_file('./migrations/data_pg.sql');
  } else {
    $self->db_conn->auto_migrate(1)->migrations->from_file('./migrations/data.sql');
  }

  $self->user_service(Service::UserService->new(db => $self->db_conn->db, config => $config));
  $self->http_log_service(Service::HttpLogService->new(db => $self->db_conn->db, config => $config));
  $self->proxy_service(Service::Proxy->new(config => $config, ua => Mojo::UserAgent->new));
  $self->admin_controller(
    Controller::AdminController->new(user_service => $self->user_service, log_service => $self->http_log_service));
  $self->user_controller(Controller::UserController->new(user_service => $self->user_service));

  # create the admin user if it doesn't exist
  $self->user_service->create_admin_user;

  # mark all users as MFA enabled if that option is set
  $self->user_service->mark_all_as_mfa;

  # login/logout shortcut - always reachable
  $self->routes->get('/logout' => sub ($c) { $self->user_controller->logout_get($c) });
  $self->routes->get('/login'  => sub ($c) { $self->user_controller->login_page_get($c) });
  $self->routes->post('/auth/login' => sub ($c) { $self->user_controller->login_post($c) });

  # add any config-file-defined proxy routes that do not require authentication
  for my $route_spec (keys %{$config->{routes}}) {
    next
      if !defined($config->{routes}->{$route_spec}->{requires_login})
      || $config->{routes}->{$route_spec}->{requires_login};

    # check not overwriting reserved routes
    die "One of the configured routes is a reserved route" if grep { $route_spec =~ m/^$_/ } $reserved_routes->@*;

    $self->routes->any(
      $route_spec => sub ($c) {
        $self->proxy_service->proxy($c, $route_spec);
      }
    );
  }

  # __IF__ our default route in the config specifies that it does NOT require
  # login then add that here and now, otherwise it'll be later on in the auth'd routes
  # below
  if (defined($config->{default_route}->{requires_login}) && !$config->{default_route}->{requires_login}) {
    $self->routes->add_condition(
      check_no_admin => sub ($route, $c, $captures, $opts) {
        return undef if $c->req->url->path =~ m!^/admin!i; # don't allow admin to be aliased over by the catch-all route

        return 1;
      }
    );
    $self->routes->any('/**')->requires(check_no_admin => {})->to(
      cb => sub ($c) {
        $self->proxy_service->proxy($c, 'default_route');
      }
    );
    $self->routes->any('*')->requires(check_no_admin => {})->to(
      cb => sub ($c) {
        $self->proxy_service->proxy($c, 'default_route');
      }
    );
  }

  # all routes from here-on require authenticated user
  my $authorized_routes = $self->routes->under('/' => sub ($c) { $self->user_service->check_user_status($c) });

  # the routes under '/admin' requires admin-type, authenticated users
  my $admin_routes = $authorized_routes->under(
    '/admin' => sub ($c) {
      if (!$self->user_service->check_user_admin($c)) {
        $c->rendered(Constants::HTTP_FORBIDDEN);
        return;
      }

      return 1;
    }
  );
  $admin_routes->get('/' => sub ($c) { $self->admin_controller->admin_page_get($c) });
  $admin_routes->post('/users' => sub ($c) { $self->admin_controller->add_user_post($c) });
  $admin_routes->put('/users' => sub ($c) { $self->admin_controller->update_user_put($c) });
  $admin_routes->get('/users' => sub ($c) { $self->admin_controller->users_get($c) });
  $admin_routes->delete('/users' => sub ($c) { $self->admin_controller->users_delete($c) });

  # Logs fetch routes
  if ($self->config->{enable_logging}) {
    $admin_routes->get('/http_logs' => sub ($c) { $self->admin_controller->get_http_logs($c) });
  } else {
    $admin_routes->get('/http_logs' =>
        sub ($c) { $c->render(json => {message => "Feature Disabled"}, status => Constants::HTTP_FORBIDDEN); });
  }

  # these routes are just for authenticated (logged in users)
  #
  # allow the password change form
  $authorized_routes->get('/auth/password/change' => sub ($c) { $self->user_controller->password_change_form_get($c) });
  $authorized_routes->post('/auth/password/change' => sub ($c) { $self->user_controller->password_change_post($c) });
  #
  # allow the MFA forms
  $authorized_routes->get('/auth/mfa/init' => sub ($c) { $self->user_controller->mfa_init_form_get($c) });
  $authorized_routes->post('/auth/mfa/init' => sub ($c) { $self->user_controller->mfa_init_form_post($c) });
  $authorized_routes->get('/auth/mfa/entry' => sub ($c) { $self->user_controller->mfa_entry_form_get($c) });
  $authorized_routes->post('/auth/mfa/entry' => sub ($c) { $self->user_controller->mfa_entry_form_post($c) });

  # add our proxy routes requiring authentication
  for my $route_spec (keys %{$config->{routes}}) {
    next
      if defined($config->{routes}->{$route_spec}->{requires_login})
      && !$config->{routes}->{$route_spec}->{requires_login};

    # check not overwriting reserved routes
    die "One of the configured routes is a reserved route" if grep { $route_spec =~ m/^$_/ } $reserved_routes->@*;

    $authorized_routes->any(
      $route_spec => sub ($c) {
        $self->proxy_service->proxy($c, $route_spec);
      }
    );
  }

  # for if our default route is a locked down route requiring an authenticated user
  if (!defined($config->{default_route}->{requires_login}) || $config->{default_route}->{requires_login}) {

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
}

sub validate_config ($self) {
  my $config = joi->object->props(
    login_page_title        => joi->string,
    mfa_secret              => joi->string,
    mfa_force_on_all        => joi->boolean,
    mfa_issuer              => joi->string,
    mfa_key_id              => joi->string,
    enable_logging          => joi->boolean,
    logging_ignore_paths    => joi->array,
    secret                  => joi->string->min(1)->required,
    admin_user              => joi->email->required,
    admin_pass              => joi->string(1)->required,
    db_type                 => joi->string->enum(["pg", "sqlite"]),
    db_uri                  => joi->string,
    cookie_name             => joi->string,
    strip_headers_to_client => joi->array,
    jwt_secret              => joi->string->required,
    routes                  => joi->object->required,
    password_valid_days     => joi->number->positive->required,
    password_complexity     => joi->object->required,
    default_route           => joi->object->required,
    test                    => joi->boolean,
    config_override         => joi->boolean    # this is put in by Mojo on config overrides in testing
  );

  if ($self->config->{mfa_secret} || $self->config->{mfa_issuer} || $self->config->{mfa_key_id}) {
    die "MFA secret/issuer/key_id must ALL be set if any of the others are set" unless 
      $self->config->{mfa_secret} && $self->config->{mfa_issuer} && $self->config->{mfa_key_id};
  }

  say "Validating config...";
  my @errors = $config->strict->validate($self->config);
  if (@errors) {
    die @errors;
  }

  my $password_complex_config = joi->object->props(
    min_length => joi->number->min(1)->required,
    alphas     => joi->number->min(0)->required,
    numbers    => joi->number->min(0)->required,
    specials   => joi->number->min(0)->required,
    spaces     => joi->boolean->required
  );

  say "Validating password complexity config...";
  @errors = $password_complex_config->strict->validate($self->config->{password_complexity});
  if (@errors) {
    die @errors;
  }

  my $default_route_config = joi->object->props(
    uri            => joi->string->required,
    enable_jwt     => joi->boolean,
    requires_login => joi->boolean,
    jwt_claims     => joi->object,
    transforms     => joi->array,
    other_headers  => joi->object
  );

  say "Validating default route config...";
  @errors = $default_route_config->validate($self->config->{default_route});
  if (@errors) {
    die @errors;
  }

  say "Validating route config...";
  for my $route (keys($self->config->{routes}->%*)) {
    say "On route " . $route;
    @errors = $default_route_config->validate($self->config->{routes}->{$route});
    if (@errors) {
      die @errors;
    }
  }

  say "App Config - Valid ✅";
}

1;

