#!/bin/bash
# cytex-subnet-install-auto.sh — fully non-interactive installer

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1) Configuration via ENV (fallback to defaults)
SSID="${SSID:-00_Cytex_Test_Net}"
WPA_PSK="${WPA_PSK:-cytexsecure}"

# 2) Validate passphrase length
if [ "${#WPA_PSK}" -lt 8 ]; then
  echo "ERROR: WPA_PSK must be at least 8 characters. Got '${WPA_PSK}' (length ${#WPA_PSK})."
  exit 1
fi

echo "[+] Installing dependencies…"
apt-get update -qq
apt-get install -y -qq dnsmasq hostapd netfilter-persistent iptables-persistent dhcpcd5

echo "[+] Enabling services…"
systemctl unmask hostapd
systemctl enable --now hostapd dnsmasq dhcpcd

# 3) Static IP via dhcpcd (Lite OS)
cat <<EOF >> /etc/dhcpcd.conf
interface wlan0
  static ip_address=192.168.4.1/24
  nohook wpa_supplicant
  static domain_name_servers=140.82.3.211 8.8.8.8
EOF
systemctl restart dhcpcd

# 4) DHCP via dnsmasq
cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
log-queries
log-dhcp
server=140.82.3.211
EOF
systemctl restart dnsmasq

# 5) hostapd config
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
wpa_passphrase=$WPA_PSK
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# Point hostapd at our config
sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
systemctl restart hostapd

# 6) Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# 7) NAT rules
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
netfilter-persistent save
netfilter-persistent reload

# 8) Lock DNS to Cytex
chattr -i /etc/resolv.conf 2>/dev/null || true
echo "nameserver 140.82.3.211" > /etc/resolv.conf
chattr +i /etc/resolv.conf

echo "[+] Setup complete. Rebooting…"
reboot
