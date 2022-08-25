package Password::Utils;
use Mojo::Base -base, -signatures;

use Crypt::Bcrypt qw/bcrypt bcrypt_check/;
use Data::Entropy::Algorithms qw(rand_bits);

sub check_complexity ($self, $new_password, $params) {

    # no complexity supplied - done here
    return 1 if !defined($params);

    my @alphas = $new_password =~ m/([[:alpha:]])/g;
    my @punct = $new_password =~ m/([[:punct:]])/g;
    my @digits = $new_password =~ m/([[:digit:]])/g;

    return 0 if (length($new_password) < $params->{min_length}  # check for length
        || @punct < $params->{specials} # check for punctuations
        || @alphas < $params->{alphas}  # check for alphas
        || @digits < $params->{numbers}  # check for digits
        || $new_password =~ m/\s/           # shouldn't contain spaces
    );

    return 1;
}


sub encode_password ($self, $password) {
  return bcrypt( $password, "2b", 12, rand_bits( 16 * 8 ) );
}


# compares the database-stored hash to the hashed version of $password
# returns 1 if they match (aka user gave the correct password)
sub check_pass ( $self, $db_password, $password ) {
  return bcrypt_check( $password, $db_password );
}

1;