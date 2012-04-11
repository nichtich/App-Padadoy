padadoy is a simple command line application to deploy PSGI web applications.

Your application must be managed in a git repository with the following layout:

    app/
      app.psgi    - application startup script
      lib/        - local application libraries
      t/          - unit tests
      Makefile.PL - application dependencies
    dotcloud.yml  - additional configuration (if you like to push to dotcloud)

After some initalization on your deployment server, you can simply deploy new
versions with `git push`. For details have a look at the Perldoc
[documentation at CPAN](http://search.cpan.org/dist/App-padadoy/).

Actually, padadoy is just a layer on top of `git`, `Starman`, and `Carton` to
deploy applications on on different PaaS services and on your own servers.

Feel free to fork and submit patches and issues!
