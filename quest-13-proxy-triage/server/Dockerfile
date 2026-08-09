FROM jrei/systemd-ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server sudo nginx curl python3 python3-flask \
      lsof psmisc procps file less vim-tiny ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN echo 'LANG=C.UTF-8' > /etc/default/locale

RUN useradd -m -s /bin/bash ec2-user \
 && echo 'ec2-user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ec2-user \
 && chmod 440 /etc/sudoers.d/90-ec2-user \
 && mkdir -p /home/ec2-user/.ssh \
 && chmod 700 /home/ec2-user/.ssh \
 && chown -R ec2-user:ec2-user /home/ec2-user/.ssh

RUN mkdir -p /opt/backend /var/lib/proxy-watchdog /run/sshd

COPY backend.py /opt/backend/backend.py
COPY backend-README /opt/backend/README
COPY backend@.service /lib/systemd/system/backend@.service
COPY nginx-site.conf /etc/nginx/conf.d/reports.conf
COPY proxy-watchdog.sh /usr/local/sbin/proxy-watchdog
COPY proxy-watchdog.service /lib/systemd/system/proxy-watchdog.service

RUN rm -f /etc/nginx/sites-enabled/default \
 && chmod +x /usr/local/sbin/proxy-watchdog \
 && systemctl enable ssh.service nginx.service proxy-watchdog.service \
      backend@9001.service backend@9002.service backend@9003.service \
 && mkdir -p /etc/systemd/system/multi-user.target.wants \
 && ln -sf /lib/systemd/system/systemd-user-sessions.service \
      /etc/systemd/system/multi-user.target.wants/systemd-user-sessions.service

EXPOSE 22 80
