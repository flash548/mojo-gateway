FROM perl
WORKDIR /opt/mojo-gateway
COPY . .
RUN cpanm install Mojolicious
RUN cpanm install Mojo::SQLite
RUN cpanm install Yancy
RUN cpanm install Mojo::JWT
EXPOSE 443
CMD perl gateway.pl daemon -m production -l https://*:443?cert=example.cert&key=example.key
