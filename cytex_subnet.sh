#!/bin/bash
# cytex_subnet.sh — all-in-one “out-of-the-box” Pi AP installer

set -e
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run this with sudo or as root."; exit 1; }

echo "[+] Updating package lists…"
apt update -qq

echo "[+] Installing prerequisites…"
apt install -y dnsmasq hostapd netfilter-persistent iptables-persistent dhcpcd5

echo "[+] Stopping competing Wi-Fi services…"
systemctl stop wpa_supplicant.service 2>/dev/null || true
systemctl disable wpa_supplicant.service 2>/dev/null || true
if command -v nmcli &>/dev/null; then
  nmcli dev set wlan0 managed no || true
fi

echo "[+] Enabling core services…"
systemctl enable --now dhcpcd dnsmasq

echo "[+] Enabling IPv4 forwarding…"
sysctl -w net.ipv4.ip_forward=1
grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf \
  || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

echo "[+] Unlocking /etc/resolv.conf…"
chattr -i /etc/resolv.conf 2>/dev/null || true

# Prompt for WPA2 passphrase
read -s -p "Enter WPA2 password for 00_Cytex_Test_Net (min 8 chars): " WPA_PSK
echo
if [ ${#WPA_PSK} -lt 8 ]; then
  echo "ERROR: password must be at least 8 characters." >&2
  exit 1
fi
SSID="00_Cytex_Test_Net"

echo "[+] Configuring static IP on wlan0…"
cat <<EOF >> /etc/dhcpcd.conf
interface wlan0
  static ip_address=192.168.4.1/24
  nohook wpa_supplicant
  static domain_name_servers=140.82.3.211 8.8.8.8
EOF
systemctl restart dhcpcd

echo "[+] Configuring DHCP (dnsmasq)…"
cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
log-queries
log-dhcp
server=140.82.3.211
EOF
systemctl restart dnsmasq

echo "[+] Writing hostapd configuration…"
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

echo "[+] Bouncing wlan0…"
rfkill unblock wlan
ip link set wlan0 down || true
ip link set wlan0 up

echo "[+] Starting hostapd…"
systemctl unmask hostapd
systemctl enable --now hostapd

echo "[+] Applying NAT rules…"
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
netfilter-persistent save

echo "[+] Locking DNS to Cytex…"
echo "nameserver 140.82.3.211" > /etc/resolv.conf
chattr +i /etc/resolv.conf

echo "[✔] Setup complete — rebooting now."
reboot