use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Gateway;
use Constants;

subtest 'Test inline templates work' => sub {  

  # a configuration that has the default_route unprotected, publicly reachable
  my $t = Test::Mojo->new(
    'Gateway',
    { test       => 1,
      admin_user => 'admin@test.com',
      admin_pass => 'testpass',
      secret     => 'secret',
      jwt_secret => 'secret',
      routes     => {
        '/somewhere'      => {template_name => "inline: <html>INLINE TEMPLATE</html>", requires_login => 0}
      },
      default_route       => {template_name => "default", requires_login => 0},
      password_valid_days => 60,
      password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
    }
  );
  $t->ua->max_redirects(3);
  $t->get_ok('/somewhere')->status_is(Constants::HTTP_OK)->content_like(qr/INLINE TEMPLATE/, 'Inline Template Test');
};

done_testing();