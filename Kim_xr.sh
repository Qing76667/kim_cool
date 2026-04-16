#!/bin/bash

CONFIG_FILE="/etc/XrayR/config.yml"
TMP_FILE="/tmp/xrayr_nodes.tmp"

[ ! -f "$TMP_FILE" ] && touch "$TMP_FILE"

# ===== 检测是否安装 =====
check_installed() {
    systemctl list-unit-files | grep -q "XrayR.service"
}

# ===== 安装 =====
install_xrayr() {
    echo "====== 安装 XrayR ======"

    if check_installed; then
        echo "⚠️  XrayR 已安装，自动跳过"
        return
    fi

    bash <(curl -Ls https://raw.githubusercontent.com/XrayR-project/XrayR-release/master/install.sh)
    echo "✅ 安装完成"
}

# ===== 卸载 =====
uninstall_xrayr() {
    echo "====== 卸载 XrayR ======"

    read -p "确认卸载? (y/n): " c
    [[ "$c" != "y" ]] && echo "已取消" && return

    systemctl stop XrayR 2>/dev/null
    systemctl disable XrayR 2>/dev/null

    rm -rf /etc/XrayR
    rm -f /usr/local/bin/XrayR
    rm -rf /usr/local/XrayR
    rm -f /etc/systemd/system/XrayR.service

    systemctl daemon-reload

    echo "✅ 已卸载完成"
}

# ===== 添加节点 =====
add_node() {
    echo "====== 添加节点 ======"

    read -p "面板类型 [默认NewV2board]: " PANEL
    PANEL=${PANEL:-NewV2board}

    read -p "面板地址: " API
    [ -z "$API" ] && echo "❌ 不能为空" && return

    read -p "ApiKey: " KEY
    [ -z "$KEY" ] && echo "❌ 不能为空" && return

    read -p "NodeID: " ID
    [[ ! "$ID" =~ ^[0-9]+$ ]] && echo "❌ 必须数字" && return

    read -p "节点类型 [默认Shadowsocks]: " TYPE
    TYPE=${TYPE:-Shadowsocks}

    echo "$PANEL|$API|$KEY|$ID|$TYPE" >> "$TMP_FILE"
    echo "✅ 添加成功"
}

# ===== 查看节点 =====
list_nodes() {
    echo "====== 当前节点 ======"

    if [ ! -s "$TMP_FILE" ]; then
        echo "暂无节点"
        return
    fi

    nl -w2 -s'. ' "$TMP_FILE" | while read line; do
        DATA=$(echo "$line" | cut -d' ' -f2-)
        IFS='|' read -r PANEL API KEY ID TYPE <<< "$DATA"
        INDEX=$(echo "$line" | cut -d'.' -f1)
        echo "[$INDEX] $PANEL | $API | NodeID:$ID | $TYPE"
    done
}

# ===== 删除节点 =====
del_node() {
    list_nodes
    echo ""
    read -p "输入编号: " n
    sed -i "${n}d" "$TMP_FILE" 2>/dev/null
    echo "✅ 已删除"
}

# ===== 生成配置 =====
generate_config() {

    if ! check_installed; then
        echo "❌ 未安装 XrayR，请先安装"
        return
    fi

    echo "====== 生成配置 ======"

    if [ ! -s "$TMP_FILE" ]; then
        echo "❌ 没有节点"
        return
    fi

    cat > "$CONFIG_FILE" <<EOF
Log:
  Level: warning

Nodes:
EOF

    while IFS='|' read -r PANEL API KEY ID TYPE; do
cat >> "$CONFIG_FILE" <<EOF
  - PanelType: "$PANEL"
    ApiConfig:
      ApiHost: "$API"
      ApiKey: "$KEY"
      NodeID: $ID
      NodeType: "$TYPE"
EOF
    done < "$TMP_FILE"

    echo "✅ 配置已生成"

    read -p "是否重启XrayR? (y/n)[y]: " r
    r=${r:-y}

    if [[ "$r" == "y" ]]; then
        systemctl restart XrayR && echo "✅ 已重启"
    fi
}

# ===== 主菜单 =====
while true; do
    echo ""
    echo "====== XrayR 管理 ======"
    echo "1. 安装 XrayR"
    echo "2. 卸载 XrayR"
    echo "3. 添加节点"
    echo "4. 删除节点"
    echo "5. 查看节点"
    echo "6. 生成配置"
    echo "0. 退出"
    echo "======================"

    read -p "选择: " c

    case $c in
        1) install_xrayr ;;
        2) uninstall_xrayr ;;
        3) add_node ;;
        4) del_node ;;
        5) list_nodes ;;
        6) generate_config ;;
        0) exit ;;
        *) echo "❌ 无效选项" ;;
    esac
done