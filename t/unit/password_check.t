use Mojolicious;
use Password::Utils;
use Test::More;

subtest 'Password Complexity' => sub {
  my $config = {alphas => 1, numbers => 1, specials => 1, spaces => 0, min_length => 8,};

  my $checker = Password::Utils->new;
  ok !$checker->check_complexity('ok',          $config), 'Test Bad Password Length';
  ok $checker->check_complexity('999a_djjdd',   $config), 'Test Password Length Good';
  ok !$checker->check_complexity('aaaaa_djjdd', $config), 'Test No Required Amount of Numbers';
  ok !$checker->check_complexity('9999_99999',  $config), 'Test No Required Amount of Letters';
  ok !$checker->check_complexity('9999a99999',  $config), 'Test No Required Amount of Specials';
  ok !$checker->check_complexity('9999 99999',  $config), 'Test Spaces Not Allowed';

};

subtest 'Password Encoding/Decoding' => sub {
  my $checker  = Password::Utils->new;
  my $password = "Boilers_Rule";

  my $enc = $checker->encode_password($password);
  ok $checker->check_pass($enc,  "Boilers_Rule"),  'Passes Password Check';
  ok !$checker->check_pass($enc, "Boilers_Rulez"), 'Fails Password Check';
};

done_testing();
