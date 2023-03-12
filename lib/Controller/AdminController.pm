package Controller::AdminController;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Constants;


# This is the Admin controller
# all the administrative actions come through here
# via the client's Admin Dashboard web UI

has 'user_service';

sub _trim { return $_[0] =~ s/^\s+|\s+$//gr; }
sub _detect_gremlins {
  my $in = shift;

  # no cntrl chars
  return 1 if $in =~ m/\p{cntrl}/;

  # no non-ascii
  return 1 if $in =~ m/[^\p{ascii}]/;
  
}

sub validate_user_object($user, $validate_password_field_present) {
  my $email = $user->{email};
  my $pass = $user->{password};

  if (!defined($email) || _trim($email) eq '' || _detect_gremlins($email)) {
    return undef;
  }

  # validate email-ness
  if ($email !~ m/.+@.+\..+$/) {
    return undef;
  }

  return 1 if !$validate_password_field_present && !defined($pass);

  # somtimes password field doesnt have to be present (like on PUT)
  # if passwd not being changed
  if (!defined($pass) || _trim($pass) eq '' || _detect_gremlins($pass) || length($pass) > 255) {
    return undef;
  }

  return 1;
}

# serve the admin SPA static page (if you're allowed to see it...)
sub admin_page_get ($self, $c) {
  $c->render('admin', email => $c->session->{user}->{email} // 'Unknown');
}

# create a user
sub add_user_post ($self, $c) {
  if (validate_user_object($c->req->json, 1)) {
    $self->user_service->add_user($c);  
  } else {
    $c->render(status => Constants::HTTP_BAD_REQUEST, json => { message => 'User object malformed'});
  }
}

# update a user
sub update_user_put ($self, $c) {
  if (validate_user_object($c->req->json, 0)) {
    $self->user_service->update_user($c);
  } else {
    $c->render(status => Constants::HTTP_BAD_REQUEST, json => { message => 'User object malformed'});
  }
}

# get all users or just one (if query param 'email' is present)
sub users_get ($self, $c) {
  # if we provide a single email via query param...
  if ($c->req->param('email')) {

    my $user = $self->user_service->get_single_user($c);
    if ($user) {
      return $c->render(json => $user);
    } else {
      $c->render(json => { message => 'User not found' }, status => Constants::HTTP_NOT_FOUND );
    }
  } else {

    # otherwise return all users
    $self->user_service->get_all_users($c);
  }
}

# delete a user (with query param 'email')
sub users_delete ($self, $c) {
  if ($c->req->param('email')) {
    my $user = $self->user_service->delete_single_user($c);
    if ($user) {
      return $c->render(json => { message => 'User Deleted' }, status => Constants::HTTP_NO_RESPONSE);
    } else {
      $c->render(json => { message => 'User not found' }, status => Constants::HTTP_NOT_FOUND );
    }
  } else {
    # bad request
    $c->render(json => { message => 'Email query param is required' }, status => Constants::HTTP_BAD_REQUEST );
  }
}

1;
