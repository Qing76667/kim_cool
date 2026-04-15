#!/bin/bash

echo "========== SOCKS5 通用稳定版 =========="

read -p "端口 (默认 985): " PORT
PORT=${PORT:-985}

read -p "用户名 (默认 kim): " USER
USER=${USER:-kim}

read -p "密码 (默认 aa123456): " PASS
PASS=${PASS:-aa123456}

echo "[INFO] 开始安装..."

apt update -y
apt install -y dante-server curl

# ===== 自动获取默认网卡（关键）=====
IFACE=$(ip route | awk '/default/ {print $5; exit}')

echo "[INFO] 检测网卡: $IFACE"

# ===== 用户 =====
id $USER >/dev/null 2>&1 || useradd -M -s /usr/sbin/nologin $USER
echo "$USER:$PASS" | chpasswd

# ===== 写配置（关键修复版）=====
cat > /etc/danted.conf <<EOF
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
EOF

systemctl restart danted
systemctl enable danted

echo "========== 状态 =========="
ss -lntp | grep $PORT || echo "❌ 未监听"

echo "IP: $(curl -s ifconfig.me)"
echo "PORT: $PORT"
echo "USER: $USER"
echo "PASS: $PASS"

echo "========== 完成 =========="
