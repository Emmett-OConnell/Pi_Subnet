#!/bin/bash
set -e

echo "Cytex Subnet Setup Initializing…"
read -s -p "Enter a WPA2 password for the Wi-Fi network (min 8 characters): " wpa_pass
echo

if [ ${#wpa_pass} -lt 8 ]; then
    echo "Error: Password must be at least 8 characters."
    exit 1
fi

SSID="00_Cytex_Test_Net"

echo "[+] Installing dependencies…"
apt update
apt install -y dnsmasq hostapd netfilter-persistent iptables-persistent network-manager

echo "[+] Starting NetworkManager…"
systemctl enable NetworkManager
systemctl start NetworkManager
sleep 2

echo "[+] Configuring wlan0 as an AP ($SSID)…"
nmcli connection delete CytexAP      &>/dev/null || true
nmcli connection add \
    type wifi ifname wlan0 con-name CytexAP autoconnect yes ssid "$SSID"

nmcli connection modify CytexAP \
    802-11-wireless.mode ap \
    802-11-wireless.band bg \
    802-11-wireless.channel 6 \
    802-11-wireless.security key-mgmt wpa-psk \
    802-11-wireless-security.psk "$wpa_pass" \
    ipv4.addresses 192.168.4.1/24 \
    ipv4.method manual \
    ipv4.dns "140.82.3.211 8.8.8.8"

nmcli connection up CytexAP

echo "[+] Configuring DHCP (dnsmasq)…"
cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
log-queries
log-dhcp
server=140.82.3.211
EOF
systemctl restart dnsmasq

echo "[+] Enabling IP forwarding…"
sysctl -w net.ipv4.ip_forward=1

echo "[+] Applying NAT rules…"
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
netfilter-persistent save
netfilter-persistent reload

echo "[+] Locking DNS resolver to Cytex…"
chattr -i /etc/resolv.conf 2>/dev/null || true
echo "nameserver 140.82.3.211" > /etc/resolv.conf
chattr +i /etc/resolv.conf

echo "[+] Setup complete — rebooting now."
reboot
