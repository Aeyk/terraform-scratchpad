E#!/usr/bin/env sh
if test "$UID" -ne 0; then
		printf "FATAL: this script require root"
    sleep 10
    exit
fi

systemctl start iptables
systemctl start ip6tables
cp /etc/iptables/rules.v{4,6} /tmp # backup incase of havok
iptables -L --line-numbers # get line numbers
ip6tables -L --line-numbers
for port in 80 443 6667 ; do
		iptables -I INPUT 6 -m state --state NEW -p tcp --dport $port -j ACCEPT
done
netfilter-persistent save
iptables -L --line-numbers # make sure accept 80,443 rules addes
ip6tables -L --line-numbers
apt-get update
apt-get install -y curl nginx certbot python3-certbot-nginx net-tools
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 
curl -sL https://github.com/thelounge/thelounge-deb/releases/download/v4.4.0/thelounge_4.4.0_all.deb -o thelounge.deb
apt-get update; apt-get install -qq -y nodejs
dpkg -i thelounge.deb
usermod thelounge -s /bin/bash
chown -R thelounge:thelounge /etc/thelounge
snap install core
snap refresh core
snap install --classic certbot
certbot --nginx --email mksybr@gmail.com --agree-tos --no-eff-email -d chat.mksybr.com

cat <<EOT >>/etc/nginx/sites-available/irc.conf
server {
	listen [::]:443 ssl ipv6only=on; # managed by Certbot
	listen 443 ssl; # managed by Certbot
	ssl_certificate /etc/letsencrypt/live/chat.mksybr.com/fullchain.pem; # managed by Certbot
	ssl_certificate_key /etc/letsencrypt/live/chat.mksybr.com/privkey.pem; # managed by Certbot
	include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
	ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
	
	location /irc/ {
		proxy_pass http://127.0.0.1:9000/;
		proxy_http_version 1.1;
		proxy_set_header Connection "upgrade";
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header X-Forwarded-For $remote_addr;
		proxy_set_header X-Forwarded-Proto $scheme;
		# by default nginx times out connections in one minute
		proxy_read_timeout 1d;
	}
}
EOT

sudo ln -s /etc/nginx/sites-available/irc.conf /etc/nginx/sites-enabled/irc.conf
systemctl restart nginx
PASS=$(dd if=/dev/random bs=16 count=1 status=none | base64)
echo $PASS
sudo -u thelounge sh -c 'PASS=$(dd if=/dev/random bs=16 count=1 status=none | base64)
printf "password: %s\n" "$PASS"
echo $PASS | thelounge add me
PASS=""'
