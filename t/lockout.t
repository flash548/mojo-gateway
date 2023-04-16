use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Gateway;
use Constants;

# Tests the account lockout feature

sub init_server {
  my $options = {
    test       => 1,
    max_login_attempts => 3,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => {uri            => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api'      => {uri            => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };
  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  return $t;
}

subtest 'Check locks out account on set number of max attempts' => sub {
  
  my $t = init_server();

  # lockout the admin account
  # do a bad login and we get error message
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => ''})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/ Login failed: User or password incorrect!/, 'Make sure we get error message on bad login 1');
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => ''})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/ Login failed: User or password incorrect!/, 'Make sure we get error message on bad login 2');
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => ''})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/ Login failed: This account is locked!/, 'Make sure we get error message we are locked out');

};

subtest 'Check locks clears bad attempts after successful login' => sub {
  
  my $t = init_server();

  ok !$t->app->db_conn->db->select('users', undef, { email => 'admin@test.com' })->hash->{bad_attempts};
  
  # lockout the admin account
  # do a bad login and we get error message
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => ''})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/ Login failed: User or password incorrect!/, 'Make sure we get error message on bad login 1');
    ok $t->app->db_conn->db->select('users', undef, { email => 'admin@test.com' })->hash->{bad_attempts} == 1;
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => ''})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/ Login failed: User or password incorrect!/, 'Make sure we get error message on bad login 2');

  ok $t->app->db_conn->db->select('users', undef, { email => 'admin@test.com' })->hash->{bad_attempts} == 2;

  # login success this time
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)
    ->content_unlike(qr/ Login failed: User or password incorrect!/, 'Login');

  # check that the bad attempts resets
  ok $t->app->db_conn->db->select('users', undef, { email => 'admin@test.com' })->hash->{bad_attempts} == 0;


};

subtest 'Test that account can be administratively locked' => sub {

  my $t = init_server();
  ok !$t->app->db_conn->db->select('users', undef, { email => 'admin@test.com' })->hash->{bad_attempts};

  # login successfully
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)
    ->content_unlike(qr/ Login failed: User or password incorrect!/, 'Login');
  
  # verify bad attempts are zero
  ok !$t->app->db_conn->db->select('users', undef, { email => 'admin@test.com' })->hash->{bad_attempts};

  # check we can access a protected route
  $t->get_ok('/')->content_like(qr/Whoa/);

  # lock the account manually
  $t->app->db_conn->db->update('users', { locked => 1 }, { email => 'admin@test.com' });

  # verify no access
  $t->get_ok('/admin')
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/account is locked/i);

  # unlock the account manually 
  $t->app->db_conn->db->update('users', { locked => 0 }, { email => 'admin@test.com' });

  # verify access
  $t->get_ok('/admin')
    ->status_is(Constants::HTTP_OK)
    ->content_unlike(qr/account is locked/i);

};

subtest 'Test that bad attempts are cleared out on an admin-resetting action' => sub {
  my $t = init_server();
  ok !$t->app->db_conn->db->select('users', undef, { email => 'admin@test.com' })->hash->{bad_attempts};

  # login successfully
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)
    ->content_unlike(qr/ Login failed: User or password incorrect!/, 'Login');

  # add non-admin-user
  $t->post_ok('/admin/users',
    json => {email => 'dude2@test.com', password => 'dude2!', reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_CREATED);

  # logout admin
  $t->get_ok('/logout');

  # login wrong as new user
  $t->post_ok('/auth/login', form => {username => 'dude2@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/ Login failed: User or password incorrect!/, 'Login');

  # login wrong as new user again
  $t->post_ok('/auth/login', form => {username => 'dude2@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/ Login failed: User or password incorrect!/, 'Login');

  # login wrong as new user again - locked
  $t->post_ok('/auth/login', form => {username => 'dude2@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/account is locked/i, 'Login');

  # verify that our dude account is locked with 3 bad attemps
  my $acct = $t->app->db_conn->db->select('users', undef, { email => 'dude2@test.com'})->hash;
  ok $acct->{locked};
  ok $acct->{bad_attempts} == 3;

  # login as admin
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)
    ->content_unlike(qr/ Login failed: User or password incorrect!/, 'Login');

  $acct->{locked} = 0;
  delete $acct->{password};

  # update user with acct unlocked
  $t->put_ok('/admin/users', json => $acct )
    ->status_is(Constants::HTTP_OK);

  $acct = $t->app->db_conn->db->select('users', undef, { email => 'dude2@test.com'});
  ok !$acct->{locked};
  ok !$acct->{bad_attempts};
};

done_testing();