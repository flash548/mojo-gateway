use Mojolicious;
use Password::Complexity;
use Test::More;

my $config = {
    alphas     => 1,
    numbers    => 1,
    special    => 1,
    spaces     => 0,
    min_length => 8,
};

my $checker = Password::Complexity->new;
ok $checker->check_complexity('ok', $config) == 0, 'Test Bad Password Length';


done_testing();
