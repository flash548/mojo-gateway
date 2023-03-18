package Service::HttpLogService;
use Mojo::Base -base, -signatures;
use Time::HiRes qw/gettimeofday/;
use POSIX       qw/ceil/;
use Time::Piece;

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

# Gets a paginated slice of logs - kind of like in a Spring Boot app and how JPA does pagination
#
# Inputs-
# $page - 0-based page number
# $page_size - integer (1 to 1000)
# $from_date - as ISO8601 yyyy-MM-ddTHH:mm:ss
# $to_date - as ISO8601 yyyy-MM-ddTHH:mm:ss
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
sub get_logs ($self, $page, $page_size, $from_date, $to_date) {

  my $items = $self->db->query(<<QUERY_END, ($from_date, $to_date, $page_size, ($page * $page_size)))->hashes;
select * from http_logs 
  where request_time >= ? and request_time <= ? 
  limit ? 
  offset ?
QUERY_END

  # get the count of the whole resultset
  my $count = $self->db->query(<<QUERY_END, ($from_date, $to_date))->arrays->[0]->[0];
select count(*) from http_logs 
  where request_time >= ? and request_time <= ? 
QUERY_END

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
