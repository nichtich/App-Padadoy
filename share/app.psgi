use File::Basename qw(dirname);
use File::Spec;
use lib File::Spec->catdir(dirname(__FILE__), 'lib');

# add your local modules here...

my $app = sub {
    my $self = shift;
    my $body = 'Hello world!'; 
    [200, ['Content-Type' => 'text/plain'], [ $body ]];
};
