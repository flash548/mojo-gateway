FROM perl
WORKDIR /opt/mojo-gateway
COPY . .
RUN cpanm install Mojolicious
RUN cpanm install Mojo::SQLite
RUN cpanm install Mojo::Pg
RUN cpanm install Mojo::JWT
RUN cpanm install Date::Parse
RUN cpanm install Crypt::Bcrypt
RUN cpanm install Data::Entropy::Algorithms

EXPOSE 3000

# fork 10 runners for prod - adjust as needed
# CMD perl ./script/mojo_gateway prefork -w 10 -m production -l http://*:3000

# just demonize for now... until figure out the db issue
CMD perl ./script/mojo_gateway daemon -m production -l http://*:3000
