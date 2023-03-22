package Utils;
use Time::Piece;
use feature qw/signatures/;


# returns a string with all leading and trailing whitespace removed
sub trim {
  return $_[0] =~ s/^\s+|\s+$//gr;
}

# detects if string contains control chars or unicode (non-ascii) chars
# and returns 1 if so.  Otherwise undef
sub detect_gremlins ($in) {

  # no cntrl chars
  return 1 if $in =~ m/\p{cntrl}/;

  # no non-ascii
  return 1 if $in =~ m/[^\p{ascii}]/;

}

# validates the str is of format yyyy-mm-ddThh:mm:ss (without the Zulu postfix)
sub validate_ISO_string ($str) {
  return 0 if $str !~ m/^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d$/;

  eval { Time::Piece->strptime($str, "%Y-%m-%dT%H:%M:%S"); };

  if ($@) { return 0; }

  return 1;
}

# validates a user object's certain fields to be valid
#
# $user - the user object to validate
# $validate_password_field_present - 1 if we're to affirm the password field is present and valid
#
# returns 1 if object good with given data/options, otherwise undef
sub validate_user_object ($user, $validate_password_field_present) {
  my $email = $user->{email};
  my $pass  = $user->{password};

  if (!defined($email) || trim($email) eq '' || detect_gremlins($email) || length($email) > 255) {
    return undef;
  }

  # validate email-ness
  if ($email !~ m/.+@.+\..+$/) {
    return undef;
  }

  # no point continuing if we don't care if the password field is present
  # and on user updates, if password field isn't provided then we didnt want to update/change
  # the password anyways
  return 1 if !$validate_password_field_present && !defined($pass);

  # sometimes password field doesnt have to be present (like on PUT)
  # if passwd not being changed
  if (!defined($pass) || trim($pass) eq '' || detect_gremlins($pass) || length($pass) > 255) {
    return undef;
  }

  return 1;
}

1;
