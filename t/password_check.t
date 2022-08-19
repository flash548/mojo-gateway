use Mojolicious;
use Password::Complexity;
use Test::More;

my $config = {
    alphas     => 1,
    numbers    => 1,
    specials   => 1,
    spaces     => 0,
    min_length => 8,
};

my $checker = Password::Complexity->new;
ok !$checker->check_complexity('ok', $config), 'Test Bad Password Length';
ok $checker->check_complexity('999a_djjdd', $config), 'Test Password Length Good';
ok !$checker->check_complexity('aaaaa_djjdd', $config), 'Test No Required Amount of Numbers';
ok !$checker->check_complexity('9999_99999', $config), 'Test No Required Amount of Letters';
ok !$checker->check_complexity('9999a99999', $config), 'Test No Required Amount of Specials';
ok !$checker->check_complexity('9999 99999', $config), 'Test Spaces Not Allowed';

done_testing();
