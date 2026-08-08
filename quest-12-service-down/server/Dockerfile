FROM jrei/systemd-ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server sudo lsof psmisc procps file less vim-tiny ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN echo 'LANG=C.UTF-8' > /etc/default/locale

RUN useradd -m -s /bin/bash ec2-user \
 && echo 'ec2-user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ec2-user \
 && chmod 440 /etc/sudoers.d/90-ec2-user \
 && mkdir -p /home/ec2-user/.ssh \
 && chmod 700 /home/ec2-user/.ssh \
 && chown -R ec2-user:ec2-user /home/ec2-user/.ssh

RUN useradd -r -s /usr/sbin/nologin orderapi \
 && mkdir -p /opt/orderapi /var/lib/orderapi /etc/orderapi /run/sshd \
 && chown orderapi:orderapi /var/lib/orderapi

COPY serve.sh /opt/orderapi/serve.sh
COPY app.conf /etc/orderapi/app.conf
COPY app.conf.example /etc/orderapi/app.conf.example
COPY orderapi.service /lib/systemd/system/orderapi.service

RUN chmod +x /opt/orderapi/serve.sh \
 && systemctl enable ssh.service orderapi.service \
 && mkdir -p /etc/systemd/system/multi-user.target.wants \
 && ln -sf /lib/systemd/system/systemd-user-sessions.service \
      /etc/systemd/system/multi-user.target.wants/systemd-user-sessions.service

EXPOSE 22
