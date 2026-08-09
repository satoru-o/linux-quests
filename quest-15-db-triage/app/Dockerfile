# アプリサーバ。運用担当はここにSSHで入り、ここからDBを叩く。
FROM jrei/systemd-ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server sudo postgresql-client-14 \
      python3 python3-psycopg2 curl jq \
      iptables iproute2 netcat-openbsd dnsutils \
      lsof psmisc procps file less vim-tiny \
 && rm -rf /var/lib/apt/lists/*

RUN echo 'LANG=C.UTF-8' > /etc/default/locale

RUN useradd -m -s /bin/bash ec2-user \
 && echo 'ec2-user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ec2-user \
 && chmod 440 /etc/sudoers.d/90-ec2-user \
 && mkdir -p /home/ec2-user/.ssh \
 && chmod 700 /home/ec2-user/.ssh \
 && chown -R ec2-user:ec2-user /home/ec2-user/.ssh \
 && useradd -r -s /usr/sbin/nologin reportapi-svc

RUN mkdir -p /opt/reportapi /opt/batch /opt/reportdb /etc/reportapi \
      /var/lib/db-watchdog /run/sshd

COPY reportapi.py /opt/reportapi/reportapi.py
COPY app.conf /etc/reportapi/app.conf
COPY conn-hog.py lock-holder.py /opt/batch/
COPY reportdb-README /opt/reportdb/README
COPY maint.conf /opt/reportdb/maint.conf
COPY db-watchdog.sh /usr/local/sbin/db-watchdog
COPY reportapi.service conn-hog.service lock-holder.service db-watchdog.service \
     /lib/systemd/system/

# 保守用の接続情報は運用担当だけが読む
RUN chmod 600 /opt/reportdb/maint.conf \
 && chmod +x /usr/local/sbin/db-watchdog \
 && systemctl enable ssh.service reportapi.service db-watchdog.service \
 && mkdir -p /etc/systemd/system/multi-user.target.wants \
 && ln -sf /lib/systemd/system/systemd-user-sessions.service \
      /etc/systemd/system/multi-user.target.wants/systemd-user-sessions.service

EXPOSE 22 8080
