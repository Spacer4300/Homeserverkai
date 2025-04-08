#!/bin/bash

CLEAN_SCRIPT="/usr/local/bin/lxc_cleanup.sh"

echo "🧹 Erstelle Reinigungs-Skript unter $CLEAN_SCRIPT ..."

cat << 'EOF' > $CLEAN_SCRIPT
#!/bin/bash

# Alte Logs, Cache, temporäre Dateien löschen
rm -rf /var/tmp/*
rm -rf /tmp/*
apt-get autoremove -y
apt-get autoclean -y
apt-get clean

# Journald begrenzen (falls aktiv)
journalctl --vacuum-time=7d > /dev/null 2>&1

# Docker prüfen und aufräumen
if command -v docker &> /dev/null; then
    docker system prune -af --volumes
fi

EOF

chmod +x $CLEAN_SCRIPT

# Cronjob erstellen
CRONJOB="0 0 * * * root $CLEAN_SCRIPT"
CRONFILE="/etc/cron.d/lxc-cleanup"

echo "🕒 Erstelle täglichen Cronjob unter $CRONFILE ..."
echo "$CRONJOB" > $CRONFILE
chmod 644 $CRONFILE

echo "✅ Setup abgeschlossen. Cleanup läuft täglich um 00:00 Uhr automatisch."
