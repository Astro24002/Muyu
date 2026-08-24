FROM postgres:16-alpine

RUN apk add --no-cache pgbackrest

RUN mkdir -p /var/lib/pgbackrest && chmod 750 /var/lib/pgbackrest
