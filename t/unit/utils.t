use Test::Mojo;
use Test::More;
use Utils;

subtest 'Check String Trim' => sub {
  my $str = "     stuff   \t\t";
  ok length(Utils::trim($str)) == 5, 'Check whitespace trimmed off';
};

subtest 'Check Detect Gremlins' => sub {
  ok Utils::detect_gremlins("Hello\0World"), 'Check nul char found';
  ok Utils::detect_gremlins("Hello\nWorld"), 'Check newline char found';
  ok Utils::detect_gremlins("Hello✅World"),  'Check unicode char found';
  ok !Utils::detect_gremlins("Hello"),       'Check no gremlins found';
};

subtest 'Check User Object' => sub {
  ok !Utils::validate_user_object({}, 0), 'Blank User Object bad';
  ok !Utils::validate_user_object({email => ''},                           0), 'Blank Email';
  ok !Utils::validate_user_object({email => "\n"},                         0), 'Blank Email 2';
  ok !Utils::validate_user_object({email => "\0"},                         0), 'Blank Email 3';
  ok !Utils::validate_user_object({email => "     "},                      0), 'Blank Email 4';
  ok !Utils::validate_user_object({email => "✅\@test.com"},                0), 'Email unicodef';
  ok !Utils::validate_user_object({email => "h@" . "test" x 100 . ".com"}, 0), 'Email over 255 chars';
  ok !Utils::validate_user_object({email => undef},                        0), 'Email null';

  ok !Utils::validate_user_object({email => "jim\@test.com"}, 1), 'Password null';
  ok !Utils::validate_user_object({email => "jim\@test.com", password => '  '},      1), 'Password blank';
  ok !Utils::validate_user_object({email => "jim\@test.com", password => '✅'},       1), 'Password unicode';
  ok !Utils::validate_user_object({email => "jim\@test.com", password => '1' x 256}, 1), 'Password too long - >255';

  ok Utils::validate_user_object({email => 'james@test.com'}, 0), 'Valid user object';

  # password complexity eval'd elsewhere
  ok Utils::validate_user_object({email => 'james@test.com', password => '1'}, 1), 'Valid user object 2';
};

subtest 'Check ISO String Format' => sub {

  ok !Utils::validate_ISO_string(undef), 'Date check - 1';
  ok !Utils::validate_ISO_string(''), 'Date check - 1';
  ok !Utils::validate_ISO_string('2022-31-31T00:00:00'), 'Date check - 3';
  ok Utils::validate_ISO_string('2022-03-31T00:00:00'), 'Date check - 4';
};


done_testing();
