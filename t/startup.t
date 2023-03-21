use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Gateway;
use Constants;

# Tests various validations we do on startup

subtest 'Check cannot overwrite reserved routes' => sub {
  my $options = {
    test       => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => {uri            => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/login' => {requires_login => 0, uri => "http://localhost:8080/everyone"},
      '/api'      => {uri            => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  eval {
    Test::Mojo->new('Gateway', $options,);
  };

  ok $@, 'Test that App failed to launch';
};

subtest 'Catches missing (required) config key' => sub {
  my $options = {
    test       => 1,
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => {uri            => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/everyone' => {requires_login => 0, uri => "http://localhost:8080/everyone"},
      '/api'      => {uri            => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  eval {
    Test::Mojo->new('Gateway', $options,);
  };

  ok $@, 'Test that App failed to launch';
  ok grep { $_ =~ m!/admin_user: Missing property! } $@;
};

done_testing();