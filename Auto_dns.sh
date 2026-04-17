#!/bin/bash

NODE="$1"
CONF="/root/config/${NODE}.conf"

[ ! -f "$CONF" ] && echo "Config not found: $NODE" && exit 1
source "$CONF"

# ===== 节点名称映射 =====
get_name() {
    echo "$NODE" | sed 's/node/接口/'
}

STATE_FILE="/tmp/${NODE}_state"
IP_FILE="/tmp/${NODE}_ip"
FAIL_FILE="/tmp/${NODE}_fail"
COOLDOWN_FILE="/tmp/${NODE}_cool"

# ================= TG =================
send_tg() {
    local MESSAGE="$1"
    local NAME=$(get_name)

    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="[$NAME] $MESSAGE" >/dev/null 2>&1
}

# ================= 日志 =================
log() {
    echo "$(date '+%F %T') $1" | tee -a "$LOG"
}

# ================= 获取IP =================
get_ip() {
    curl -s --max-time 10 "$API_URL" | sed -n 's/.*"ip":"\([^"]*\)".*/\1/p'
}

# ================= 国内检测 =================
check_cn() {
    HTTP=$(curl -s -o /tmp/${NODE}_cn.txt -w "%{http_code}" --max-time 10 "$CN_CHECK")
    RESULT=$(cat /tmp/${NODE}_cn.txt 2>/dev/null)

    if [ "$HTTP" = "000" ] || [ -z "$RESULT" ]; then
        echo "NET_ERR"; return
    fi

    [ "$RESULT" = "ok" ] && echo "OK" && return
    [ "$RESULT" = "fail" ] && echo "BLOCKED" && return

    echo "NET_ERR"
}

# ================= 获取当前IP =================
IP=$(get_ip)
[ -z "$IP" ] && log "获取IP失败" && exit 1

log "当前IP: $IP"

# ================= IP变化 =================
LAST_IP=$(cat "$IP_FILE" 2>/dev/null)

if [ -z "$LAST_IP" ]; then
    echo "$IP" > "$IP_FILE"
    send_tg "🆕 初始IP记录 | IP: $IP"
else
    if [ "$IP" != "$LAST_IP" ]; then
        send_tg "🔁 IP变化 | $LAST_IP -> $IP"
        echo "$IP" > "$IP_FILE"
    fi
fi

# ================= 同步国内 =================
curl -s "${CN_SET_IP}${IP}" >/dev/null

STATUS=$(check_cn)
LAST_STATE=$(cat "$STATE_FILE" 2>/dev/null)

# ================= 正常 =================
if [ "$STATUS" = "OK" ]; then
    # 只在初始化或从 BLOCKED 恢复时通知
    if [ -z "$LAST_STATE" ]; then
        send_tg "✔️ Autodns 正常 | IP: $IP"
    elif [ "$LAST_STATE" = "BLOCKED" ]; then
        send_tg "✅ 已恢复正常 | IP: $IP"
    fi

    echo "OK" > "$STATE_FILE"
    rm -f "$FAIL_FILE"
    exit 0
fi

# ================= 网络异常（不通知） =================
if [ "$STATUS" = "NET_ERR" ]; then
    echo "NET_ERR" > "$STATE_FILE"
    exit 0
fi

# ================= 国内不可达 =================
if [ "$STATUS" = "BLOCKED" ]; then
    COUNT=$(cat "$FAIL_FILE" 2>/dev/null)
    COUNT=$((COUNT+1))
    echo "$COUNT" > "$FAIL_FILE"

    # 连续3次才报警
    if [ "$COUNT" -eq 3 ]; then
        send_tg "⚠️ 国内不可达（已确认）| IP: $IP"
    fi

    # 未达到换IP阈值
    [ "$COUNT" -lt 3 ] && exit 0

    # 防重复触发
    [ -f "$COOLDOWN_FILE" ] && exit 0
    touch "$COOLDOWN_FILE"

    log "触发换IP"
    send_tg "🔁 触发更换IP | 当前IP: $IP"

    curl -s "$CHANGE_IP_URL" >/dev/null

    sleep 10

    NEW_IP=$(get_ip)

    if [ -n "$NEW_IP" ] && [ "$NEW_IP" != "$IP" ]; then
        send_tg "✅ IP更换成功 | 新IP: $NEW_IP"
        echo "$NEW_IP" > "$IP_FILE"
        echo "OK" > "$STATE_FILE"
    else
        send_tg "❌ IP更换失败"
    fi

    rm -f "$FAIL_FILE"
    sleep 60
    rm -f "$COOLDOWN_FILE"
fi
