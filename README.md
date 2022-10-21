## Mojo::Gateway

`
🚨 Note: This project is in active development/rapidly changing, thus not yet intended for any production usage.  New features are being added and at the same time existing ones may be getting removed or changed.  So usage at this point is at your own risk! If you want a "stable-ish" snapshot pull from the tags until v1.0.
`

[Mojolicious](https://metacpan.org/pod/Mojolicious) framework based (Perl) reverse-proxy for securing microservices with JSON Web Token (JWT).  Intended to be used in cloud environments, where
this service can sit on the edge of your network and authenticate requests based on users registered with the service. The service assumes HTTP inbound, so placing this service behind a load-balancer that terminates an SSL connection would be the best (and IMO most secure option).  If the request's cookie reveals they have/are authenticated, then the request is then routed (along with a JWT) to the path determined in the service's routes defined in the configuration JSON file (see the `gateway.json` file above for an example).

![Example usage](./example.png)


The service also uses [Mojo::JWT](https://metacpan.org/pod/Mojo::JWT) to create and inject a JWT into authenticated requests before they are proxied to their intended micro-service. This allows other services to not have to worry about authentication/account management.  If they get a request, they can assume it has been vetted and authenticated. Services can then use the JWT to identify the requester and perform their own Authorization (AuthZ) on it.

The need came from SSO environments, but not having the cloud resources to host such large services and layers (e.g. Keycloak/Envoy/Istio...).  There seemed to be a need for a lightweight solution - so stitching together various Mojolicious libraries off CPAN produced this functional (albeit basic) service.

Below shows an example of usage for an environment that has a NGINX container (perhaps serving a React application or something) and a backend service running some stack connected to a database that needs to perform Authorization based on username/email.  

Example configuration file that uses a Postgres database:

```json
{
  "login_page_title": "Login",
  "secret": "<%= $ENV{SECRET} // 'change_this' %>",
  "admin_user": "<%= $ENV{ADMIN_USER} // 'admin@admin.com' %>",
  "admin_pass": "<%= $ENV{ADMIN_PASS} // 'password' %>",
  "db_type": "<%= $ENV{DB_TYPE} // 'pg' %>",
  "db_uri": "<%= $ENV{DB_URI} // 'postgresql://somedude:password@localhost:5432/test' %>",
  "cookie_name": "<%= $ENV{COOKIE_NAME} // 'mojolicious' %>",
  "strip_headers_to_client": [ "authorization", "server", "x-powered-by"  ],
  "jwt_secret": "<%= $ENV{SECRET} // 'change_this' %>",
  "routes": {
    "/": {
      "uri": "<%= $ENV{FRONTEND_URI} // 'http://localhost:8080/' %>",
      "enable_jwt": true,
      "jwt_claims": {
        "email": "$c->session->{user}->{email}"
      }
    },
    "/api/**" : {
      "uri": "<%= $ENV{BACKEND_URI} // 'http://localhost:9000/' %>",
      "enable_jwt": true,
      "jwt_claims": {
        "email": "$c->session->{user}->{email}"
      }
    },
    "/some-other-api" : {
      "uri" : "<%= $ENV{OTHER_BACKEND_URI} // 'http://localhost:8081/' %>",
      "enable_jwt": true,
      "jwt_claims": {
        "email": "$c->session->{user}->{email}",
        "usercertificate": "\"Developer.\" . $c->session->{user}->{dod_id}"
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
    "jwt_claims": {
      "email": "$c->session->{user}->{email}"
    },
    "transforms": [{
      "condition": "$c->req->url =~ m/environment\\.js/",
      "action": "$body =~ s!http://localhost:8080/api/v1!/api/v1!"
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
        depends_on:
            - postgres
  
    # build docker image from this repo's dockerfile
    # here post-wise, assumed requests come in as HTTP (having HTTPS terminated elsewhere...)
    proxy:
        build: https://github.com/flash548/mojo-gateway.git#main
        ports:
            - "8080:3000"
        environment:
            - ADMIN_USER='admin@example.com'
            - ADMIN_PASS=password

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
- ✅ Delete user accounts (WIP)
- ✅ Update user accounts (change, expire passwords, change names, etc)
- View traffic stats (route usage, status, etc) (WIP)

## Roadmap

Desired features in order of most likely implementation:


### App Features

- Set optional config param for max attempts of unsuccessful login (e.g. lock account after 3 bad attempts)
- Admin lock-out account
- MFA option - integration with Google Authenticator
- Audit Log - route usage stats
- Add forgot-password feature -- vague at this point
- Allow some type of configurable, self-registration - not sure what that looks like yet
- Integration with AWS SES or the like - for email notifications

### App Todos

- Config validation on bootstrap - decide which fields are non-optional, and croak (or something) if not present or found
- JSON validation for backend API endpoints

## Tests

Run the test suite from the root of the project with: `prove -lr t/`

Make sure you dont have a server running locally that might interfere with port 8080 etc - as some of the tests actually standup a running instance of the service.


## Design System/Theme Credits

Uses the new Dracula-UI! (https://ui.draculatheme.com/)
