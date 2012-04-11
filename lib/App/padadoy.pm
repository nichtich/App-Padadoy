use strict;
use warnings;
package App::padadoy;
#ABSTRACT: Simply deploy PSGI web applications

use 5.010;
use autodie;
use Try::Tiny;
use IPC::System::Simple qw(run capture);
use File::Slurp;
use File::ShareDir qw(dist_file);
use Sys::Hostname;
use Cwd;

# required for deployment
use Plack::Handler::Starman;
use Carton;

# some utility functions
sub _fail ($) {
    say STDERR shift;
    exit 1;
}

=method new ( [$config] )

Start padadoy, optionally with some configuration. The command line
client used C<./padadoy.conf> or C<~/padadoy.conf> as config files.

=cut

sub new {
    my ($class, $config) = @_;

    my $self = bless { }, $class;

    if ($config) {
        # $self->_msg("Reading configuration from $config");
        open (my $fh, "<", $config);
        while(<$fh>) {
            next if /^\s*$/;
            if (/^\s*([a-z]+)\s*[:=]\s*(.*?)\s*$/) {
                $self->{$1} = ($2 // '');         
            } elsif ($_ !~ /^\s*#/) {
                _fail("syntax error in config file: $_");
            }
        }
        close $fh;
    }

    $self->{user}       ||= getlogin || getpwuid($<);
    $self->{home}       ||= '/home/'.$self->{user};
    $self->{repository} ||= $self->{home}.'/repository';
    $self->{port}       ||= 6000;
    $self->{pidfile}    ||= $self->{home}.'/starman.pid';

    $self->{config} = $config;

    # TODO: fail on invalid config values (e.g. port=0)

    $self;
}

=method create

Create an application boilerplate.

=cut

sub create {
    my $self = shift;

    $self->_provide_config;

    $self->_msg("[create] app directory");
    mkdir 'app';

    $self->_msg("[create] minimal dotcloud.yml");
    write_file( 'dotcloud.yml', "www:\n  type: perl\n  approot: app" );

    # TODO: dependencies should be detectable automatically
    # with Perl::PrereqScanner::App
    $self->_msg("[create] minimal Makefile.PL");
    run('cp',dist_file('App-padadoy','Makefile.template'),'app/Makefile.PL');

    $self->_msg("[create] minimal app/app.psgi");
    run('cp',dist_file('App-padadoy','app.psgi'),'app/app.psgi');

    $self->_msg("[create] You must initialize a git repository and add remotes");
}

=method init

Initialize on your deployment machine.

=cut

sub init {
    my $self = shift;
    $self->_msg("Initializing environment");

    _fail "Expected to run in ".$self->{home} 
        unless cwd eq $self->{home};
    _fail 'Expected to run in an EMPTY home directory' 
        if grep { $_ ne $0 and $_ ne 'padadoy.conf' } <*>;

    $self->_provide_config;

    try { 
        run('git', 'init', '--bare', $self->{repository});
    } catch {
        _fail 'Failed to init git repository in '.$self->{repository}; 
    };

    my %scripts = map { chomp; $_ } split /---+\n/, join "", <DATA>;
    while (my ($file, $content) = each %scripts) {
        say "creating $file as executable";
        open my $fh, '>', $file;
        print $fh $content;
        close $fh;
        chmod 0755, $file;
    }

    # TODO: current and data dir
    #run('ln', '-s', 'current/app/logs/', 'logs') unless -e "logs";
    mkdir "data" unless -d "data";

    $self->_msg("To add as remote: git remote add prod %s@%s:%s", 
        $self->{user}, hostname, $self->{repository});
}

=method config

Show configuration values.

=cut

sub config {
    my $self = shift;
    my $fh   = shift || *STDOUT;
    foreach (sort keys %$self) {
        say $fh "$_=" . $self->{$_};
    }
}

=method restart

Start or gracefully restart the application if running.

=cut

sub restart {
    my $self = shift;

    my $pid = $self->_pid;
    if ($pid) {
        $self->_msg( "[restart] Gracefully restarting starman as deamon on port %d (pid in %s)",
            $self->{port}, $self->{pidfile} );
        run('kill','-HUP',$pid);
    } else {
        $self->start;
    }
}

=method start

Start starman webserver with carton.

=cut

sub start {
    my $self = shift;

    # TODO: change in app dir
    chdir 'current/app';
    $self->_msg( "[start] Starting starman as deamon on port %d (pid in %s)",
        $self->{port}, $self->{pidfile} );

    # TODO: we could better directly use Carton here
    $ENV{PLACK_ENV} = 'production';
    run(qw(carton exec -Ilib -- starman --port),$self->{port},'-D','--pid',$self->{pidfile});
}

=method stop

Stop starman webserver.

=cut

sub stop {
    my $self = shift;

    my $pid = $self->_pid;
    if ( $pid ) {
        $self->_msg( "[stop] killing old process" );
        run('kill',$pid);
    } else {
        $self->_msg( "[stop] no PID file found" );
    }
}

sub _pid {
    my $self = shift;
    return unless $self->{pidfile} and -f $self->{pidfile};
    my $pid = read_file($self->{pidfile}) || 0;
    return ($pid =~ s/^(\d+).*$/$1/sm ? $pid : 0);
}

=method status

Show some status information.

=cut

sub status {
    my $self = shift;

    _fail("No configuration file found") unless $self->{config};
    say "Configuration from ".$self->{config};

    # PID file?
    my $pid = $self->_pid;
    if ($pid) {
        say "Process running: $pid (PID in ", $self->{pidfile} . ")";
    } else {
        say "PID file " . $self->{pidfile} . " not found or broken";
    }

    my $port = $self->{port};
    
    # something listening on the port?
    my $sock = IO::Socket::INET->new( PeerAddr => "localhost:$port" );
    say "Port is $port - " . ($sock ? "currently used" : "not used");

    # find out whether this users owns the socket (there should be a better way!) 
    my ($command,$pid2,$user);
    my @lsof = eval { grep /LISTEN/, ( capture('lsof','-i',":$port") ) };
    if (@lsof) { 
        foreach (@lsof) { # there may be multiple processes
            my @f = split /\s+/, $_;
            ($command,$pid2,$user) = @f if !$pid2 or $f[1] < $pid2;
        }
    } else {
        $self->_msg("Not listening at port $port");
    }

    if ($sock or $pid2) {
        if ($pid and $pid eq $pid2) {
            say "Port $port is used by process $pid as given in ".$self->{pidfile};
        } elsif (!$pid and $user and $user eq $self->{user}) {
            say "Looks like " . $self->{pidfile} . " is missing (should contain PID $pid2) ".
                "maybe you run another instance as same user ".$self->{user};
        } else {
            say "Looks like the port $port is used by someone else!"; 
        }
    }
}

sub _provide_config {
    my $self = shift;
    return if $self->{config};

    $self->{config} = cwd.'/padadoy.conf';
    $self->_msg("No configuration found - writing defaults to ".$self->{config});
    open (my $fh,'>',$self->{config});
    $self->config($fh);
    close $fh;
}

sub _msg {
    my $self = shift;
    my $msg = shift;
    return if $self->{quiet};
    say (@_ ? sprintf($msg, @_) : $msg);
}

1;

=head1 DESCRIPTION

L<padadoy> is a simple script to facilitate deployment of L<Plack> and/or
L<Dancer> applications, inspired by L<http://dotcloud.com>. It is based on
L<Carton> module dependency manager, L<Starman> webserver, and git.

In short, development and deployment with padadoy works like this: Your 
application must be managed in a git repository with the following structure:

    app/
      app.psgi    - application startup script
      lib/        - local application libraries
      t/          - unit tests
      Makefile.PL - ..
    deplist.txt   - application dependencies
    dotcloud.yml  - additional configuration if you like to push to dotcloud

For each deployment machine you create a remote repository and initialize it:

  $ padadoy init

You may then edit the file C<padadoy.conf> to adjust the port and other
settings. Back on another machine you can simply push to the deployment
repository with C<git push>. C<padadoy init> installs some hooks in the
deployment repository so new code is first tested before activation.

I<This is an early preview release, be warned!>

=head1 SYNOPSIS

On your deployment machine

  $ padadoy init

On your development machine

  $ padadoy create
  $ git init
  $ git add *
  $ git commit -m "inial commit"
  $ git remote add ...
  $ git push prod master

=head1 DEPLOYMENT

Actually, you don't need padadoy if you only deploy at some PaaS provider, but
deployment at dotCloud and OpenShift is also documented below for convenience.

=head2 On your own server

The following should work at least with a fresh Ubuntu installation and Perl >=
5.10.  First you need to install git, a build toolchain, and cpanminus:

  $ sudo apt-get install git-core build-essential lbssl-dev
  $ wget -O - http://cpanmin.us | sudo perl - --self-upgrade

Now you can install padadoy from CPAN:

  $ sudo cpanm App::padadoy

Depending on the Perl modules your application requires, you may need some
additional packages, such as C<libexpat1-dev> for XML. For instance for HTTPS 
you need L<LWP::Protocol::https> that requires C<libnet-ssleay-perl> to build:

  $ sudo apt-get install libnet-ssleay-perl
  $ sudo cpanm LWP::Protocol::https

=head2 On dotCloud

Create a dotCloud account and install the command line client as documented at
L<https://docloud.com>.

=head2 On OpenShift

Create an OpenShift account, install the command line client, and create a domain,
as documented at L<https://openshift.redhat.com/app/getting_started> (you may need
to C<sudo apt-get install libopenssl-ruby> and find the client at 
C</var/lib/gems/1.8/bin/rhc> to actually make use of it).

=head1 SEE ALSO

There are many ways to deploy. See this presentation by TatsuhikoMiyagawa for
an overview:

L<http://www.slideshare.net/miyagawa/deploying-plack-web-applications-oscon-2011-8706659>

By now, padadoy only supports Starman web server, but it might be easy to
support more.

This should also work on Amazon EC2 but I have not tested yet. See for instance
L<http://www.deepakg.com/prog/2011/01/deploying-a-perl-dancer-application-on-amazon-ec2/>.

In addition to your own server (with padadoy) and dotcloud, you might want to try out
OpenShift: L<https://openshift.redhat.com/app/> (not tested yet).

=head1 FAQ

I<What does "padadoy" mean?> The funny name is derived from "PlAck DAncer
DeplOYment" but it does not mean anything: the application is not limited 
to Plack and Dancer.

=cut

__DATA__
repository/hooks/update
-----------------------
#!/bin/bash

# TODO: put this in padadoy

refname="$1" 
oldrev="$2" 
newrev="$3" 
 
if [ -z "$refname" -o -z "$oldrev" -o -z "$newrev" ]; then 
    echo "Usage: $0 <ref> <oldrev> <newrev>" >&2 
    echo "  where <newrev> is relevant only" >&2
    exit 1 
fi 

# Any command that fails will cause the entire script to fail
set -e

export GIT_WORK_TREE=~/$newrev
export GIT_DIR=~/repository

cd
[ -d $GIT_WORK_TREE ] && echo "work tree $GIT_WORK_TREE already exists!" && exit 1

# reuse existing working tree for faster updates
# TODO: build from scratch if somehow required to do so!
if [ -d current ]; then
    rsync -a current/ $GIT_WORK_TREE
else
    mkdir $GIT_WORK_TREE
fi

echo "[UPDATE] Checking out $GIT_DIR in $GIT_WORK_TREE"
cd $GIT_WORK_TREE
git checkout -q -f $newrev

echo "[UPDATE] installing dependencies and testing"
# TODO: Makefile.PL required - fail is missing!
cd app
pwd
carton install
perl Makefile.PL
carton exec -Ilib -- make test
carton exec -Ilib -- make clean

export PLACK_ENV=production

# TODO: test running with starman on testing port!!!

echo "[UPDATE] new -> $GIT_WORK_TREE/app"
cd
rm -f new
ln -s $GIT_WORK_TREE new

echo "[UPDATE] revision $GIT_WORK_TREE installed at ~/new"

-----------------------------
repository/hooks/post-receive
-----------------------------
#!/bin/bash
set -e

# TODO: cd home
cd
echo "[POST-RECEIVE] new => current"
if [ -d "new" ]; then
    rm -f current
    mv new current
else
    echo "[POST-RECEIVE] missing directory 'new'"
    exit 1
fi

# graceful restart seems broken
# padadoy restart
padadoy stop
padadoy start

# TODO: cleanup old revisions
