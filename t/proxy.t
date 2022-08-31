use Test::Mojo;
use Test::More;
use Mojo::File qw(curfile);
use Gateway;

# our mock Mojo::UserAgent that we inject into the app after bootstrap
package MockAgent;

sub new {
  bless({}, 'MockAgent');
}

# echo back the headers - so we can inspect in the test below to see if the proxy injects the expected headers
sub start {
  my ($self, $transaction) = @_;
  my $tx  = Mojo::Transaction->new;
  my $res = Mojo::Message::Response->new;
  $res->code(200);
  for my $header (keys %{$transaction->req->headers->to_hash}) {
    $res->headers->add($header => $transaction->req->headers->to_hash->{$header});
  }
  $res->headers->add(location => '/frontend');
  $res->headers->add(content_type => 'application/json');
  $tx->res($res);
  return $tx;
}

package main;

my $config = {
  test       => 1,
  admin_user => 'admin@test.com',
  admin_pass => 'testpass',
  secret     => 'secret',
  jwt_secret => 'secret',
  strip_headers_to_client => [  ],
  routes     => {
    '/s' => {
      uri        => "http://localhost:3000/frontend",
      enable_jwt => 1,
      jwt_claims => {email => '$c->session->{user}->{email}'},
    },
  },
  default_route       => {uri => "http://localhost:3000/frontend", enable_jwt => 0,},
  password_valid_days => 60,
  password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
};

subtest 'Test JWT injected if config says to' => sub {
  my $t = Test::Mojo->new(
    'Gateway',
    $config);

  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  # test we get the login page form elements
  $t->get_ok('/s')->status_is(200)->content_like(qr/login/i, 'Test Login screen landing')
    ->element_exists('[name=username]')->element_exists('[name=password]');

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})->status_is(200)
    ->content_unlike(qr/login/i, 'Login OK');

  # test that the JWT was injected as spec'd in the config json
  $t->get_ok('/s')->status_is(200)->header_exists('Authorization', 'Authorization header present as expected')
    ->header_is('location' => '/frontend')
    ->header_is('content_type' => 'application/json')
    ->tap(sub ($t) {
      my $jwt = Mojo::JWT->new(secret => 'secret')->decode(
        do { my $val = $t->tx->res->headers->authorization; $val =~ s/Bearer\s//g; $val; }
      );
      return is('admin@test.com', $jwt->{email});
    });

  # should be no JWT on the default route as spec'd in the config json
  $t->get_ok('/other-route')->status_is(200)
    ->header_exists_not('Authorization', 'Authorization header NOT present as expected');

  # should strip authorization header from ever getting to client - if provided in config
  $t->app->config->{strip_headers_to_client} = [ 'authorization' ];
   # test that the JWT was injected as spec'd in the config json
  $t->get_ok('/s')->status_is(200)->header_exists_not('Authorization', 'Authorization header NOT present as commanded')
    ->header_is('location' => '/frontend')
    ->header_is('content_type' => 'application/json');

};

subtest 'check user-agent and other client headers are preserved after proxy' => sub {
  my $t = Test::Mojo->new(
    'Gateway',
    $config);
    
  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  # test we get the login page form elements
  $t->get_ok('/s')->status_is(200)->content_like(qr/login/i, 'Test Login screen landing')
    ->element_exists('[name=username]')->element_exists('[name=password]');

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})->status_is(200)
    ->content_unlike(qr/login/i, 'Login OK');

  $t->ua->transactor->name("Chrome");
  $t->get_ok('/s')->status_is(200)->header_is('User-Agent' => 'Chrome', 'Test User Agent is intact');
};

done_testing();
