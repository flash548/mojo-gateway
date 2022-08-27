package Controller::Admin;
use Mojo::Base 'Mojolicious::Controller', -signatures;

has 'user_service';

sub admin_page_get($self, $c) {
  if (!$self->user_service->check_user_admin($c)) {
    $c->render('no_response');
    return;
  }

  $c->render('admin');
};

sub add_user_post($self, $c) {
  if (!$self->user_service->check_user_admin($c)) {
    $c->rendered(403);
    return;
  }

  $self->user_service->add_user($c);
};

sub update_user_put($self, $c) {
  if (!$self->user_service->check_user_admin($c)) {
    $c->rendered(403);
    return;
  }

  $self->user_service->update_user($c);
};


sub all_users_get($self, $c) {
  if (!$self->user_service->check_user_admin($c)) {
    $c->rendered(403);
    return;
  }

  $self->user_service->get_all_users($c);
};


1;
