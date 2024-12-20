## Mojo::Gateway

### DockerHub

This project is hosted on Dockerhub as a Docker Image.  [flash548/mojo-gateway](https://hub.docker.com/r/flash548/mojo-gateway)

### Wiki

Documentation on configuration file on project's [Wiki Page](https://github.com/flash548/mojo-gateway/wiki)

### About

`
🚨 Note: This project is in active development/rapidly changing, thus not yet intended for any production usage.  New features are being added and at the same time existing ones may be getting removed or changed.  So usage at this point is at your own risk! If you want a "stable-ish" snapshot pull from the tags until v1.0.
`

[Mojolicious](https://metacpan.org/pod/Mojolicious) framework based (Perl) reverse-proxy for securing microservices with JSON Web Token (JWT).  Intended to be used in cloud environments, where
this service can sit on the edge of your network and authenticate requests based on users registered with the service. The service assumes HTTP inbound, so placing this service behind a load-balancer that terminates an SSL connection would be the best (and IMO most secure option).  If the request's cookie reveals they have/are authenticated, then the request is then routed (along with a JWT) to the path determined in the service's routes defined in the configuration JSON file (see the `gateway.json` file above for an example).

![Example usage](./example.png)


The service also uses [Mojo::JWT](https://metacpan.org/pod/Mojo::JWT) to create and inject a JWT into authenticated requests before they are proxied to their intended micro-service. This allows other services to not have to worry about authentication/account management.  If they get a request, they can assume it has been vetted and authenticated. Services can then use the JWT to identify the requester and perform their own Authorization (AuthZ) on it.

The need came from SSO environments, but not having the cloud resources to host such large services and layers (e.g. Keycloak/Envoy/Istio...).  There seemed to be a need for a lightweight solution - so stitching together various Mojolicious libraries off CPAN produced this functional (albeit basic) service.

Below shows an example of usage for an environment that has a NGINX container (perhaps serving a React application or something) and a backend service running some stack connected to a database that needs to perform Authorization based on username/email or other JWT claim.  

Example configuration file that uses a Postgres database:

```json
{
  "login_page_title": "Login",
  "mfa_secret": "secret",
  "mfa_issuer": "mojo_gateway",
  "mfa_key_id": "login",
  "mfa_force_on_all": false,
  "enable_logging": true,
  "logging_ignore_paths": [ "/admin/http_logs", "/favicon", "/js", "/css", "/icons", "/fonts" ],
  "secret": "<%= $ENV{SECRET} // 'change_this' %>",
  "admin_user": "<%= $ENV{ADMIN_USER} // 'admin@admin.com' %>",
  "admin_pass": "<%= $ENV{ADMIN_PASS} // 'password' %>",
  "db_type": "<%= $ENV{DB_TYPE} // 'pg' %>",
  "db_uri": "<%= $ENV{DB_URI} // 'postgresql://somedude:password@localhost:5432/database' %>",
  "cookie_name": "<%= $ENV{COOKIE_NAME} // 'mojolicious' %>",
  "strip_headers_to_client": [ "authorization", "server", "x-powered-by"  ],
  "jwt_secret": "<%= $ENV{SECRET} // 'change_this' %>",
  "routes": {
    "/": {
      "uri": "<%= $ENV{FRONTEND_URI} // 'http://localhost:8080/' %>",
      "enable_jwt": true,
      "requires_login": true,
      "jwt_claims": {
        "email": ":email"
      }
    },
    "/api/**" : {
      "uri": "<%= $ENV{BACKEND_URI} // 'http://localhost:9000/' %>",
      "enable_jwt": true,
      "requires_login": true,
      "jwt_claims": {
        "email": ":email",4
        "user_id": ":user_id/i"
      }
    },
    "/other-api" : {
      "uri" : "<%= $ENV{OTHER_BACKEND_URI} // 'http://localhost:8081/' %>",
      "enable_jwt": true,
      "requires_login": true,
      "jwt_claims": {
        "email": ":email",
        "usercertificate": [ "Some.Developer.", ":user_id" ]
      },
      "other_headers": {
        "x-forwarded-client-cert": "some other header data"
      }
    }
  },
  "password_valid_days": 60,
  "password_complexity": {
    "min_length": 8,
    "alphas": 1,
    "numbers": 1,
    "specials": 1,
    "spaces": false
  },
  "default_route": {
    "uri": "<%= $ENV{FRONTEND_URI} // 'http://localhost:8080/' %>",
    "enable_jwt": true,
    "requires_login": true,
    "jwt_claims": {
      "email": ":email"
    },
    "transforms": [{
      "path": "environment.js",
      "action": { "search": "http://localhost:8080/api/v1", "replace": "/api/v1" }
    }]
  }
}


```

Example `docker-compose` usage:

```YAML
version: "3.9"
services:

    # some api microservice....
    backend:
        image: some-registry/image:latest
        ports:
          - "8080:8080"
        depends_on:
            - postgres
  
    # build docker image from this repo's dockerfile
    # here post-wise, assumed requests come in as HTTP (having HTTPS terminated elsewhere...)
    proxy:
        image: flash548/mojo-gateway:latest
        ports:
            - "8080:3000"
        volumes:
            - "./private.json:/opt/mojo-gateway/private.json"
            - "./templates:/opt/mojo-gateway/custom/templates"
            - "./public:/opt/mojo-gateway/custom/public"
        environment:
            - ADMIN_USER='admin@example.com'
            - ADMIN_PASS=password
            - SECRET=some-secret
            - BACKEND_URI=http://backend:8080

            # override the default config with whatever here
            - MOJO_CONFIG=private.json

            # or could be 'pg' in which case you'd need to provide 'DB_URI'
            # replace user and password obviously
            # - DB_URI='postgresql://user:password@app-db:5432/db-name'
            - DB_TYPE=sqlite


    # some web app UI...
    ui:
        image: some-docker-image:latest
    
    # a postgres db for api
    postgres:
        image: postgres
        environment:
            - POSTGRES_PASSWORD=password
        volumes:
            - backend-postgres:/var/lib/postgresql/data

    # a postgres db for mojo::gateway if you're using Postgres
    # db-name:
    #     image: postgres
    #     environment:
    #         - POSTGRES_USER=user
    #         - POSTGRES_PASSWORD=password
    #     volumes:
    #         - proxy-postgres:/var/lib/postgresql/data

volumes:
    backend-postgres:
    # proxy-postgres:


```

## Admin Interface

The Admin interface (WIP) is located at `/admin`.  It is available only to authenticated users with the `is_admin` field set to true.  The interface is written in `Preact` JS and uses the browswer
fetch API to interact with the API.  

Within the admin interface you can:

- ✅ Add user accounts
- ✅ Delete user accounts
- ✅ Update user accounts (change, expire passwords, change names, lock, etc)
- ✅ View traffic stats / Audit Log

## App Features

- ✅ Add/Edit/User accounts
- ✅ Audit Log
- ✅ MFA option - integration with Google Authenticator
- ✅ Console/Debug logging (via MOJO_LOG_LEVEL in Dockerfile for prod)
- ✅ Set optional config param ("max_login_attempts") for max attempts of unsuccessful login (e.g. lock account after 3 bad attempts)
- ✅ Admin lock-out account
- 🔳 Add forgot-password feature -- vague at this point
- 🔳 Allow some type of configurable, self-registration - not sure what that looks like yet
- 🔳 Integration with AWS SES or the like - for email notifications

## Dependency Management

This project uses `Carton` for dependency management.  Therefore your Perl distribution needs to have it installed.

Need to install it?  Suggest using `cpanm` to install via `sudo cpanm install Carton`.  If you need `cpanm` then install via 
`sudo curl -L https://cpanmin.us | sudo perl - App::cpanminus`.

Once `Carton` is installed, then you can install dependencies via `carton install` at the root of the project directory, and then you can do `carton exec perl script/mojo-gateway daemon` etc to start the app or `carton exec morbo script/mojo-gateway`...

## Tests

Run the test suite from the root of the project with: `carton exec prove -lr t/`

Make sure you dont have a server running locally that might interfere with port 8080 etc - as some of the tests actually standup a running instance of the service.


## Design System/Theme

This service's pages are rendered using the Astro UXDS from Rocket Communications.  It uses an older css file sans the web components.  You should check their Github out [here](https://github.com/RocketCommunicationsInc) and their [website](https://www.astrouxds.com/)!

## Credits

- Mojolicious Framework (https://github.com/mojolicious/mojo) and various other CPAN libraries (e.g. Auth::GoogleAuth)
- Astro UXDS from RocketCommunicationsInc (https://github.com/RocketCommunicationsInc)
- Ag-Grid Community (v23.2.1) (www.ag-grid.com)
- Preact.js (https://github.com/preactjs/preact)
- toastify-js (https://github.com/apvarun/toastify-js)
- htm (https://github.com/developit/htm)
- Tachyons CSS (https://tachyons.io/)
