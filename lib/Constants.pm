package Constants;

# package to alias HTTP statuses to plain english

use constant HTTP_OK          => 200;
use constant HTTP_CREATED     => 201;
use constant HTTP_NO_CONTENT  => 204;
use constant HTTP_BAD_REQUEST => 400;
use constant HTTP_FORBIDDEN   => 403;
use constant HTTP_NOT_FOUND   => 404;
use constant HTTP_CONFLICT    => 409;
use constant HTTP_REDIRECT    => 302;

1;
