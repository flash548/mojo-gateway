package Controller::AdminController;
use Mojo::Base 'Mojolicious::Controller', -signatures;

# This is the Admin controller
# all the administrative actions come through here
# via the client's Admin Dashboard web UI

has 'user_service';

# serve the admin SPA static page (if you're allowed to see it...)
sub admin_page_get ($self, $c) {
  $c->render('admin', email => $c->session->{user}->{email} // 'Unknown');
}

# create a user
sub add_user_post ($self, $c) {
  $self->user_service->add_user($c);
}

# update a user
sub update_user_put ($self, $c) {
  $self->user_service->update_user($c);
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
