#!/usr/bin/perl
use ExtUtils::MakeMaker;
use autodie;

# You should better add your dependencies in deplist.txt!

my %deplist = ();

if (-f 'deplist.txt') {
	open my $fh, '<', 'deplist.txt';
    %deplist = map { 
        chomp;
        $_ => 0;
    } grep { $_ !~ /^\s*(#.*)?$/ } <$fh>;
	close $fh;
}

WriteMakefile(
    PREREQ_PM => {
        %deplist,
        'Plack::Handler::Starman' => 0,
        # Comment out if you need HTTPS
        # 'Crypt::OpenSSL::Random'   => 0.04,
     }
);
