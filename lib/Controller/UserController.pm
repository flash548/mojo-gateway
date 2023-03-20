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


1;
