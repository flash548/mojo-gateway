package Service::Proxy;
use Mojo::Base -base, -signatures;
use Mojo::UserAgent;
use Mojo::JWT;
has 'config';
has 'ua';

#
# Find the route spec information in the config given 
# the name of the route spec (the matched route spec the mojo router used -- e.g. /anyone/**) 
sub _find_route_spec ($self, $name) {
    use Data::Dumper;
    use Test::More;
  my $r = $self->config->{ routes }->{ $name };

  if (!$r) {

    # if '$name' was not a main path spec in the config (e.g. a hash key), then
    # take all route specs from the config, and grab out their paths, and any add'l paths
    # then finally flatten all that into an array
    my $sub_paths = Mojo::Collection::c(keys %{ $self->config->{ routes } })->map(sub ($spec) {
      return $self->config->{ routes }->{ $spec }
        if defined($self->config->{ routes }->{ $spec }->{ additional_paths })
        && @{ $self->config->{ routes }->{ $spec }->{ additional_paths } } > 0;
    })->compact->map(sub ($spec) {
      my @paths  = @{ $spec->{ additional_paths } };
      my @retVal = ();
      for my $p (@paths) {
        push @retVal, { $p => $spec };
      }
      return \@retVal;
    })->flatten;
    

    # look through all these flattened route paths, and see
    # if we find the one that matches '$name'
    my $matched_spec = $sub_paths->map(sub ($spec) {
      my @keys = keys %{ $spec };
      
      if (@keys > 0 && $keys[0] eq $name) {
        return $spec->{ $name };
      }
    })->compact->to_array;

    if (@{ $matched_spec } > 0) {

      # return the matched spec from the config
      return $matched_spec->[0];
    } else {

      # fallback to default route
      return $self->config->{ default_route };
    }
  } else {

    # return the main matched spec (i.e. was not a nested/add'l path)
    return $r;
  }
}

# takes the request object ($c) and the matched route from the config
# and does what its settings dictate (e.g. proxy to uri or return a template, inline template, etc)
sub proxy ($self, $c, $name) {

  # find the route spec from the config (note: it may be in a nested 'additional_paths', so look there too)
  my $route_spec = $self->_find_route_spec($name);
  if (defined($route_spec->{ template_name })) {

    # this isn't a request to be proxied, its just a local template render (or inline render)
    if ($route_spec->{ template_name } =~ m/^<%=/) {
      $c->render(inline => $route_spec->{ template_name });
    } else {
      $c->render(template => $route_spec->{ template_name });
    }
    return;
  }

  my $request = $c->req->clone;
  my $uri     = $route_spec->{ uri };

  if ( $route_spec->{ rewrite_path }
    && defined($route_spec->{ rewrite_path }->{ match })
    && defined($route_spec->{ rewrite_path }->{ with })) {
    my $match    = $route_spec->{ rewrite_path }->{ match };
    my $with     = $route_spec->{ rewrite_path }->{ with };
    my $new_path = ($c->req->url->path =~ s/$match/$with/re);
    $c->req->url->path($new_path);
  }

  # remove the trailing slash if present
  $uri =~ s!/$!!;
  $request->url(Mojo::URL->new($uri . $c->req->url));

  # see if we wanna use JWT for this proxy route
  if ($route_spec->{ enable_jwt }) {
    my $claims = {};
    for my $claim (keys %{ $route_spec->{ jwt_claims } }) {
      $claims->{ $claim } = eval $route_spec->{ jwt_claims }->{ $claim };
    }
    my $jwt = Mojo::JWT->new(claims => $claims, secret => $self->config->{ jwt_secret });

    $request->headers->add('Authorization', 'Bearer ' . $jwt->encode);
  }

  # add any other static-text headers specified in our config json
  for my $header (keys %{ $route_spec->{ other_headers } }) {
    $request->headers->add($header => $route_spec->{ other_headers }->{ $header });
  }

  my $tx = $self->ua->start(Mojo::Transaction::HTTP->new(req => $request));

  # proxy actioning inspired from Mojolicious::Plugin::Proxy -> without it would not have figured this proxying out
  # trick is to copy the res over to the $c->tx->res not $c->res directly
  if (defined($tx->res->code)) {
    my $res  = $tx->res;
    my $body = $res->body;

    # do any transforms specified for this route
    if ($route_spec->{ transforms }) {
      for my $transform (@{ $route_spec->{ transforms } }) {
        my $condition = eval $transform->{ condition };
        if ($condition) {
          eval $transform->{ action };
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
