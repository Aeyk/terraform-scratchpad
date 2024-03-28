#!/usr/bin/env sh

curl https://docs.oracle.com/en-us/iaas/Content/Resources/Assets/secondary_vnic_all_configure.sh | sudo tee /usr/local/bin/vnic
cat << EOF > /etc/systemd/system/vnic.service
[Unit]
Description=Setting the secondary vnic
After=default.target
[Service]
User=root
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/vnic -c
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable vnic.service
sudo reboot
