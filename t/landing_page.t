use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Gateway;
use Constants;

# Tests various combinations of ingress for the landing page.

subtest 'Check vanilla login goes to landing page specified - existing resrved route' => sub {
  my $options = {
    test         => 1,
    admin_user   => 'admin@test.com',
    landing_page => '/admin',           # should go right to the admin page on login
    admin_pass   => 'testpass',
    secret       => 'secret',
    jwt_secret   => 'secret',
    routes       => {
      '/'    => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api' => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  # do a login and we get redirected to admin page
  $t->post_ok("/auth/login", form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/Admin/i, 'Check at Admin page');
};

subtest 'Check vanilla login goes to landing page specified - specified inline template' => sub {
  my $options = {
    test         => 1,
    admin_user   => 'admin@test.com',
    landing_page => '/landing_page',
    admin_pass   => 'testpass',
    secret       => 'secret',
    jwt_secret   => 'secret',
    routes       => {
      '/'             => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api'          => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1},
      '/landing_page' => {template_name => '<%= 1 + 1 %>'}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  # do a login and we get redirected to admin page
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/2/i, 'Check at Template page');
};

subtest 'Check vanilla login goes to landing page specified - specified inline template' => sub {
  my $options = {
    test         => 1,
    admin_user   => 'admin@test.com',
    landing_page => '/landing_page',
    admin_pass   => 'testpass',
    secret       => 'secret',
    jwt_secret   => 'secret',
    routes       => {
      '/'             => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api'          => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1},
      '/landing_page' => {template_name => 'restricted_page'}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  # do a login and we get redirected to admin page
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/Whoa!! This is a restricted page/i, 'Check at Template page');
};

subtest 'Check landing page can be accessed if requires_login false' => sub {
  my $options = {
    test         => 1,
    admin_user   => 'admin@test.com',
    landing_page => '/landing_page',
    admin_pass   => 'testpass',
    secret       => 'secret',
    jwt_secret   => 'secret',
    routes       => {
      '/'             => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api'          => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1},
      '/landing_page' => {template_name => '<%= qw(landing_page!!!) %>', requires_login => 0}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(0);

  # do a login and we get redirected to admin page
  $t->get_ok('/landing_page')->status_is(Constants::HTTP_OK)
    ->content_like(qr/landing_page!!!/i, 'Check at Template page');
};

subtest 'Check landing page can be cannot be accessed if requires_login is true' => sub {
  my $options = {
    test         => 1,
    admin_user   => 'admin@test.com',
    landing_page => '/landing_page',
    admin_pass   => 'testpass',
    secret       => 'secret',
    jwt_secret   => 'secret',
    routes       => {
      '/'             => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api'          => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1},
      '/landing_page' => {template_name => '<%= qw(landing_page!!!) %>', requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  # go to landing page - but can't initially because need to login
  $t->get_ok('/landing_page')->status_is(Constants::HTTP_OK)->content_like(qr/Login/i, 'Check at Login page');

  # login, should be at landing page
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/landing_page!!!/i, 'Check at Landing page');

};

subtest 'Check landing page is used upon subsequent login after explicit logout' => sub {
  my $options = {
    test         => 1,
    admin_user   => 'admin@test.com',
    landing_page => '/landing_page',
    admin_pass   => 'testpass',
    secret       => 'secret',
    jwt_secret   => 'secret',
    routes       => {
      '/'             => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api'          => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1},
      '/landing_page' => {template_name => '<%= qw(landing_page!!!) %>', requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  # go to api page - but can't initially because need to login
  $t->get_ok('/api')->status_is(Constants::HTTP_OK)->content_like(qr/Login/i, 'Check at Login page');

  # login, should be at api page
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/Whoa!!/i, 'Check at API page');

  # logout
  $t->get_ok('/logout');

  # login again, and should go right to landing page
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/landing_page!!!/i, 'Check at Landing page');

};

done_testing();
