use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Data::Dumper;

# mock web server from the Mojolicious docs that we'll use
# to echo back what we proxied
my $ua = Mojo::UserAgent->new;
$ua->server->app(Mojolicious->new);
$ua->server->ioloop(Mojo::IOLoop->new);
$ua->server->app->routes->any('*' => sub($c) {
    $c->render(json => $c->req->headers->clone);
});

# init our application and set up our test client to be
# like the browser where we'll follow re-directs
my $t = Test::Mojo->new(Mojo::File->new('./gateway.pl'), { test => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret => 'secret',
    routes => {
      '/' => {
        uri => 'http://localhost:8080',
        enable_jwt => 0
      },
      '/api' => {
        uri => 'http://localhost:8080',
        enable_jwt => 0
      }
    }
});
$t->ua->max_redirects(3);

# test that we need to authenticate - get redirect to the login (we follow redirects)
$t->get_ok('/')
    ->status_is(200)
    ->content_like(qr/login/i, 'Test Login screen landing');

$t->get_ok('/api')
    ->status_is(200)
    ->content_like(qr/login/i, 'Test Login screen landing');

# test we get the login page
$t->get_ok('/api')
    ->status_is(200)
    ->content_like(qr/login/i, 'Test Login screen landing')
    ->element_exists('[name=username]')
    ->element_exists('[name=password]');

done_testing();