**padadoy** is a simple command line application to deploy PSGI applications.
In short, padadoy is just a layer on top of `git`, `Starman`, and `Carton`.

*This is an early preview - be warned!*

Your application must be managed in a git repository that should conform to 
the following layout, inspired by the PaaS providers dotCloud and OpenShift.
You can create a boilerplate with `padadoy create`.

    app/
       app.psgi      - application startup script
       lib/          - local perl modules (at least the actual application)
       t/            - unit tests
       Makefile.PL   - used to determine required modules and to run tests

    deplist.txt      - a list of perl modules required to run (o)
      
    data/            - persistent data (o)

    dotcloud.yml     - basic configuration for dotCloud (o)
    
    libs -> app/lib  - symlink for OpenShift (o)
	perl/
	   index.pl      - CGI script to run app.psgi for OpenShift (o)
    deplist.txt -> app/deplist.txt - symlink for OpenShift (o)

    .openshift/      - hooks for OpenShift (o)
       action_hooks/ - scripts that get run every git push (o)

This directory layout helps to easy deploy on multiple platforms. Files and 
directories marked by `(o)` are optional, depending on what platform you want
to deploy. Padadoy also facilitates deploying to your own servers just like
a PaaS provider.

On the deployment machine there is a directory with the following structure:

    repository/      - the bare git repository that the app is pushed to
    current -> ...   - symbolic link to the current working directory
    new -> ...       - symbolic link to the new working directory on updates
    padadoy.conf     - local configuration

You can create this layout with `padadoy remote init`. After adding the remote
repository as git remote, you can simply deploy new versions with `git push`.

The [documentation at CPAN](http://search.cpan.org/dist/App-Padadoy/), as 
generated from `lib/App/Padadoy.pm` contains more details.

Feel free to fork and submit patches and issues!
