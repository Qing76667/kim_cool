#!/bin/bash

BASE_DIR="/etc"
DB_FILE="$BASE_DIR/kim_socks5.db"   # 存储端口|用户|密码
DEFAULT_PORT=985

# ===== 安装依赖 =====
install_dependencies() {
    apt update -y
    DEBIAN_FRONTEND=noninteractive apt install -y dante-server curl
}

# ===== 检测默认网卡 =====
get_iface() {
    ip route | awk '/default/ {print $5; exit}'
}

# ===== 检查端口是否可用 =====
check_port_free() {
    local PORT=$1
    ss -lnt | awk '{print $4}' | grep -q ":$PORT$"
    return $?
}

# ===== 生成 Dante 配置 =====
generate_config() {
    local PORT=$1
    local USER=$2
    local PASS=$3
    local IFACE=$(get_iface)
    local CONF_FILE="$BASE_DIR/danted_${PORT}.conf"

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

# 虚拟用户认证
username: $BASE_DIR/danted_${PORT}.passwd
EOF

    # 写入用户文件
    echo "$USER:$PASS" > "$BASE_DIR/danted_${PORT}.passwd"

    # 启动 Dante
    if systemctl list-units --all | grep -q danted; then
        pkill danted 2>/dev/null
        /usr/sbin/danted -f "$CONF_FILE" &
        echo "[INFO] Dante 端口 $PORT 已启动 (systemd 非严格管理)"
    else
        /usr/sbin/danted -f "$CONF_FILE" &
        echo "[INFO] Dante 端口 $PORT 已启动"
    fi
}

# ===== 初始化安装 =====
initialize() {
    echo "========== Kim SOCKS5 初始化 =========="
    install_dependencies

    read -p "端口 (默认 $DEFAULT_PORT): " PORT
    PORT=${PORT:-$DEFAULT_PORT}

    check_port_free $PORT && {
        echo "❌ 端口 $PORT 已被占用，请换一个端口"
        return
    }

    read -p "用户名 (默认 kim): " USER
    USER=${USER:-kim}

    read -p "密码 (默认 aa123456): " PASS
    PASS=${PASS:-aa123456}

    # 保存到数据库
    echo "$PORT|$USER|$PASS" >> "$DB_FILE"

    # 生成配置并启动
    generate_config $PORT $USER $PASS

    echo "✅ 初始化完成: 端口 $PORT 用户 $USER"
}

# ===== 添加用户 =====
add_user() {
    read -p "端口: " PORT
    PORT=${PORT:-$DEFAULT_PORT}

    check_port_free $PORT || {
        echo "❌ 端口 $PORT 已被占用，请换一个端口"
        return
    }

    read -p "用户名: " USER
    read -p "密码: " PASS

    # 保存数据库
    echo "$PORT|$USER|$PASS" >> "$DB_FILE"

    # 生成配置并启动
    generate_config $PORT $USER $PASS

    echo "✅ 用户 $USER 添加成功，端口 $PORT"
}

# ===== 删除用户 =====
del_user() {
    read -p "端口: " PORT
    [[ -f "$BASE_DIR/danted_${PORT}.conf" ]] || { echo "❌ 端口 $PORT 未初始化"; return; }

    # 删除数据库记录
    sed -i "/^$PORT|/d" "$DB_FILE"

    # 删除配置和用户文件
    rm -f "$BASE_DIR/danted_${PORT}.conf"
    rm -f "$BASE_DIR/danted_${PORT}.passwd"

    # 杀掉 Dante 进程
    pkill -f "danted.*danted_${PORT}.conf" 2>/dev/null

    echo "✅ 端口 $PORT 用户已删除"
}

# ===== 列出所有用户 =====
list_users() {
    echo "========== SOCKS5 用户列表 =========="
    [[ -f "$DB_FILE" ]] || { echo "❌ 没有用户"; return; }
    awk -F'|' '{printf "端口: %-6s 用户: %-10s 密码: %s\n",$1,$2,$3}' "$DB_FILE"
    echo "===================================="
}

# ===== 主菜单 =====
while true; do
    echo
    echo "========== Kim SOCKS5 管理 =========="
    echo "1) 初始化安装/初始化端口"
    echo "2) 添加用户（新端口+用户）"
    echo "3) 删除用户（按端口）"
    echo "4) 列出用户"
    echo "5) 退出"
    echo "====================================="
    read -p "选择操作: " CHOICE
    case $CHOICE in
        1) initialize ;;
        2) add_user ;;
        3) del_user ;;
        4) list_users ;;
        5) exit ;;
        *) echo "❌ 无效选项" ;;
    esac
done
