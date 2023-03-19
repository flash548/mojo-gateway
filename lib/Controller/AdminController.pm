package Controller::AdminController;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Constants;
use Utils;
use Time::Piece;

# This is the Admin controller
# all the administrative actions come through here
# via the client's Admin Dashboard web UI so you need to be
# an admin to be able to reach these endpoints

has 'user_service';
has 'log_service';

# GET /admin
#
# Reachable by: 'ADMIN'
#
# Description-
# Serve the admin SPA static page
#
# Content-Type: 'text/html'
sub admin_page_get ($self, $c) {
  $c->render('admin', email => $c->session->{user}->{email} // 'Unknown');
}

# POST /admin/users
#
# Reachable by: 'ADMIN'
#
# Body-
# Json object of person to create
#
# Description-
# creates a user
#
# Content-Type: 'application/json'
sub add_user_post ($self, $c) {
  if (Utils::validate_user_object($c->req->json, 1)) {
    $self->user_service->add_user($c);
  } else {
    $c->render(status => Constants::HTTP_BAD_REQUEST, json => {message => 'User object malformed'});
  }
}

# PUT /admin/users
#
# Reachable by: 'ADMIN'
#
# Body-
# Json object of the person to update
#
# Description-
# update a single user
#
# Content-Type: 'application/json'
sub update_user_put ($self, $c) {
  if (Utils::validate_user_object($c->req->json, 0)) {
    $self->user_service->update_user($c);
  } else {
    $c->render(status => Constants::HTTP_BAD_REQUEST, json => {message => 'User object malformed'});
  }
}

# GET /admin/users
#
# Reachable by: 'ADMIN'
#
# Query Params-
# email (optional, if you want to just fetch one user vs all)
#
# Description-
# Get all users or just one (if query param 'email' is present)
#
# Content-Type: 'application/json'
sub users_get ($self, $c) {

  # if we provide a single email via query param...
  if ($c->req->param('email')) {

    my $user = $self->user_service->get_single_user($c);
    if ($user) {
      return $c->render(json => $user);
    } else {
      $c->render(json => {message => 'User not found'}, status => Constants::HTTP_NOT_FOUND);
    }
  } else {

    # otherwise return all users
    $self->user_service->get_all_users($c);
  }
}

# DELETE /admin/user
#
# Reachable by: 'ADMIN'
#
# Query Params-
# email - (required, the email of the user to delete)
#
# Description-
# deletes a user (with query param 'email')
#
# Content-Type: 'application/json'
sub users_delete ($self, $c) {
  if ($c->req->param('email')) {
    my $user = $self->user_service->delete_single_user($c);
    if ($user) {
      return $c->render(json => {message => 'User Deleted'}, status => Constants::HTTP_NO_RESPONSE);
    } else {
      $c->render(json => {message => 'User not found'}, status => Constants::HTTP_NOT_FOUND);
    }
  } else {

    # bad request
    $c->render(json => {message => 'Email query param is required'}, status => Constants::HTTP_BAD_REQUEST);
  }
}

# GET /admin/http_logs
#
# Reachable by: 'ADMIN'
#
# Query Params-
# pageSize (int) (optional, defaults to 25)
# page (int) (optional, defaults to 0th page)
# fromDate (iso8601) (optional, defaults to now - 30days)
# toDate (iso8601) (optional, defaults to now)
#
# Description-
# gets a set of logs of given length and in given date/time range
#
# Returns-
# {
# page: n, page_size: n, from_date: n, to_date: n, total_pages: n,
# total_items: n,
# results: [
#  {
#   user_email,
#   response_status,
#   request_path,
#   request_query_string,
#   request_time,
#   request_method,
#   request_host,
#   request_user_agent,
#   time_taken_ms,
#  }
# ]
#
# Content-Type: 'application/json'
sub get_http_logs ($self, $c) {

  # default to 30 days before now
  my $from_date = $c->req->param('fromDate') // gmtime()->add(30 * (-24 * 60 * 60))->datetime;

  # default to now
  my $to_date = $c->req->param('toDate') // gmtime()->datetime;

  # default to page 0
  my $page = $c->req->param('page') // 0;

  # default to page size 25
  my $page_size = $c->req->param('pageSize') // 25;

  my $status_code        = $c->req->param('statusCode');
  my $user_email         = $c->req->param('email');
  my $path               = $c->req->param('path');
  my $request_method     = $c->req->param('method');
  my $user_agent         = $c->req->param('userAgent');
  my $request_host       = $c->req->param('hostname');
  my $query              = $c->req->param('queryString');
  my $time_taken_less    = $c->req->param('timeLessThan');
  my $time_taken_greater = $c->req->param('timeGreaterThan');

  # validate all this stuff
  if (!($page_size >= 1 && $page_size <= 1000)) {
    $c->render(json => {message => 'Page Size must be 1 to 1000'}, status => Constants::HTTP_BAD_REQUEST);
  } elsif ($page < 0) {
    $c->render(json => {message => 'Page cannot be less than 0'}, status => Constants::HTTP_BAD_REQUEST);
  } elsif (!Utils::validate_ISO_string($from_date)) {
    $c->render(
      json   => {message => 'From date does not appear to be the format yyyy-MM-ddThh:mm:ss'},
      status => Constants::HTTP_BAD_REQUEST
    );
  } elsif (!Utils::validate_ISO_string($to_date)) {
    $c->render(
      json   => {message => 'To date does not appear to be the format yyyy-MM-ddThh:mm:ss'},
      status => Constants::HTTP_BAD_REQUEST
    );
  } else {
    my $results = $self->log_service->get_logs(
      $c,            $page,       $page_size,       $from_date,      $to_date,
      $status_code,  $user_email, $path,            $request_method, $user_agent,
      $request_host, $query,      $time_taken_less, $time_taken_greater
    );
    $c->render(json => $results) if $results;    # if results is falsy then weve already errored out and responded
  }

}

1;
