#!/usr/bin/perl

use Test::More;
use File::Temp qw(tempdir);
use File::Spec::Functions;
use Cwd;

use App::Padadoy;

my ($cwd) = (cwd =~ /^(.*)$/g); # untainted cwd

my $devdir = tempdir( CLEANUP => 1 );
chdir $devdir;

my $padadoy = App::Padadoy->new('', quiet => 1);
$padadoy->create('Foo::Bar');

ok( -d catdir($devdir,$_), "$_/ created" )
    for qw(app data logs app/lib app/t app/lib/Foo libs);

ok( -f catdir($devdir,$_), "$_ created" )
    for qw(app/app.psgi app/lib/Foo/Bar.pm dotcloud.yml);

# TODO: deplist.txt is not checked

# TODO: test newly created application

chdir $cwd; # be back before cleanup
done_testing;
