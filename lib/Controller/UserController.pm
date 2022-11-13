package Controller::UserController;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Password::Utils;

# These are all authenticated user-reachable endpoints or always-reachable
# ones such as login/logout

has 'user_service';

sub login_page_get ($self, $c) {
  $c->flash({return_to => $c->flash('return_to') // '/'});
  $c->render('login_page');
}

sub logout_get ($self, $c) {
  $c->session(expires => 1);
  $c->flash({ return_to => '/'});
  $c->redirect_to('/login');
}

sub login_post ($self, $c) {
  $self->user_service->do_login($c);
}

sub password_change_form_get ($self, $c) {

  # preserve the flash value
  $c->flash({return_to => $c->flash('return_to') // '/'});

  # render the change_password form
  $c->render('password_change');
}

sub password_change_post ($self, $c) {
  $self->user_service->do_password_change($c);
}


1;
