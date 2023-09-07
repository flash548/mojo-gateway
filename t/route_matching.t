use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Gateway;
use Constants;

# Tests route matching combinations from the config

subtest 'Check can find nested, additional routes' => sub {
  my $options = {
    test       => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => { uri              => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1 },
      '/everyone' => { additional_paths => ['/every-one', '/anybody/**' ], requires_login => 0, template_name => "<%= Hello World %>" },
      '/anyone'   => { requires_login   => 0,              uri            => "http://localhost:8080/anyone" },
      '/api'      => { uri              => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1 }
    },
    default_route       => { uri => 'https://localhost:8080/frontend', requires_login => 1 },
    password_valid_days => 60,
    password_complexity => { min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0 }
  };
  my $proxy = Service::Proxy->new(config => $options);
  ok $proxy->_find_route_spec('/')->{uri} eq "http://localhost:8080/frontend";
  ok $proxy->_find_route_spec('/everyone')->{template_name} eq "<%= Hello World %>";
  ok $proxy->_find_route_spec('/every-one')->{template_name} eq "<%= Hello World %>";
  ok $proxy->_find_route_spec('/anybody/**')->{template_name} eq "<%= Hello World %>";
  ok !defined($proxy->_find_route_spec('/anyone')->{template_name});
  ok $proxy->_find_route_spec('/anyone')->{uri} eq "http://localhost:8080/anyone";

  # goes to default fallback route
  ok $proxy->_find_route_spec('/whatever')->{uri} eq "https://localhost:8080/frontend";

};

subtest 'Check matches compound spec' => sub {
  my $options = {
    test       => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => { uri              => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1 },
      '/everyone' => { additional_paths => ['/every-one', '/anybody/**'], requires_login => 0, template_name => "<%= Hello World %>" },
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
  $t->get_ok('/anybody/anywhere')->content_like(qr/Hello World/, 'Routes to everyone page 4');
  $t->get_ok('/anyone')->content_like(qr/Whoa/, 'Bad Route page');
  $t->get_ok('/everY--one')->content_like(qr/Login/, 'Routes to login');
};

done_testing();
