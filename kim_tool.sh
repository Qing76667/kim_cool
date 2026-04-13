#!/bin/bash

OUT=/etc/XrayR/custom_outbound.json
ROUTE=/etc/XrayR/route.json

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# =========================
# 初始化防崩
# =========================
init_guard() {
  if [ ! -s "$ROUTE" ] || ! jq empty "$ROUTE" 2>/dev/null; then
    echo "[系统] route损坏，自动修复"
    cat > "$ROUTE" <<EOF
{
  "domainStrategy": "IPOnDemand",
  "rules": []
}
EOF
  fi
}

# =========================
# 自动整理 route（含兜底）
# =========================
fix_route() {

  tmp=$(mktemp)

  jq '
    .rules |= (
      map(select(has("inboundTag")))
      | unique_by(.inboundTag)
      | (map(select(.outboundTag != "block"))) as $normal
      | (map(select(.outboundTag == "block"))) as $block
      | if ($block | length) == 0 then
          $normal + [{
            "type": "field",
            "network": "tcp,udp",
            "outboundTag": "block"
          }]
        else
          $normal + $block
        end
    )
  ' "$ROUTE" > "$tmp"

  if jq empty "$tmp" 2>/dev/null; then
    mv "$tmp" "$ROUTE"
    echo -e "${GREEN}[✔] route 已整理${RESET}"
  else
    rm -f "$tmp"
    echo -e "${RED}[✖] route 修复失败${RESET}"
  fi
}

# =========================
# 添加节点（插入到block前）
# =========================
add_node() {

  echo -e "${CYAN}===== 添加节点 =====${RESET}"

  read -p "NodeID(端口): " nodeid
  read -p "国家(UK/US/JP): " country
  read -p "落地IP: " ip
  read -p "端口: " port
  read -p "用户名: " user
  read -p "密码: " pass

  outbound_tag="${country}_${nodeid}"
  inbound_tag="Vless_0.0.0.0_${nodeid}"

  # ===== outbound =====
  jq --arg tag "$outbound_tag" \
     --arg ip "$ip" \
     --argjson port "$port" \
     --arg user "$user" \
     --arg pass "$pass" '
    . += [{
      "tag": $tag,
      "protocol": "socks",
      "settings": {
        "servers": [{
          "address": $ip,
          "port": $port,
          "users": [{
            "user": $user,
            "pass": $pass
          }]
        }]
      }
    }]
  ' "$OUT" > /tmp/o.tmp && mv /tmp/o.tmp "$OUT"

  # ===== route（插入到block前）=====
  jq --arg inbound "$inbound_tag" \
     --arg outbound "$outbound_tag" '
    .rules |= (
      (map(select(.outboundTag != "block")))
      + [{
          "type": "field",
          "inboundTag": [$inbound],
          "outboundTag": $outbound,
          "network": "tcp,udp"
        }]
      + (map(select(.outboundTag == "block")))
    )
  ' "$ROUTE" > /tmp/r.tmp && mv /tmp/r.tmp "$ROUTE"

  fix_route

  echo -e "${GREEN}添加成功：$outbound_tag${RESET}"
}

# =========================
# 删除节点
# =========================
delete_node() {

  echo -e "${CYAN}===== 删除节点 =====${RESET}"

  read -p "NodeID(端口): " nodeid
  read -p "国家(UK/US/JP): " country

  outbound_tag="${country}_${nodeid}"
  inbound_tag="Vless_0.0.0.0_${nodeid}"

  jq --arg tag "$outbound_tag" '
    map(select(.tag != $tag))
  ' "$OUT" > /tmp/o.tmp && mv /tmp/o.tmp "$OUT"

  jq --arg inbound "$inbound_tag" '
    .rules |= map(select(.inboundTag != [$inbound]))
  ' "$ROUTE" > /tmp/r.tmp && mv /tmp/r.tmp "$ROUTE"

  fix_route

  echo -e "${RED}删除成功：$outbound_tag${RESET}"
}

# =========================
# 查看（TCP测速）
# =========================
view() {

  init_guard

  clear

  echo -e "${CYAN}====================================${RESET}"
  echo -e "${CYAN}      Kim XrayR 运维面板${RESET}"
  echo -e "${CYAN}====================================${RESET}"
  echo ""

  echo -e "${CYAN}[系统] 正在TCP测速...${RESET}"
  echo ""

  nodes=$(mktemp)
  result_file=$(mktemp)

  jq -r '
    .[]
    | select(.protocol=="socks" and .tag!="socks5-warp")
    | "\(.tag)|\(.settings.servers[0].address)|\(.settings.servers[0].port)"
  ' "$OUT" > "$nodes"

  while IFS="|" read tag ip port; do

    start=$(date +%s%N)
    timeout 3 bash -c "</dev/tcp/$ip/$port" 2>/dev/null
    end=$(date +%s%N)

    if [ $? -eq 0 ]; then
      ms=$(( (end - start) / 1000000 ))
      echo "OK|$tag|$ip|$port|$ms" >> "$result_file"
    else
      echo "FAIL|$tag|$ip|$port|0" >> "$result_file"
    fi

  done < "$nodes"

  echo -e "${CYAN}========= 节点结果 =========${RESET}"
  echo ""

  while IFS="|" read -r status tag ip port ms; do
    if [ "$status" = "OK" ]; then
      printf "${GREEN}[✔] %-12s %-15s:%-5s %5sms${RESET}\n" "$tag" "$ip" "$port" "$ms"
    else
      printf "${RED}[✖] %-12s %-15s:%-5s TIMEOUT${RESET}\n" "$tag" "$ip" "$port"
    fi
  done < "$result_file"

  rm -f "$nodes" "$result_file"

  echo ""
  echo -e "${CYAN}====================================${RESET}"
}

# =========================
# 菜单（不改UI）
# =========================
while true; do

  echo ""
  echo -e "${YELLOW}==============================${RESET}"
  echo -e "${YELLOW}   Kim XrayR转发系统${RESET}"
  echo -e "${YELLOW}==============================${RESET}"
  echo -e "${YELLOW}1) 添加节点${RESET}"
  echo -e "${YELLOW}2) 删除节点${RESET}"
  echo -e "${YELLOW}3) 查看节点${RESET}"
  echo -e "${YELLOW}0) 退出${RESET}"
  echo -e "${YELLOW}==============================${RESET}"

  read -p "选择: " opt

  case $opt in
    1) add_node ;;
    2) delete_node ;;
    3) view ;;
    0) exit 0 ;;
    *) echo -e "${RED}无效选项${RESET}" ;;
  esac

done