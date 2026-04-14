#!/bin/bash

NODE="$1"
CONF="/root/config/${NODE}.conf"

[ ! -f "$CONF" ] && echo "Config not found: $NODE" && exit 1
source "$CONF"

# ===== 节点名转换 =====
get_name() {
    echo "$NODE" | sed 's/node/接口/'
}

LOG="/var/log/ddns_${NODE}.log"

RETRY=3
SLEEP=2

send_telegram() {
    local MESSAGE="$1"
    local NAME=$(get_name)

    curl -s --max-time 10 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="[$NAME] $MESSAGE" >/dev/null
}

log() {
    echo "$(date '+%F %T') $1" >> "$LOG"
    echo "$1" >&2
}

get_ip() {
    local i=0
    local ip=""
    local status=""

    while [ $i -lt $RETRY ]; do
        RESP=$(curl -s --fail --max-time 10 "$API_URL")

        status=$(echo "$RESP" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
        ip=$(echo "$RESP" | sed -n 's/.*"ip":"\([^"]*\)".*/\1/p')

        if [ "$status" = "success" ] && [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi

        echo "Attempt $((i+1)): API Response: $RESP" >&2
        i=$((i+1))
        sleep $SLEEP
    done

    return 1
}

IP=$(get_ip)

if [ -z "$IP" ]; then
    send_telegram "❌ 获取IP失败"
    exit 1
fi

if ! [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    send_telegram "❌ 非法IP: $IP"
    exit 1
fi

RECORD=$(curl -s --max-time 10 \
"https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DOMAIN" \
-H "Authorization: Bearer $TOKEN" \
-H "Content-Type: application/json")

RECORD_ID=$(echo "$RECORD" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
OLD_IP=$(echo "$RECORD" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | head -1)

if [ -z "$RECORD_ID" ]; then
    send_telegram "❌ DNS记录不存在"
    exit 1
fi

if [ "$IP" = "$OLD_IP" ]; then
    exit 0
fi

log "IP变化: $OLD_IP -> $IP"
send_telegram "⚠️ IP变化 | $OLD_IP -> $IP"

RESULT=$(curl -s --max-time 15 -X PUT \
"https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
-H "Authorization: Bearer $TOKEN" \
-H "Content-Type: application/json" \
--data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$IP\",\"ttl\":1,\"proxied\":false}")

echo "DNS update result: $RESULT" >&2

if echo "$RESULT" | grep -q '"success":true'; then
    log "DNS更新成功 -> $IP"
    send_telegram "✅ DNS更新成功 | $DOMAIN -> $IP"
else
    send_telegram "❌ DNS更新失败"
    exit 1
fi