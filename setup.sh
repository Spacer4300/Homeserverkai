#!/bin/bash

# === EINSTELLUNGEN ============================================================
UPDATEMON_IP="192.168.178.159"
REPORT_URL="http://$UPDATEMON_IP:5000/report"
CTID=$(hostname | grep -o '[0-9]*$')
PYTHON_BIN="/usr/bin/python3"
# ===============================================================================

echo "📦 Installiere Abhängigkeiten..."
apt update && apt install curl jq python3 python3-pip -y
pip3 install flask

# === check_updates.sh mit dynamischer Logik + IP ===============================
echo "🛠️ Erstelle dynamisches /usr/local/bin/check_updates.sh"
cat <<'EOF' > /usr/local/bin/check_updates.sh
#!/bin/bash

CTID=$(hostname | grep -o '[0-9]*$')
UPDATEMON="192.168.178.159"
IP=$(hostname -I | awk '{print $1}')

SERVICE=""
INSTALLED=""
LATEST=""

# === JELLYFIN ===
if dpkg -s jellyfin &>/dev/null; then
  SERVICE="Jellyfin"
  INSTALLED=$(dpkg -s jellyfin | grep Version | awk '{print $2}' | cut -d+ -f1)
  LATEST=$(curl -s https://api.github.com/repos/jellyfin/jellyfin/releases/latest | jq -r .tag_name | sed 's/^v//')

# === GLANCE ===
elif [ -f /opt/glance/version.txt ]; then
  SERVICE="Glance"
  INSTALLED=$(cat /opt/glance/version.txt | sed 's/^v//' | tr -d '[:space:]')
  LATEST=$(curl -s https://api.github.com/repos/glanceapp/glance/releases/latest | jq -r .tag_name | sed 's/^v//')

# === UPTIME KUMA ===
elif [ -f /opt/uptime-kuma/package.json ]; then
  SERVICE="Uptime Kuma"
  INSTALLED=$(grep '"version"' /opt/uptime-kuma/package.json | head -1 | grep -o '[0-9.]\+')
  LATEST=$(curl -s https://api.github.com/repos/louislam/uptime-kuma/releases/latest | jq -r .tag_name | sed 's/^v//')

# === DOCKGE ===
elif [ -f /opt/dockge/package.json ]; then
  SERVICE="Dockge"
  INSTALLED=$(grep '"version"' /opt/dockge/package.json | head -1 | grep -o '[0-9.]\+')
  LATEST=$(curl -s https://api.github.com/repos/louislam/dockge/releases/latest | jq -r .tag_name | sed 's/^v//')

# === FILEBROWSER ===
elif command -v filebrowser &>/dev/null; then
  SERVICE="Filebrowser"
  INSTALLED=$(filebrowser version | grep Version | awk '{print $2}')
  LATEST=$(curl -s https://api.github.com/repos/filebrowser/filebrowser/releases/latest | jq -r .tag_name | sed 's/^v//')

# === PIHOLE ===
elif command -v pihole &>/dev/null; then
  SERVICE="Pi-hole"
  INSTALLED=$(pihole -v | grep Core | awk '{print $5}' | sed 's/v//')
  LATEST=$(curl -s https://api.github.com/repos/pi-hole/pi-hole/releases/latest | jq -r .tag_name | sed 's/^v//')

# === TRACCAR ===
elif [ -f /opt/traccar/conf/traccar.xml ]; then
  SERVICE="Traccar"
  INSTALLED=$(grep -oPm1 "(?<=<version>)[^<]+" /opt/traccar/conf/traccar.xml)
  LATEST=$(curl -s https://api.github.com/repos/traccar/traccar/releases/latest | jq -r .tag_name | sed 's/^v//')

else
  echo "❌ Kein unterstützter Dienst gefunden – kein Report gesendet."
  exit 1
fi

curl -s -X POST http://$UPDATEMON:5000/report \
  -H "Content-Type: application/json" \
  -d "{\"ctid\":\"$CTID\",\"ip\":\"$IP\",\"service\":\"$SERVICE\",\"installed\":\"$INSTALLED\",\"latest\":\"$LATEST\"}"
EOF

chmod +x /usr/local/bin/check_updates.sh

# === upgrade.sh ================================================================
echo "🛠️ Erstelle /usr/local/bin/upgrade.sh"
cat <<'EOF' > /usr/local/bin/upgrade.sh
#!/bin/bash
echo "▶️ Update gestartet... (hier eigenen Update-Befehl einfügen)"
# Beispiel: apt update && apt upgrade -y
EOF
chmod +x /usr/local/bin/upgrade.sh

# === update_api.py =============================================================
echo "🛠️ Erstelle /usr/local/bin/update_api.py"
cat <<'EOF' > /usr/local/bin/update_api.py
from flask import Flask
import subprocess

app = Flask(__name__)

@app.route("/update-now", methods=["POST"])
def trigger_update():
    try:
        subprocess.run(["/usr/local/bin/upgrade.sh"], check=True)
        return "Update erfolgreich", 200
    except:
        return "Fehlgeschlagen", 500

app.run(host="0.0.0.0", port=5000)
EOF

# === systemd-Service für API ===================================================
echo "⚙️ Erstelle systemd-Service für API"
cat <<EOF > /etc/systemd/system/update-api.service
[Unit]
Description=Update API (autotriggerbar vom Updatemon)
After=network.target

[Service]
ExecStart=$PYTHON_BIN /usr/local/bin/update_api.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable update-api
systemctl start update-api

# === Cronjob eintragen =========================================================
echo "⏱️ Füge Cronjob hinzu für check_updates.sh"
(crontab -l 2>/dev/null | grep -Fv 'check_updates.sh'; echo "*/30 * * * * /usr/local/bin/check_updates.sh") | crontab -

echo "✅ Fertig! Automatische Versionserkennung & IP-Reporting aktiv!"
echo "📡 Update-API aktiv unter: http://<dieser-container>:5000/update-now"
