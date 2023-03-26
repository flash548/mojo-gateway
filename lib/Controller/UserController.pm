package Controller::UserController;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Password::Utils;

# These are all authenticated-user-reachable endpoints or always-reachable
# ones such as login/logout

has 'user_service';

# GET /login
#
# Reachable by: anyone (public)
#
# Description:
# Presents the login page
#
# Content-Type: 'text/html'
sub login_page_get ($self, $c) {
  $c->flash({return_to => $c->flash('return_to') // '/'});
  $c->render('login_page');
}

# GET /logout
#
# Reachable by: anyone (public)
#
# Description:
# Logs out a user
#
# Content-Type: 'text/html'
sub logout_get ($self, $c) {
  $c->session(expires => 1);
  $c->flash({return_to => '/'});
  $c->redirect_to('/login');
}

# POST /auth/login
#
# Reachable by: anyone (public)
#
# Body-
# { username, password }
#
# Description-
# Handles logging in a user, which if successful will redirect them where requested
# or if not successful, will keep them on the login page with a given error message
#
# Content-Type: 'text/html'
sub login_post ($self, $c) {
  $self->user_service->do_login($c);
}

# GET /auth/password/change
#
# Reachable by: any logged in USER
#
# Description:
# Presents the password change page
#
# Content-Type: 'text/html'
sub password_change_form_get ($self, $c) {

  # preserve the flash value
  $c->flash({return_to => $c->flash('return_to') // '/'});

  # render the change_password form
  $c->render('password_change');
}

# POST /auth/password/change
#
# Reachable by: any logged in user
#
# Description:
# Handles password change request
#
# Content-Type: 'form-data'
sub password_change_post ($self, $c) {
  $self->user_service->do_password_change($c);
}


# GET /auth/mfa/init
#
# Reachable by: any logged in user AND a logged in user that has to init MFA
#
# Description: Renders the MFA init page template
#
# Content-Type: 'text/html'
sub mfa_init_form_get ($self, $c) {

  # check that we're not just arbitrarily trying to come here
  # check that we were sent here
  if ($c->session->{mfa_setup_required}) {
    $self->user_service->set_up_mfa($c);
  } else {
    $c->render('restricted_page');
  }

}

# POST /auth/mfa/init
#
# Reachable by: any logged in user AND a logged in user that has to init MFA
#
# Description: Signals that user is done with MFA setup and continues on to orginal
# requested page
#
# Content-Type: 'text/html'
sub mfa_init_form_post ($self, $c) {
  if ($c->session->{mfa_setup_required}) {
    delete $c->session->{mfa_setup_required};
    $c->flash({return_to => $c->flash('return_to')});
    $c->redirect_to($c->flash('return_to') // '/');
  } else {
    $c->render('restricted_page');
  }
}

sub mfa_entry_form_get ($self, $c) {

  # check that we just came from a successful user/pass entry...
  if ($c->session->{user_pass_ok}) {
    $c->user_service->render('mfa_entry_page');
  } else {
    $c->render('restricted_page');
  }
}

sub mfa_entry_form_post ($self, $c) {

  # check that we just came from a successful user/pass entry...
  if ($c->session->{user_pass_ok}) {
    $c->user_service->check_mfa_code($c);
  } else {
    $c->render('restricted_page');
  }
}



1;
