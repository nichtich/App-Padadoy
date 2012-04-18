use strict;
use warnings;
package App::Padadoy;
#ABSTRACT: Simply deploy PSGI applications

use 5.010;
use autodie;
use Try::Tiny;
use IPC::System::Simple qw(run capture $EXITVAL);
use File::Slurp;
use List::Util qw(max);
use File::ShareDir qw(dist_file);
use File::Path qw(make_path);
use Sys::Hostname;
use Cwd;

# required for deployment
use Plack::Handler::Starman qw();
use Carton qw(0.9.4);

# required for testing
use Plack::Test qw();
use HTTP::Request::Common qw();

our @commands = qw(init start stop restart config status create deplist cartontest);
our @configs = qw(user base repository port pidfile logs errrorlog accesslog quiet);

# _msg( $fh, [\$caller], $msg [@args] )
sub _msg (@) { 
    my $fh = shift;
    my $caller = ref($_[0]) ? ${(shift)} :
            ((caller(2))[3] =~ /^App::Padadoy::(.+)/ ? $1 : '');
    my $text  = shift;
    say $fh (($caller ? "[$caller] " : "") 
        . (@_ ? sprintf($text, @_) : $text));
}

sub fail (@) {
    _msg(*STDERR, @_);
    exit 1;
}

sub msg {
    my $self = shift;
    _msg( *STDOUT, @_ ) unless $self->{quiet};
}

=method new ( [$configfile] [%configvalues] )

Start padadoy, optionally with some configuration. The command line
client used C<./padadoy.conf> or C<~/padadoy.conf> as config files.

=cut

sub new {
    my ($class, $config, %values) = @_;

    my $self = bless { }, $class;

    if ($config) {
        # $self->msg("Reading configuration from $config");
        open (my $fh, "<", $config);
        while(<$fh>) {
            next if /^\s*$/;
            if (/^\s*([a-z]+)\s*[:=]\s*(.*?)\s*$/) {
                $self->{$1} = ($2 // '');         
            } elsif ($_ !~ /^\s*#/) {
                fail "syntax error in config file: $_";
            }
        }
        close $fh;
    }

    foreach (@configs) {
        $self->{$_} = $values{$_} if defined $values{$_};
    }

    $self->{user}       ||= getlogin || getpwuid($<);
    $self->{base}       ||= cwd; # '/base/'.$self->{user};
    $self->{repository} ||= $self->{base}.'/repository';
    $self->{port}       ||= 6000;
    $self->{pidfile}    ||= $self->{base}.'/starman.pid';
    $self->{logs}       ||= $self->{base}.'/logs';
    $self->{errorlog}   ||= $self->{logs}.'/error.log'; 
    $self->{accesslog}  ||= $self->{logs}.'/access.log';

    # config file
    $self->{config} = $config;

    # TODO: validate config values

    $self;
}

=method create

Create an application boilerplate.

=cut

sub create {
    my $self   = shift;
    my $module = shift;

    $self->{module} = $module;
    fail("Invalid module name: $module") 
        if $module and $module !~ /^([a-z][a-z0-9]*(::[a-z][a-z0-9]*)*)$/i;

    $self->_provide_config('create');

    $self->msg('Using base directory '.$self->{base});
    chdir $self->{base};

    $self->msg('app/');
    mkdir 'app';

    $self->msg('app/Makefile.PL');
    write_file('app/Makefile.PL',{no_clobber => 1},
        read_file(dist_file('App-padadoy','Makefile.PL')));

    if ( $module ) {
        $self->msg("app/app.psgi (calling $module)");
        my $content = read_file(dist_file('App-padadoy','app2.psgi'));
        $content =~ s/YOUR_MODULE/$module/mg;
        write_file('app/app.psgi',{no_clobber => 1},$content);

        my @parts = ('app', 'lib', split('::', $module));
        my $name = pop @parts;

        my $path = join '/', @parts;
        $self->msg("$path/");
        make_path ($path);

        $self->msg("$path/$name.pm");
        $content = read_file(dist_file('App-padadoy','Module.pm.template'));
        $content =~ s/YOUR_MODULE/$module/mg;
        write_file( "$path/$name.pm", {no_clobber => 1}, $content );

        $self->msg('app/t/');
        make_path('app/t');

        $self->msg('app/t/basic.t');
        my $test = read_file(dist_file('App-padadoy','basic.t'));
        $test =~ s/YOUR_MODULE/$module/mg;
        write_file('app/t/basic.t',{no_clobber => 1},$test);
    } else {
        $self->msg('app/app.psgi');
        write_file('app/app.psgi',{no_clobber => 1},
            read_file(dist_file('App-padadoy','app1.psgi')));

        $self->msg('app/lib/');
        mkdir 'app/lib';
        write_file('app/lib/.gitkeep',{no_clobber => 1},''); # TODO: required?

        $self->msg('app/t/');
        mkdir 'app/t';
        write_file('app/t/.gitkeep',{no_clobber => 1},''); # TODO: required?
    }

    $self->msg('data/');
    mkdir 'data';

    $self->msg('dotcloud.yml');
    write_file( 'dotcloud.yml',{no_clobber => 1},
         "www:\n  type: perl\n  approot: app" );
    
    my $content = read_file(dist_file('App-padadoy','index.pl.template'));
    $self->msg("perl/index.pl");
    make_path("perl");
    write_file("perl/index.pl",{no_clobber = 1}, $content);

    my %symlinks = (libs => 'app/lib','deplist.txt' => 'app/deplist.txt');
    while (my ($from,$to) = each %symlinks) {
        $self->msg("$from -> $to");
        symlink $to, $from;
    }

    # TODO:
    # .openshift/      - hooks for OpenShift (o)
    #   action_hooks/  - scripts that get run every git push (o)

    $self->msg('logs/');
    mkdir 'logs';
    write_file('logs/.gitignore','*');
    write_file('logs/access.log','');
    write_file('logs/error.log','');
}

=method deplist

List dependencies (not implemented yet).

=cut

sub deplist {
    my $self = shift;

    eval "use Perl::PrereqScanner";
    fail "Perl::PrereqScanner required" if $@;

    fail "not implemented yet";

    # TODO: dependencies should be detectable automatically
    # with Perl::PrereqScanner::App

    $self->msg("You must initialize a git repository and add remotes");
}

=method init

Initialize on your deployment machine.

=cut

sub init {
    my $self = shift;
    $self->msg("Initializing environment");

    fail "Expected to run in ".$self->{base} 
        unless cwd eq $self->{base};
    fail 'Expected to run in an EMPTY base directory' 
        if grep { $_ ne $0 and $_ ne 'padadoy.conf' } <*>;

    $self->_provide_config('init');

    try { 
        my $out = capture('git', 'init', '--bare', $self->{repository});
        $self->msg(\'init',$_) for split "\n", $out;
    } catch {
        fail 'Failed to init git repository in ' . $self->{repository};
    };

    my $file = $self->{repository}.'/hooks/update';
    $self->msg("$file as executable");
    write_file($file, read_file(dist_file('App-padadoy','update')));
    chmod 0755,$file;

    $file = $self->{repository}.'/hooks/post-receive';
    $self->msg("$file as executable");
    write_file($file, read_file(dist_file('App-padadoy','post-receive')));
    chmod 0755,$file;

    $self->msg("logs -> current/logs");
    symlink 'current/logs', 'logs';

    $self->msg("To add as remote: git remote add prod %s@%s:%s", 
        $self->{user}, hostname, $self->{repository});
}

=method config

Show configuration values.

=cut

sub config {
    say shift->_config;
}

sub _config {
    my $self = shift;
    my $max = max map { length } keys %$self;
    join "\n", map { sprintf( "%-${max}s = %s", $_, $self->{$_} // '' ) }
        sort keys %$self;
}

=method restart

Start or gracefully restart the application if running.

=cut

sub restart {
    my $self = shift;

    my $pid = $self->_pid;
    if ($pid) {
        $self->msg("Gracefully restarting starman as deamon on port %d (pid in %s)",
            $self->{port}, $self->{pidfile});
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

    fail "No configuration file found" unless $self->{config};

    chdir $self->{base}.'/app';

if (0) { # FIXME
    # check whether dependencies are satisfied
    my @out = split "\n", capture('carton check --nocolor 2>&1');
    if (@out > 1) { # carton check always seems to exit with zero (?!)
        $out[0] = 
        _msg( *STDERR, \'start', $_) for @out;
        exit 1;
    }
}

    $self->msg("Starting starman as deamon on port %d (pid in %s)",
        $self->{port}, $self->{pidfile});

    # TODO: refactor after release of carton 1.0
    $ENV{PLACK_ENV} = 'production';
    my @opt = (
        'starman','--port' => $self->{port},
        '-D','--pid'   => $self->{pidfile},
        '--error-log'  => $self->{errorlog},
        '--access-log' => $self->{accesslog},
    );
    run('carton','exec','-Ilib','--',@opt);
}

=method stop

Stop starman webserver.

=cut

sub stop {
    my $self = shift;

    my $pid = $self->_pid;
    if ( $pid ) {
        $self->msg("killing old process");
        run('kill',$pid);
    } else {
        $self->msg("no PID file found");
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

    fail "No configuration file found" unless $self->{config};
    $self->msg("Configuration from ".$self->{config});

    # PID file?
    my $pid = $self->_pid;
    if ($pid) {
        $self->msg("Process running: $pid (PID in %s)", $self->{pidfile});
    } else {
        $self->msg("PID file %s not found or broken", $self->{pidfile});
    }

    my $port = $self->{port};
    
    # something listening on the port?
    my $sock = IO::Socket::INET->new( PeerAddr => "localhost:$port" );
    $self->msg("Port is $port - " . ($sock ? "currently used" : "not used"));

    # find out whether this users owns the socket (there should be a better way!) 
    my ($command,$pid2,$user);
    my @lsof = eval { grep /LISTEN/, ( capture('lsof','-i',":$port") ) };
    if (@lsof) { 
        foreach (@lsof) { # there may be multiple processes
            my @f = split /\s+/, $_;
            ($command,$pid2,$user) = @f if !$pid2 or $f[1] < $pid2;
        }
    } else {
        $self->msg("Not listening at port $port");
    }

    if ($sock or $pid2) {
        if ($pid and $pid eq $pid2) {
            $self->msg("Port $port is used by process $pid as given in ".$self->{pidfile});
        } elsif (!$pid and $user and $user eq $self->{user}) {
            $self->msg("Looks like " . $self->{pidfile} . " is missing (should contain PID $pid2) ".
                "maybe you run another instance as same user ".$self->{user});
        } else {
            $self->msg("Looks like the port $port is used by someone else!"); 
        }
    }
}

sub _provide_config {
    my ($self, $caller) = @_;
    return if $self->{config};

    $self->{config} = cwd.'/padadoy.conf';
    $self->msg(\$caller,"Writing default configuration to ".$self->{config});
    # TODO: better use template with comments instead
    write_file( $self->{config}, $self->_config );
}

=method method cartontest

Update dependencies with carton and run tests.

=cut

sub cartontest {
    my $self = shift;

    chdir $self->{base}.'/app';
    $self->msg("installing dependencies and testing");

    run('carton install');
    run('perl Makefile.PL');
    run('carton exec -Ilib -- make test');
    run('carton exec -Ilib -- make clean > /dev/null');
}

1;

=head1 SYNOPSIS

Create a new application and start it locally on your development machine:

  $ padadoy create Your::Module
  $ plackup app/app.psgi

Manage your application files in a git repository:

  $ git init
  $ git add *
  $ git add -f logs/.gitignore
  $ git commit -m "inial commit"

Start application locally as deamon with bundled dependencies:

  $ padadoy cartontest
  $ padadoy start

Show status of your running application and stop it:

  $ padadoy status
  $ padadoy stop

Deploy the application at dotCloud

  $ dotcloud create nameoryourapp
  $ dotcloud push nameofyourapp

Prepare your own deployment machine

  $ ssh $SERVER
  $ padadoy init

Add your deployment machine as git remote and deploy:

  $ git remote add ...
  $ git push prod master

=head1 DESCRIPTION

I<This is an early preview release, be warned! Design changes are likely,
at least until a stable carton 1.0 has been released!>

L<Padadoy|padadoy> is a command line application to facilitate deployment of
L<PSGI> applications, inspired by L<http://dotcloud.com>. Padadoy is based on
the L<Carton> module dependency manager, L<Starman> webserver, and git. In
short, an application is managed in a git repository and pushed to a remote
repository for deployment. At the remote server, required modules are installed
and unit tests are run, to minimize the chance of a broken installation.

An application is managed in a git repository with following structure.  You
can create it automatically with C<padadoy create> or C<padadoy create
Your::App::Module>.  

    app/
       app.psgi      - application startup script
       lib/          - local perl modules (at least the actual application)
       t/            - unit tests
       Makefile.PL   - used to determine required modules and to run tests
       deplist.txt   - a list of perl modules required to run (o)
      
    data/            - persistent data (o)

    dotcloud.yml     - basic configuration for dotCloud (o)
    
    libs -> app/lib                - symlink for OpenShift (o)
    deplist.txt -> app/deplist.txt - symlink for OpenShift (o)
    perl/index.pl                  - CGI script for OpenShift (o)

    logs/            - logfiles (access and error)
     
Files and directories marked by C<(o)> are optional, depending on whether you
also want to deploy at dotcloud and/or OpenShift.

To deploy your application, just do a C<git push> (after some initalization).

=head1 DEPLOYMENT

Actually, you don't need padadoy if you only deploy at some PaaS provider, but
deployment at dotCloud and OpenShift is also documented below for convenience.

=head2 On your own server

The following should work at least with a fresh Ubuntu installation and Perl >=
5.10.  First you need to install git, a build toolchain, and cpanminus:

  $ sudo apt-get install git-core build-essential lbssl-dev
  $ wget -O - http://cpanmin.us | sudo perl - --self-upgrade

Now you can install padadoy from CPAN:

  $ sudo cpanm App::Padadoy

Depending on the Perl modules your application requires, you may need some
additional packages, such as C<libexpat1-dev> for XML. For instance for HTTPS 
you need L<LWP::Protocol::https> that requires C<libnet-ssleay-perl> to build:

  $ sudo apt-get install libnet-ssleay-perl
  $ sudo cpanm LWP::Protocol::https

For each deployment you create a remote repository and initialize it:

  $ padadoy init

You may then edit the file C<padadoy.conf> to adjust the port and other
settings. Back on another machine you can simply push to the deployment
repository with C<git push>. C<padadoy init> installs some hooks in the
deployment repository so new code is first tested before activation.


=head2 On dotCloud

Create a dotCloud account and install the command line client as documented at
L<https://docloud.com>.

=head2 On OpenShift

Create an OpenShift account, install the command line client, and create a
domain, as documented at L<https://openshift.redhat.com/app/getting_started>
(you may need to C<sudo apt-get install libopenssl-ruby>, and to find and
fiddle around the client at C</var/lib/gems/1.8/bin/rhc> to actually make use
of it). Att your OpenShift repository as remote and merge.

=head1 SEE ALSO

There are many ways to deploy PSGI applications. See this presentation by 
Tatsuhiko Miyagawa for an overview:

L<http://www.slideshare.net/miyagawa/deploying-plack-web-applications-oscon-2011-8706659>

By now, padadoy only supports Starman web server, but it might be easy to
support more.

This should also work on Amazon EC2 but I have not tested yet. See for instance
L<http://www.deepakg.com/prog/2011/01/deploying-a-perl-dancer-application-on-amazon-ec2/>.

=head1 FAQ

I<What does "padadoy" mean?> The funny name was derived from "PlAck DAncer
DeplOYment" but it does not mean anything.

=cut
