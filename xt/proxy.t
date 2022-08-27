use Mojolicious -signatures;
use Service::Proxy;
use Test::Mojo;
use Test::More;
use Mojo::File qw(curfile);

subtest 'Test JWT injected if config says to' => sub {

  my $jwt;

  my $host = Test::Mojo->new;
  my $server = $host->ua;
  $server->server->app(Mojolicious->new);
  $server->server->ioloop(Mojo::IOLoop->new);
  $server->server->app->routes->get('/api/' => sub ($c) {
    $c->render(json => { 'message' =>  $c->req->headers->clone }, status => 200);
  });

  my $config = {
    test => 1,
    jwt_secret => 'secret',
    routes => {
      "/" => {
        uri => "http://localhost:" . $server->server->url->port . "/api",
        enable_jwt => 1,
        jwt_claims => {
          email => '$c->session->{email}'
        }
      }
    }
  };

  my $t = Test::Mojo->new;
  my $ua = $t->ua;
  my $proxy = Service::Proxy->new(config => $config, ua => $ua);
  $ua->server->app(Mojolicious->new);
  $ua->server->app->routes->get('/' => sub ($c) {
    $c->session({email => 'test@test.com'});
    $proxy->proxy($c, '/');
  });

  $t->get_ok('/')->status_is(200);

  ok defined($jwt);

};

done_testing();
