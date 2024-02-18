#!/usr/bin/env sh
if test "$UID" -ne 0; then
		printf "FATAL: this script require root" && \
    sleep 10 && \
    exit
fi

dnf groupinstall -y "server with GUI"
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf config-manager --set-enabled crb
dnf install -y epel-release epel-release-next
dnf install -y --enablerepo="epel" xrdp
# not necessary as i will make a ssh tunnel on client before connecting via:
# 	ssh opc@me.mksybr.com -L3389:127.0.0.1:3389
# firewall-cmd --permanent --add-service=rdp
# firewall-cmd --permanent --add-port=3389/tcp
# firewall-cmd --reload
echo 'me  ALL=(ALL:ALL) ALL' >> /etc/sudoers.d/me
systemctl enable --now xrdp
