**padadoy** is a simple command line application to deploy PSGI applications.

*This is an early preview - be warned!*

Your application must be managed in a git repository that should conform to 
the following layout, inspired by the PaaS providers dotCloud and OpenShift:

    app/
       app.psgi      - application startup script
       lib/          - local perl modules (at least the actual application)
       t/            - unit tests
       Makefile.PL   - used to determine required modules and to run tests
      
    data/            - persistent data (o)

    dotcloud.yml     - basic configuration for dotCloud (o)
    
    deplist.txt      - a list of perl modules required to run (o)
    libs -> app/lib  - symlink for OpenShift (o)
    .openshift/      - hooks for OpenShift (o)
       action_hooks/ - scripts that get run every git push (o)

    logs/            - logfiles (access and error)
     
Files and directories marked by `(o)` are optional, depending on what platform
you want to deploy. Actually you don't need padadoy if you only deploy to
dotCloud and/or OpenShift (just use their command line clients). But if you
also want to deploy at your own server, padadoy may facilitate some steps.
After some initalization, you can simply deploy new versions with `git push`.

Actually, padadoy is just a layer on top of `git`, `Starman`, and `Carton`.

The [documentation at CPAN](http://search.cpan.org/dist/App-padadoy/), as 
generated from `lib/App/padadoy.pm` contains some details.

Feel free to fork and submit patches and issues!
