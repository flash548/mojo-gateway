package Service::HttpLogService;
use Mojo::Base -base, -signatures;
use Time::HiRes qw/gettimeofday/;
use POSIX       qw/ceil/;
use Time::Piece;
use Scalar::Util qw(looks_like_number);

use Constants;

has 'db';
has 'config';

# initiates the start timestamp of the request and starts
# the 'clock' on it
sub start_trace ($self, $c) {

  # skip logging if enable_logging isn't truthy
  return unless $self->config->{enable_logging};

  my ($secs, $micros) = gettimeofday();
  $c->{http_req_start}   = gmtime()->datetime;
  $c->{http_trace_start} = $micros;
}

# closes out the request trace and logs it to the db
sub end_trace ($self, $c) {

  # skip logging if enable_logging isn't truthy
  return unless $self->config->{enable_logging};

  # skip if its a path we dont want to log
  return
    if ($self->config->{logging_ignore_paths}
    && $self->config->{logging_ignore_paths}->@* > 0
    && grep { $c->req->url->path->to_string =~ m/^$_/ } $self->config->{logging_ignore_paths}->@*);

  my ($secs, $micros) = gettimeofday();

  # convert to mS
  my $time_delta = ($micros - $c->{http_trace_start}) / 1000;

  if ($time_delta) {
    $self->db->insert(
      http_logs => {
        user_email           => $c->session->{user}->{email},
        response_status      => $c->res->code,
        request_path         => $c->req->url->path->to_string,
        request_query_string => $c->req->url->query->to_string,
        request_time         => $c->{http_req_start},
        request_method       => $c->req->method,
        request_host         => $c->req->url->base->{host},
        request_user_agent   => $c->req->headers->user_agent,
        time_taken_ms        => $time_delta,
      }
    );
  }
}

# helper method that validates some of the search parameters
# for sane-ness (no semicolons, numbers are numbers, etc)
#
# returns undef if validation failed (by then we'll have rendered a json message/error)
# otherwise its 1/true
sub _validate_search_params (
  $self,                  $c,                       $status_code_is,      $user_email_contains,
  $path_contains,         $request_method_is,       $user_agent_contains, $request_host_contains,
  $query_string_contains, $time_taken_ms_less_than, $time_taken_ms_greater_than
) {
  # status code - if provided - needs to be a number
  if (defined($status_code_is) && !looks_like_number($status_code_is)) {
    $c->render(json => {message => "Status Code must be a number"}, status => Constants::HTTP_BAD_REQUEST);
    return;
  }

  # user-email must contain valid chars (more to do there)
  if (defined($user_email_contains) && $user_email_contains =~ m/;/) {
    $c->render(json => {message => "Email contains invalid characters"}, status => Constants::HTTP_BAD_REQUEST);
    return;
  }

  # path_contains must contain valid chars
  if (defined($path_contains) && $path_contains =~ m/;/) {
    $c->render(json => {message => "Path contains invalid characters"}, status => Constants::HTTP_BAD_REQUEST);
    return;
  }

  # request_method_is must contain valid chars
  if (defined($request_method_is) && $request_method_is =~ m/;/) {
    $c->render(
      json   => {message => "Request Method contains invalid characters"},
      status => Constants::HTTP_BAD_REQUEST
    );
    return;
  }

  # user_agent_contains must contain valid chars
  if (defined($user_agent_contains) && $user_agent_contains =~ m/;/) {
    $c->render(json => {message => "User agent contains invalid characters"}, status => Constants::HTTP_BAD_REQUEST);
    return;
  }

  # request_host_contains must contain valid chars
  if (defined($request_host_contains) && $request_host_contains =~ m/;/) {
    $c->render(json => {message => "Host contains invalid characters"}, status => Constants::HTTP_BAD_REQUEST);
    return;
  }

  # query_string_contains must contain valid chars
  if (defined($query_string_contains) && $query_string_contains =~ m/;/) {
    $c->render(json => {message => "Query String contains invalid characters"}, status => Constants::HTTP_BAD_REQUEST);
    return;
  }

  # time_taken_ms_less_than must be a number
  if (defined($time_taken_ms_less_than) && !looks_like_number($time_taken_ms_less_than)) {
    $c->render(json => {message => "Time Less than must be a number"}, status => Constants::HTTP_BAD_REQUEST);
    return;
  }

  # time_taken_ms_greater_than must be a number
  if (defined($time_taken_ms_greater_than) && !looks_like_number($time_taken_ms_greater_than)) {
    $c->render(json => {message => "Time Greater than must be a number"}, status => Constants::HTTP_BAD_REQUEST);
    return;
  }

  1;
}

# helper method to build out two queries, one to get the items
# according to input params (paginated appropriately), and the other to count
# the TOTAL in the result set (not paginated)
#
# returns an array ref of [ items_sql_query,
#   items_query_bindings,
#   items_count_sql_query,
#   count_bindings]
sub _build_query (
  $self,                    $page,                $page_size,             $from_date,
  $to_date,                 $status_code_is,      $user_email_contains,   $path_contains,
  $request_method_is,       $user_agent_contains, $request_host_contains, $query_string_contains,
  $time_taken_ms_less_than, $time_taken_ms_greater_than
) {
  my @bindings    = ($from_date, $to_date);
  my $items_query = <<QUERY_END;
select * from http_logs 
  where request_time >= ? and request_time <= ? 
QUERY_END

  my $items_total_query = <<QUERY_END;
select count(*) from http_logs 
  where request_time >= ? and request_time <= ? 
QUERY_END

  my $query = "";

  if (defined($status_code_is)) {
    push @bindings, $status_code_is;
    $query .= " and response_status = ? ";
  }

  if (defined($user_email_contains)) {
    push @bindings, '%' . lc $user_email_contains . '%';
    $query .= " and lower(user_email) like ?";
  }

  if (defined($path_contains)) {
    push @bindings, '%' . lc $path_contains . '%';
    $query .= " and lower(request_path) like ?";
  }

  if (defined($request_method_is)) {
    push @bindings, lc $request_method_is;
    $query .= " and lower(request_method) = ?";
  }

  if (defined($user_agent_contains)) {
    push @bindings, '%' . lc $user_agent_contains . '%';
    $query .= " and lower(request_user_agent) like ?";
  }

  if (defined($request_host_contains)) {
    push @bindings, '%' . lc $request_host_contains . '%';
    $query .= " and lower(request_host) like ?";
  }

  if (defined($time_taken_ms_less_than)) {
    push @bindings, $time_taken_ms_less_than;
    $query .= " and time_taken_ms < ?";
  }

  if (defined($time_taken_ms_greater_than)) {
    push @bindings, $time_taken_ms_greater_than;
    $query .= " and time_taken_ms > ?";
  }

  if (defined($query_string_contains)) {
    push @bindings, '%' . lc $query_string_contains . '%';
    $query .= " and lower(request_query_string) like ?";
  }

  # stop here for the total_count_query, next part is just for slicing/paginating
  my $total_count_query    = $items_total_query . $query;
  my @total_count_bindings = @bindings;

  push @bindings, $page_size, ($page * $page_size);
  $query .= " order by request_time asc limit ? offset ? ";

  return [$items_query . $query, \@bindings, $total_count_query, \@total_count_bindings];
}

# Gets a paginated slice of logs - kind of like in a Spring Boot app and how JPA does pagination
#
# Inputs-
# $c - request context
# $page - 0-based page number
# $page_size - integer (1 to 1000)
# $from_date - as ISO8601 yyyy-MM-ddTHH:mm:ss
# $to_date - as ISO8601 yyyy-MM-ddTHH:mm:ss
# $status_code_is - (optional) integer, status code to search for,
# $user_email_contains - (optional) string, user login/email contains (case insensitive)
# $path_contains - (optional) string, searching part of the request string (case insensitive)
# $request_method_is - (optional) string, request method is equal to (case insensitive)
# $user_agent_contains - (optional) string, user agent of request contains (case insensitive)
# $request_host_contains - (optional) string, request host contains (case insensitive)
# $query_string_contains - (optional) string, query string contains (case insensitive)
# $time_taken_ms_less_than - (optional) integer, request duration less than in ms
# $time_taken_ms_greater_than - (optional) integer, request duration greater than in ms
#
# Returns-  {
# page: n,
# page_size: n,
# from_date: n,
# to_date: n,
# total_pages: n,
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
sub get_logs (
  $self,                  $c,                       $page,                $page_size,
  $from_date,             $to_date,                 $status_code_is,      $user_email_contains,
  $path_contains,         $request_method_is,       $user_agent_contains, $request_host_contains,
  $query_string_contains, $time_taken_ms_less_than, $time_taken_ms_greater_than
) {

  # do some validation, quit now (returning undef) if validation returns
  # something NOT truthy
  return
    unless $self->_validate_search_params(
    $c,                       $status_code_is,      $user_email_contains,   $path_contains,
    $request_method_is,       $user_agent_contains, $request_host_contains, $query_string_contains,
    $time_taken_ms_less_than, $time_taken_ms_greater_than
    );

  # build query(s) from given search params
  my ($query, $query_bindings, $total_count_query, $total_count_bindings) = $self->_build_query(
    $page,                $page_size,             $from_date,             $to_date,
    $status_code_is,      $user_email_contains,   $path_contains,         $request_method_is,
    $user_agent_contains, $request_host_contains, $query_string_contains, $time_taken_ms_less_than,
    $time_taken_ms_greater_than
  )->@*;

  # get the items from the built query
  my $items = $self->db->query($query, $query_bindings->@*)->hashes;

  # get the count of the whole, unpaged/unoffset'd resultset so our pagination UIs will
  # know the total/max to page up to -- yes its a duplicate query for now
  my $count = $self->db->query($total_count_query, $total_count_bindings->@*)->arrays->[0]->[0];

  return {
    page        => int($page),
    page_size   => int($page_size),
    from_date   => $from_date,
    to_date     => $to_date,
    total_items => $count,
    total_pages => ceil($count / $page_size),
    results     => $items,
  };
}

1;
