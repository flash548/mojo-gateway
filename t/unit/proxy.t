use Test::Mojo;
use Test::More;
use Gateway;
use Constants;
use Mojo::JSON qw/to_json/;

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
  for my $header (keys %{ $transaction->req->headers->to_hash }) {
    $res->headers->add($header => $transaction->req->headers->to_hash->{ $header });
  }
  $res->headers->header(orig_location => $transaction->req->url);
  $res->headers->header(location      => '/frontend');
  $res->headers->header(content_type  => 'application/json');
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
      jwt_claims => {
        email             => ':email',
        user_id           => ['My',  ':email',    'here'],
        my_id             => ':user_id/i',
        my_boolified_id   => ':user_id/b',
        flattened_id_str  => ['My ',  ':email/b',    ' id'],
        other_claim       => ['My ', 'password ', 'is ', ':password'],
        another_claim     => ['My ', 'password ', 'is ', undef],
        yet_another_claim => undef,
      },
    },
  },
  default_route       => { uri => "http://localhost:3000/frontend", enable_jwt => 0 },
  password_valid_days => 60,
  password_complexity => { min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0 }
};

subtest 'Test JWT injected if config says to' => sub {
  my $t = Test::Mojo->new('Gateway', $config);

  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  # test we get the login page form elements
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing')
    ->element_exists('[name=username]')->element_exists('[name=password]');

  $t->post_ok('/auth/login', form => { username => 'admin@test.com', password => 'testpass' })
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login OK');

  # test that the JWT was injected as spec'd in the config json
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)
    ->header_exists('Authorization', 'Authorization header present as expected')->header_is('location' => '/frontend')
    ->header_is('content_type' => 'application/json')->tap(sub ($t) {
    my $jwt = Mojo::JWT->new(secret => 'secret')->decode(
      do { my $val = $t->tx->res->headers->authorization; $val =~ s/Bearer\s//g; $val; }
    );
    return is($jwt->{ email }, 'admin@test.com');
    })

    # test undefs dont explode
    ->tap(sub ($t) {
    my $jwt = Mojo::JWT->new(secret => 'secret')->decode(
      do { my $val = $t->tx->res->headers->authorization; $val =~ s/Bearer\s//g; $val; }
    );
    return is($jwt->{ another_claim }, 'My password is ');
    })->tap(sub ($t) {
    my $jwt = Mojo::JWT->new(secret => 'secret')->decode(
      do { my $val = $t->tx->res->headers->authorization; $val =~ s/Bearer\s//g; $val; }
    );
    return is($jwt->{ yet_another_claim }, '');
    })

    # test we cant get sensitive fields out of the user record for injection
    ->tap(sub ($t) {
    my $jwt = Mojo::JWT->new(secret => 'secret')->decode(
      do { my $val = $t->tx->res->headers->authorization; $val =~ s/Bearer\s//g; $val; }
    );
    return is($jwt->{ other_claim }, 'My password is :password');
    })->tap(sub ($t) {
    my $jwt = Mojo::JWT->new(secret => 'secret')->decode(
      do { my $val = $t->tx->res->headers->authorization; $val =~ s/Bearer\s//g; $val; }
    );
    return is($jwt->{ user_id }, 'Myadmin@test.comhere');
    })
    # test my_id claim is integer type (not string)
    ->tap(sub ($t) {
    my $jwt = Mojo::JWT->new(secret => 'secret')->decode(
      do { my $val = $t->tx->res->headers->authorization; $val =~ s/Bearer\s//g; $val; }
    );
    return is($jwt->{ my_id }, 123456789) && ok(!($jwt->{ my_id } & ~$jwt->{ my_id }));
    })
    # test my_boolified_id claim is boolean type (not string)
    ->tap(sub ($t) {
    my $jwt = Mojo::JWT->new(secret => 'secret')->decode(
      do { my $val = $t->tx->res->headers->authorization; $val =~ s/Bearer\s//g; $val; }
    );
    return ok(to_json($jwt) =~ m/"my_boolified_id":true/);
    })
    # test flattened_id_str claim is string type, unaffected by any coercions (in this case boolean doesnt affect it)
    ->tap(sub ($t) {
    my $jwt = Mojo::JWT->new(secret => 'secret')->decode(
      do { my $val = $t->tx->res->headers->authorization; $val =~ s/Bearer\s//g; $val; }
    );
    return ok(to_json($jwt) =~ m/"flattened_id_str":"My admin\@test.com id"/);
    });

  # should be no JWT on the default route as spec'd in the config json
  $t->get_ok('/other-route')->status_is(Constants::HTTP_OK)
    ->header_exists_not('Authorization', 'Authorization header NOT present as expected');

  # should strip authorization header from ever getting to client - if provided in config (case insensitive)
  $t->app->config->{ strip_headers_to_client } = ['auTHORIZation'];

  # test that the JWT was injected as spec'd in the config json
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)
    ->header_exists_not('Authorization', 'Authorization header NOT present as commanded')
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

  $t->post_ok('/auth/login', form => { username => 'admin@test.com', password => 'testpass' })
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login OK');

  $t->ua->transactor->name("Chrome");
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->header_is('User-Agent' => 'Chrome', 'Test User Agent is intact');
};

subtest 'check that we can do response body transforms' => sub {
  my $mod_config = $config;
  $config->{ routes }->{ '/s' }->{ transforms }       = [{ action => { search => '.*', replace => "Mojo Rocks!" } }];
  $config->{ routes }->{ '/r' }->{ uri }              = "http://localhost:3000/frontend";
  $config->{ routes }->{ '/r' }->{ additional_paths } = ['/r/**'];
  $config->{ routes }->{ '/r' }->{ transforms }
    = [{ action => { search => '.*', replace => 'Mojo Web!' }, path => '/r' }];

  my $t = Test::Mojo->new('Gateway', $mod_config);

  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  # test we get the login page form elements
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing')
    ->element_exists('[name=username]')->element_exists('[name=password]');

  $t->post_ok('/auth/login', form => { username => 'admin@test.com', password => 'testpass' })
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login OK');

  # make sure we modified the body as specified for this route
  $t->get_ok('/s')->status_is(Constants::HTTP_OK)->content_is('Mojo Rocks!');
  
  # make sure we can do other body transforms that match 'addtional_paths'
  $t->get_ok('/r/index.js')->status_is(Constants::HTTP_OK)->content_is('Mojo Web!');
};

subtest 'check that we can do inbound request path rewrites' => sub {
  my $config2 = $config;
  $config2->{ routes }->{ '/ui/**' }->{ rewrite_path }->{ match } = "^/ui";
  $config2->{ routes }->{ '/ui/**' }->{ rewrite_path }->{ with }  = "";
  $config2->{ routes }->{ '/ui/**' }->{ requires_login }          = 0;
  $config2->{ routes }->{ '/ui/**' }->{ uri }                     = 'http://localhost:3000/frontend';
  my $t = Test::Mojo->new('Gateway', $config2);

  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  $t->get_ok('/ui/some-page')->status_is(Constants::HTTP_OK)->header_is('location' => '/frontend')
    ->header_is('orig_location' => 'http://localhost:3000/frontend/some-page');
};

subtest 'check that user provided Authorization header doesnt make it through the gateway with enable_jwt false' => sub {
  my $config2 = $config;
  $config2->{ routes }->{ '/ui/**' }->{ rewrite_path }->{ match } = "^/ui";
  $config2->{ routes }->{ '/ui/**' }->{ rewrite_path }->{ with }  = "";
  $config2->{ routes }->{ '/ui/**' }->{ enable_jwt }              = 0;
  $config2->{ routes }->{ '/ui/**' }->{ requires_login }          = 0;
  $config2->{ routes }->{ '/ui/**' }->{ uri }                     = 'http://localhost:3000/frontend';
  my $t = Test::Mojo->new('Gateway', $config2);

  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  $t->get_ok('/ui/some-page' => { Authorization => 'bogus'})->status_is(Constants::HTTP_OK)->header_exists_not('authorization', 'Header Existed');
};

subtest 'check that user provided Authorization header doesnt make it through the gateway with enable_jwt true' => sub {
  my $config2 = $config;
  $config2->{ routes }->{ '/ui/**' }->{ rewrite_path }->{ match } = "^/ui";
  $config2->{ routes }->{ '/ui/**' }->{ rewrite_path }->{ with }  = "";
  $config2->{ routes }->{ '/ui/**' }->{ enable_jwt }              = 1;
  $config2->{ routes }->{ '/ui/**' }->{ requires_login }          = 0;
  $config2->{ routes }->{ '/ui/**' }->{ uri }                     = 'http://localhost:3000/frontend';
  my $t = Test::Mojo->new('Gateway', $config2);

  $t->ua->max_redirects(3);

  # inject our mocked UserAgent class
  $t->app->proxy_service->ua(MockAgent->new);

  $t->get_ok('/ui/some-page' => { Authorization => 'bogus'})->status_is(Constants::HTTP_OK)
    ->header_exists('authorization', 'Header Existed')
    ->header_unlike('Authorization' => qr/blah/i, 'User provided header not present')
    ->header_like('Authorization' => qr/Bearer ey/i, 'Generated header present');
};

done_testing();
