package Service::UserService;
use Mojo::Base -base, -signatures;
use Time::Piece;

use Password::Utils;
use Constants;

has 'db';
has 'config';
has 'password_util'           => sub { Password::Utils->new };

# other fields/keys allowed to POST/PUT besides the the email field (otherwise they're ignored)
has 'user_obj_allowed_fields' => sub { ['reset_password', 'first_name', 'last_name', 'is_admin', 'user_id'] };

# creates a default admin user if it doesnt exist
sub create_admin_user ($self) {
  $self->db->insert(
    users => {
      email    => lc $self->config->{admin_user},
      password => $self->password_util->encode_password($self->config->{admin_pass}),
      user_id  => 123456789,
      is_admin => 1
    }
  ) unless defined($self->db->select('users', undef, {email => $self->config->{admin_user}})->hash);
}

sub check_user_status ($self, $c) {

  # if there's no current_user populated in the session cookie,
  # then we're not authenticated, so re-direct to the sign-in page...
  unless ($c->session->{user}->{email}) {

    # set return_to value to go back to initially requested url
    # dont allow redirect back to itself - default to /
    if ($c->req->url =~ m/auth\/login/ || !defined($c->req->url)) {
      $c->req->url('/');
    }
    $c->flash({return_to => $c->req->url});
    $c->redirect_to('/login');
    return undef;
  }

# if user record shows we need to reset-password, and we're not already at the password path,
#  then re-direct to that page
  if ($c->session->{user}->{reset_password} && $c->req->url !~ /auth\/password\/change/) {
    $c->flash({return_to => $c->req->url});
    $c->redirect_to('/auth/password/change');
    return undef;
  }

# user authenticated OK or already-authenticated, check password expiry if we've defined
#  that setting and its more than 0 days
  if (
    (
      $c->session->{user}->{reset_password}
      || (defined($self->config->{password_valid_days}) && $self->config->{password_valid_days} > 0)
    )
    && $c->req->url !~ /auth\/password\/change/
  ) {
    # because we said so
    if ($c->session->{user}->{reset_password}) {
      $c->flash({return_to => $c->req->url, expired => 0, mandated => 1});
      $c->redirect_to('/auth/password/change');
      return undef;
    }

# ok didnt blatantly say we need to change the password, so
# if last_reset is undef, then set it to now, not sure how'd that be though, should default to current date time
# otherwise check the age of the password
    if (!defined($c->session->{user}->{last_reset})) {
      $self->db->update("users", {last_reset => get_gmstamp()}, {email => lc $c->session->{user}->{email}});
    } else {

      # check days delta between NOW and last_reset
      my $last_reset = $c->session->{user}->{last_reset};
      if ($self->get_days_since_gmstamp($last_reset) >= $self->config->{password_valid_days}) {
        $c->flash({return_to => $c->req->url, expired => 1, mandated => 0});
        $c->redirect_to('/auth/password/change');
        return undef;
      }
    }
  }

  # continue on to the routes below
  return 1;
}

sub do_login ($self, $c) {

  if (!$c->req->param('username') || !$c->req->param('password')) {
    $c->render(json => {message => 'Username and password fields are required'}, status => Constants::HTTP_BAD_REQUEST);
  }

  my $username = lc $c->req->param('username');
  my $password = $c->req->param('password');

  my $record = $self->_get_user($username);
  if ($record && $self->password_util->check_pass($record->{password}, $password)) {
    delete $record->{password};

    # fix an undef 'last_reset' to now
    if (!defined($record->{last_reset})) {
      $self->db->update("users", {last_reset => $self->get_gmstamp()}, {email => $username});
      $record = $self->_get_user($username);
      delete $record->{password};
    }

    # update person's last login time, set the session to the user's record
    # and return them to where they were trying to go to (or default to /)
    $self->db->update("users", {last_login => $self->get_gmstamp()}, {email => $username});
    $record = $self->_get_user($username);
    $c->session->{user} = $record;
    $c->redirect_to($c->flash('return_to') // '/');
  } else {
    $c->render('login_page', login_failed => 1);
  }
}

sub _get_user ($self, $username) {
  return $self->db->select("users", undef, {email => lc $username})->hash;
}

sub _user_exists ($self, $username) {
  return defined($self->_get_user($username));
}

sub get_all_users ($self, $c) {
  my $users = $self->db->select('users', ['email', 'reset_password', 'user_id', 'last_reset', 'last_login', 'is_admin'])
    ->hashes;
  $c->render(json => $users);
}

sub get_single_user ($self, $c) {
  my $user = $self->_get_user($c->req->param('email'));
  delete $user->{password} if defined($user);
  return $user;
}

sub check_user_admin ($self, $c) {
  return $c->session->{user}->{is_admin};
}

# adds a new user
sub add_user ($self, $c) {

  if ($self->db->select('users', undef, {email => lc $c->req->json->{email}})->hashes->size > 0) {
    $c->render(status => Constants::HTTP_CONFLICT, json => {message => 'User exists'});
  } else {
    my $user = {};
    if (!$c->req->json->{email} || !$c->req->json->{password}) {
      $c->render(json => {message => 'Email and Password required minimum'}, status => Constants::HTTP_BAD_REQUEST);
      return;
    }
    $user->{email}    = lc $c->req->json->{email};
    $user->{password} = $self->password_util->encode_password($c->req->json->{password});

    # copy over rest of "allowed" fields
    for my $field (@{$self->user_obj_allowed_fields}) {
      if (defined($c->req->json->{$field})) {
        $user->{$field} = $c->req->json->{$field};
      }
    }

    $self->db->insert(users => $user);
    my $new_user = $self->_get_user($c->req->json->{email});

    delete $new_user->{password};    # dont ever return the password
    $c->render(status => Constants::HTTP_CREATED, json => $new_user);
  }
}

# updates user
sub update_user ($self, $c) {
  if (!$c->req->json->{email}) {
    $c->render(json => {message => 'Email required minimum'}, status => Constants::HTTP_BAD_REQUEST);
    return;
  }

  if ($self->db->select('users', undef, {email => lc $c->req->json->{email}})->hashes->size) {

    my $existing_user     = $self->_get_user(lc($c->req->json->{email}));

    # now go through the keys of the payload and update the existing_user record
    # if new field wasn't undefined - that way we dont always have to provide password updates if we're not changing it
    # if we have to go in an manually expire someone's account
    my $user = $c->req->json;
    for my $key (keys %{$user}) {
      if (defined($user->{$key})) {

        # check if its a password field
        if ($key eq 'password' && defined($user->{password}) && $user->{password} ne '') {
          $existing_user->{password}   = $self->password_util->encode_password($user->{password});          
          $existing_user->{last_reset} = $self->get_gmstamp();
        } elsif (grep { $key =~ m/$_/} @{$self->user_obj_allowed_fields}) {
          # if its an allowed field for the body model, then add it to the existing_user obj
          # we're about to persist...
          $existing_user->{$key} = $user->{$key};
        }
      }
    }

    $self->db->update('users', $existing_user, {email => lc($existing_user->{email})});
    my $updated_user = $self->_get_user(lc($existing_user->{email}));

    # dont ever return the password
    delete $updated_user->{password};

    $c->render(status => Constants::HTTP_OK, json => $updated_user);
  } else {
    $c->render(status => Constants::HTTP_NOT_FOUND, json => {message => 'User does not exist'});
  }
}

sub do_password_change ($self, $c) {

  if (!$c->req->param('current-password') || !$c->req->param('new-password') || !$c->req->param('retyped-new-password'))
  {
    $c->flash({return_to => $c->flash('return_to'), error_msg => 'Required fields not present or they were blank'});
    $c->redirect_to('/auth/password/change',);
    return;
  }

  my $existing_password = $c->req->param('current-password');
  my $new_password      = $c->req->param('new-password');
  my $retyped_password  = $c->req->param('retyped-new-password');

  # see if the existing password was correct
  if ( !$existing_password
    || !$self->password_util->check_pass($self->_get_user($c->session->{user}->{email})->{password}, $existing_password)
  ) {
    $c->flash({return_to => $c->flash('return_to'), error_msg => 'Existing Password Incorrect'});
    $c->redirect_to('/auth/password/change',);
  }

  # see if the new password doesn't equal the existing password
  elsif ($new_password eq $existing_password) {
    $c->flash({return_to => $c->flash('return_to'), error_msg => 'New Password cannot equal the existing password'});
    $c->redirect_to('/auth/password/change',);
  }

  # make sure the retyped password equals the new password
  elsif ($new_password ne $retyped_password) {
    $c->flash({return_to => $c->flash('return_to'), error_msg => 'New Password does not equal Retyped New Password'});
    $c->redirect_to('/auth/password/change',);
  }

  # make sure we pass the complexity checks
  elsif (!$self->password_util->check_complexity($new_password, $self->config->{password_complexity})) {
    $c->flash({return_to => $c->flash('return_to'), error_msg => 'New Password does not meet complexity requirements'});
    $c->redirect_to('/auth/password/change',);
  }

# if we make it here, then change the password in the database, and update the user's session
  else {

    $self->db->update(
      "users",
      {
        password       => $self->password_util->encode_password($new_password),
        reset_password => 0,
        last_reset     => $self->get_gmstamp()
      },
      {email => $c->session->{user}->{email}}
    );

    # now update the session cookie with updated user record, so we
    # don't get to the change password screen again on next request
    my $record = $self->_get_user($c->session->{user}->{email});
    delete $record->{password};
    $c->session->{user} = $record;

    $c->redirect_to($c->flash('return_to') // '/');
  }
}

# returns 'now' as a ISO8601 UTC string (with no 'Z')
sub get_gmstamp {
  return gmtime()->datetime;
}

# returns time since given date stamp (in ISO 8601 format) in days
sub get_days_since_gmstamp ($self, $time) {
  if (defined($self->config->{db_type}) && $self->config->{db_type} eq 'pg') {
    return (gmtime() - Time::Piece->strptime($time, "%Y-%m-%d %H:%M:%S"))->days;
  } else {
    return (gmtime() - Time::Piece->strptime($time, "%Y-%m-%dT%H:%M:%SZ"))->days;
  }
}

sub delete_single_user ($self, $c) {
  my $username = lc $c->req->param('email');
  if (!$self->_user_exists($username)) {
    $c->rendered(Constants::HTTP_NOT_FOUND);
    return;
  }

  $self->db->delete('users', {email => $username});
}

1;
