#!/bin/bash

# =========================
# Kim SOCKS5 多用户管理脚本（按端口）
# =========================

BASE_DIR="/etc"
DEFAULT_PORT=985

# ===== 安装依赖 =====
install_dependencies() {
    apt update -y
    apt install -y dante-server curl
}

# ===== 检测默认网卡 =====
get_iface() {
    ip route | awk '/default/ {print $5; exit}'
}

# ===== 生成配置 =====
generate_config() {
    local PORT=$1
    local IFACE=$2
    local CONF_FILE="$BASE_DIR/danted_${PORT}.conf"
    local PASSWD_FILE="$BASE_DIR/danted_${PORT}.passwd"

    cat > "$CONF_FILE" <<EOF
logoutput: syslog

internal: 0.0.0.0 port = $PORT
external: $IFACE

socksmethod: username
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
}

# 虚拟用户认证文件
username: $PASSWD_FILE
EOF

    # 启动 Dante
    if systemctl list-units --all | grep -q danted; then
        systemctl restart danted
        systemctl enable danted
        echo "[INFO] Dante 服务已启动 (systemd)"
    else
        echo "[INFO] systemd 未找到，直接启动 Dante 进程"
        pkill danted 2>/dev/null
        /usr/sbin/danted -f "$CONF_FILE" &
    fi
}

# ===== 初始化端口 =====
initialize() {
    echo "========== 初始化 Kim SOCKS5 =========="
    read -p "端口 (默认 $DEFAULT_PORT): " PORT
    PORT=${PORT:-$DEFAULT_PORT}

    read -p "初始用户名 (默认 kim): " USER
    USER=${USER:-kim}

    read -p "初始密码 (默认 aa123456): " PASS
    PASS=${PASS:-aa123456}

    install_dependencies
    IFACE=$(get_iface)

    # 创建用户文件
    PASSWD_FILE="$BASE_DIR/danted_${PORT}.passwd"
    echo "$USER:$PASS" > "$PASSWD_FILE"

    generate_config $PORT $IFACE

    echo "========== 初始化完成 =========="
    echo "IP: $(curl -s ifconfig.me)"
    echo "PORT: $PORT"
    echo "USER: $USER"
    echo "PASS: $PASS"
}

# ===== 添加用户 =====
add_user() {
    read -p "端口: " PORT
    PORT=${PORT:-$DEFAULT_PORT}
    PASSWD_FILE="$BASE_DIR/danted_${PORT}.passwd"
    IFACE=$(get_iface)

    if [[ ! -f "$PASSWD_FILE" ]]; then
        echo "❌ 端口 $PORT 未初始化，请先初始化"
        return
    fi

    read -p "用户名: " U
    read -p "密码: " P

    if grep -q "^$U:" "$PASSWD_FILE" 2>/dev/null; then
        echo "❌ 用户已存在"
        return
    fi

    echo "$U:$P" >> "$PASSWD_FILE"
    generate_config $PORT $IFACE
    echo "✅ 用户 $U 已添加到端口 $PORT"
}

# ===== 删除用户 =====
del_user() {
    read -p "端口: " PORT
    PORT=${PORT:-$DEFAULT_PORT}
    PASSWD_FILE="$BASE_DIR/danted_${PORT}.passwd"
    IFACE=$(get_iface)

    if [[ ! -f "$PASSWD_FILE" ]]; then
        echo "❌ 端口 $PORT 未初始化"
        return
    fi

    read -p "用户名: " U

    if ! grep -q "^$U:" "$PASSWD_FILE" 2>/dev/null; then
        echo "❌ 用户不存在"
        return
    fi

    sed -i "/^$U:/d" "$PASSWD_FILE"
    generate_config $PORT $IFACE
    echo "✅ 用户 $U 已从端口 $PORT 删除"
}

# ===== 列出用户 =====
list_users() {
    read -p "端口: " PORT
    PORT=${PORT:-$DEFAULT_PORT}
    PASSWD_FILE="$BASE_DIR/danted_${PORT}.passwd"

    echo "========== 用户列表 (端口 $PORT) =========="
    if [[ -f "$PASSWD_FILE" ]]; then
        awk -F: '{print $1}' "$PASSWD_FILE"
    else
        echo "❌ 无用户或端口未初始化"
    fi
    echo "========================================="
}

# ===== 修改端口 =====
set_port() {
    read -p "当前端口: " OLD_PORT
    OLD_PORT=${OLD_PORT:-$DEFAULT_PORT}
    OLD_PASSWD="$BASE_DIR/danted_${OLD_PORT}.passwd"
    OLD_CONF="$BASE_DIR/danted_${OLD_PORT}.conf"
    IFACE=$(get_iface)

    if [[ ! -f "$OLD_PASSWD" ]]; then
        echo "❌ 端口 $OLD_PORT 未初始化"
        return
    fi

    read -p "新端口: " NEW_PORT
    NEW_PORT=${NEW_PORT:-$OLD_PORT}

    # 拷贝用户文件到新端口
    cp "$OLD_PASSWD" "$BASE_DIR/danted_${NEW_PORT}.passwd"
    generate_config $NEW_PORT $IFACE

    echo "✅ 已为新端口 $NEW_PORT 生成配置，用户与旧端口相同"
}

# ===== 主菜单 =====
while true; do
    echo
    echo "========== Kim SOCKS5 管理 =========="
    echo "1) 初始化安装/初始化端口"
    echo "2) 添加用户"
    echo "3) 删除用户"
    echo "4) 列出用户"
    echo "5) 设置/迁移端口"
    echo "6) 退出"
    echo "====================================="
    read -p "选择操作: " CHOICE
    case $CHOICE in
        1) initialize ;;
        2) add_user ;;
        3) del_user ;;
        4) list_users ;;
        5) set_port ;;
        6) exit ;;
        *) echo "❌ 无效选项" ;;
    esac
done
