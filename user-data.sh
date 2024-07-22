#!/bin/bash
set -xe

#dnf update -y
#dnf install -y aws-cli

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)
DISCORD_WEBHOOK_URL="YOUR_DISCORD_WEBHOOK_URL"
RECORD="$RECORD_NAME"

cat <<EOF >change-batch.json
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$RECORD",
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

send_discord_notification() {
  MESSAGE=$1
  PAYLOAD=$(jq -n --arg content "$MESSAGE" '{content: $content}')
  curl -H "Content-Type: application/json" -X POST -d "$PAYLOAD" $DISCORD_WEBHOOK_URL
}

aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file://change-batch.json
send_discord_notification "$RECORD IP: $IP が起動しました"

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

monitor_ssh_connections() {
  initial_rx=$(get_rx_bytes)
  while true; do
    sleep $INTERVAL
    current_rx=$(get_rx_bytes)
    received=$((current_rx - initial_rx))
    if [[ $received -eq 0 ]]; then
      send_discord_notification "$RECORD IP: $IP をストップしました"
      aws autoscaling set-desired-capacity --auto-scaling-group-name $ASG_NAME --desired-capacity 0
    fi
    initial_rx=$current_rx
  done
}

set +xe
monitor_ssh_connections &
