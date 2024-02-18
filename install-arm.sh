#!/usr/bin/env sh
if test "$UID" -ne 0; then
		printf "FATAL: this script require root"
    sleep 10
    exit
fi

dnf groupinstall "server with GUI"
dnf install -y epel-release
dnf install -y xrdp
firewall-cmd -permanent -add-port=3389/tcp
firewall-cmd -reload
