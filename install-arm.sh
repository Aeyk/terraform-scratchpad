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
firewall-cmd --permanent --add-service=rdp
firewall-cmd --permanent --add-port=3389/tcp
firewall-cmd --reload
systemctl enable --now xrdp
