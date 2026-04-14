#!/bin/bash

CONFIG_DIR="/root/config"
DNS_SCRIPT="/root/Auto_dns.sh"
DDNS_SCRIPT="/root/Auto_ddns.sh"

mkdir -p "$CONFIG_DIR"

# =========================
# GitHub 自动更新脚本
# =========================
REPO="https://raw.githubusercontent.com/Qing76667/kim_cool/refs/heads/main"

download_scripts() {
    echo "📦 同步脚本..."

    curl -s -o /root/Auto_dns.sh "$REPO/Auto_dns.sh"
    curl -s -o /root/Auto_ddns.sh "$REPO/Auto_ddns.sh"

    chmod +x /root/Auto_dns.sh /root/Auto_ddns.sh

    echo "✔ 脚本更新完成"
    echo ""
}

download_scripts

# =========================
# 全局配置（只初始化一次）
# =========================
GLOBAL_FILE="/root/config/.global.conf"

if [ ! -f "$GLOBAL_FILE" ]; then
    echo "🌐 初始化全局配置"
    echo ""

    read -p "国内域名(https://xxx.com): " CN_DOMAIN
    read -p "BOT_TOKEN: " BOT_TOKEN
    read -p "CHAT_ID: " CHAT_ID
    read -p "CF_ZONE_ID: " ZONE_ID
    read -p "CF_TOKEN: " TOKEN

    cat > "$GLOBAL_FILE" <<EOF
CN_DOMAIN="$CN_DOMAIN"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
ZONE_ID="$ZONE_ID"
TOKEN="$TOKEN"
EOF

    echo "✔ 全局配置已保存"
    echo ""
fi

source "$GLOBAL_FILE"

# =========================
# 节点列表
# =========================
get_nodes() {
    ls "$CONFIG_DIR" 2>/dev/null | sed 's/\.conf$//' | sort
}

view_nodes() {
    echo ""
    echo "📊 节点列表"
    echo "----------------"

    nodes=$(get_nodes)

    if [ -z "$nodes" ]; then
        echo "❌ 无节点"
        return
    fi

    for n in $nodes; do
        echo "✔ $n"
    done
}

# =========================
# cron（稳定去重）
# =========================
add_cron() {
    node="$1"

    dns_job="* * * * * /bin/bash $DNS_SCRIPT $node >> /var/log/dns_${node}.log 2>&1"
    ddns_job="*/2 * * * * /bin/bash $DDNS_SCRIPT $node >> /var/log/ddns_${node}.log 2>&1"

    tmp=$(mktemp)
    crontab -l 2>/dev/null > "$tmp"

    grep -F "$dns_job" "$tmp" >/dev/null || echo "$dns_job" >> "$tmp"
    grep -F "$ddns_job" "$tmp" >/dev/null || echo "$ddns_job" >> "$tmp"

    crontab "$tmp"
    rm -f "$tmp"
}

del_cron() {
    node="$1"

    tmp=$(mktemp)
    crontab -l 2>/dev/null > "$tmp"

    grep -v "$DNS_SCRIPT $node" "$tmp" | grep -v "$DDNS_SCRIPT $node" > "${tmp}.new"

    crontab "${tmp}.new"

    rm -f "$tmp" "${tmp}.new"
}

# =========================
# 新增节点
# =========================
add_node() {
    read -p "节点名称: " NODE

    FILE="$CONFIG_DIR/${NODE}.conf"

    if [ -f "$FILE" ]; then
        echo "⚠️ 节点已存在"
        return
    fi

    read -p "API_URL: " API_URL
    read -p "CHANGE_IP_URL: " CHANGE_IP_URL
    read -p "节点域名: " DOMAIN

    cat > "$FILE" <<EOF
NODE="$NODE"
API_URL="$API_URL"
CHANGE_IP_URL="$CHANGE_IP_URL"

CN_SET_IP="${CN_DOMAIN}/setip.php?node=${NODE}&ip="
CN_CHECK="${CN_DOMAIN}/ip_check.php?node=${NODE}"

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"

LOG="/var/log/dns_${NODE}.log"

ZONE_ID="$ZONE_ID"
TOKEN="$TOKEN"
DOMAIN="$DOMAIN"
EOF

    echo "✔ 节点创建完成: $NODE"

    add_cron "$NODE"

    echo "✔ cron 已写入"
}

# =========================
# 删除节点
# =========================
delete_node() {
    read -p "删除节点: " NODE

    rm -f "$CONFIG_DIR/${NODE}.conf"
    del_cron "$NODE"

    echo "✔ 已删除 $NODE"
    echo "✔ cron 已清理"
}

# =========================
# 菜单
# =========================
while true; do
    echo ""
    echo "========================"
    echo " 🚀 AutoDNS System"
    echo "========================"
    echo "1) 新增节点"
    echo "2) 删除节点"
    echo "3) 查看节点"
    echo "4) 退出"
    echo "========================"

    read -p "选择: " opt

    case $opt in
        1) add_node ;;
        2) delete_node ;;
        3) view_nodes ;;
        4) exit 0 ;;
        *) echo "❌ 无效选项" ;;
    esac
done