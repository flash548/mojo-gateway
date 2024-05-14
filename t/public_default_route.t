use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Gateway;
use Constants;

subtest 'Test public user can access default route but not protected one' => sub {  

  # a configuration that has the default_route unprotected, publicly reachable
  my $t = Test::Mojo->new(
    'Gateway',
    { test       => 1,
      admin_user => 'admin@test.com',
      admin_pass => 'testpass',
      secret     => 'secret',
      jwt_secret => 'secret',
      routes     => {
        '/protected'      => {uri            => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1}
      },
      default_route       => {template_name => "default", requires_login => 0},
      password_valid_days => 60,
      password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
    }
  );
  $t->ua->max_redirects(3);
  $t->get_ok('/')->status_is(Constants::HTTP_OK)->content_like(qr/Landing Page/i, 'Landing Page Accessible Test');
  $t->get_ok('/protected')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Protected Route Login');
};

subtest 'Test public user can access blog route but not default one' => sub {  

  # a configuration that has the default_route unprotected, publicly reachable
  my $t = Test::Mojo->new(
    'Gateway',
    { test       => 1,
      admin_user => 'admin@test.com',
      admin_pass => 'testpass',
      secret     => 'secret',
      jwt_secret => 'secret',
      routes     => {
        '/blog'      => {template_name            => "default", enable_jwt => 1, requires_login => 0}
      },
      default_route       => {template_name => "default", requires_login => 1},
      password_valid_days => 60,
      password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
    }
  );
  $t->ua->max_redirects(3);
  $t->get_ok('/blog')->status_is(Constants::HTTP_OK)->content_like(qr/Landing Page/i, 'Blog Page Accessible Test');
  $t->get_ok('/')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Protected Route Login');
};

subtest 'Test still allows manually specifying the "/" route as public' => sub {  

  # a configuration that has the default_route unprotected, publicly reachable
  my $t = Test::Mojo->new(
    'Gateway',
    { test       => 1,
      admin_user => 'admin@test.com',
      admin_pass => 'testpass',
      secret     => 'secret',
      jwt_secret => 'secret',
      routes     => {
        '/' => { template_name => "default", requires_login => 0 },
        '/blog'      => {template_name            => "default", enable_jwt => 1, requires_login => 0}
      },
      default_route       => {template_name => "default", requires_login => 1},
      password_valid_days => 60,
      password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
    }
  );
  $t->ua->max_redirects(3);
  $t->get_ok('/blog')->status_is(Constants::HTTP_OK)->content_like(qr/Landing Page/i, 'Blog Page Accessible Test');
  $t->get_ok('/')->status_is(Constants::HTTP_OK)->content_like(qr/Landing Page/i, 'Blog Page Accessible Test');
  $t->get_ok('/something-else')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Protected Route Login');
};

subtest 'Test still allows manually specifying the "/" route as secured' => sub {  

  # a configuration that has the default_route unprotected, publicly reachable
  my $t = Test::Mojo->new(
    'Gateway',
    { test       => 1,
      admin_user => 'admin@test.com',
      admin_pass => 'testpass',
      secret     => 'secret',
      jwt_secret => 'secret',
      routes     => {
        '/' => { template_name => "default", requires_login => 1 },
        '/blog'      => {template_name            => "default", enable_jwt => 1, requires_login => 0}
      },
      default_route       => {template_name => "default", requires_login => 1},
      password_valid_days => 60,
      password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
    }
  );
  $t->ua->max_redirects(3);
  $t->get_ok('/blog')->status_is(Constants::HTTP_OK)->content_like(qr/Landing Page/i, 'Blog Page Accessible Test');
  $t->get_ok('/something-else')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Protected Route Login');
  $t->get_ok('/')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Protected Route Login');
};

done_testing();
