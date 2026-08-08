FROM jrei/systemd-ubuntu:22.04

# サーバに入っていそうな道具一式
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server sudo lsof psmisc procps file less vim-tiny ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# 作業用ユーザー(EC2のAmazon Linux/Ubuntuに寄せた名前)
RUN useradd -m -s /bin/bash ec2-user \
 && echo 'ec2-user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ec2-user \
 && chmod 440 /etc/sudoers.d/90-ec2-user \
 && mkdir -p /home/ec2-user/.ssh \
 && chmod 700 /home/ec2-user/.ssh \
 && chown -R ec2-user:ec2-user /home/ec2-user/.ssh

# pam_env が毎回エラーを出して journalctl を汚すので用意しておく
RUN echo 'LANG=C.UTF-8' > /etc/default/locale

RUN mkdir -p /var/lib/reportd /var/log/reportd /run/sshd

COPY reportd.sh /usr/local/bin/reportd
COPY reportd.service /etc/systemd/system/reportd.service
COPY var-log-reportd.mount /etc/systemd/system/var-log-reportd.mount
COPY debug-collector.service /etc/systemd/system/debug-collector.service
RUN chmod +x /usr/local/bin/reportd \
 && systemctl enable ssh.service reportd.service var-log-reportd.mount \
 # このイメージでは systemd-user-sessions が起動せず /run/nologin が残るため明示的に有効化する
 && mkdir -p /etc/systemd/system/multi-user.target.wants \
 && ln -sf /lib/systemd/system/systemd-user-sessions.service \
      /etc/systemd/system/multi-user.target.wants/systemd-user-sessions.service

EXPOSE 22
