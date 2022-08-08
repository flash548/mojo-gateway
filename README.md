## Mojo::Gateway

[Mojolicious::Lite](https://metacpan.org/pod/Mojolicious::Lite) framework based (Perl) reverse-proxy for securing microservices with JWT.  Intended to be used in cloud environments, where
this service can sit on the edge of your network and authenticate requests based on users registered with the service. If
the request's cookie reveals they have/are authenticated, then the request is then routed (along with a JWT) to the path determined
in the service's routes defined in the configuration JSON file (see the `gateway.json` file above for an example).

Most of the keys in the config json are used except for the password complexity configuration - that is a WIP.  Right now it enforces
passwords 8 chars or greater containing at least 1 alpha, 1 number, 1 special, and no spaces hard-coded.

![Example usage](./example.png)


The service also uses [Mojo::JWT](https://metacpan.org/pod/Mojo::JWT) to create and inject a Json Web Token (JWT) into authenticated 
requests before they are proxied to their intended micro-service.  Services can use the JWT to identify the request and perform their 
own Authorization (AuthZ) on it.

The need came from SSO environments, but not having the cloud resources to host such huge services and layers (e.g. Keycloak).  There seemed to be a need 
for a lightweight solution - so a couple hours plus stitching together various Mojolicious libraries off CPAN produced this functional, albeit basic 
service.

Below shows an example of usage for an environment that has a NGINX container perhaps serving a React application and a backend service 
running some stack connected to a database - that needs to perform Authorization based on username/email.  Obviously real-world would want 
to use a more persistent database for the Mojo Gateway users (perhaps AWS RDS) that is also used by the API service so that User/Person accounts 
are sync/linked between the two services.

Example usage in a docker-compose file.  The key env vars the gateway service needs is 
`ADMIN_USER` and `ADMIN_PASS` for the initial admin credentials. 

The routes are configured in JSON within the `gateway.json` or whatever file you set ENV `MOJO_CONFIG` to.

```json
"routes": {
    "/": {
      "uri": "http://frontend:8080/",
      "enable_jwt": true,
      "jwt_claims": {
        "email": "$c->session->{email}"  // evaluated string - would be the user's email/username after resolution
      }
    },
    "/api/**" : {
      "uri": "http://backend:8080/",
      "enable_jwt": true,
      "jwt_claims": {
        "email": "$c->session->{email}"
      }
    },
    "/some-other-api" : {
      "uri" : "http://api:8080/",
      "enable_jwt": true,
      "jwt_claims": {
        "email": "$c->session->{email}",
        "usercertificate": "\"Developer.\" . $c->sesion->{employee_id}"  // some other custom header to be eval'd
      },
      "other_headers": { 
        "x-forwarded-client-cert": "some other header data"  // other headers to be added to requests going to `/some-other-api`  (there are NOT eval'd)
      }
    }
  },

```

Example `docker-compose` usage:
```dockerfile
version: "3.9"
services:
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


    # web app UI
    ui:
        image: some-docker-image:latest
    
    # a postgres db for api
    postgres:
        image: postgres
        environment:
            - POSTGRES_PASSWORD=password
        volumes:
            - backend-postgres:/var/lib/postgresql/data

    # a postgres db for mojo::gateway if you're using Postgres/non-SQLITE
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

