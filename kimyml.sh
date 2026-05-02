#!/bin/bash

BASE_DIR="/etc/XrayR"
CONF="$BASE_DIR/config.yml"
TMP_CONF="$BASE_DIR/config.yml.tmp"
DATA="$BASE_DIR/nodes.db"
PANEL_DB="$BASE_DIR/panels.db"
BACKUP_DIR="$BASE_DIR/backup"

mkdir -p "$BASE_DIR" "$BACKUP_DIR"
[ ! -f "$DATA" ] && touch "$DATA"
[ ! -f "$PANEL_DB" ] && touch "$PANEL_DB"

# =========================
# UI
# =========================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

ok(){ echo -e "${GREEN}[成功] $1${RESET}"; }
err(){ echo -e "${RED}[错误] $1${RESET}"; }
warn(){ echo -e "${YELLOW}[提示] $1${RESET}"; }
info(){ echo -e "${BLUE}[信息] $1${RESET}"; }

section(){
    echo -e "${BLUE}====================================${RESET}"
    echo -e "${BLUE}$1${RESET}"
    echo -e "${BLUE}====================================${RESET}"
}

# =========================
# 基础函数
# =========================
backup_config(){
    BACKUP_FILE="$BACKUP_DIR/config.yml.$(date +%F_%H-%M-%S)"
    cp "$CONF" "$BACKUP_FILE" 2>/dev/null
    echo "$BACKUP_FILE" > "$BACKUP_DIR/latest"
}

rollback_last(){
    [ ! -f "$BACKUP_DIR/latest" ] && err "无备份" && return
    cp "$(cat "$BACKUP_DIR/latest")" "$CONF"
    systemctl restart XrayR
    warn "已回滚"
}

get_panel_name(){
    awk -F'|' -v name="$1" '$2==name {print $2}' "$PANEL_DB"
}

get_panel_info(){
    awk -F'|' -v name="$1" '$2==name {print $0}' "$PANEL_DB"
}

append_node(){
    local line="$1"

    grep -Fxq "$line" "$DATA" && return
    echo "$line" >> "$DATA"
}

get_panel_id_by_name(){
    awk -F'|' -v name="$1" '$2==name {print $1; exit}' "$PANEL_DB"
}

# =========================
# API（自动识别核心）
# =========================
fetch_node_api(){
    local HOST="$1"
    local KEY="$2"
    local NODEID="$3"

    curl -s -H "X-API-Key: $KEY" "$HOST/api/node/$NODEID" 2>/dev/null
}

# =========================
# 面板管理
# =========================
add_panel(){
    section "添加面板"

    # =========================
    # 名称
    # =========================
    while true; do
        read -p "名称: " NAME
        NAME=$(echo "$NAME" | xargs)

        [ -z "$NAME" ] && err "名称不能为空" && continue
        break
    done

    # =========================
    # ApiHost
    # =========================
    while true; do
        read -p "ApiHost: " HOST
        HOST=$(echo "$HOST" | xargs)

        [ -z "$HOST" ] && err "ApiHost不能为空" && continue
        break
    done

    # =========================
    # ApiKey
    # =========================
    while true; do
        read -p "ApiKey: " KEY
        KEY=$(echo "$KEY" | xargs)

        [ -z "$KEY" ] && err "ApiKey不能为空" && continue
        break
    done

    # =========================
    # PID生成
    # =========================
    PID=$(awk -F'|' '{print $1}' "$PANEL_DB" | sort -n | tail -1)
    PID=$((PID+1))

    echo "${PID}|${NAME}|${HOST}|${KEY}" >> "$PANEL_DB"
    ok "已添加"
}

list_panels(){
    section "面板列表"

    i=1
    while IFS='|' read -r id name host key; do
        echo "$i) $name | $host | $key"
        ((i++))
    done < "$PANEL_DB"
}

edit_panel(){
    section "编辑面板"

    i=1
    MAP=()

    while IFS='|' read -r id name host key; do
        echo "$i) $name"
        MAP[$i]="$id"
        ((i++))
    done < "$PANEL_DB"

    read -p "选择面板: " sel
    PID="${MAP[$sel]}"
    [ -z "$PID" ] && err "取消" && return

    panel=$(grep "^$PID|" "$PANEL_DB")
    IFS='|' read -r id name host key <<< "$panel"

    read -p "ApiHost(回车不改): " new_host
    read -p "ApiKey(回车不改): " new_key

    [ -z "$new_host" ] && new_host="$host"
    [ -z "$new_key" ] && new_key="$key"

    sed -i "/^$PID|/d" "$PANEL_DB"
    echo "${PID}|${name}|${new_host}|${new_key}" >> "$PANEL_DB"

    ok "更新成功"
}

# =========================
# 节点管理
# =========================
add_node(){
    section "添加节点"

    read -p "NodeID: " NODE_ID
    read -p "类型(Vless): " NODE_TYPE
    NODE_TYPE=${NODE_TYPE:-Vless}

    i=1
    MAP=()

    while IFS='|' read -r id name host key; do
        echo "$i) $name"
        MAP[$i]="$id"
        ((i++))
    done < "$PANEL_DB"

    read -p "选择面板: " sel
    PANEL_ID="${MAP[$sel]}"

    [ -z "$PANEL_ID" ] && err "取消" && return

    # echo "${NODE_ID}|${NODE_TYPE}|${PANEL_ID}" >> "$DATA" 原写法
    append_node "${NODE_ID}|${NODE_TYPE}|${PANEL_ID}"
    ok "添加成功"
}

list_nodes(){

    section "节点列表"

    i=1

    while IFS='|' read -r id type panel; do

        # pname=$(get_panel_name "$panel")
        pname="$panel"
        echo "编号:$i | NodeID:$id | 类型:$type | 面板:${pname:-未知}"

        ((i++))

    done < "$DATA"
}

edit_node_panel(){

    section "修改节点面板"

count=0
MAP=()

while IFS='|' read -r id type panel; do

    ((count++))

    echo "$count) NodeID:$id | 类型:$type | 面板:$panel"
    MAP[$count]="$id|$type|$panel"

done < "$DATA"

    echo "------------------------"
    read -p "输入节点编号(1-${i-1}): " sel

    node="${MAP[$sel]}"
    [ -z "$node" ] && err "无效选择" && return

    IFS='|' read -r id type old_panel <<< "$node"

    echo ""
    echo "当前面板: $old_panel"
    echo ""

    j=1
    PMAP=()

    while IFS='|' read -r pid name host key; do
        echo "$j) $name"
        PMAP[$j]="$pid"
        ((j++))
    done < "$PANEL_DB"

    read -p "选择新面板(回车取消): " psel
    new_panel="${PMAP[$psel]}"

    [ -z "$new_panel" ] && warn "未修改" && return

    # =========================
    # 更新 nodes.db（只改面板字段）
    # =========================
    tmp="$DATA.tmp"
    > "$tmp"

    while IFS='|' read -r nid ntype npanel; do

        if [ "$nid" = "$id" ]; then
            echo "$nid|$ntype|$new_panel" >> "$tmp"
        else
            echo "$nid|$ntype|$npanel" >> "$tmp"
        fi

    done < "$DATA"

    mv "$tmp" "$DATA"

    ok "节点面板已更新"
}

del_node(){
    list_nodes
    read -p "要删除的节点编号: " num

    tmp="$DATA.tmp"
    > "$tmp"

    i=0
    while IFS='|' read -r id type panel; do
        # ✅ 就加在这里（关键）
        [ -z "$id" ] && continue
        
        ((i++))
        [ "$i" = "$num" ] && continue
        echo "$id|$type|$panel" >> "$tmp"
    done < "$DATA"

    mv "$tmp" "$DATA"
    ok "删除成功"
}

# =========================
# ⭐ 智能同步（API识别版）
# =========================
sync_nodes(){

    section "同步节点（最终稳定快照版）"

    TMP="$DATA.tmp"
    > "$TMP"

    # =========================
    # 面板映射：ApiHost -> PanelName
    # =========================
    declare -A PANEL_MAP

    while IFS='|' read -r id name host key; do
        host=$(echo "$host" | tr -d '"' | tr -d '\r' | xargs)
        PANEL_MAP["$host"]="$name"
    done < "$PANEL_DB"

    # =========================
    # 解析 XrayR config
    # =========================
    NODE_ID=""
    API_HOST=""

    while IFS= read -r line; do

        # NodeID
        if echo "$line" | grep -q "NodeID"; then
            NODE_ID=$(echo "$line" | grep -oE "[0-9]+")
        fi

        # ApiHost（关键修复）
        if echo "$line" | grep -q "ApiHost"; then
            API_HOST=$(echo "$line" \
                | sed 's/.*ApiHost:[ ]*//' \
                | tr -d '"' \
                | tr -d '\r' \
                | xargs)
        fi

        # =========================
        # 写入临时快照
        # =========================
        if [ -n "$NODE_ID" ] && [ -n "$API_HOST" ]; then

            PANEL_NAME="${PANEL_MAP[$API_HOST]}"

            if [ -z "$PANEL_NAME" ]; then
                PANEL_NAME="unknown"
            fi

            # echo "$NODE_ID|Vless|$PANEL_NAME" >> "$TMP"  原写法
            grep -Fxq "$NODE_ID|Vless|$PANEL_NAME" "$TMP" && continue
            echo "$NODE_ID|Vless|$PANEL_NAME" >> "$TMP"

            warn "NodeID:$NODE_ID -> $PANEL_NAME"

            NODE_ID=""
            API_HOST=""
        fi

    done < "$CONF"

    # =========================
    # ⭐ 核心修复：完全快照覆盖（禁止追加）
    # =========================
    sort -u "$TMP" > "$DATA"

    ok "同步完成（快照模式，已消除历史污染）"
}
# =========================
# 生成配置（稳定版）
# =========================
generate_config(){

    section "生成配置"

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

while IFS='|' read -r NODE_ID NODE_TYPE PANEL_NAME; do

    PANEL_ID=$(get_panel_id_by_name "$PANEL_NAME")

    [ -z "$PANEL_ID" ] && continue

    panel=$(grep "^$PANEL_ID|" "$PANEL_DB")
    IFS='|' read -r pid name API_HOST API_KEY <<< "$panel"

        [ -z "$API_HOST" ] && continue
        [ -z "$API_KEY" ] && continue

cat >> "$TMP_CONF" <<EOF
  - PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "$API_HOST"
      ApiKey: "$API_KEY"
      NodeID: $NODE_ID
      NodeType: $NODE_TYPE
      Timeout: 30
      EnableVless: false
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

    done < "$DATA"

    echo "预览:"
    head -n 20 "$TMP_CONF"

    read -p "确认生成? (y/n): " c
    [ "$c" != "y" ] && return

    backup_config
    mv "$TMP_CONF" "$CONF"
    systemctl restart XrayR

    ok "完成"
}

# =========================
# 主菜单（恢复完整）
# =========================
menu(){
while true; do
clear

section "XrayR 管理系统"

echo "================ 面板 ================="
echo "1) 添加面板"
echo "2) 查看面板"
echo "3) 编辑面板"

echo ""
echo "================ 节点 ================="
echo "4) 添加节点"
echo "5) 删除节点"
echo "6) 查看节点"
echo "7) 修改节点面板"

echo ""
echo "================ 系统 ================="
echo "8) 智能同步节点（API识别）"
echo "9) 生成配置"
echo "0) 退出"

echo "======================================="

read -p "选择: " c

case $c in
1) add_panel ;;
2) list_panels ;;
3) edit_panel ;;
4) add_node ;;
5) del_node ;;
6) list_nodes ;;
7) edit_node_panel ;;
8) sync_nodes ;;
9) generate_config ;;
0) exit ;;
esac

read -p "回车继续..."
done
}

menu
