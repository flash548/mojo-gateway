use Mojolicious;
use Test::Mojo;
use Test::More;
use Mojo::UserAgent -signatures;
use Gateway;
use Constants;

my $options = {
  test       => 1,
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
};


subtest 'Test Logging Feature - Disabled' => sub {
  my $t = Test::Mojo->new('Gateway', $options,);
  $t->ua->max_redirects(3);

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login as admin user');

  # check that we get a 403 on logs endpoint
  $t->get_ok('/admin/http_logs')->status_is(Constants::HTTP_FORBIDDEN, 'Http Logs Endpoint Forbidden')
    ->json_is('/message' => 'Feature Disabled', 'Forbidden Endpoint');
};

subtest 'Test Logging Feature - Enabled' => sub {

  my $logging_enabled_options = $options;
  $logging_enabled_options->{enable_logging} = 1;

  my $t = Test::Mojo->new('Gateway', $logging_enabled_options);
  $t->ua->max_redirects(3);

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login as admin user');

  # check that we get a 200 on logs endpoint
  $t->get_ok('/admin/http_logs')->status_is(Constants::HTTP_OK, 'Http Logs Endpoint Available')
    ->json_has('/results', 'Allowed Endpoint');

  # check that we get a 400 on logs fetch
  $t->get_ok('/admin/http_logs?pageSize=25&page=-1')->status_is(Constants::HTTP_BAD_REQUEST, 'Bad Input Parameter - 1')
    ->json_is('/message' => 'Page cannot be less than 0', 'Bad Page Number');

  $t->get_ok('/admin/http_logs?pageSize=-10&page=0')->status_is(Constants::HTTP_BAD_REQUEST, 'Bad Input Parameter - 2')
    ->json_is('/message' => 'Page Size must be 1 to 1000', 'Bad Page Min Size');

  $t->get_ok('/admin/http_logs?pageSize=10000&page=0')
    ->status_is(Constants::HTTP_BAD_REQUEST, 'Bad Input Parameter - 3')
    ->json_is('/message' => 'Page Size must be 1 to 1000', 'Bad Page Max Size');

  $t->get_ok('/admin/http_logs?pageSize=25&page=0&fromDate=2022-21:02:000000')
    ->status_is(Constants::HTTP_BAD_REQUEST, 'Bad Input Parameter - 4')
    ->json_is('/message' => 'From date does not appear to be the format yyyy-MM-ddThh:mm:ss', 'Bad From Date');

  $t->get_ok('/admin/http_logs?pageSize=25&page=0&toDate=2022-21:02:000000')
    ->status_is(Constants::HTTP_BAD_REQUEST, 'Bad Input Parameter - 5')
    ->json_is('/message' => 'To date does not appear to be the format yyyy-MM-ddThh:mm:ss', 'Bad To Date');
};

subtest 'Test Ignore Paths for Logging' => sub {

  my $logging_enabled_options = $options;
  $logging_enabled_options->{enable_logging}       = 1;
  $logging_enabled_options->{logging_ignore_paths} = ['/everyone'];

  my $t = Test::Mojo->new('Gateway', $logging_enabled_options);
  $t->ua->max_redirects(3);

  $t->post_ok('/auth/login', form => {username => 'admin@test.com', password => 'testpass'})
    ->status_is(Constants::HTTP_OK)->content_unlike(qr/login/i, 'Login as admin user');

  # check that we get a 200 on logs endpoint
  $t->get_ok('/admin/http_logs')->status_is(Constants::HTTP_OK, 'Http Logs Endpoint Available')
    ->json_has('/results', 'Allowed Endpoint');

  $t->get_ok('/everyone');

  # custom function for inspecting http logs response
  my $json_coll_has = sub ($t, $value, $desc = '') {
    my $result = grep { $_->{request_path} =~ m/$value/ } $t->tx->res->json->{results}->@*;
    return $t->success(is($result, 0, $desc));
  };

  # check that request to /everyone isn't in the http logs and ignored
  $t->get_ok('/admin/http_logs')->status_is(Constants::HTTP_OK)->json_has('/results', 'Allowed Endpoint')
    ->$json_coll_has('/everyone', 'No occurances of /everyone path request');
};


done_testing();
