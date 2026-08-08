FROM jrei/systemd-ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server sudo cron lsof psmisc procps file less vim-tiny ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN echo 'LANG=C.UTF-8' > /etc/default/locale

RUN useradd -m -s /bin/bash ec2-user \
 && echo 'ec2-user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ec2-user \
 && chmod 440 /etc/sudoers.d/90-ec2-user \
 && mkdir -p /home/ec2-user/.ssh \
 && chmod 700 /home/ec2-user/.ssh \
 && chown -R ec2-user:ec2-user /home/ec2-user/.ssh

RUN mkdir -p /opt/batch/bin /opt/batch/etc /var/lib/batch /var/log/batch /run/sshd

COPY aggregate.sh /opt/batch/aggregate.sh
COPY batch.conf /opt/batch/etc/batch.conf
COPY batch-README /opt/batch/README
COPY reportcalc /opt/batch/bin/reportcalc
COPY batch-watchdog.sh /usr/local/sbin/batch-watchdog
COPY batch-watchdog.service /etc/systemd/system/batch-watchdog.service
COPY cron-batch /etc/cron.d/batch

RUN chmod +x /opt/batch/aggregate.sh /opt/batch/bin/reportcalc /usr/local/sbin/batch-watchdog \
 && chmod 644 /etc/cron.d/batch \
 && systemctl enable ssh.service cron.service batch-watchdog.service \
 && mkdir -p /etc/systemd/system/multi-user.target.wants \
 && ln -sf /lib/systemd/system/systemd-user-sessions.service \
      /etc/systemd/system/multi-user.target.wants/systemd-user-sessions.service

EXPOSE 22
