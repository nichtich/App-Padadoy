use strict;
use warnings;

use Test::More;
use Plack::Test;
use HTTP::Request::Common;

use_ok('YOUR_MODULE');

my $app = YOUR_MODULE->new;

test_psgi $app, sub {
    my $cb = shift;
    my $res = $cb->(GET "/");
    ok $res->content, "Non-empty response at '/'"; 
    is $res->code, "200", "HTTP status 200 at '/'";
};

done_testing;
