FROM jrei/systemd-ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server sudo nginx curl openssl ca-certificates faketime \
      lsof psmisc procps file less vim-tiny \
 && rm -rf /var/lib/apt/lists/*

RUN echo 'LANG=C.UTF-8' > /etc/default/locale

RUN useradd -m -s /bin/bash ec2-user \
 && echo 'ec2-user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ec2-user \
 && chmod 440 /etc/sudoers.d/90-ec2-user \
 && mkdir -p /home/ec2-user/.ssh \
 && chmod 700 /home/ec2-user/.ssh \
 && chown -R ec2-user:ec2-user /home/ec2-user/.ssh

RUN mkdir -p /etc/nginx/tls /var/lib/tls-watchdog /run/sshd

COPY gen-certs.sh /usr/local/sbin/gen-certs
RUN chmod +x /usr/local/sbin/gen-certs && /usr/local/sbin/gen-certs

# 運用状態: nginxには連鎖つきの証明書を、信頼ストアにはルートCAを置く
RUN cp /opt/tls/fullchain.crt /etc/nginx/tls/server.crt \
 && cp /opt/tls/server.key /etc/nginx/tls/server.key \
 && chmod 640 /etc/nginx/tls/server.key \
 && cp /opt/tls/rootCA.crt /usr/local/share/ca-certificates/reports-root.crt \
 && update-ca-certificates

COPY pki-README /opt/tls/README
COPY nginx-tls.conf /etc/nginx/conf.d/reports.conf
COPY tls-watchdog.sh /usr/local/sbin/tls-watchdog
COPY tls-watchdog.service /lib/systemd/system/tls-watchdog.service

RUN rm -f /etc/nginx/sites-enabled/default \
 && chmod +x /usr/local/sbin/tls-watchdog \
 && systemctl enable ssh.service nginx.service tls-watchdog.service \
 && mkdir -p /etc/systemd/system/multi-user.target.wants \
 && ln -sf /lib/systemd/system/systemd-user-sessions.service \
      /etc/systemd/system/multi-user.target.wants/systemd-user-sessions.service

EXPOSE 22 443
