#!/bin/bash
# USMS db tier bootstrap. Runs ONCE, as root, at first boot, via cloud-init.
# Idempotent: exits early if the marker file already exists.
set -x
exec > /var/log/usms-db-bootstrap.log 2>&1

MARKER=/var/log/usms-db-bootstrap.done

if [ -f "$MARKER" ]; then
  echo "Marker $MARKER already present — bootstrap already ran. Exiting."
  exit 0
fi

echo "USMS db bootstrap starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

dnf -y update
dnf -y install postgresql15-server postgresql15

postgresql-setup --initdb
systemctl enable --now postgresql

sudo -u postgres psql -c "CREATE DATABASE usms;"

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/instance-id")

printf 'instance=%s\ncompleted=%s\n' \
  "$INSTANCE_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARKER"

echo "USMS db bootstrap complete"
