use Test::Mojo;
use Test::More;
use Service::HttpLogService;
use Mojo::URL;
use Mojo::Message::Response;

# mock Mojo Results
package MockResults;
use Mojo::Collection qw/c/;
sub new {
  bless({ table => [] }, 'MockResults');
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
  bless({ table => [] }, 'MockDb');
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
    $results->{table} = [ [0] ];
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
  bless({ session => {}, req => {}, res => {}}, 'MockContext')
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
  $context->{session} = { user => { email => 'test@test.com' }};
  $context->{req} = $req;
  $context->{res} = $res;

  my $db_mock = MockDb->new;
  my $service = Service::HttpLogService->new({ db => $db_mock, config => { enable_logging => 1 }});
  $service->start_trace($context);
  ok defined($context->{http_req_start}), "Http Trace time noted";
  ok defined($context->{http_trace_start}), "Http Trace time noted - microseconds";

  # check db empty, log the trace, then check db isnt empty
  ok $db_mock->{table}->@* == 0, 'DB empty';
  $service->end_trace($context);
  ok $db_mock->{table}->@* > 0, 'DB modified';

  # fetch logs
  ok defined($service->get_logs(0, 10, '2023-01-01T00:00:00', '2023-02-01T00:00:00')), 'Logs returned';
};

subtest 'Test Http Trace Logging - disabled' => sub {

  my $context = { };
  my $service = Service::HttpLogService->new({ db => undef, config => { enable_logging => 0 }});
  $service->start_trace($context);
  ok !defined($context->{http_req_start}), "Http Trace time NOT noted";
  ok !defined($context->{http_trace_start}), "Http Trace time NOT noted - microseconds";
};


done_testing();

1;