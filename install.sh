#!/bin/bash
set -e

# ========= root 检查 =========
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 运行"
  exit 1
fi

# ========= 端口设置（默认 443） =========
read -p "请输入 Xray Reality 端口（默认 443，不懂就回车）: " INPUT_PORT
if [ -z "$INPUT_PORT" ]; then
  XRAY_PORT=443
else
  XRAY_PORT=$INPUT_PORT
fi

# ========= Reality 域名设置（默认 www.icloud.com） =========
read -p "请输入 Reality 伪装域名（默认 www.icloud.com，不懂就回车）: " INPUT_DOMAIN
if [ -z "$INPUT_DOMAIN" ]; then
  DEST_DOMAIN="www.icloud.com"
  SERVER_NAME="www.icloud.com"
else
  DEST_DOMAIN="$INPUT_DOMAIN"
  SERVER_NAME="$INPUT_DOMAIN"
fi

# ========= 基础依赖 =========
apt update
apt install -y curl unzip openssl

# ========= 检查并启用 BBR + FQ =========
echo ">>> 检查 BBR + FQ 状态..."

CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
CURRENT_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "")

if [[ "$CURRENT_CC" == "bbr" && "$CURRENT_QDISC" == "fq" ]]; then
  echo "BBR + FQ 已启用，跳过设置"
else
  echo "未启用 BBR + FQ，正在设置..."

  modprobe tcp_bbr || true

  cat > /etc/sysctl.d/99-xray-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

  sysctl --system
fi

echo "当前拥塞控制算法: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "当前队列算法    : $(sysctl -n net.core.default_qdisc)"

# ========= 安装 Xray =========
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# ========= 生成 UUID =========
UUID=$(xray uuid)

# ========= 生成 Reality 密钥 =========
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep '^PrivateKey:' | cut -d':' -f2 | tr -d ' ')
PUBLIC_KEY=$(echo "$KEYS" | grep '^Password:' | cut -d':' -f2 | tr -d ' ')

# ========= shortIds（官方规范） =========
SHORT_ID=$(openssl rand -hex 4)
SHORT_IDS_JSON="[\"\", \"$SHORT_ID\"]"

# ========= 写入配置 =========
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
"dns": {
    "servers": [
     "8.8.8.8",
      "1.1.1.1"
    ]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
        {
      "type": "field",
      "domain": [
        "geosite:apple",
        "geosite:microsoft"
      ],
      "outboundTag": "direct"
    },
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "port": "443",
        "network": "udp",
        "outboundTag": "block"
      },
     {
      "type": "field",
     "outboundTag": "direct",
     "network": "udp,tcp"
     }
  ]
 },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$DEST_DOMAIN:443",
          "xver": 0,
          "serverNames": [
            "$SERVER_NAME"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": $SHORT_IDS_JSON
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
    "outbounds": [
    {
      "protocol": "blackhole",
      "tag": "block"
    },
     {
       "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
       },
        "tag": "direct"
     }
    ]
}
EOF

# ========= 启动服务 =========
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

sleep 1
systemctl is-active --quiet xray && echo "Xray 运行正常" || echo "❌ Xray 启动失败"

# ========= 获取服务器 IP =========
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ip.sb)

# ========= 生成 v2rayN 链接 =========
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${XRAY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Xray-Reality"

# ========= 输出 =========
echo "===================================="
echo " Xray Reality 已安装完成（BBR + FQ 已启用）"
echo "------------------------------------"
echo "服务器IP : $SERVER_IP"
echo "端口     : $XRAY_PORT"
echo "UUID     : $UUID"
echo "Reality 公钥 (pbk): $PUBLIC_KEY"
echo "shortId  : $SHORT_ID"
echo "SNI      : $SERVER_NAME"
echo "flow     : xtls-rprx-vision"
echo "------------------------------------"
echo "v2rayN 节点链接（可直接复制）："
echo ""
echo "$VLESS_LINK"
echo ""
echo "v2rayN → 从剪贴板导入即可使用"
echo "===================================="
