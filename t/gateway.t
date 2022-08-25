use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Data::Dumper;

# init our application and set up our test client to be
# like the browser where we'll follow re-directs
my $t = Test::Mojo->new(Mojo::File->new('./gateway.pl'), { test => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret => 'secret',
    jwt_secret => 'secret',
    routes => {
      '/' => {
        uri => 'http://localhost:8080/frontend',
        enable_jwt => 1
      },
      '/api' => {
        uri => 'http://localhost:8080/api',
        enable_jwt => 1
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

$t->post_ok('/auth/login', form => { username => 'admin@test.com', password => 'testpass' })
  ->status_is(200)
  ->content_unlike(qr/login/i, 'Make sure we are not at the login page anymore');

$t->get_ok('/admin')
  ->status_is(200)
  ->content_like(qr/Admin/, 'Make sure we are at the Admin page');

$t->get_ok('/')
  ->status_is(200)
  ->content_like(qr/authorization/i);

done_testing();