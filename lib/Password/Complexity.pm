package Password::Complexity;
use Mojo::Base -base, -signatures;

sub check_complexity ($self, $new_password) {

    return 0 if (length($new_password) < 8  # check for length
        || $new_password !~ m/[[:punct:]]/  # check for punctuations
        || $new_password !~ m/[[:alpha:]]/  # check for alphas
        || $new_password !~ m/[[:digit:]]/  # check for digits
        || $new_password =~ m/\s/           # shouldn't contain spaces
    );
}

1;