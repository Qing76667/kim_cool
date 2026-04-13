#!/bin/bash

BASE="/etc/3proxy"
USER_DIR="$BASE/users"
CFG="$BASE/3proxy.cfg"
SERVICE="/etc/systemd/system/3proxy.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pause() {
    echo ""
    read -p "👉 回车返回..."
    clear
}

ok() {
    echo -e "${GREEN}[OK] $1${NC}"
    pause
}

err() {
    echo -e "${RED}[ERROR] $1${NC}"
    pause
}

# ================= 自愈 =================
self_heal() {

    mkdir -p "$USER_DIR"

    # 保底用户（纯数据层）
    if [ ! "$(ls -A $USER_DIR 2>/dev/null)" ]; then
        echo "admin:123456" > "$USER_DIR/1080.db"
    fi

    generate_cfg

    if [ ! -f "$SERVICE" ]; then
        cat > "$SERVICE" <<EOF
[Unit]
Description=3proxy SOCKS5
After=network.target

[Service]
Type=simple
ExecStart=/root/3proxy/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
    fi
}

# ================= 核心：生成 cfg（双层转换） =================
generate_cfg() {

    echo "maxconn 1000" > "$CFG"
    echo "nserver 8.8.8.8" >> "$CFG"
    echo "nserver 1.1.1.1" >> "$CFG"
    echo "" >> "$CFG"
    echo "auth strong" >> "$CFG"

    FOUND=0

    for f in "$USER_DIR"/*.db; do
        [ -f "$f" ] || continue

        PORT=$(basename "$f" | cut -d'.' -f1)

        while IFS=: read -r USER PASS; do

            # 防空行
            [ -z "$USER" ] && continue
            [ -z "$PASS" ] && continue

            # 转换为 3proxy格式（运行层）
            echo "users $USER:CL:$PASS" >> "$CFG"

        done < "$f"

        echo "allow *" >> "$CFG"
        echo "socks -p$PORT" >> "$CFG"

        FOUND=1
    done

    # 防止空崩
    if [ "$FOUND" -eq 0 ]; then
        echo "users admin:CL:123456" >> "$CFG"
        echo "allow *" >> "$CFG"
        echo "socks -p1080" >> "$CFG"
    fi
}

# ================= 安装 =================
install() {

    self_heal

    systemctl daemon-reload
    systemctl enable 3proxy
    systemctl restart 3proxy

    ok "安装完成（双层隔离已启用）"
}

# ================= 添加用户（纯数据层） =================
add_user() {

    self_heal

    read -p "端口: " PORT
    read -p "用户名: " U
    read -p "密码: " P

    # ❗ 纯数据写入（无3proxy语法）
    echo "$U:$P" > "$USER_DIR/$PORT.db"

    generate_cfg
    systemctl restart 3proxy

    ok "用户已添加"
}

# ================= 删除用户 =================
del_user() {

    self_heal

    read -p "端口: " PORT

    rm -f "$USER_DIR/$PORT.db"

    generate_cfg
    systemctl restart 3proxy

    ok "用户已删除"
}

# ================= 用户列表 =================
list_users() {

    self_heal

    echo ""
    echo "=============================="
    echo "     SOCKS5 用户列表"
    echo "=============================="

    IP=$(curl -s ifconfig.me)

    shopt -s nullglob
    files=("$USER_DIR"/*.db)

    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${YELLOW}暂无用户${NC}"
        pause
        return
    fi

    for f in "${files[@]}"; do

        PORT=$(basename "$f" | cut -d'.' -f1)

        while IFS=: read -r USER PASS; do

            echo ""
            echo -e "${BLUE}端口: $PORT${NC}"
            echo -e "${GREEN}用户名: $USER${NC}"
            echo -e "${GREEN}密码: $PASS${NC}"
            echo -e "${YELLOW}socks5://$USER:$PASS@$IP:$PORT${NC}"
            echo "----------------------"

        done < "$f"

    done

    pause
}

# ================= 状态 =================
status() {

    self_heal

    if systemctl is-active --quiet 3proxy; then
        echo -e "${GREEN}[状态] 运行中${NC}"
    else
        echo -e "${YELLOW}[状态] 未运行，重启中...${NC}"
        systemctl restart 3proxy
    fi

    echo "IP: $(curl -s ifconfig.me)"
    pause
}

# ================= 重启 =================
restart() {

    self_heal
    generate_cfg

    systemctl reset-failed 3proxy
    systemctl restart 3proxy

    systemctl status 3proxy -l
}

# ================= 卸载 =================
uninstall() {

    systemctl stop 3proxy
    systemctl disable 3proxy

    rm -rf "$BASE"
    rm -f "$SERVICE"

    systemctl daemon-reload

    ok "已卸载"
}

# ================= 菜单 =================
menu() {

    while true; do

        echo ""
        echo "=============================="
        echo -e "${YELLOW} SOCKS5 双层隔离标准版${NC}"
        echo "=============================="
        echo "1) 安装"
        echo "2) 状态"
        echo "3) 添加用户"
        echo "4) 删除用户"
        echo "5) 用户列表"
        echo "6) 重启"
        echo "7) 卸载"
        echo "0) 退出"
        echo "=============================="

        read -p "选择: " opt

        case $opt in
            1) install ;;
            2) status ;;
            3) add_user ;;
            4) del_user ;;
            5) list_users ;;
            6) restart ;;
            7) uninstall ;;
            0) exit 0 ;;
            *) err "无效选项" ;;
        esac
    done
}

menu