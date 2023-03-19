use Test::Mojo;
use Test::More;
use Service::HttpLogService;
use Mojo::URL;
use Mojo::Message::Response;

# mock Mojo Results
package MockResults;
use Mojo::Collection qw/c/;

sub new {
  bless({table => []}, 'MockResults');
}

sub hashes {
  return shift->{table};
}

sub arrays {
  return c(shift->{table}->@*);
}
#####################

# mock db instance
package MockDb;

sub new {
  bless({table => []}, 'MockDb');
}

sub insert {
  my ($self, $row) = @_;
  push @{$self->{table}}, $row;
}

sub query {
  shift;
  my $query = shift;
  if ($query =~ m/count/) {
    my $results = MockResults->new();
    $results->{table} = [[0]];
    return $results;
  } else {
    my $results = MockResults->new();
    $results->{table} = $self->{table};
    return $results;
  }
}
#####################

# mock context
package MockContext;

sub new {
  bless({session => {}, req => {}, res => {}, error_message => {}, render_called => 0}, 'MockContext');
}

sub session {
  return shift->{session};
}

sub req {
  return shift->{req};
}

sub res {
  return shift->{res};
}

sub render {
  my $self = shift;
  $self->{render_called} = 1;
  my %args = @_;
  $self->{error_message} = \%args;

}

sub _reset_render {
  my $self = shift;
  $self->{render_called} = 0;
  $self->{error_message} = {};
}
#####################

package main;

subtest 'Test Http Trace Logging' => sub {

  my $res = Mojo::Message::Response->new;
  $res->code(200);

  my $headers = Mojo::Headers->new;
  $headers->user_agent("Netscape Gold");

  my $req = Mojo::Message::Request->new;
  $req->url(Mojo::URL->new("http://localhost:8080/some/path?option=1"));
  $req->method('GET');
  $req->headers($headers);

  my $context = MockContext->new;
  $context->{session} = {user => {email => 'test@test.com'}};
  $context->{req}     = $req;
  $context->{res}     = $res;

  my $db_mock = MockDb->new;
  my $service = Service::HttpLogService->new({db => $db_mock, config => {enable_logging => 1}});
  $service->start_trace($context);
  ok defined($context->{http_req_start}),   "Http Trace time noted";
  ok defined($context->{http_trace_start}), "Http Trace time noted - microseconds";

  # check db empty, log the trace, then check db isnt empty
  ok $db_mock->{table}->@* == 0, 'DB empty';
  $service->end_trace($context);
  ok $db_mock->{table}->@* > 0, 'DB modified';

  # fetch logs
  ok defined($service->get_logs(
    $context, 0, 10, '2023-01-01T00:00:00', '2023-02-01T00:00:00', undef, undef, undef, undef, undef, undef, undef,
    undef,    undef
    )),
    'Logs returned';
};

subtest 'Test Http Trace Logging - disabled' => sub {

  my $context = {};
  my $service = Service::HttpLogService->new({db => undef, config => {enable_logging => 0}});
  $service->start_trace($context);
  ok !defined($context->{http_req_start}),   "Http Trace time NOT noted";
  ok !defined($context->{http_trace_start}), "Http Trace time NOT noted - microseconds";
};

subtest 'Test Search Param Validation' => sub {
  my $context = MockContext->new;
  my $service = Service::HttpLogService->new({db => undef, config => {enable_logging => 1}});

  # check status code
  $service->_validate_search_params($context, 'ok', undef, undef, undef, undef, undef, undef, undef, undef);
  ok $context->{render_called}, 'Test that early render was called';
  ok $context->{error_message}->{status} == 400;
  ok $context->{error_message}->{json}->{message} eq 'Status Code must be a number';
  $context->_reset_render;

  # check email param
  $service->_validate_search_params($context, 200, 'some@test.com;', undef, undef, undef, undef, undef, undef, undef);
  ok $context->{render_called}, 'Test that early render was called';
  ok $context->{error_message}->{status} == 400;
  ok $context->{error_message}->{json}->{message} eq 'Email contains invalid characters';
  $context->_reset_render;

  # check path param
  $service->_validate_search_params($context, 200, 'some@test.com', '; something', undef, undef, undef, undef, undef,
    undef);
  ok $context->{render_called}, 'Test that early render was called';
  ok $context->{error_message}->{status} == 400;
  ok $context->{error_message}->{json}->{message} eq 'Path contains invalid characters';
  $context->_reset_render;

  # check request method
  $service->_validate_search_params($context, 200, 'some@test.com', undef, ';df', undef, undef, undef, undef, undef);
  ok $context->{render_called}, 'Test that early render was called';
  ok $context->{error_message}->{status} == 400;
  ok $context->{error_message}->{json}->{message} eq 'Request Method contains invalid characters';
  $context->_reset_render;

  # check user agent
  $service->_validate_search_params($context, 200, 'some@test.com', undef, undef, ';sfdf', undef, undef, undef, undef);
  ok $context->{render_called}, 'Test that early render was called';
  ok $context->{error_message}->{status} == 400;
  ok $context->{error_message}->{json}->{message} eq 'User agent contains invalid characters';
  $context->_reset_render;

  # check hostname
  $service->_validate_search_params($context, 200, 'some@test.com', undef, undef, undef, ';fdsf!', undef, undef, undef);
  ok $context->{render_called}, 'Test that early render was called';
  ok $context->{error_message}->{status} == 400;
  ok $context->{error_message}->{json}->{message} eq 'Host contains invalid characters';
  $context->_reset_render;

  # check query string
  $service->_validate_search_params($context, 200, 'some@test.com', undef, undef, undef, undef, 'sdf;!', undef, undef);
  ok $context->{render_called}, 'Test that early render was called';
  ok $context->{error_message}->{status} == 400;
  ok $context->{error_message}->{json}->{message} eq 'Query String contains invalid characters';
  $context->_reset_render;

  # check time less
  $service->_validate_search_params($context, 200, 'some@test.com', undef, undef, undef, undef, undef, ';sdf', undef);
  ok $context->{render_called}, 'Test that early render was called';
  ok $context->{error_message}->{status} == 400;
  ok $context->{error_message}->{json}->{message} eq 'Time Less than must be a number';
  $context->_reset_render;

  # check time greater
  $service->_validate_search_params($context, 200, 'some@test.com', undef, undef, undef, undef, undef, undef, ';ff');
  ok $context->{render_called}, 'Test that early render was called';
  ok $context->{error_message}->{status} == 400;
  ok $context->{error_message}->{json}->{message} eq 'Time Greater than must be a number';
  $context->_reset_render;

};

subtest 'Test Build Query' => sub {
  my $service = Service::HttpLogService->new({db => undef, config => {enable_logging => 1}});

  my ($query, $query_bindings, $count_query, $count_bindings)
    = $service->_build_query(0, 25, '2023-01-03T00:00:00', '2023-02-01T00:00:00', 200, 'test@test.com',
    'logs', 'GET', 'mozilla', 'yahoo.com', 'test', 1000, 500)->@*;

  ok $query =~ m/http_logs\s+where\srequest_time >= \? and request_time <= \?/s, 'Test Query Content - 1';
  ok $query =~ m/and response_status = \?/s, 'Test Query Content - 2';
  ok $query =~ m/and lower\(user_email\) like \?/s, 'Test Query Content - 3';
  ok $query =~ m/and lower\(request_path\) like \?/s, 'Test Query Content - 4';
  ok $query =~ m/ and lower\(request_method\) = \?/s, 'Test Query Content - 5';
  ok $query =~ m/and lower\(request_user_agent\) like \?/s, 'Test Query Content - 6';
  ok $query =~ m/and lower\(request_host\) like \?/s, 'Test Query Content - 7';
  ok $query =~ m/and time_taken_ms > \?/s, 'Test Query Content - 8';
  ok $query =~ m/and lower\(request_query_string\) like \?/s, 'Test Query Content - 9';
  ok $query =~ m/order by request_time asc limit \? offset \?/s, 'Test Query Content - Pagination';

  ok $query_bindings->[0] eq '2023-01-03T00:00:00', 'Test Query Bindings - 1';
  ok $query_bindings->[1] eq '2023-02-01T00:00:00', 'Test Query Bindings - 2';
  ok $query_bindings->[2] eq '200', 'Test Query Bindings - 3';
  ok $query_bindings->[3] eq '%test@test.com%', 'Test Query Bindings - 4';
  ok $query_bindings->[4] eq '%logs%', 'Test Query Bindings - 5';
  ok $query_bindings->[5] eq 'get', 'Test Query Bindings - 6';
  ok $query_bindings->[6] eq '%mozilla%', 'Test Query Bindings - 7';
  ok $query_bindings->[7] eq '%yahoo.com%', 'Test Query Bindings - 8';
  ok $query_bindings->[8] eq '1000', 'Test Query Bindings - 9';
  ok $query_bindings->[9] eq '500', 'Test Query Bindings - 10';
  ok $query_bindings->[10] eq '%test%', 'Test Query Bindings - 11'; 

};


done_testing();

1;
