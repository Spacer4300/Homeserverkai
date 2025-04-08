#!/bin/bash

PORT=5005
echo "📦 Setup der /version API auf Port $PORT beginnt..."

# Flask installieren
apt update && apt install python3 python3-pip -y
pip3 install flask

# Dienst automatisch erkennen
SERVICE=""
VERSION_CMD=""
VERSION_PATH=""

# === Glance
if [ -f /opt/glance/version.txt ]; then
    SERVICE="Glance"
    VERSION_CMD=""
    VERSION_PATH="/opt/glance/version.txt"

# === Jellyfin
elif dpkg -s jellyfin &>/dev/null; then
    SERVICE="Jellyfin"
    VERSION_CMD="dpkg-query -W -f='\${Version}' jellyfin"

# === Uptime Kuma
elif [ -f /opt/uptime-kuma/package.json ]; then
    SERVICE="Uptime Kuma"
    VERSION_CMD="grep '\"version\"' /opt/uptime-kuma/package.json | head -1 | grep -o '[0-9.]\+'"

# === Dockge
elif [ -f /opt/dockge/package.json ]; then
    SERVICE="Dockge"
    VERSION_CMD="grep '\"version\"' /opt/dockge/package.json | head -1 | grep -o '[0-9.]\+'"

# === Filebrowser
elif command -v filebrowser &>/dev/null; then
    SERVICE="Filebrowser"
    VERSION_CMD="filebrowser version | grep Version | awk '{print \$2}'"

# === Pi-hole
elif command -v pihole &>/dev/null; then
    SERVICE="Pi-hole"
    VERSION_CMD="pihole -v | grep Core | awk '{print \$5}' | sed 's/v//'"

# === Traccar
elif [ -f /opt/traccar/conf/traccar.xml ]; then
    SERVICE="Traccar"
    VERSION_CMD="grep -oPm1 '(?<=<version>)[^<]+' /opt/traccar/conf/traccar.xml"
fi

# === Fallback
if [ -z "$SERVICE" ]; then
    echo "❌ Kein unterstützter Dienst erkannt. Abbruch."
    exit 1
fi

echo "✅ Erkannt: $SERVICE"

# === Flask API schreiben
cat <<EOF > /usr/local/bin/version_api.py
from flask import Flask, jsonify
import subprocess

app = Flask(__name__)

@app.route("/version")
def version():
    try:
EOF

if [ -n "$VERSION_PATH" ]; then
    echo "        with open(\"$VERSION_PATH\") as f:" >> /usr/local/bin/version_api.py
    echo "            ver = f.read().strip().lstrip('v')" >> /usr/local/bin/version_api.py
else
    echo "        ver = subprocess.check_output(\"$VERSION_CMD\", shell=True).decode().strip()" >> /usr/local/bin/version_api.py
    echo "        ver = ver.lstrip('v')" >> /usr/local/bin/version_api.py
fi

cat <<EOF >> /usr/local/bin/version_api.py
    except:
        ver = "❌ Fehler"
    return jsonify({"service": "$SERVICE", "version": ver})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=$PORT)
EOF

chmod +x /usr/local/bin/version_api.py

# === systemd Service erstellen
cat <<EOF > /etc/systemd/system/version-api.service
[Unit]
Description=Mini API für Versionsabfrage ($SERVICE)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/version_api.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable version-api
systemctl start version-api

echo "✅ API gestartet auf Port $PORT! Teste: http://<IP-des-Containers>:${PORT}/version"
