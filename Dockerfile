FROM perl
WORKDIR /opt/mojo-gateway
COPY . .
RUN cpanm install Mojolicious
RUN cpanm install Mojo::SQLite
RUN cpanm install Yancy
RUN cpanm install Mojo::JWT
RUN cpanm IO::Socket::SSL
EXPOSE 3000
CMD perl gateway.pl daemon -m production -l http://*:3000
