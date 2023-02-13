package Service::Proxy;
use Mojo::Base -base, -signatures;
use Mojo::UserAgent;
use Mojo::JWT;
has 'config';
has 'ua';

# takes the request object ($c) named route from the config
sub proxy ($self, $c, $name) {
  my $request = $c->req->clone;
  my $route_spec = $self->config->{routes}->{$name} // $self->config->{default_route};
  my $uri     = $route_spec->{uri};
  
  if ($route_spec->{rewrite_path} 
    && defined($route_spec->{rewrite_path}->{match})
    && defined($route_spec->{rewrite_path}->{with})) {
    my $match = $route_spec->{rewrite_path}->{match};
    my $with = $route_spec->{rewrite_path}->{with};
    my $new_path = ($c->req->url->path =~ s/$match/$with/re);
    $c->req->url->path($new_path);
  }

  # remove the trailing slash if present
  $uri =~ s!/$!!;
  say $uri . $c->req->url;
  $request->url(Mojo::URL->new($uri . $c->req->url));

  # see if we wanna use JWT for this proxy route
  if ($route_spec->{enable_jwt}) {
    my $claims = {};
    for my $claim (keys %{$route_spec->{jwt_claims}}) {
      $claims->{$claim} = eval $route_spec->{jwt_claims}->{$claim};
    }
    my $jwt = Mojo::JWT->new(claims => $claims, secret => $self->config->{jwt_secret});

    $request->headers->add('Authorization', 'Bearer ' . $jwt->encode);
  }

  # add any other static-text headers specified in our config json
  for my $header (keys %{$route_spec->{other_headers}}) {
    $request->headers->add($header => $route_spec->{other_headers}->{$header});
  }

  my $tx = $self->ua->start(Mojo::Transaction::HTTP->new(req => $request));

  # proxy actioning inspired from Mojolicious::Plugin::Proxy -> without it would not have figured this proxying out
  # trick is to copy the res over to the $c->tx->res not $c->res directly
  if (defined($tx->res->code)) {
    my $res = $tx->res;
    my $body = $res->body;

    # do any transforms specified for this route
    if ($route_spec->{transforms}) {
      for my $transform (@{$route_spec->{transforms}}) {
        my $condition = eval $transform->{condition};
        if ($condition) {
          eval $transform->{action};
          $res->headers->content_length(length($body));
          $res->body($body);
        }
      }
    }

    $res->fix_headers;
    $c->tx->res($res);
    $c->rendered;
  } else {

    # something went wrong and we didnt get a response from the proxy target
    $c->render("no_response");
  }
}

1;
