use Mojolicious;
use Mojo::Collection;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Gateway;
use Constants;


# Tests various MFA feature

subtest 'Check cannot navigate to the MFA endpoints without being signed in' => sub {
  my $options = {
    test       => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'    => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api' => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  $t->get_ok('/auth/mfa/init')->content_like(qr/Login/, 'Cannot get to the MFA init page - 1');
  $t->post_ok('/auth/mfa/init')->content_like(qr/Login/, 'Cannot get to the MFA init page - 2');
  $t->get_ok('/auth/mfa/entry')->content_like(qr/Login/, 'Cannot get to the MFA entry page - 2');
  $t->post_ok('/auth/mfa/entry')->content_like(qr/Login/, 'Cannot get to the MFA entry page - 2');
};

subtest 'Check cannot navigate to the MFA endpoints when being signed in' => sub {
  my $options = {
    test       => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'    => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api' => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Admin Login');

  $t->get_ok('/auth/mfa/init')
    ->content_like(qr/This is a restricted page/, 'Logged in - Cannot get to the MFA init page - 1');
  $t->post_ok('/auth/mfa/init')
    ->content_like(qr/This is a restricted page/, 'Logged in - Cannot get to the MFA init page - 2');
  $t->get_ok('/auth/mfa/entry')
    ->content_like(qr/This is a restricted page/, 'Logged in - Cannot get to the MFA entry page - 1');
  $t->post_ok('/auth/mfa/entry')
    ->content_like(qr/This is a restricted page/, 'Logged in - Cannot get to the MFA entry page - 2');
};

subtest 'Test MFA does not work unless secret/key_id/issuer set' => sub {
  my $options = {
    test       => 1,
    mfa_secret => 'secret',
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'    => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api' => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  eval { Test::Mojo->new('Gateway', $options); };

  ok $@, 'Test that App failed to launch with invalid MFA params';
};

subtest 'Test user forced to enroll into the MFA when all users forced' => sub {
  my $options = {
    test             => 1,
    mfa_secret       => 'secret',
    mfa_issuer       => 'mojo',
    mfa_key_id       => 'login',
    mfa_force_on_all => 1,
    admin_user       => 'admin@test.com',
    admin_pass       => 'testpass',
    secret           => 'secret',
    jwt_secret       => 'secret',
    routes           => {
      '/'    => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api' => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/MFA/i, 'Check MFA Enrollment');

  $t->post_ok('/auth/mfa/init')->content_like(qr/Whoa/, 'Check done with MFA enrollment and back to requested page');

  # now logout
  $t->get_ok('/logout');

  # login again, should get to the MFA entry page
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/MFA/i, 'Enter MFA Code screen');

  # cheat and set the secret
  $t->app->db_conn->db->update('users', {mfa_secret => 'zhnkr4uxdpkw4z5y'});

  # enter the code for secret(zhnkr4uxdpkw4z5y)
  use Auth::GoogleAuth;
  my $auth = Auth::GoogleAuth->new({secret => 'secret', issuer => 'mojo_gateway', key_id => 'login',});
  $auth->secret32('zhnkr4uxdpkw4z5y');
  my $code = $auth->code;
  $t->post_ok('/auth/mfa/entry' => form => {'mfa-entry' => $code})->content_unlike(qr/MFA/);

  # check that user no longer has MFA screen when disenrolled from MFA
  $t->get_ok('/logout');

  # cheat and unset the MFA
  $t->app->db_conn->db->update('users', {is_mfa => 0});

  # login again, should NOT get to the MFA entry page
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/MFA/i, 'No MFA Code screen');

  # our secret should also have been wiped out just by logging in
  ok !defined(($t->app->db_conn->db->select('users', undef, {email => 'admin@test.com'})->hashes->[0]->{mfa_secret}));

};

subtest 'Test that user secret is undef-d on user PUT from API' => sub {
  my $options = {
    test             => 1,
    mfa_secret       => 'secret',
    mfa_issuer       => 'mojo',
    mfa_key_id       => 'login',
    mfa_force_on_all => 0,
    admin_user       => 'admin@test.com',
    admin_pass       => 'testpass',
    secret           => 'secret',
    jwt_secret       => 'secret',
    routes           => {
      '/'    => {uri => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/api' => {uri => "http://localhost:8080/api",      enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  };

  my $t = Test::Mojo->new('Gateway', $options);
  $t->ua->max_redirects(3);

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/MFA/i, 'Should not get MFA Enrollment');

  # create new user - check return data - check does NOT have the mfa secret in it
  $t->post_ok('/admin/users',
    json => {email => 'test-perler@test.com', password => 'password', reset_password => 0, is_mfa => 1, is_admin => 0,})
    ->status_is(Constants::HTTP_CREATED)->json_like('/is_mfa' => qr/1/)->json_hasnt('/password')
    ->json_hasnt('/mfa_secret');

  # check that the MFA flag was set for next login enrollment
  ok($t->app->db_conn->db->select('users', undef, {email => 'test-perler@test.com'})->hashes->[0]->{is_mfa});

  # secret should still not be populated yet
  ok !
    defined($t->app->db_conn->db->select('users', undef, {email => 'test-perler@test.com'})->hashes->[0]->{mfa_secret});

  # logout admin
  $t->get_ok('/logout');

  # login as new user and do MFA enrollment
  $t->post_ok('/auth/login', form => {username => 'test-perler@test.com', password => 'password'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/MFA/i, 'Should get MFA Enrollment');

  # pretend we scanned our QR code
  $t->post_ok('/auth/mfa/init');

  # test that the secret was populated in the database
  ok
    defined($t->app->db_conn->db->select('users', undef, {email => 'test-perler@test.com'})->hashes->[0]->{mfa_secret});

  # cheat and overwrite/set the secret
  $t->app->db_conn->db->update('users', {mfa_secret => 'zhnkr4uxdpkw4z5y'});

  # enter the code for secret(zhnkr4uxdpkw4z5y)
  use Auth::GoogleAuth;
  my $auth = Auth::GoogleAuth->new({secret => 'secret', issuer => 'mojo_gateway', key_id => 'login',});
  $auth->secret32('zhnkr4uxdpkw4z5y');
  my $code = $auth->code;
  $t->post_ok('/auth/mfa/entry' => form => {'mfa-entry' => $code})->content_unlike(qr/MFA/);

  # logout
  $t->get_ok('/logout');

  # login as admin
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/MFA/i, 'Admin login');

  # check user get ALL return doesn't have mfa_secret in it or password
  my $users_all = $t->app->db_conn->db->select('users')->hashes;
  for (my $i = 0; $i < $users_all->size; $i++) {
    $t->get_ok('/admin/users?id=' . $users_all->[$i]->{id})->status_is(Constants::HTTP_OK)->json_hasnt("/mfa_secret")
      ->json_hasnt("/password");
  }

  $t->get_ok('/admin/users')->status_is(Constants::HTTP_OK);
  my $users = Mojo::Collection->new($t->tx->res->json->{results})->flatten;
  my $id = $users->first(sub { $_->{email} eq 'test-perler@test.com'})->{id};

  # check user get return doesn't have mfa_secret in it or password
  $t->get_ok('/admin/users?id=' . $id)->status_is(Constants::HTTP_OK)->json_hasnt('/mfa_secret')
    ->json_hasnt('/password');

  # login as admin and PUT update test-perler's account to not be MFA anymore
  $t->put_ok('/admin/users' => json => {id => $id, email => 'test-perler@test.com', is_mfa => 0, is_admin => 0,})
    ->status_is(Constants::HTTP_OK)->json_hasnt('/mfa_secret')->json_hasnt('/password');

  # test the database secret is gone
  ok !
    defined($t->app->db_conn->db->select('users', undef, {email => 'test-perler@test.com'})->hashes->[0]->{mfa_secret});

  # logout admin
  $t->get_ok('/logout');

  # login as test-perler and NO MFA
  $t->post_ok('/auth/login', form => {username => 'test-perler@test.com', password => 'password'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/MFA/i, 'Should NOT get MFA screen');

};

done_testing();
