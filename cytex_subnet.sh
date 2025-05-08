#!/bin/bash
# cytex_subnet.sh — prepare & provision Pi as a Cytex‐monitored AP (hostapd‐only)

set -e
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }

echo "[+] Updating package lists…"
apt update -qq

# 1) Install core deps
apt install -y dnsmasq hostapd netfilter-persistent iptables-persistent dhcpcd5

# 2) Stop any competing Wi-Fi services
systemctl stop wpa_supplicant.service 2>/dev/null || true
systemctl disable wpa_supplicant.service 2>/dev/null || true

# 3) Disable NetworkManager on wlan0 if present
if command -v nmcli &>/dev/null; then
  echo "[+] Disabling NM for wlan0…"
  nmcli dev set wlan0 managed no || true
fi

# 4) Enable dhcpcd (static IP) & dnsmasq & hostapd
systemctl enable --now dhcpcd dnsmasq hostapd

# 5) Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1
grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf \
  || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

# 6) Unlock resolv.conf so we can overwrite it later
chattr -i /etc/resolv.conf 2>/dev/null || true

# 7) Ask for your WPA2 passphrase
read -s -p "Enter a WPA2 password for '00_Cytex_Test_Net' (min 8 chars): " WPA_PSK
echo
[ ${#WPA_PSK} -ge 8 ] || { echo "Passphrase too short"; exit 1; }
SSID="00_Cytex_Test_Net"

# 8) Static IP via dhcpcd
cat <<EOF >> /etc/dhcpcd.conf
interface wlan0
  static ip_address=192.168.4.1/24
  nohook wpa_supplicant
  static domain_name_servers=140.82.3.211 8.8.8.8
EOF
systemctl restart dhcpcd

# 9) DHCP server config
cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
log-queries
log-dhcp
server=140.82.3.211
EOF
systemctl restart dnsmasq

# 🔟 hostapd config
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

# Point hostapd at it
sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# 1️⃣1️⃣ Bounce & unblock wlan0
rfkill unblock wlan
ip link set wlan0 down || true
ip link set wlan0 up

# 1️⃣2️⃣ Start hostapd cleanly
systemctl unmask hostapd
systemctl enable --now hostapd

# 1️⃣3️⃣ NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
netfilter-persistent save
netfilter-persistent reload

# 1️⃣4️⃣ Lock DNS to Cytex
echo "nameserver 140.82.3.211" > /etc/resolv.conf
chattr +i /etc/resolv.conf

echo "[✔] Done — rebooting now."
reboot
