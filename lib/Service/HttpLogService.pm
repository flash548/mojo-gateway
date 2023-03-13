package Service::HttpLogService;
use Mojo::Base -base, -signatures;
use Time::Piece;

use Constants;

has 'db';
has 'config';


1;