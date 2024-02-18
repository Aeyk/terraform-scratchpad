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

sudo su zulip -c '/home/zulip/deployments/current/manage.py generate_realm_creation_link'

# TODO(Malik): terraform aws ses, setup, get dns txt records
# TODO(Malik): terraform digital ocean dns record a & txt
# TODO(Malik): ansible for configuration management
# TODO(Malik): backups
# TODO(Malik): high availability (what does this take)

# https://github.com/42wim/matterbridge#readme
# TODO(Malik): matterbridge: irc connectors
# TODO(Malik): replace dummy values 
read -r -d '' MATTERBRIDGE_CONF << EOF
[slack]
[slack.test]
Token="yourslacktoken"
PrefixMessagesWithNick=true

[discord]
[discord.test]
Token="yourdiscordtoken"
Server="yourdiscordservername"

[general]
RemoteNickFormat="[{PROTOCOL}/{BRIDGE}] <{NICK}> "

[[gateway]]
    name = "mygateway"
    enable=true

    [[gateway.inout]]
    account = "discord.test"
    channel="general"

    [[gateway.inout]]
    account ="slack.test"
    channel = "general"
EOF

read -r -d '' MATTERBRIDGE_SERVICE << EOF
[Unit]
Description=Matterbridge daemon
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/matterbridge -conf /etc/matterbridge/matterbridge.conf
Restart=always
RestartSec=5s
User=matterbridge

[Install]
WantedBy=multi-user.target
EOF

sudo useradd -r matterbridge -s /bin/false
curl -fLO https://github.com/42wim/matterbridge/releases/download/v1.26.0/matterbridge-1.26.0-linux-arm64
sudo mv ./matterbridge* /usr/local/bin/matterbridge
echo "$MATTERBRIDGE_SERVICE" | sudo tee /etc/systemd/system/matterbridge.service > /dev/null 
sudo mkdir /etc/matterbridge
echo "$MATTERBRIDGE_CONF' | sudo tee /etc/matterbridge/matterbridge.conf > /dev/null

