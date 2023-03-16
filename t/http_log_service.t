use Test::Mojo;
use Test::More;
use Service::HttpLogService;
use Mojo::URL;
use Mojo::Message::Response;

# mock db instance to return what we give the insert method
package MockDb;
sub new {
  bless({}, 'MockDb');
}
sub insert {
  shift;
  return shift;
}

package main;

subtest 'Test Http Trace Logging' => sub {

  my $res = Mojo::Message::Response->new; 
  $res->code(200);

  my $req = Mojo::Message::Request->new;
  req->url(Mojo::URL->new("http://localhost:8080/some/path?option=1"));
  req->method('GET');
  req->headers()

  my $context = { session => { user => 'tony '}, res => { code => 200 }, req => { 
    url => 
  }};

  my $db_mock = MockDb->new;
  my $service = Service::HttpLogService->new({ db => $db_mock, config => { enable_logging => 1 }});
  $service->start_trace($context);
  ok defined($context->{http_req_start}), "Http Trace time noted";
  ok defined($context->{http_trace_start}), "Http Trace time noted - microseconds";

  $service->end_trace()
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