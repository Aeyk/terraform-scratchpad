# -*- mode: ruby -*-

Vagrant.configure("2") do |config|
    config.vm.box = "ubuntu/jammy64"
    config.vm.network "private_network", ip: "192.168.56.255"
    config.vm.hostname = "chat.mksybr.com"
    config.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
    end
    config.ssh.insert_key = 'true'
    config.vm.provision "shell", 
      inline: <<-INSTALL
apt-get update
apt-get install -y curl nginx certbot python3-certbot-nginx net-tools
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 
curl -sL https://github.com/thelounge/thelounge-deb/releases/download/v4.4.0/thelounge_4.4.0_all.deb -o thelounge.deb
apt-get update; apt-get install -qq -y nodejs
dpkg -i thelounge.deb
chown -R thelounge:thelounge /etc/thelounge
snap install core
snap refresh core
snap install --classic certbot
certbot certonly --nginx --email mksybr@gmail.com --agree-tos --no-eff-email --staging  -d chat.mksybr.com --dry-run
systemctl restart nginx
      INSTALL
end
