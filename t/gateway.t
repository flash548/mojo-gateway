use Mojolicious::Lite;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;

#################################
# Main Test for the Application #
#################################


# init our application and set up our test client to be
# like the browser (where we'll follow re-directs)
my $t = Test::Mojo->new(Mojo::File->new('./gateway.pl'), { 
    test => 1,
    admin_user => 'admin@test.com',
    admin_pass => 'testpass',
    secret => 'secret',
    jwt_secret => 'secret',
    routes => {
      '/' => {
        uri => "http://localhost:8080/frontend",
        enable_jwt => 1
      },
      '/api' => {
        uri => "http://localhost:8080/api",
        enable_jwt => 1
      }
    },
    password_valid_days => 60,
    password_complexity => {
      min_length => 8,
      alphas => 1,
      numbers => 1,
      specials => 1,
      spaces => 0
  }
});
$t->ua->max_redirects(3);

# for our two routes in the config above.....
# test that we need to authenticate for them - we get redirect to the login
$t->get_ok('/')
  ->status_is(200)
  ->content_like(qr/login/i, 'Test Login screen landing 1');
$t->get_ok('/api')
  ->status_is(200)
  ->content_like(qr/login/i, 'Test Login screen landing 2');

# test we get the login page form elements
$t->get_ok('/api')
  ->status_is(200)
  ->content_like(qr/login/i, 'Test Login screen landing 3')
  ->element_exists('[name=username]')
  ->element_exists('[name=password]');

# do a login and we dont get the login form anymore
$t->post_ok('/auth/login', form => { username => 'admin@test.com', password => 'testpass' })
  ->status_is(200)
  ->content_unlike(qr/login/i, 'Make sure we are not at the login page anymore');

# since we're an admin we should get the admin page at /admin
$t->get_ok('/admin')
  ->status_is(200)
  ->content_like(qr/Admin/, 'Make sure we are at the Admin page');

# test we get the "Whoa!!" error page since we have no server to proxy to
$t->get_ok('/api')
  ->status_is(200)
  ->content_like(qr/Whoa/i, 'Test Routing Failed 1');
$t->get_ok('/')
  ->status_is(200)
  ->content_like(qr/Whoa/i, 'Test Routing Failed 2');

# test logout
$t->get_ok('/logout')
  ->status_is(200)
  ->content_like(qr/login/i, 'Test Logout');

# test that we really are logged out
$t->get_ok('/')
  ->status_is(200)
  ->content_like(qr/login/i, 'Test Login screen landing 4');
$t->get_ok('/api')
  ->status_is(200)
  ->content_like(qr/login/i, 'Test Login screen landing 5');
$t->get_ok('/admin')
  ->status_is(200)
  ->content_like(qr/login/i, 'Test Login screen landing 6');

# log back in - should land at the admin page since thats what we last tried to get to
$t->post_ok('/auth/login', form => { username => 'admin@test.com', password => 'testpass' })
  ->status_is(200)
  ->content_like(qr/Admin/i, 'Log Back In Successfully - Land at Admin Page');

# make a new, non-admin user via API call with expired password (as the admin interface would do)
# in the admin interface we dont enforce password complexity
# return should be the new user record with expected fields - WITHOUT the password field hash
$t->post_ok('/admin/users', json => { email => 'test@test.com', password => 'password', reset_password => 1, is_admin => 0, })
  ->status_is(201)
  ->json_has('/email')
  ->json_has('/dod_id')
  ->json_has('/is_admin')
  ->json_has('/reset_password')
  ->json_has('/last_reset')
  ->json_has('/last_login')
  ->json_hasnt('/password');


# try to add them again and get a 409 (already exists)
$t->post_ok('/admin/users', json => { email => 'test@test.com', password => 'password', is_admin => 0, })
  ->status_is(409);

# try to add then again, but in CAPS, to prove we're case insensitive (409 still)
# try to add them again and get a 409 (already exists)
$t->post_ok('/admin/users', json => { email => 'TEST@test.com', password => 'password', is_admin => 0, })
  ->status_is(409);

# admin logout
$t->get_ok('/logout')
  ->status_is(200);

# login as the test user, get forwarded to the password change screen
$t->post_ok('/auth/login', form => { username => 'test@test.com', password => 'password' })
  ->status_is(200)
  ->element_exists('[name=current-password]')
  ->element_exists('[name=new-password]')
  ->element_exists('[name=retyped-new-password]')
  ->content_like(qr/Change/i, 'Log Back In - Get Force password change screen');

# change password - provide bad existing one - fails with error
$t->post_ok('/auth/password/change', form => { 'current-password' => 'blah', 'new-password' => 'blah2', 'retyped-new-password' => 'blah2' })
  ->status_is(200)
  ->content_like(qr/Password Change Failed: Existing/, 'Existing Password was wrong');

# change password - provide mistype existing as the new - fails with error
$t->post_ok('/auth/password/change', form => { 'current-password' => 'password', 'new-password' => 'password', 'retyped-new-password' => 'blah3' })
  ->status_is(200)
  ->content_like(qr/Password Change Failed: New Password cannot equal the existing password/, 'New Password cant be existing');

# change password - provide new and re-typed not equal - fails with error
$t->post_ok('/auth/password/change', form => { 'current-password' => 'password', 'new-password' => 'blah2', 'retyped-new-password' => 'blah3' })
  ->status_is(200)
  ->content_like(qr/Password Change Failed: New Password does not equal Retyped New Password/, 'New Password not equal to re-typed variant');

# change password - new password doesnt meet complexity - fails with error
$t->post_ok('/auth/password/change', form => { 'current-password' => 'password', 'new-password' => 'blah2', 'retyped-new-password' => 'blah2' })
  ->status_is(200)
  ->content_like(qr/Password Change Failed: New Password does not meet complexity requirements/, 'New Password doesnt meet complexity');

# change password, get re-directed back to root route upon success
$t->post_ok('/auth/password/change', form => { 'current-password' => 'password', 'new-password' => 'blah234!', 'retyped-new-password' => 'blah234!' })
  ->status_is(200)
  ->content_like(qr/Whoa/, 'Password Change OK - Re-directs to root route');

# check that non-admin's can't access the admin interface
$t->get_ok('/admin')
  ->status_is(200)
  ->content_like(qr/Whoa/, 'Non-Admins cant access the Admin interface');

# check that non-admin's can't access the admin API either
$t->get_ok('/users')
  ->status_is(403, 'Non-admins cant access Admin API');

# log the user out
$t->get_ok('/logout')
  ->status_is(200)
  ->content_like(qr/Login/i);

# login as admin to expire the user's password via date
$t->get_ok('/admin')
  ->status_is(200)
  ->content_like(qr/Login/i);

$t->post_ok('/auth/login', form => { username => 'admin@test.com', password => 'testpass' })
  ->status_is(200)
  ->content_like(qr/Admin/, 'Make sure we are not at the login page anymore');

$t->put_ok('/admin/users', json => { email => 'test@test.com', last_reset => '2022-01-01T00:00:00Z'})
  ->status_is(200)
  ->json_is('/email' => 'test@test.com')
  ->json_is('/dod_id' => undef)
  ->json_is('/is_admin' => 0)
  ->json_is('/reset_password' => 0)
  ->json_is('/last_reset' => '2022-01-01T00:00:00Z')
  ->json_hasnt('/password');

# logout the admin
$t->get_ok('/logout')
  ->status_is(200)
  ->content_like(qr/Login/i);

# login as the user - should get expired password / change screen
$t->post_ok('/auth/login', form => { username => 'test@test.com', password => 'blah234!' })
  ->status_is(200)
  ->element_exists('[name=current-password]')
  ->element_exists('[name=new-password]')
  ->element_exists('[name=retyped-new-password]')
  ->content_like(qr/Change/i, 'Log Back In - Get Force password change screen again');

done_testing();