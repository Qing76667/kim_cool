#!/bin/bash

REPO="https://raw.githubusercontent.com/YOURNAME/YOURREPO/main"

echo "📦 下载系统中..."

curl -s -o /root/node_manager.sh "$REPO/node_manager.sh"
curl -s -o /root/Auto_dns.sh "$REPO/Auto_dns.sh"
curl -s -o /root/Auto_ddns.sh "$REPO/Auto_ddns.sh"

chmod +x /root/node_manager.sh /root/Auto_dns.sh /root/Auto_ddns.sh

echo "✔ 安装完成"
echo ""
bash /root/node_manager.sh
