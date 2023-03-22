use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Gateway;
use Constants;

#################################
# Main Test for the Application
# Integration style tests in this file
#################################

# init our application and set up our test client to be
# like the browser (where we'll follow re-directs)
my $t = Test::Mojo->new(
  'Gateway',
  { test       => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret     => 'secret',
    jwt_secret => 'secret',
    routes     => {
      '/'         => {uri            => "http://localhost:8080/frontend", enable_jwt => 1, requires_login => 1},
      '/everyone' => {requires_login => 0, uri => "http://localhost:8080/everyone"},
      '/api'      => {uri            => "http://localhost:8080/api", enable_jwt => 1, requires_login => 1}
    },
    default_route       => {uri => 'https://localhost:8080/frontend', requires_login => 1},
    password_valid_days => 60,
    password_complexity => {min_length => 8, alphas => 1, numbers => 1, specials => 1, spaces => 0}
  }
);
$t->ua->max_redirects(3);

subtest 'Test User Login/Logout/Admin operations' => sub {

  # for our two routes in the config above.....
  # test that we need to authenticate for them - we get redirect to the login
  $t->get_ok('/')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing 1');
  $t->get_ok('/api')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing 2');

  # test we get the login page form elements
  $t->get_ok('/api')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing 3')
    ->element_exists('[name=username]')->element_exists('[name=password]');

  # do a login and we dont get the login form anymore
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Make sure we are not at the login page anymore');

  # since we're an admin we should get the admin page at /admin
  $t->get_ok('/admin')->status_is(Constants::HTTP_OK)->content_like(qr/Admin/, 'Make sure we are at the Admin page');

  # test we get the "Whoa!!" error page since we have no server to proxy to
  $t->get_ok('/api')->status_is(Constants::HTTP_OK)->content_like(qr/Whoa/i, 'Test Routing Failed 1');
  $t->get_ok('/')->status_is(Constants::HTTP_OK)->content_like(qr/Whoa/i, 'Test Routing Failed 2');

  # test logout
  $t->get_ok('/logout')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Logout');

  # test that we really are logged out
  $t->get_ok('/')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing 4');
  $t->get_ok('/api')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing 5');
  $t->get_ok('/admin')->status_is(Constants::HTTP_OK)->content_like(qr/login/i, 'Test Login screen landing 6');

# log back in - should land at the admin page since thats what we last tried to get to
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/Admin/i, 'Log Back In Successfully - Land at Admin Page');

# make a new, non-admin user via API call with expired password (as the admin interface would do)
# in the admin interface we dont enforce password complexity
# return should be the new user record with expected fields - WITHOUT the password field hash
  $t->post_ok('/admin/users',
    json => {email => 'test@test.com', password => 'password', reset_password => 1, is_admin => 0,})
    ->status_is(Constants::HTTP_CREATED)->json_has('/email')->json_has('/user_id')->json_has('/is_admin')
    ->json_has('/reset_password')->json_has('/last_reset')->json_has('/last_login')->json_hasnt('/password');

  # try to add them again and get a 409 (already exists)
  $t->post_ok('/admin/users', json => {email => 'test@test.com', password => 'password', is_admin => 0,})
    ->status_is(Constants::HTTP_CONFLICT);

# try to add then again, but in CAPS, to prove we're case insensitive (409 still)
# try to add them again and get a 409 (already exists)
  $t->post_ok('/admin/users', json => {email => 'TEST@test.com', password => 'password', is_admin => 0,})
    ->status_is(Constants::HTTP_CONFLICT);

  # admin logout
  $t->get_ok('/logout')->status_is(Constants::HTTP_OK);

  # login as the test user, get forwarded to the password change screen
  $t->post_ok('/auth/login', form => {username => 'test@test.com', password => 'password'})
    ->status_is(Constants::HTTP_OK)->element_exists('[name=current-password]')->element_exists('[name=new-password]')
    ->element_exists('[name=retyped-new-password]')
    ->content_like(qr/Change/i, 'Log Back In - Get Force password change screen');

  # change password - provide missing/blank field - fails with error
  $t->post_ok('/auth/password/change', form => {'current-password' => 'blah', 'new-password' => 'blah2',})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/Password Change Failed: Required fields not/, 'Missing re-typed field');

  # change password - provide bad existing one - fails with error
  $t->post_ok('/auth/password/change',
    form => {'current-password' => 'blah', 'new-password' => 'blah2', 'retyped-new-password' => 'blah2'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/Password Change Failed: Existing/, 'Existing Password was wrong');

  # change password - provide mistype existing as the new - fails with error
  $t->post_ok('/auth/password/change',
    form => {'current-password' => 'password', 'new-password' => 'password', 'retyped-new-password' => 'blah3'})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/Password Change Failed: New Password cannot equal the existing password/,
    'New Password cant be existing');

  # change password - provide new and re-typed not equal - fails with error
  $t->post_ok('/auth/password/change',
    form => {'current-password' => 'password', 'new-password' => 'blah2', 'retyped-new-password' => 'blah3'})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/Password Change Failed: New Password does not equal Retyped New Password/,
    'New Password not equal to re-typed variant');

  # change password - new password doesnt meet complexity - fails with error
  $t->post_ok('/auth/password/change',
    form => {'current-password' => 'password', 'new-password' => 'blah2', 'retyped-new-password' => 'blah2'})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/Password Change Failed: New Password does not meet complexity requirements/,
    'New Password doesnt meet complexity');

  # change password - passwords pure whitespace - fails with error
  $t->post_ok('/auth/password/change',
    form => {'current-password' => 'password', 'new-password' => '  ', 'retyped-new-password' => '  '})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/Password Change Failed: Passwords cannot be whitespace/, 'Passwords cannot be whitespace');

  # change password - non-ascii characters - fails with error
  $t->post_ok(
    '/auth/password/change',
    form => {
      'current-password'     => 'password',
      'new-password'         => "password!\0-2world",
      'retyped-new-password' => "password!\0-2world"
    }
  )->status_is(Constants::HTTP_OK)
    ->content_like(qr/Password Change Failed: Passwords cannot contain non-ascii characters/,
    'Passwords cannot contain non-ascii characters');

  # change password - non-ascii characters - fails with error
  $t->post_ok(
    '/auth/password/change',
    form => {
      'current-password'     => 'password',
      'new-password'         => 'password!✅2world',
      'retyped-new-password' => 'password!✅2world'
    }
  )->status_is(Constants::HTTP_OK)
    ->content_like(qr/Password Change Failed: Passwords cannot contain non-ascii characters/,
    'Passwords cannot contain non-ascii characters');

  # change password - over 255 chars - fails with error
  $t->post_ok('/auth/password/change',
    form => {'current-password' => 'password', 'new-password' => 'p' x 256, 'retyped-new-password' => 'p' x 256})
    ->status_is(Constants::HTTP_OK)
    ->content_like(qr/Password Change Failed: Passwords cannot exceed 255 chars/, 'Passwords cannot exceed 255 chars');

  # change password, get re-directed back to root route upon success
  $t->post_ok('/auth/password/change',
    form => {'current-password' => 'password', 'new-password' => 'blah234!', 'retyped-new-password' => 'blah234!'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/Whoa/, 'Password Change OK - Re-directs to root route');

  # check that non-admin's can't access the admin interface
  $t->get_ok('/admin')->status_is(Constants::HTTP_FORBIDDEN, 'Non-Admins cant access the Admin interface');

  # check that non-admin's can't access the admin API either
  $t->get_ok('/admin/users')->status_is(Constants::HTTP_FORBIDDEN, 'Non-admins cant access Admin API');

  # log the user out
  $t->get_ok('/logout')->status_is(Constants::HTTP_OK)->content_like(qr/Login/i);

  # login as admin to expire the user's password via date
  $t->get_ok('/admin')->status_is(Constants::HTTP_OK)->content_like(qr/Login/i);

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/Admin/, 'Make sure we are not at the login page anymore');

  $t->put_ok('/admin/users', json => {email => 'test@test.com', user_id => '222222', callsign => 'japh'})
    ->status_is(Constants::HTTP_OK)->json_is('/email' => 'test@test.com')->json_is('/user_id' => 222222)
    ->json_is('/is_admin' => 0)->json_is('/reset_password' => 0)
    ->json_unlike('/last_reset' => qr/2022-01-01T00:00:00Z/)->json_hasnt('/callsign')->json_hasnt('/password');

  # expire it manually
  $t->app->db_conn->db->update("users", {last_reset => "2022-01-01T00:00:00Z"}, {email => "test\@test.com"});

  # logout the admin
  $t->get_ok('/logout')->status_is(Constants::HTTP_OK)->content_like(qr/Login/i);

  # login as the user - should get expired password / change screen
  $t->post_ok('/auth/login', form => {username => 'test@test.com', password => 'blah234!'})
    ->status_is(Constants::HTTP_OK)->element_exists('[name=current-password]')->element_exists('[name=new-password]')
    ->element_exists('[name=retyped-new-password]')
    ->content_like(qr/Change/i, 'Log Back In - Get Force password change screen again');

  # logout and log back in as admin
  $t->get_ok('/logout')->status_is(Constants::HTTP_OK);
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK);

  $t->delete_ok('/admin/users')->status_is(Constants::HTTP_BAD_REQUEST, 'Bad request');
  $t->delete_ok('/admin/users?email=test2@test.com')->status_is(Constants::HTTP_NOT_FOUND, 'Bogus user delete');
  $t->delete_ok('/admin/users?email=test@test.com')->status_is(Constants::HTTP_OK, 'Successfully deleted user');

  # trust but verify user deleted
  $t->get_ok('/admin/users')->status_is(Constants::HTTP_OK)
    ->content_unlike(qr/test\@test.com/, 'No more test@test.com user');
};

subtest 'Test user account updates cannot modify read-only fields' => sub {

  # do a login and we dont get the login form anymore
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login as user');

  my ($last_login, $last_reset);

  # get current reset date and last_login
  $t->get_ok('/admin/users?email=admin@test.com')->status_is(Constants::HTTP_OK)->tap(sub ($t) {
    $last_login = $t->tx->res->json->{last_login};
    $last_reset = $t->tx->res->json->{last_reset};
  });

# post an update to self as admin to try to changed the last_reset and last_login fields
  $t->put_ok('/admin/users', json => {email => 'admin@test.com', last_reset => '2022-08-01T12:00:00Z'})
    ->status_is(Constants::HTTP_OK);

  # check the read-only fields are not changed
  $t->get_ok('/admin/users?email=admin@test.com')->status_is(Constants::HTTP_OK)
    ->json_is('/last_reset', $last_reset, 'Last Reset field is unchanged')
    ->json_is('/last_login', $last_login, 'Last Login field is unchanged');

# logout and login again to prove we didn't change password since we didn't include the field
  $t->get_ok('/logout');
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login as user');
  $t->get_ok('/logout')->status_is(Constants::HTTP_OK);
};

subtest 'Test Extra Fields cannot be added to user objects' => sub {
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login as admin user');

  # try to add a user with extra fields
  $t->post_ok('/admin/users',
    json =>
      {email => 'dude@test.com', password => 'dude2!', reset_password => 1, is_admin => 0, other_field => 'hacker'})
    ->status_is(Constants::HTTP_CREATED)->json_hasnt('/other_field');

  $t->get_ok('/logout')->status_is(Constants::HTTP_OK);
};

subtest 'Test that routes not requiring authentication work without logging in' => sub {

  # make sure we're logged out to prevent false positives
  $t->get_ok('/logout')->status_is(Constants::HTTP_OK);

  $t->get_ok('/everyone')->status_is(Constants::HTTP_OK)->content_like(qr/Whoa/, 'Can go right to the public routes');

  # should get the login page
  $t->get_ok('/api')->status_is(Constants::HTTP_OK)->content_unlike(qr/Whoa/, 'Protected routes are still protected');
};

subtest 'Test that other users cant change other users passwords' => sub {

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login as admin user');

  # add non-admin-user
  $t->post_ok('/admin/users',
    json => {email => 'dude2@test.com', password => 'dude2!', reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_CREATED);

  # add non-admin-user
  $t->post_ok('/admin/users',
    json => {email => 'dude3@test.com', password => 'dude3!', reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_CREATED);

  # logout admin
  $t->get_ok('/logout')->status_is(Constants::HTTP_OK);

  # login as a non-admin
  $t->post_ok('/auth/login', form => {username => 'dude2@test.com', password => 'dude2!'})
    ->status_is(Constants::HTTP_OK)->content_like(qr/Whoa/, 'Non-admin logged in');

  # test gets 403 when doing it via API
  $t->put_ok('/admin/users', json => {email => 'admin@test.com', password => 'hacked'})
    ->status_is(Constants::HTTP_FORBIDDEN);
};

subtest 'Test malformed user object is caught' => sub {
  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login as admin user');

  # add non-admin-user - bad email
  $t->post_ok('/admin/users', json => {email => ' ', password => 'dude2!', reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_BAD_REQUEST);

  # add non-admin-user - bad password
  $t->post_ok('/admin/users',
    json => {email => 'newuser@test.com', password => ' ', reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_BAD_REQUEST);

  # add non-admin-user - bad username
  $t->post_ok('/admin/users', json => {email => "\0", password => ' ', reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_BAD_REQUEST);

  # add non-admin-user - bad username
  $t->post_ok('/admin/users', json => {email => "\n", password => ' ', reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_BAD_REQUEST);

  # add non-admin-user - bad username (not an email)
  $t->post_ok('/admin/users',
    json => {email => 'somedude', password => 'legit password', reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_BAD_REQUEST);

  # add non-admin-user - nulchar
  $t->post_ok('/admin/users',
    json => {email => "some\0dude\@test.com", password => 'legit password', reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_BAD_REQUEST);

  # add non-admin-user - nulchar
  $t->post_ok('/admin/users',
    json => {email => "somedude\@test2.com", password => "legit\0password", reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_BAD_REQUEST);

  # add non-admin-user - unicode disallowed
  $t->post_ok('/admin/users',
    json => {email => "somedude\@test2.com", password => "legit✅password", reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_BAD_REQUEST);

  # add non-admin-user - pass over 255 chars
  $t->post_ok('/admin/users',
    json => {email => "somedude\@test2.com", password => "l!221q" . "w" x 250, reset_password => 0, is_admin => 0})
    ->status_is(Constants::HTTP_BAD_REQUEST);
};

done_testing();
