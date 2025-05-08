# Cytex Raspberry PI Subnet Setup Guide

---

## 🧰 What You’ll Need

- **Hardware**  
  - Raspberry Pi 3 or newer (built-in Wi-Fi)  
  - microSD card (16 GB+)  
  - Pi power supply  
  - Ethernet cable (to your main router)  

- **Software & Accounts**  
  - A computer with an SD-card reader  
  - [Raspberry Pi Imager](https://www.raspberrypi.com/software/)  
  - Your Pi’s external IP whitelisted in Cytex (email **emmett@cytex.io**)  

---

## 1️⃣ Flash & Prep the SD Card

1. **Download & run** Raspberry Pi Imager.  
2. **Select OS** → _Raspberry Pi OS Lite (64-bit)_  
3. **Choose your SD card** and click **Write**.  
4. **Enable SSH (headless)**  
   - After “Write” completes, open the **boot** partition on your computer.  
   - Create an **empty** file named:
     ```bash
     ssh
     ```
5. **Eject** the card and insert it into your Pi.

---

## 2️⃣ First Boot & SSH In

1. Power on the Pi, wait 30 s for boot.  
2. From your computer’s terminal:
   ```bash
   ssh pi@raspberrypi.local
   ```
3. _Default password_: `raspberry`  

---

## 3️⃣ Download & Run the One-Script Installer

1. **Fetch the installer**:
   ```bash
   curl -O https://raw.githubusercontent.com/Emmett-OConnell/Pi_Subnet/main/cytex_subnet.sh
   ```
2. **Make it executable**:
   ```bash
   chmod +x cytex_subnet.sh
   ```
3. **Run it** (you’ll be prompted for your Wi-Fi passphrase):
   ```bash
   sudo ./cytex_subnet.sh
   ```
   - **SSID is fixed** to `00_Cytex_Test_Net`  
   - **Enter a WPA2 passphrase** (≥ 8 chars) when asked  

4. The script will:
   - Install and enable all required services  
   - Apply a **static IP** `192.168.4.1/24` on `wlan0`  
   - Configure **dnsmasq** for DHCP (`192.168.4.10–192.168.4.100`)  
   - Write a proper **hostapd.conf** and take exclusive control of `wlan0`  
   - Set up **iptables** NAT and **lock DNS** to `140.82.3.211`  
   - **Reboot** automatically when done  

---

## 4️⃣ Verify Your New Subnet

After the Pi reboots:

1. **SSH back in** (via Ethernet side):
   ```bash
   ssh pi@<your-LAN-IP>  
   # or: ssh pi@raspberrypi.local
   ```
2. **On any Wi-Fi device**, join:
   - **Network**: `00_Cytex_Test_Net`  
   - **Password**: (the passphrase you entered)  

3. **Check your client IP** (should be `192.168.4.x`):
   ```bash
   ipconfig getifaddr en0    # macOS
   # or
   ip addr show wlan0        # Linux
   ```

4. **Connect your subnet to Cytex** 

   Type the following comand to get the IP of your pi then add it to cytex using our [**DNS Setup Guide**](https://broadstonetechnologies-my.sharepoint.com/:w:/g/personal/emmett_broadstonetechnologies_onmicrosoft_com/EcgwjBtaV-NPpVJiWQd5mfIB1xOIDcRQlBOHY-g_DuJ3qQ?rtime=76f2Qk-O3Ug)
   ```
   ip -4 addr show eth0 | awk '/inet /{print $2}' | cut -d/ -f1
   ```

5. **Ping the Pi gateway**:
   ```bash
   ping -c 3 192.168.4.1
   ```

6. **Test Internet**:
   ```bash
   ping -c 3 8.8.8.8
   ```

7. **Test DNS via Cytex**:
   ```bash
   nslookup example.com 140.82.3.211
   ```

---

## ✅ You’re Done!

If all tests pass, you now have a working subnet:

- **AP IP**: `192.168.4.1`  
- **DHCP range**: `192.168.4.10–192.168.4.100`  
- **DNS**: `140.82.3.211` (Cytex)  
- **NAT**: traffic forwarded to your main router via `eth0`

For support please contact **emmett@cytex.io**
