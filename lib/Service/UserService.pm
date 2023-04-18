package Service::UserService;
use Mojo::Base -base, -signatures;
use Time::Piece;
use Auth::GoogleAuth;

use Password::Utils;
use Constants;
use Utils;

has 'db';
has 'config';
has 'password_util' => sub { Password::Utils->new };

# other fields/keys ALLOWED to POST/PUT (otherwise they're ignored)
has 'user_obj_allowed_fields' => sub { ['reset_password', 'first_name', 'last_name', 'is_admin', 'user_id', 'is_mfa', 'locked'] };

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

# checks each incoming request that are destined to any route requiring
# authentication
sub check_user_status ($self, $c) {

  my $email = $c->session->{user}->{email};
  my $record;

  # if there's no current_user populated in the session cookie
  # then we're not authenticated, OR if we fail user lookup, then re-direct to the sign-in page...
  if (!$email || !defined(do { $record = $self->_get_user($email); $record; })) {

    # set return_to value to go back to initially requested url
    # dont allow redirect back to itself - default to /
    if ($c->req->url =~ m/auth\/login/ || !defined($c->req->url)) {
      $c->req->url('/');
    }
    $c->flash({return_to => $c->req->url});
    $c->redirect_to('/login');
    return undef;
  }

  # put the user record into the stash for reference later on if needed
  $c->stash({record => $record});
  
  # check if account is locked
  if ($record->{locked}) {
    # set return_to value to go back to initially requested url
    # dont allow redirect back to itself - default to /
    if ($c->req->url =~ m/auth\/login/ || !defined($c->req->url)) {
      $c->req->url('/');
    }
    $c->flash({return_to => $c->req->url, acct_locked => 1});
    $c->redirect_to('/login');
    return undef;
  }

  # covers the case where we log in with user/pass on an mfa acct, then we nav away and come back 
  # and we haven't done the mfa yet
  if ($c->session->{user_pass_ok} && $record->{is_mfa} && $c->req->url !~ /auth\/mfa\/entry/) {
    # so far so good, but we're an MFA account, so go do that
    $c->session->{user_pass_ok} = 1;
    $c->flash({return_to => $c->flash('return_to')});
    $c->redirect_to('/auth/mfa/entry');
    return undef;
  }

  # if user record shows we need to reset-password, and we're not already at the password path,
  #  then re-direct to that page
  if ($record->{reset_password} && $c->req->url !~ /auth\/password\/change/) {
    $c->flash({return_to => $c->req->url});
    $c->redirect_to('/auth/password/change');
    return undef;
  }

  # user authenticated OK or was already authenticated, check password expiry if we've defined
  #  that setting and its more than 0 days
  if (
    ( $record->{reset_password}
      || (defined($self->config->{password_valid_days}) && $self->config->{password_valid_days} > 0)
    )
    && $c->req->url !~ /auth\/password\/change/
  ) {
    # because we said so
    if ($record->{reset_password}) {
      $c->flash({return_to => $c->req->url, expired => 0, mandated => 1});
      $c->redirect_to('/auth/password/change');
      return undef;
    }

    # ok didnt blatantly say we need to change the password, so
    # if last_reset is undef, then set it to now, not sure how'd that be though, should default to current date time
    # otherwise check the age of the password
    if (!defined($record->{last_reset})) {
      $self->db->update("users", {last_reset => get_gmstamp()}, {email => lc $email});
    } else {

      # check days delta between NOW and last_reset
      my $last_reset = $record->{last_reset};
      if ($self->get_days_since_gmstamp($last_reset) >= $self->config->{password_valid_days}) {
        $c->flash({return_to => $c->req->url, expired => 1, mandated => 0});
        $c->redirect_to('/auth/password/change');
        return undef;
      }
    }
  }

  # if user account is set to be MFA-enabled, then check to see if we
  # need to set that up...
  if ($record->{is_mfa} && !defined($record->{mfa_secret}) && $c->req->url !~ /auth\/mfa\/init/) {
    $c->flash({return_to => $c->req->url});
    $c->session->{mfa_setup_required} = 1;
    $c->redirect_to('/auth/mfa/init');
    return undef;
  } elsif (!$record->{is_mfa} && defined($record->{mfa_secret})) {

    # if user is disenrolled from MFA but has a secret still on file - null that out
    $self->db->update('users', {mfa_secret => undef}, {email => $email});
  }

  # continue on
  return 1;
}

# handles the login process
sub do_login ($self, $c) {

  if (!$c->req->param('username') || !defined($c->req->param('password'))) {
    $c->render('login_page', login_failed => 1);
    return;
  }

  my $username = lc $c->req->param('username');
  my $password = $c->req->param('password');

  my $record = $self->_get_user($username);
  if ($record && $self->password_util->check_pass($record->{password}, $password)) {

    # fix an undef 'last_reset' to now
    if (!defined($record->{last_reset})) {
      $self->db->update("users", {last_reset => $self->get_gmstamp()}, {email => $username});
      $record = $self->_get_user($username);
    }

    # set the session cookie username - since user/pass was good
    $c->session->{user} = {email => $record->{email}};

    # if user account is set to be MFA-enabled, then check to see if we
    # need to set that up...
    if ($record->{is_mfa} && !defined($record->{mfa_secret})) {
      $c->flash({return_to => $c->req->url});
      $c->session->{mfa_setup_required} = 1;
      $c->redirect_to('/auth/mfa/init');
    } elsif ($record->{is_mfa}) {
      # so far so good, but we're an MFA account, so go do that
      $c->session->{user_pass_ok} = 1;
      $c->flash({return_to => $c->flash('return_to')});
      $c->redirect_to('/auth/mfa/entry');
    } else {

      # update person's last login time, set the session to the user's record
      # and return them to where they were trying to go to (or default to /)
      $self->db->update("users", {last_login => $self->get_gmstamp(), bad_attempts => 0}, {email => $username});
      $c->redirect_to($c->flash('return_to') // '/');
    }
  } else {
    # see if we're to allow a max number of unsuccessful password login attempts
    my $locked = 0;
    if (defined($self->config->{max_login_attempts})) {
      my $bad_attempts = ($record->{bad_attempts} // 0) + 1;
      $locked = $bad_attempts >= $self->config->{max_login_attempts};
      $self->db->update("users", { bad_attempts => $bad_attempts, locked => $locked }, {email => $username});
    } 
    $c->render('login_page', acct_locked => $locked, login_failed => 1, user => $username);
  }
}

# private method to get a user from the database with all fields present
sub _get_user ($self, $username) {
  return $self->db->select("users", undef, {email => lc $username})->hash;
}

# private method to say whether a user exists or not
sub _user_exists ($self, $username) {
  return defined($self->_get_user($username));
}

# gets all the users for the get-all-users endpoint
sub get_all_users ($self, $c) {
  my $users = $self->db->select('users')->hashes->map(sub { $self->sanatize_user_obj($_); $_; });
  $c->render(json => $users);
}

# helper to pull a single user from the db by their email
# using a private helper but sanatizing the return before we send it back
sub get_single_user ($self, $c) {
  my $user = $self->_get_user($c->req->param('email'));
  $self->sanatize_user_obj($user) if defined($user);
  return $user;
}

# helper to return a boolean on whether a user is admin-blessed
sub check_user_admin ($self, $c) {
  my $record = $self->_get_user($c->session->{user}->{email});
  return defined($record) && $record->{is_admin};
}

# helper to make sure we remove sensitive fields from user object
sub sanatize_user_obj ($self, $obj) {
  delete $obj->{password};      # dont ever return the password
  delete $obj->{mfa_secret};    # done ever return the mfa secret
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

    $self->sanatize_user_obj($new_user);
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

    my $existing_user = $self->_get_user(lc($c->req->json->{email}));

    # now go through the keys of the payload and update the existing_user record
    # if new field wasn't undefined - that way we dont always have to provide password updates if we're not changing it
    # if we have to go in an manually expire someone's account
    my $user = $c->req->json;
    for my $key (keys %{$user}) {
      if (defined($user->{$key})) {

        # check if its a password field, and its defined/truthy then update password field
        if ($key eq 'password' && defined($user->{password}) && $user->{password} ne '') {
          $existing_user->{password}   = $self->password_util->encode_password($user->{password});
          $existing_user->{last_reset} = $self->get_gmstamp();
        } elsif ($key eq 'locked' &&  defined($user->{locked}) && !$user->{locked}) {

          # if its the 'locked' field, and its defined and falsy, then reset not just 'locked'
          # but also reset any bad attempts
          $existing_user->{locked} = 0;
          $existing_user->{bad_attempts} = 0;
        } elsif (grep { $key =~ m/$_/ } @{$self->user_obj_allowed_fields}) {

          # if its an allowed field for the body model, then add it to the existing_user obj
          # we're about to persist...
          $existing_user->{$key} = $user->{$key};
        }
      }
    }

    # clear out MFA hash if we're disabling MFA for this user
    if (defined($user->{is_mfa}) && !$user->{is_mfa}) {
      $existing_user->{mfa_secret} = undef;
    }

    # commit the update
    $self->db->update('users', $existing_user, {email => lc($existing_user->{email})});
    my $updated_user = $self->_get_user(lc($existing_user->{email}));

    # dont ever return the password or the MFA secret
    $self->sanatize_user_obj($updated_user);

    $c->render(status => Constants::HTTP_OK, json => $updated_user);
  } else {
    $c->render(status => Constants::HTTP_NOT_FOUND, json => {message => 'User does not exist'});
  }
}

# handles a user password change submission
sub do_password_change ($self, $c) {

  my $existing_password = $c->req->param('current-password');
  my $new_password      = $c->req->param('new-password');
  my $retyped_password  = $c->req->param('retyped-new-password');

  if (!$existing_password || !$new_password || !$retyped_password) {
    $c->flash({return_to => $c->flash('return_to'), error_msg => 'Required fields not present or they were blank'});
    $c->redirect_to('/auth/password/change',);
  }

  # check for empty pass after trim (even though it would fail complexity anyways...)
  elsif (Utils::trim($existing_password) eq ''
    || Utils::trim($new_password) eq ''
    || Utils::trim($retyped_password) eq '') {
    $c->flash({return_to => $c->flash('return_to'), error_msg => 'Passwords cannot be whitespace'});
    $c->redirect_to('/auth/password/change',);
  }

  # check for non-ascii
  elsif (Utils::detect_gremlins($existing_password)
    || Utils::detect_gremlins($new_password)
    || Utils::detect_gremlins($retyped_password)) {
    $c->flash({return_to => $c->flash('return_to'), error_msg => 'Passwords cannot contain non-ascii characters'});
    $c->redirect_to('/auth/password/change',);
  }

  # check for max length
  elsif (length($new_password) > 255) {
    $c->flash({return_to => $c->flash('return_to'), error_msg => 'Passwords cannot exceed 255 chars'});
    $c->redirect_to('/auth/password/change',);
  }

  # see if the existing password was correct
  elsif (!$existing_password
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
    $c->flash({return_to => $c->flash('return_to'), error_msg => 'New Password does not meet complexity requirements', complexity => $self->config->{password_complexity}});
    $c->redirect_to('/auth/password/change',);
  }

  # if we make it here, then change the password in the database, and update the user's session
  else {

    $self->db->update(
      "users",
      { password       => $self->password_util->encode_password($new_password),
        reset_password => 0,
        bad_attempts => 0,
        bad_attempts => 0,
        last_reset     => $self->get_gmstamp()
      },
      {email => $c->session->{user}->{email}}
    );

    $c->redirect_to($c->flash('return_to') // '/');
  }
}

# returns 'now' as a ISO8601 UTC string (with no 'Z')
sub get_gmstamp {
  return gmtime()->datetime;
}

# TODO: re-consider refactor for this... find when the `%Y-%m-%dT%H:%M:%S` vs
# `%Y-%m-%d %H:%M:%S` format presents itself.  I think its on brand new accounts?
#
# returns time since given date stamp (in ISO 8601 format) in days
sub get_days_since_gmstamp ($self, $time) {
  if (defined($self->config->{db_type}) && $self->config->{db_type} eq 'pg') {

    # consider if time format is of varying formats for pg
    if ($time =~ m/^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d$/) {
      return (gmtime() - Time::Piece->strptime($time, "%Y-%m-%dT%H:%M:%S"))->days;
    } else {
      return (gmtime() - Time::Piece->strptime($time, "%Y-%m-%d %H:%M:%S"))->days;
    }

  } else {
    return (gmtime() - Time::Piece->strptime($time, "%Y-%m-%dT%H:%M:%SZ"))->days;
  }
}

# deletes a single user - given their email
sub delete_single_user ($self, $c) {
  my $username = lc $c->req->param('email');
  if (!$self->_user_exists($username)) {
    $c->rendered(Constants::HTTP_NOT_FOUND);
    return;
  }

  $self->db->delete('users', {email => $username});
}

# handler to check a submitted MFA code against the server's
# generated code.
sub check_mfa_code ($self, $c) {

  # pull users record...so we can get their MFA secret
  my $record = $self->_get_user($c->session->{user}->{email});
  if (!$record || !$record->{mfa_secret} || !$record->{is_mfa}) {
    $c->render(text => 'This is not a valid account for MFA');
    return;
  }

  # load the code, check the code
  my $auth = Auth::GoogleAuth->new;
  $auth = Auth::GoogleAuth->new({
    secret => $self->config->{mfa_secret} // 'secret',
    issuer => $self->config->{mfa_issuer} // 'mojo_gateway',
    key_id => $self->config->{mfa_key_id} // 'login',
  });
  $auth->secret32($record->{mfa_secret});

  my $code = $c->req->param('mfa-entry');
  if (!defined($code) || !$auth->verify($code)) {

    # bad request, try again
    $c->flash({return_to => $c->flash('return_to')});
    $c->render('mfa_entry_page', mfa_failed => 1);
  } else {

    # they matched
    # update person's last login time, set the session to the user's record
    # and return them to where they were trying to go to (or default to /)
    delete $c->session->{user_pass_ok};
    $self->db->update("users", {last_login => $self->get_gmstamp()}, {email => $record->{email}});
    $c->session->{user} = {email => $record->{email}};
    $c->redirect_to($c->flash('return_to') // '/');
  }
}

# hander that presents the QR code page for when a user
# enrolls into MFA
sub set_up_mfa ($self, $c) {
  my $auth = Auth::GoogleAuth->new;
  $auth = Auth::GoogleAuth->new({
    secret => $self->config->{mfa_secret} // 'secret',
    issuer => $self->config->{mfa_issuer} // 'mojo_gateway',
    key_id => $self->config->{mfa_key_id} // 'login',
  });

  my $secret32 = $auth->generate_secret32;
  my $png_url  = $auth->qr_code($secret32);

  # put secret in flash for the finalization stage
  $c->flash({qr_code => $secret32});

  # render the mfa qr page
  $c->render('mfa_qr_page', qr_code_url => $png_url);
}

# handler for when user is done with the MFA init/enroll
# QR code page, here we write the secret to the database and
# then attempt to forward them to their original destination
sub finalize_mfa_setup ($self, $c) {
  delete $c->session->{mfa_setup_required};
  $c->flash({return_to => $c->flash('return_to')});

  # store this users secret
  $self->db->update('users', {mfa_secret => $c->flash('qr_code')}, {email => $c->session->{user}->{email}});

  $c->redirect_to($c->flash('return_to') // '/');
}

# helper to mark all accounts as MFA enabled on app bootstrap
# note that unmarking that setting in the config will NOT disable
# MFA from accounts...
sub mark_all_as_mfa ($self) {
  if ( $self->config->{mfa_force_on_all}
    && $self->config->{mfa_secret}
    && $self->config->{mfa_issuer}
    && $self->config->{mfa_key_id}) {

    # enable MFA for all users
    $self->db->update('users', {is_mfa => 1});
  }
}

1;
