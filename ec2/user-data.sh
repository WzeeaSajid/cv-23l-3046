#!/bin/bash
set -x
dnf install -y httpd
systemctl enable --now httpd

# Get the sync script from the public GitHub repo
curl -fsSL --retry 5 --retry-delay 3 \
  https://raw.githubusercontent.com/WzeeaSajid/cv-23l-3046/main/ec2/sync-cv.sh \
  -o /usr/local/bin/sync-cv.sh
sed -i 's/\r$//' /usr/local/bin/sync-cv.sh
chmod +x /usr/local/bin/sync-cv.sh

# systemd service + timer (runs every 2 minutes)
cat > /etc/systemd/system/cv-sync.service <<'EOF'
[Unit]
Description=Sync CV site from S3

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-cv.sh
EOF

cat > /etc/systemd/system/cv-sync.timer <<'EOF'
[Unit]
Description=Run CV sync every 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now cv-sync.timer

# Run the sync once right now
/usr/local/bin/sync-cv.sh