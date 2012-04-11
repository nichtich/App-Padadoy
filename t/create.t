#!/usr/bin/perl

use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Cwd;

use App::padadoy;

my ($cwd) = (cwd =~ /^(.*)$/g); # untainted cwd

my $dir = tempdir( CLEANUP => 1 );
chdir $dir;

my $padadoy = App::padadoy->new;
$padadoy->create;


ok( -f File::Spec->catfile($dir,'app','app.psgi'),    'app.psgi created' );
ok( -f File::Spec->catfile($dir,'app','Makefile.PL'), 'Makefile.PL created' );


chdir $cwd; # be back before cleanup
done_testing;
