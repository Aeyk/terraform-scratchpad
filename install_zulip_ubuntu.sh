#!/usr/bin/env bash

set -o xtrace

EMAIL=mksybr@gmail.com
DOMAIN=zulip.mksybr.com
CERT_OPTS=--self-signed-cert
PUBLIC_IP=$(curl -fsSL ipconfig.me)

# TODO(Malik): if nslookup of $DOMAIN contains $PUBLIC_IP then set CERT_OPTS=--certbot


cd $(mktemp -d)
curl -fLO https://download.zulip.com/server/zulip-server-latest.tar.gz
curl -fLO https://download.zulip.com/server/SHA256SUMS.txt
# TODO(Malik): check sha256sum and failout if wrong
tar -xf zulip-server-latest.tar.gz


sudo ./zulip-server-*/scripts/setup/install $CERT_OPTS \
    --email=$EMAIL --hostname=$DOMAIN
