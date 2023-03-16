use Test::Mojo;
use Test::More;
use Gateway;
use Constants;

# our mock Mojo::UserAgent that we inject into the app after bootstrap
package MockAgent;
use Test::More;
sub new {
  bless({}, 'MockAgent');
}

# echo back the headers - so we can inspect in the test below to see if the proxy injects the expected headers
sub start {
  my ($self, $transaction) = @_;
  my $tx  = Mojo::Transaction->new;
  my $res = Mojo::Message::Response->new;
  $res->code(Constants::HTTP_OK);
  for my $header (keys %{$transaction->req->headers->to_hash}) {
    $res->headers->add($header => $transaction->req->headers->to_hash->{$header});
  }
  $res->headers->add(orig_location => $transaction->req->url);
  $res->headers->add(location     => '/frontend');
  $res->headers->add(content_type => 'application/json');
  $tx->res($res);
  return $tx;
}

package main;

my $config = {
  test                    => 1,
  admin_user              => 'admin@test.com',
  admin_pass              => 'testpass',
  secret                  => 'secret',
  jwt_secret              => 'secret',
  strip_headers_to_client => [],
  routes                  => {
    '/s' => {
      uri        => "http://localhost:3000/frontend",
      enable_jwt => 1,
      jwt_claims => {email => '$c->session->{user}->{email}'},
    },
  },
  default_route       => {uri => "http://localhost:3000/frontend", enable_jwt => 0 },
  password_valid_days => 60,
  password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
};

subtest 'Test JWT injected if config says to' => sub {
  my $t = Test::Mojo->new('Gateway', $config);

  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  # test we get the login page form elements
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing')
    ->element_exists('[name=username]')->element_exists('[name=password]');

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})->status_is(Constants::HTTP_OK)
    ->content_unlike(qr/login/i, 'Login OK');

  # test that the JWT was injected as spec'd in the config json
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->header_exists('Authorization', 'Authorization header present as expected')
    ->header_is('location' => '/frontend')->header_is('content_type' => 'application/json')->tap(sub ($t) {
    my $jwt = Mojo::JWT->new(secret => 'secret')->decode(
      do { my $val = $t->tx->res->headers->authorization; $val =~ s/Bearer\s//g; $val; }
    );
    return is('admin@test.com', $jwt->{email});
    });

  # should be no JWT on the default route as spec'd in the config json
  $t->get_ok('/other-route')->status_is(Constants::HTTP_OK)
    ->header_exists_not('Authorization', 'Authorization header NOT present as expected');

  # should strip authorization header from ever getting to client - if provided in config
  $t->app->config->{strip_headers_to_client} = ['authorization'];

  # test that the JWT was injected as spec'd in the config json
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->header_exists_not('Authorization', 'Authorization header NOT present as commanded')
    ->header_is('location' => '/frontend')->header_is('content_type' => 'application/json');

};

subtest 'check user-agent and other client headers are preserved after proxy' => sub {
  my $t = Test::Mojo->new('Gateway', $config);

  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  # test we get the login page form elements
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing')
    ->element_exists('[name=username]')->element_exists('[name=password]');

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})->status_is(Constants::HTTP_OK)
    ->content_unlike(qr/login/i, 'Login OK');

  $t->ua->transactor->name("Chrome");
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->header_is('User-Agent' => 'Chrome', 'Test User Agent is intact');
};

subtest 'check that we can do response body transforms' => sub {
  my $mod_config = $config;
  $config->{routes}->{'/s'}->{transforms}
    = [{condition => '$c->req->url->path =~ m/\/s/', action => '$body = "Mojo Rocks!"'}];

  my $t = Test::Mojo->new('Gateway', $mod_config);

  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  # test we get the login page form elements
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing')
    ->element_exists('[name=username]')->element_exists('[name=password]');

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})->status_is(Constants::HTTP_OK)
    ->content_unlike(qr/login/i, 'Login OK');

  # make sure we modified the body as specified for this route
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->content_like(qr/Mojo Rocks!/);
};

subtest 'check that we can do inbound request path rewrites' => sub {
  my $config2 = $config;
  $config2->{routes}->{'/ui/**'}->{rewrite_path}->{match} = "^/ui";
  $config2->{routes}->{'/ui/**'}->{rewrite_path}->{with} = "";
  $config2->{routes}->{'/ui/**'}->{requires_login} = 0;
  $config2->{routes}->{'/ui/**'}->{uri} = 'http://localhost:3000/frontend';
  my $t = Test::Mojo->new('Gateway', $config2);

  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  $t->get_ok('/ui/some-page')
    ->status_is(Constants::HTTP_OK)
    ->header_is('location' => '/frontend')
    ->header_is('orig_location' => 'http://localhost:3000/frontend/some-page');
};

done_testing();
