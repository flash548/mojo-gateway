package Service::Proxy;
use Mojo::Base -base, -signatures;
use Mojo::UserAgent;
use Mojo::JWT;

has 'config';
has 'user_service';
has 'ua';

#
# Find the route spec information in the config given
# the name of the route spec (the matched route spec the mojo router used -- e.g. /anyone/**)
sub _find_route_spec ($self, $name) {
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

# takes a desired claim value specification from the config
# and sees if user wants something out of the user record to resolve as the value
# or if its just a static string.  Something out of the user record would begin with ':'
sub resolve_jwt_claim ($self, $c, $claim_spec) {
  my @resolved_claims = ();
  if (!defined($claim_spec)) { $claim_spec = ''; }
  if ($self->user_service) {
    my @claim_specs = ();
    if (ref($claim_spec) eq 'ARRAY') {
      for (@{ $claim_spec }) {
        push @claim_specs, !defined($_) ? '' : $_;
      }
    } else {
      push @claim_specs, $claim_spec;
    }

    for my $spec (@claim_specs) {
      my $found_user_field_match = 0;
      use Test::More;
      if ($spec =~ m/^:(.*)/) {

        # see if the requested field is "safe/allowed"... note we add "email" manually
        # since that list of allowed fields from user service does not have that
        # (since users can't change their email [yet])
        for my $user_field ($self->user_service->user_obj_allowed_fields->@*) {
          if (($1 eq 'email' || $1 eq $user_field) && $c->session->{ user }->{ email }) {
            my $user_record = $self->user_service->_get_user($c->session->{ user }->{ email });
            if ($user_record) {
              push @resolved_claims, $user_record->{ $1 };
              $found_user_field_match = 1;
              last;
            }
          }
        }
      }

      # if its wasn't a valid user field then just use the raw value
      if (!$found_user_field_match) {
        push @resolved_claims, $spec;
      }
    }
  }

  # finally return the concat of our results
  return join("", @resolved_claims);
}

# takes the request object ($c) and the matched route from the config
# and does what its settings dictate (e.g. proxy to uri or return a template, inline template, etc)
sub proxy ($self, $c, $name) {

  # find the route spec from the config (note: it may be in a nested 'additional_paths', so look there too)
  my $route_spec = $self->_find_route_spec($name);

  if (defined($route_spec->{ template_name })) {

    # this isn't a request to be proxied, its just a local template render (or inline render)
    if ($route_spec->{ template_name } =~ m/^inline:/i) {
      $c->app->log->info("Proxying $name to inline template response");
      my $inline_spec = ($route_spec->{ template_name } =~ s/^inline://ir);
      $c->render(inline => $inline_spec);
    } else {
      $c->app->log->info("Proxying " . $name . " to template " . $route_spec->{ template_name });
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
    $c->app->log->info(sprintf("Rewriting request to path: " . $name . " to $new_path"));
    $c->req->url->path($new_path);
  }

  # remove the trailing slash if present
  $uri =~ s!/$!!;
  $request->url(Mojo::URL->new($uri . $c->req->url));

  # see if we wanna use JWT for this proxy route
  if ($route_spec->{ enable_jwt }) {
    $c->app->log->trace("Injecting JWT to proxied request");
    my $claims = {};
    for my $claim (keys %{ $route_spec->{ jwt_claims } }) {
      $c->app->log->trace("Injecting claim: $claim into JWT");
      $claims->{ $claim } = $self->resolve_jwt_claim($c, $route_spec->{ jwt_claims }->{ $claim });
    }
    my $jwt = Mojo::JWT->new(claims => $claims, secret => $self->config->{ jwt_secret });

    $request->headers->add('Authorization', 'Bearer ' . $jwt->encode);
  }

  # add any other static-text headers specified in our config json
  for my $header (keys %{ $route_spec->{ other_headers } }) {
    $c->app->log->trace("Injecting header: $header into request");
    $request->headers->add($header => $route_spec->{ other_headers }->{ $header });
  }

  my $tx = $self->ua->start(Mojo::Transaction::HTTP->new(req => $request));
  $c->app->log->info(sprintf("Proxying $name to host: " . $route_spec->{ uri }));

  # proxy actioning inspired from Mojolicious::Plugin::Proxy -> without it would not have figured this proxying out
  # trick is to copy the res over to the $c->tx->res not $c->res directly
  if (defined($tx->res->code)) {
    my $res  = $tx->res;
    my $body = $res->body;

    # do any transforms specified for this route
    if ($route_spec->{ transforms }) {
      for my $transform (@{ $route_spec->{ transforms } }) {

        # only do the transform if the path matches (or always do the transform if path key is omitted)
        if (!defined($transform->{ path })
          || (defined($transform->{ path }) && $c->req->url->path =~ m/\Q$transform->{path}/)) {
          $c->app->log->trace("Doing response transform");
          # make sure we have defined search and replacement
          my $search  = $transform->{ action }->{ search };
          my $replace = $transform->{ action }->{ replace };
          if ($search && $replace) {
            $body =~ s/$search/$replace/g;
            $res->headers->content_length(length($body));
            $res->body($body);
          }
        }
      }
    }

    $res->fix_headers;
    $c->app->log->info("Received response from " . $request->url->to_string . " / status: " . $res->code);
    $c->tx->res($res);
    $c->rendered;
  } else {

    # something went wrong and we didnt get a response from the proxy target
    $c->app->log->warn("No response from target " . $request->url->to_string);
    $c->render("no_response");
  }
}

1;
