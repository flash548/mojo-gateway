## Mojo Gateway

[Mojolicious::Lite](https://metacpan.org/pod/Mojolicious::Lite) framework based (Perl) reverse-proxy for securing microservices with JWT.  Intended to be used in cloud environments,
this service can sit on the edge of your network and authenticate requests based on users registered with the service. If
the request's cookie reveals they have/are authenticated, then the request is then routed (along with a JWT) to the path determined
in the service's router.

![Example usage](./example.png)

In its current state, the service is very feature-less and does not support user registration yet (on purpose).  The user login
is handled by the [Yancy](https://metacpan.org/pod/Yancy) Mojolicious CMS library which has a ton of customizable options.  But in 
this service we just use the [Yancy::Plugin::Auth](https://metacpan.org/pod/Yancy::Plugin::Auth) to save not having to implement 
my own user authentication.  

The service also uses [Mojo::JWT](https://metacpan.org/pod/Mojo::JWT) to create and inject a Json Web Token (JWT) into authenticated 
requests before they are proxied to their intended micro-service.  Services can use the JWT to identify the request and perform their 
own Authorization (AuthZ) on it.

The need came from SSO environments, but not having the cloud resources to host such huge services and layers.  There seemed to be a need 
for a lightweight solution - so a couple hours plus stitching together various Mojolicious libraries produced this functional, albeit basic 
service.

Below shows an example of usage for an environment that has a NGINX container perhaps serving a React application and a backend service 
running some stack connected to a database - that needs to perform Authorization based on username/email.  Obviously real-world would want 
to use a more persistent database for the Mojo Gateway users (perhaps AWS RDS) that is also used by the API service so that User/Person accounts 
are sync/linked between the two services.

Example usage in a docker-compose file.  The key env vars the gateway service needs is 
`ADMIN_USER` and `ADMIN_PASS` for the initial admin credentials.  And the `BACKEND_URI` and `FRONTEND_URI` to say where to 
proxy traffic to (what other microservice to proxy to).

By default the gateway, forces any request to be authenticated... others could perhaps modify accordingly to allow for routes 
that do not require the request to have been authenticated previously.  This modification is left to the imagination of the reader.

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
            - FRONTEND_URI=http://ui:8080
            - BACKEND_URI=http://backend:8080

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

volumes:
    backend-postgres:


```

### Login Page

You can customize the login page as described in the `Yancy` docs or modify the example one that I made in `/templates/yancy/auth/password/login_page.html.ep`.  Or
if you wish to use the default Yancy one, just delete the entire `./templates` directory.