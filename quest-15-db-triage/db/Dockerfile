# DBインスタンス。シェルもSSHも無い。psqlでしか触れない。
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends postgresql-14 \
 && rm -rf /var/lib/apt/lists/*

RUN CONF=/etc/postgresql/14/main/postgresql.conf \
 && HBA=/etc/postgresql/14/main/pg_hba.conf \
 && printf "\n# レポート基盤\nlisten_addresses = '*'\nmax_connections = 30\n" >> "$CONF" \
 && printf 'host    all    all    0.0.0.0/0    scram-sha-256\n' >> "$HBA"

COPY init.sql /tmp/init.sql
RUN pg_ctlcluster 14 main start \
 && su postgres -c 'psql -v ON_ERROR_STOP=1 -f /tmp/init.sql' \
 && pg_ctlcluster 14 main stop \
 && rm -f /tmp/init.sql

EXPOSE 5432
USER postgres
CMD ["/usr/lib/postgresql/14/bin/postgres", "-D", "/var/lib/postgresql/14/main", \
     "-c", "config_file=/etc/postgresql/14/main/postgresql.conf"]
