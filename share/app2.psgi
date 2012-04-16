use File::Basename qw(dirname);
use File::Spec;
use lib File::Spec->catdir(dirname(__FILE__), 'lib');

use YOUR_MODULE;

# TODO: if YOUR_MODULE derives from Dancer:
## use Dancer;
## dance;

# otherwise:
my $app = YOUR_MODULE->new;

$app;
