#!/bin/bash
set -e

dnf update -y
dnf install -y aws-cli

INTERVAL=600
IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
ZONE_ID="Z08397422LH3IDIZRIAIU"
RECORD_NAME="p.suzu.me.uk"
TTL=300

cat <<EOF >change-batch.json
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$RECORD_NAME",
        "Type": "A",
        "TTL": $TTL,
        "ResourceRecords": [
          {
            "Value": "$IP"
          }
        ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file://change-batch.json

get_rx_bytes() {
    total_rx=0
    for pid in $(pidof sshd); do
        file=/proc/${pid}/net/dev
        if [[ -f $file ]]; then
            rx=$(awk '{if (NR>2) sum+=$2} END {print sum}' "${file}")
            total_rx=$((total_rx + rx))
        fi
    done
    echo $total_rx
}

initial_rx=$(get_rx_bytes)
while true; do
    sleep $INTERVAL
    current_rx=$(get_rx_bytes)
    received=$((current_rx - initial_rx))
    if [[ $received -eq 0 ]]; then
        aws autoscaling set-desired-capacity --auto-scaling-group-name ASG_NAME --desired-capacity 0
    fi
    initial_rx=$current_rx
done
