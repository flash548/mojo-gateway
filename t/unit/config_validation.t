use Test::Mojo;
use Test::More;
use Service::ConfigValidationService;
binmode STDOUT, ":encoding(UTF-8)";
# Tests the config validation logic

subtest 'Test good validation' => sub {
  my $options = {
    test       => 1,
    max_login_attempts => 3,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => {uri            => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api'      => {uri            => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  eval {
    Service::ConfigValidationService->new(config => $options)->validate_config;
  };
  ok $@ eq '', 'Test Config Good - No Template routing';
};

subtest 'Test validation with proxy routes and routes to a template' => sub {
  my $options = {
    test       => 1,
    max_login_attempts => 3,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => {uri            => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api'      => {uri            => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1},
      '/landing_page'      => {template_name => "cool_template", requires_login => 1},
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  eval {
    Service::ConfigValidationService->new(config => $options)->validate_config;
  };
  ok $@ eq '', 'Test Config Good - Both proxy and template routes';
};

subtest 'Test validation fail with dual uri/template fields on default route spec' => sub {
  my $options = {
    test       => 1,
    max_login_attempts => 3,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => {uri            => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api'      => {uri            => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1},
      '/landing_page'      => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    },
    default_route       =>{ template_name => 'blah', uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  eval {
    Service::ConfigValidationService->new(config => $options)->validate_config;
  };
  ok grep { m/Cannot specify both uri and template fields on the default route spec/ } $@, 'Test Config bad - bad default route';
};

subtest 'Test validation fail with dual uri/template fields' => sub {
  my $options = {
    test       => 1,
    max_login_attempts => 3,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => {uri            => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api'      => {uri            => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1},
      '/landing_page'      => {uri => 'https://localhost:8080/frontend', template_name => "cool_template", requires_login => 1},
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  eval {
    Service::ConfigValidationService->new(config => $options)->validate_config;
  };
  ok grep { m/Cannot specify both uri and template fields on a proxy route spec/ } $@, 'Test Config bad - route spec';
};

done_testing();