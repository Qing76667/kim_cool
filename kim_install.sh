#!/bin/bash

REPO="https://raw.githubusercontent.com/Qing76667/kim_cool/main"

echo "=================================="
echo "   🚀 KIM AutoDNS Installer"
echo "=================================="
echo ""

echo "📦 下载系统组件..."

curl -s -o /root/node_manager.sh "$REPO/node_manager.sh"
curl -s -o /root/Auto_dns.sh "$REPO/Auto_dns.sh"
curl -s -o /root/Auto_ddns.sh "$REPO/Auto_ddns.sh"

chmod +x /root/node_manager.sh /root/Auto_dns.sh /root/Auto_ddns.sh

echo ""
echo "✔ 安装完成"
echo "🚀 正在启动管理器..."
echo ""

bash /root/node_manager.sh
