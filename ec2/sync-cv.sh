#!/bin/bash
# Copy the site/ prefix of the CV bucket into the web root,
# replace the footer placeholder, and log whether it worked.
BUCKET="cv-23l-3046"
PREFIX="site/"
REGION="us-east-1"
WEBROOT="/var/www/html"
LOG="/var/log/cv-sync.log"
TMP="$(mktemp -d)"

# IMDSv2: get a session token, then read the instance ID
TOKEN="$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')"
INSTANCE_ID="$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)"

if aws s3 sync "s3://${BUCKET}/${PREFIX}" "$TMP" --region "$REGION" --only-show-errors \
   && [ -s "$TMP/index.html" ]; then
  sed -i "s|{{HOSTED_ON}}|EC2 ${INSTANCE_ID}|g" "$TMP/index.html"
  cp -f "$TMP"/* "$WEBROOT"/
  chmod 644 "$WEBROOT"/*
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) sync OK instance=${INSTANCE_ID}" >> "$LOG"
else
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) sync FAILED" >> "$LOG"
fi
rm -rf "$TMP"