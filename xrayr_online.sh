#!/bin/bash
# 文件: /root/xrayr_online.sh
# 功能: 一条命令自动恢复 XrayR 并生成菜单

ZIP_URL="https://menghuan168.ru/XrayR_Kim2026.zip"
TMP_DIR="/tmp/XrayR_tmp"
XR_DIR="/usr/local/XrayR"
XR_ETC="/etc/XrayR"
SERVICE="XrayR.service"
MENU="/usr/bin/kimxr"

echo "🔹 开始 XrayR 在线恢复..."

# 1️⃣ 清理临时目录
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 2️⃣ 下载 zip
echo "⬇ 下载备份文件..."
if ! curl -fsSL "$ZIP_URL" -o "$TMP_DIR/XrayR.zip"; then
    echo "❌ 下载失败"
    exit 1
fi

# 3️⃣ 解压
echo "📦 解压文件..."
if ! unzip -q "$TMP_DIR/XrayR.zip" -d "$TMP_DIR"; then
    echo "❌ 解压失败"
    exit 1
fi

# 4️⃣ 拷贝文件
echo "📂 恢复文件..."
mkdir -p "$XR_DIR" "$XR_ETC"

# 程序文件
if [ -f "$TMP_DIR/XrayR_Kim2026/usr/local/XrayR/XrayR" ]; then
    cp -rf "$TMP_DIR/XrayR_Kim2026/usr/local/XrayR/"* "$XR_DIR/"
    chmod +x "$XR_DIR/XrayR"
else
    echo "❌ XrayR 可执行文件不存在"
    exit 1
fi

# 配置文件
if [ -d "$TMP_DIR/XrayR_Kim2026/etc/XrayR" ]; then
    cp -rf "$TMP_DIR/XrayR_Kim2026/etc/XrayR/"* "$XR_ETC/"
else
    echo "⚠ 没有找到 /etc/XrayR/ 配置文件"
fi

# 5️⃣ 创建已安装标记
touch "$XR_ETC/.installed"

# 6️⃣ systemd 服务
echo "⚙ 配置 systemd 服务..."
cat > /etc/systemd/system/$SERVICE <<EOF
[Unit]
Description=XrayR Service
After=network.target

[Service]
Type=simple
ExecStart=$XR_DIR/XrayR --config $XR_ETC/config.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE
systemctl restart $SERVICE

# 检查是否启动成功
if systemctl is-active --quiet $SERVICE; then
    echo "✅ XrayR 已启动"
else
    echo "❌ XrayR 启动失败"
fi

# 7️⃣ 菜单命令
echo "📖 创建菜单命令 $MENU ..."
cat > "$MENU" <<'EOF'
#!/bin/bash
XR="/usr/local/XrayR/XrayR"
CFG="/etc/XrayR/config.yml"
SVC="XrayR.service"

while true; do
clear
echo ""
echo "  XrayR 后端管理脚本"
echo "------------------------------------------"
echo "0) 修改配置 (vi $CFG)"
echo "1) 启动 XrayR"
echo "2) 停止 XrayR"
echo "3) 重启 XrayR"
echo "4) 查看状态"
echo "5) 查看日志"
echo "6) 设置开机自启"
echo "7) 取消开机自启"
echo "8) 卸载 XrayR"
echo "------------------------------------------"
read -p "选择 [0-8]: " c

case $c in
0) vi "$CFG" ;;
1) systemctl start "$SVC"; if systemctl is-active --quiet "$SVC"; then echo "✅ 启动成功"; else echo "❌ 启动失败"; fi; read ;;
2) systemctl stop "$SVC"; if systemctl is-active --quiet "$SVC"; then echo "❌ 停止失败"; else echo "✅ 停止完成"; fi; read ;;
3) systemctl restart "$SVC"; if systemctl is-active --quiet "$SVC"; then echo "✅ 重启成功"; else echo "❌ 重启失败"; fi; read ;;
4) systemctl status "$SVC" --no-pager; read ;;
5) journalctl -u "$SVC" -n 50 --no-pager; read ;;
6) systemctl enable "$SVC"; echo "✅ 设置开机自启"; read ;;
7) systemctl disable "$SVC"; echo "✅ 取消开机自启"; read ;;
8)
    read -p "⚠ 确认卸载 XrayR? [y/N]: " yn
    case "$yn" in
        y|Y)
            systemctl stop "$SVC"
            systemctl disable "$SVC"
            rm -rf /etc/XrayR /usr/local/XrayR /usr/bin/kimxr /etc/systemd/system/$SVC
            systemctl daemon-reload
            echo "✅ XrayR 已卸载"; read ;;
        *) echo "取消卸载"; read ;;
    esac
    ;;
*) echo "❌ 无效选择"; read ;;
esac
done
EOF

chmod +x "$MENU"

echo "🎉 恢复完成，菜单命令: kimxr"