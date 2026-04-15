#!/bin/bash

BASE_DIR="/etc/XrayR"
CONF="$BASE_DIR/config.yml"
TMP_CONF="$BASE_DIR/config.yml.tmp"
DATA="$BASE_DIR/nodes.db"
BASE_CONF="$BASE_DIR/base.conf"
BACKUP_DIR="$BASE_DIR/backup"

mkdir -p "$BASE_DIR" "$BACKUP_DIR"
[ ! -f "$DATA" ] && touch "$DATA"

# =========================
# 颜色UI（兼容终端）
# =========================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
RESET="\033[0m"

ok() { echo -e "${GREEN}[成功] $1${RESET}"; }
err() { echo -e "${RED}[错误] $1${RESET}"; }
warn() { echo -e "${YELLOW}[警告] $1${RESET}"; }
info() { echo -e "${CYAN}[信息] $1${RESET}"; }

section() {
    echo -e "${BLUE}====================================${RESET}"
    echo -e "${BLUE}$1${RESET}"
    echo -e "${BLUE}====================================${RESET}"
}

# =========================
# API 配置
# =========================
read_base() {
    if [ ! -f "$BASE_CONF" ]; then
        echo "首次配置 API"
        read -p "请输入 ApiHost: " API_HOST
        read -p "请输入 ApiKey: " API_KEY
        save_base
    fi
    source "$BASE_CONF"
}

save_base() {
cat > "$BASE_CONF" <<EOF
API_HOST="$API_HOST"
API_KEY="$API_KEY"
EOF
}

reset_api() {
    echo ""
    section "重新设置 API"
    read -p "请输入 ApiHost: " API_HOST
    read -p "请输入 ApiKey: " API_KEY
    save_base
    ok "API 已更新"
}

# =========================
# 节点管理
# =========================
list_nodes() {
    echo ""
    section "节点列表"

    if [ ! -s "$DATA" ]; then
        warn "当前没有节点"
        return
    fi

    while IFS='|' read -r id type panel; do
        echo -e "${GREEN}NodeID:${RESET} $id"
        echo -e "${BLUE}节点类型:${RESET} $type"
        echo -e "${YELLOW}面板类型:${RESET} $panel"
        echo "------------------------------------"
    done < "$DATA"
}

add_node() {
    echo ""
    section "添加节点"

    read -p "请输入 NodeID: " NODE_ID

    if grep -q "^${NODE_ID}|" "$DATA"; then
        err "该 NodeID 已存在"
        return
    fi

    read -p "请输入节点类型 (默认 Vless): " NODE_TYPE
    NODE_TYPE=${NODE_TYPE:-Vless}

    read -p "请输入面板类型 (默认 NewV2board): " PANEL_TYPE
    PANEL_TYPE=${PANEL_TYPE:-NewV2board}

    echo "${NODE_ID}|${NODE_TYPE}|${PANEL_TYPE}" >> "$DATA"

    ok "节点添加成功"
}

del_node() {
    echo ""
    section "删除节点"

    list_nodes
    read -p "请输入要删除的 NodeID: " ID

    sed -i "/^${ID}|/d" "$DATA"

    ok "节点已删除"
}

# =========================
# 备份 / 回滚
# =========================
backup_config() {
    BACKUP_FILE="$BACKUP_DIR/config.yml.$(date +%F_%H-%M-%S)"
    cp "$CONF" "$BACKUP_FILE" 2>/dev/null
    echo "$BACKUP_FILE" > "$BACKUP_DIR/latest"
}

rollback_last() {
    if [ ! -f "$BACKUP_DIR/latest" ]; then
        err "没有可回滚的备份"
        return 1
    fi

    LAST=$(cat "$BACKUP_DIR/latest")

    if [ ! -f "$LAST" ]; then
        err "备份文件不存在"
        return 1
    fi

    cp "$LAST" "$CONF"
    warn "已回滚到上一个版本"

    systemctl restart XrayR
}

# =========================
# YAML 校验
# =========================
validate_yaml() {
    grep -q "^Nodes:" "$TMP_CONF"
}

# =========================
# 生成配置
# =========================
generate_config() {

    read_base

    info "开始生成配置..."

cat > "$TMP_CONF" <<EOF
Log:
  Level: warning
  AccessPath:
  ErrorPath:

DnsConfigPath:
RouteConfigPath: /etc/XrayR/route.json
InboundConfigPath:
OutboundConfigPath: /etc/XrayR/custom_outbound.json

ConnectionConfig:
  Handshake: 4
  ConnIdle: 30
  UplinkOnly: 2
  DownlinkOnly: 4
  BufferSize: 64

Nodes:
EOF

    while read -r line; do
        [ -z "$line" ] && continue

        IFS='|' read -r NODE_ID NODE_TYPE PANEL_TYPE <<< "$line"

cat >> "$TMP_CONF" <<EOF
  - PanelType: "$PANEL_TYPE"
    ApiConfig:
      ApiHost: "$API_HOST"
      ApiKey: "$API_KEY"
      NodeID: $NODE_ID
      NodeType: $NODE_TYPE
      Timeout: 30
      EnableVless: true
      VlessFlow: "xtls-rprx-vision"
      SpeedLimit: 0
      DeviceLimit: 0
      RuleListPath:
      DisableCustomConfig: false

    ControllerConfig:
      ListenIP: 0.0.0.0
      SendIP: 0.0.0.0
      UpdatePeriodic: 60

      EnableDNS: false
      DNSType: AsIs
      EnableProxyProtocol: false

      AutoSpeedLimitConfig:
        Limit: 0
        WarnTimes: 0
        LimitSpeed: 0
        LimitDuration: 0

      GlobalDeviceLimitConfig:
        Enable: false
        RedisNetwork: tcp
        RedisAddr: 127.0.0.1:6379
        RedisUsername:
        RedisPassword: YOUR PASSWORD
        RedisDB: 0
        Timeout: 5
        Expiry: 60

      EnableFallback: false
      FallBackConfigs:
        - SNI:
          Alpn:
          Path:
          Dest: 80
          ProxyProtocolVer: 0

      DisableLocalREALITYConfig: true
      EnableREALITY: false

      REALITYConfigs:
        Show: true
        Dest: www.amazon.com:443
        ProxyProtocolVer: 0
        ServerNames:
          - www.amazon.com
        PrivateKey: YOUR_PRIVATE_KEY
        MinClientVer:
        MaxClientVer:
        MaxTimeDiff: 0
        ShortIds:
          - ""
          - "0123456789abcdef"

      CertConfig:
        CertMode: dns
        CertDomain: "node1.test.com"
        CertFile: /etc/XrayR/cert/node1.test.com.cert
        KeyFile: /etc/XrayR/cert/node1.test.com.key
        Provider: alidns
        Email: test@me.com
        DNSEnv:
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb

EOF

        echo "" >> "$TMP_CONF"

    done < "$DATA"

    info "正在校验配置..."

    if ! validate_yaml; then
        err "配置校验失败，正在回滚"
        rm -f "$TMP_CONF"
        rollback_last
        return 1
    fi

    ok "配置校验通过"

    mv "$TMP_CONF" "$CONF"

    backup_config

    systemctl restart XrayR

    ok "配置已更新并重启 XrayR"
}

# =========================
# 菜单
# =========================
menu() {
while true; do
clear

section "XrayR 配置管理工具"

echo "节点管理"
echo "  1) 添加节点"
echo "  2) 删除节点"
echo "  3) 查看节点"

echo ""
echo "系统功能"
echo "  4) 生成配置"
echo "  5) 重置 Api"
echo "  0) 退出"

echo "===================================="
echo -e "${YELLOW}提示：添加/删除节点后都需要“生成配置”才会生效${RESET}"
echo -e "${YELLOW}提示：如需修改ApiHost和ApiKey，请选择 重置Api${RESET}"
echo "===================================="

read -p "请选择操作: " c

case $c in
    1) add_node ;;
    2) del_node ;;
    3) list_nodes ;;
    4) generate_config ;;
    5) reset_api ;;
    0) exit ;;
    *) err "无效选项" ;;
esac

echo ""
read -p "按回车返回菜单..."
done
}

menu
