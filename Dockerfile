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
RUN cpanm install Auth::GoogleAuth;
RUN cpanm install JSON::Validator::Joi;

EXPOSE 3000

# adjust as needed, or just delete if you dont want
# logging verbosity in prod
ENV MOJO_LOG_LEVEL=info

# example of pre-fork operation
# fork 10 runners for prod - adjust as needed
# CMD perl ./script/mojo_gateway prefork -w 10 -m production -l http://*:3000

# or just demonize... for low volume traffic
CMD perl ./script/mojo_gateway daemon -m production -l http://*:3000
