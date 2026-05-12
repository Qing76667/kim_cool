#!/bin/bash

# =========================
# Kim SOCKS5 多用户管理脚本
# =========================

DANTE_CONF="/etc/danted.conf"
PASSWD_FILE="/etc/danted.passwd"
PORT_FILE="/etc/danted_port"
DEFAULT_PORT=985

# ===== 获取默认网卡 =====
IFACE=$(ip route | awk '/default/ {print $5; exit}')

# ===== 安装依赖 =====
install_dependencies() {
    apt update -y
    apt install -y dante-server curl
}

# ===== 生成/更新 Dante 配置 =====
generate_config() {
    local port=$1
    cat > "$DANTE_CONF" <<EOF
logoutput: syslog

internal: 0.0.0.0 port = $port
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

    systemctl restart danted
    systemctl enable danted
    echo "$port" > "$PORT_FILE"
}

# ===== 显示当前端口 =====
show_port() {
    if [[ -f "$PORT_FILE" ]]; then
        cat "$PORT_FILE"
    else
        echo "$DEFAULT_PORT"
    fi
}

# ===== 添加用户 =====
add_user() {
    read -p "用户名: " U
    read -p "密码: " P

    # 检查是否存在
    if grep -q "^$U:" "$PASSWD_FILE" 2>/dev/null; then
        echo "❌ 用户已存在！"
        return
    fi

    # 添加
    echo "$U:$P" >> "$PASSWD_FILE"
    generate_config $(show_port)
    echo "✅ 用户 $U 已添加"
}

# ===== 删除用户 =====
del_user() {
    read -p "用户名: " U

    if ! grep -q "^$U:" "$PASSWD_FILE" 2>/dev/null; then
        echo "❌ 用户不存在！"
        return
    fi

    sed -i "/^$U:/d" "$PASSWD_FILE"
    generate_config $(show_port)
    echo "✅ 用户 $U 已删除"
}

# ===== 列出用户 =====
list_users() {
    echo "========== SOCKS5 用户列表 =========="
    if [[ -f "$PASSWD_FILE" ]]; then
        awk -F: '{print $1}' "$PASSWD_FILE"
    else
        echo "❌ 暂无用户"
    fi
    echo "端口: $(show_port)"
    echo "IP: $(curl -s ifconfig.me)"
    echo "====================================="
}

# ===== 修改端口 =====
set_port() {
    read -p "输入端口 (当前: $(show_port)): " PORT
    PORT=${PORT:-$(show_port)}
    generate_config $PORT
    echo "✅ 端口已更新为 $PORT"
}

# ===== 主菜单 =====
while true; do
    echo
    echo "========== Kim SOCKS5 管理 =========="
    echo "1) 添加用户"
    echo "2) 删除用户"
    echo "3) 列出用户"
    echo "4) 设置端口"
    echo "5) 安装依赖并初始化"
    echo "6) 退出"
    echo "====================================="
    read -p "选择操作: " CHOICE
    case $CHOICE in
        1) add_user ;;
        2) del_user ;;
        3) list_users ;;
        4) set_port ;;
        5) install_dependencies
           generate_config $(show_port)
           echo "✅ 初始化完成"
           ;;
        6) exit ;;
        *) echo "❌ 无效选项" ;;
    esac
done
