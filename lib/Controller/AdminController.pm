package Controller::AdminController;
use Mojo::Base 'Mojolicious::Controller', -signatures;

# This is the Admin controller
# all the administrative actions come through here
# via the client's Admin Dashboard web UI

has 'user_service';

sub admin_page_get ($self, $c) {
  $c->render('admin');
}

sub add_user_post ($self, $c) {
  $self->user_service->add_user($c);
}

sub update_user_put ($self, $c) {
  $self->user_service->update_user($c);
}

sub users_get ($self, $c) {
  # if we provide a single email via query param...
  if ($c->req->param('email')) {

    my $user = $self->user_service->get_single_user($c);
    if ($user) {
      return $c->render(json => $user);
    } else {
      $c->rendered(Constants::HTTP_NOT_FOUND);
    }
  } else {

    # otherwise return all users
    $self->user_service->get_all_users($c);
  }
}


sub users_delete ($self, $c) {
  if ($c->req->param('email')) {
    my $user = $self->user_service->delete_single_user($c);
    if ($user) {
      return $c->rendered(Constants::HTTP_NO_RESPONSE);
    } else {
      $c->rendered(Constants::HTTP_NOT_FOUND);
    }
  } else {
    # bad request
    $c->rendered(Constants::HTTP_BAD_REQUEST);
  }
}

1;
