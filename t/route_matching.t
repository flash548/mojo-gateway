use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Gateway;
use Constants;

# Tests route matching combinations from the config

subtest 'Check matches compound spec' => sub {
  my $options = {
    test       => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => { uri              => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1 },
      '/everyone' => { additional_paths => ['/every-one'], requires_login => 0, template_name => "<%= Hello World %>" },
      '/anyone'   => { requires_login   => 0,              uri            => "http://localhost:8080/anyone" },
      '/api'      => { uri              => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1 }
    },
    default_route       => { uri => 'https://localhost:8080/frontend', requires_login => 1 },
    password_valid_days => 60,
    password_complexity => { min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0 }
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  $t->get_ok('/everyone')->content_like(qr/Hello World/, 'Routes to everyone page 1');
  $t->get_ok('/every-one')->content_like(qr/Hello World/, 'Routes to everyone page 2');
  $t->get_ok('/every-one/')->content_like(qr/Hello World/, 'Routes to everyone page 3');
  $t->get_ok('/anyone')->content_like(qr/Whoa/, 'Bad Route page');
  $t->get_ok('/everY--one')->content_like(qr/Login/, 'Routes to login');
};

done_testing();
