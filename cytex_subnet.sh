#!/bin/bash
# cytex_subnet.sh — prepare & provision Pi as a Cytex-monitored AP

set -e
[ "$(id -u)" -eq 0 ] || { echo "Run this with sudo"; exit 1; }

# 1) Update & install core packages
apt update -qq
apt install -y dnsmasq hostapd netfilter-persistent iptables-persistent dhcpcd5

# 2) Stop/disable any wpa_supplicant or NetworkManager on wlan0
systemctl stop wpa_supplicant.service 2>/dev/null || true
systemctl disable wpa_supplicant.service 2>/dev/null || true
if command -v nmcli &>/dev/null; then
  nmcli dev set wlan0 managed no 2>/dev/null || true
fi

# 3) Enable dhcpcd, dnsmasq & hostapd
systemctl enable --now dhcpcd dnsmasq hostapd

# 4) Turn on IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1
grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf \
  || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

# 5) Unlock resolv.conf so we can override it later
chattr -i /etc/resolv.conf 2>/dev/null || true

# 6) Prompt for the WPA2 passphrase
read -s -p "Enter WPA2 password for 00_Cytex_Test_Net (min 8 chars): " WPA_PSK
echo
[ ${#WPA_PSK} -ge 8 ] || { echo "Passphrase too short"; exit 1; }
SSID="00_Cytex_Test_Net"

# 7) Configure static IP on wlan0 via dhcpcd
cat <<EOF >> /etc/dhcpcd.conf
interface wlan0
  static ip_address=192.168.4.1/24
  nohook wpa_supplicant
  static domain_name_servers=140.82.3.211 8.8.8.8
EOF
systemctl restart dhcpcd

# 8) Configure DHCP in dnsmasq
cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
log-queries
log-dhcp
server=140.82.3.211
EOF
systemctl restart dnsmasq

# 9) Write hostapd.conf
cat <<EOF > /etc/hostapd/hostapd.conf
interface=wlan0
driver=nl80211
ssid=$SSID
country_code=US
ieee80211n=1
hw_mode=g
channel=6
wmm_enabled=1
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WPA_PSK
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# 10) Clean up & bring up wlan0 exclusively for hostapd
rfkill unblock wlan
ip link set wlan0 down || true
ip link set wlan0 up
systemctl unmask hostapd
systemctl enable --now hostapd

# 11) NAT rules
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
netfilter-persistent save
netfilter-persistent reload

# 12) Lock DNS to Cytex
echo "nameserver 140.82.3.211" > /etc/resolv.conf
chattr +i /etc/resolv.conf

echo "[✔] Setup complete — rebooting…"
reboot
