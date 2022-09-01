package Service::Proxy;
use Mojo::Base -base, -signatures;
use Mojo::UserAgent;
use Mojo::JWT;
has 'config';
has 'ua';

# takes the request object ($c) named route from the config
sub proxy ($self, $c, $name) {
  my $request = $c->req->clone;
  my $uri     = $self->config->{routes}->{$name}->{uri} // $self->config->{default_route}->{uri};

  # remove the trailing slash if present
  $uri =~ s!/$!!;
  $request->url(Mojo::URL->new($uri . $c->req->url));

  # see if we wanna use JWT for this proxy route
  if ($self->config->{routes}->{$name}->{enable_jwt}) {
    my $claims = {};
    for my $claim (keys %{$self->config->{routes}->{$name}->{jwt_claims}}) {
      $claims->{$claim} = eval $self->config->{routes}->{$name}->{jwt_claims}->{$claim};
    }
    my $jwt = Mojo::JWT->new(claims => $claims, secret => $self->config->{jwt_secret});

    $request->headers->add('Authorization', 'Bearer ' . $jwt->encode);
  }

  # add any other static-text headers specified in our config json
  for my $header (keys %{$self->config->{routes}->{$name}->{other_headers} // {}}) {
    $request->headers->add($header, $self->config->{routes}->{$name}->{other_headers}->{$header});
  }

  my $tx = $self->ua->start(Mojo::Transaction::HTTP->new(req => $request));
  if (defined($tx->res->code)) {
    $c->res($tx->res);
    for my $header (keys %{$tx->res->headers->to_hash}) {
      $c->res->headers->add($header => $tx->res->headers->to_hash->{$header});
    }
    my $body = $tx->res->body;

    # do any transforms specified for this route
    if ($self->config->{routes}->{$name}->{transforms}) {
      for my $transform (@{$self->config->{routes}->{$name}->{transforms}}) {
        my $condition = eval $transform->{condition};
        if ($condition) {
          eval $transform->{action};
        }
      }
    }

    $c->res->body($body);
    $c->rendered;
  } else {

    # something went wrong and we didnt get a response from the proxy target
    $c->render("no_response");
  }
}

1;
