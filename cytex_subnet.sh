#!/bin/bash
# cytex_subnet.sh — combined prereq-setup & subnet installer for Cytex Lab
set -e

# 1️⃣ Ensure root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run this with sudo or as root." >&2
  exit 1
fi

echo "[+] Updating package lists…"
apt update -qq

# 2️⃣ Common prerequisites
pkgs=(dnsmasq hostapd netfilter-persistent iptables-persistent)

# 3️⃣ Detect network manager or dhcpcd
if command -v nmcli &>/dev/null; then
  echo "[+] Detected NetworkManager"
  manager="nm"
  pkgs+=(network-manager)
elif dpkg -l dhcpcd5 &>/dev/null; then
  echo "[+] Detected dhcpcd5"
  manager="dhcpcd"
else
  echo "[+] Installing dhcpcd5 (Lite OS)"
  pkgs+=(dhcpcd5)
  manager="dhcpcd"
fi

# 4️⃣ Install any missing packages
echo "[+] Installing: ${pkgs[*]}"
DEBIAN_FRONTEND=noninteractive apt install -y -qq "${pkgs[@]}"

# 5️⃣ Enable networking service
if [ "$manager" = "nm" ]; then
  systemctl enable --now NetworkManager
else
  systemctl enable --now dhcpcd
fi

# 6️⃣ Enable dnsmasq & hostapd
systemctl enable --now dnsmasq hostapd

# 7️⃣ Enable IPv4 forwarding
echo "[+] Enabling IP forwarding…"
sysctl -w net.ipv4.ip_forward=1
grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf || \
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

# 8️⃣ Unlock resolv.conf so we can lock it later
chattr -i /etc/resolv.conf 2>/dev/null || true

# 9️⃣ Prompt for WPA2 passphrase
read -s -p "Enter a WPA2 password for '00_Cytex_Test_Net' (min 8 chars): " WPA_PSK
echo
if [ ${#WPA_PSK} -lt 8 ]; then
  echo "Error: password must be at least 8 characters." >&2
  exit 1
fi
SSID="00_Cytex_Test_Net"

# 🔟 Configure static IP & DNS
if [ "$manager" = "nm" ]; then
  echo "[+] Configuring static IP via NetworkManager…"
  nmcli connection delete CytexAP 2>/dev/null || true
  nmcli connection add type wifi ifname wlan0 con-name CytexAP autoconnect yes ssid "$SSID"
  nmcli connection modify CytexAP \
    802-11-wireless.mode ap \
    802-11-wireless.band bg \
    802-11-wireless.channel 6 \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$WPA_PSK" \
    ipv4.addresses 192.168.4.1/24 \
    ipv4.method manual \
    ipv4.dns "140.82.3.211 8.8.8.8"
  nmcli connection up CytexAP
else
  echo "[+] Configuring static IP via dhcpcd…"
  cat <<EOF >> /etc/dhcpcd.conf
interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
    static domain_name_servers=140.82.3.211 8.8.8.8
EOF
  systemctl restart dhcpcd
fi

# 1️⃣1️⃣ Configure DHCP (dnsmasq)
echo "[+] Configuring DHCP (dnsmasq)…"
cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
log-queries
log-dhcp
server=140.82.3.211
EOF
systemctl restart dnsmasq

# 1️⃣2️⃣ Configure hostapd
echo "[+] Configuring hostapd…"
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
sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
systemctl unmask hostapd
systemctl enable --now hostapd

# 1️⃣3️⃣ Apply NAT rules
echo "[+] Applying NAT…"
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
netfilter-persistent save
netfilter-persistent reload

# 1️⃣4️⃣ Lock DNS to Cytex
echo "[+] Locking DNS resolver…"
chattr -i /etc/resolv.conf 2>/dev/null || true
echo "nameserver 140.82.3.211" > /etc/resolv.conf
chattr +i /etc/resolv.conf

echo "[✔] Setup complete — rebooting…"
reboot
