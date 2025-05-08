#!/bin/bash
set -e

echo "Cytex Subnet Setup Initializing..."
read -s -p "Enter a WPA2 password for the Wi-Fi network (min 8 characters): " wpa_pass
echo

if [ ${#wpa_pass} -lt 8 ]; then
    echo "Error: Password must be at least 8 characters."
    exit 1
fi

SSID="00_Cytex_Test_Net"

echo "[+] Updating system and installing dependencies..."
apt update && apt install -y dnsmasq hostapd netfilter-persistent iptables-persistent

echo "[+] Enabling services..."
systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq

echo "[+] Configuring static IP for wlan0..."
cat <<EOF >> /etc/dhcpcd.conf
interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
    static domain_name_servers=140.82.3.211 8.8.8.8
EOF
systemctl restart dhcpcd

echo "[+] Configuring dnsmasq..."
cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
log-queries
log-dhcp
server=140.82.3.211
EOF

echo "[+] Creating hostapd configuration..."
cat <<EOF > /etc/hostapd/hostapd.conf
interface=wlan0
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
wmm_enabled=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$wpa_pass
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd

echo "[+] Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "[+] Setting up NAT routing..."
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
netfilter-persistent save
netfilter-persistent reload

echo "[+] Locking DNS resolver config..."
chattr -i /etc/resolv.conf || true
echo "nameserver 140.82.3.211" > /etc/resolv.conf
chattr +i /etc/resolv.conf

echo "[+] Setup complete. Rebooting..."
reboot
