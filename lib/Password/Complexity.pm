package Password::Complexity;
use Mojo::Base -base, -signatures;

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

1;