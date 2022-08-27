use Service::Proxy;
use Test::Mojo;
use Test::More;
use Mojo::File qw(curfile);

# yes this test is a hacky mess

system(<<'END');
perl -E '
use Mojolicious::Lite -signatures;
$SIG{ALRM} = sub { exit(0); };
get "/frontend" => sub ($c) {
  $c->render(json => $c->req->headers->to_hash);
  alarm(1);
};

get "/exit" => sub ($c) {
  $c->rendered(204);
  alarm(1);
};

app->start("daemon", "-l", "http://*:3000");' &

END


subtest 'Test JWT injected if config says to' => sub {

  my $t = Test::Mojo->new(Mojo::File->new('./gateway.pl'), { 
    test => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret => 'secret',
    jwt_secret => 'secret',
    routes => {
      '/' => {
        uri => "http://localhost:3000/frontend",
        enable_jwt => 1,
        jwt_claims => {
          'email' => '$c->session->{user}->{email}'
        }
      },
    },
    default_route => {
      uri => "http://localhost:3000/exit",
      enable_jwt => 1,
      jwt_claims => {
          'email' => '$c->session->{user}->{email}'
        }
    },
    password_valid_days => 60,
    password_complexity => {
      min_length => 8,
      alphas => 1,
      numbers => 1,
      specials => 1,
      spaces => 0
    }
  });
  $t->ua->max_redirects(3);

  # test we get the login page form elements
  $t->get_ok('/')
    ->status_is(200)
    ->content_like(qr/login/i, 'Test Login screen landing 3')
    ->element_exists('[name=username]')
    ->element_exists('[name=password]');
  
  $t->post_ok('/auth/login', form => { username => 'admin@test.com', password => 'testpass' })
    ->status_is(200)
    ->content_unlike(qr/login/i, 'Login OK');

  $t->get_ok('/')
    ->status_is(200)
    ->json_has('/Authorization');

  $t->get_ok('/exit')
    ->status_is(204);
};

done_testing();
