#!/bin/bash
set -e

# ========= 固定参数 =========
XRAY_PORT=443
DEST_DOMAIN="www.icloud.com"
SERVER_NAME="www.icloud.com"

# ========= root 检查 =========
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 运行"
  exit 1
fi

# ========= 基础依赖 =========
apt update
apt install -y curl unzip openssl

# ========= 安装 Xray =========
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# ========= 生成 UUID（官方方式） =========
UUID=$(xray uuid)

# ========= 生成 Reality 密钥（完全对齐官方输出） =========
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep '^PrivateKey:' | cut -d':' -f2 | tr -d ' ')
PUBLIC_KEY=$(echo "$KEYS" | grep '^Password:'   | cut -d':' -f2 | tr -d ' ')

# ========= shortId =========
SHORT_ID=$(openssl rand -hex 8)

# ========= 写入配置 =========
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
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
          "shortIds": [
            "$SHORT_ID"
          ]
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
      "protocol": "freedom",
      "tag": "direct",
      "settings": {}
    }
  ]
}
EOF

# ========= 启动服务 =========
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# ========= 输出客户端信息 =========
echo "===================================="
echo "Xray Reality 已安装完成"
echo ""
echo "服务器IP : 你的服务器IP"
echo "端口     : $XRAY_PORT"
echo "UUID     : $UUID"
echo "Reality 公钥 : $PUBLIC_KEY"
echo "shortId  : $SHORT_ID"
echo "SNI      : $SERVER_NAME"
echo "flow     : xtls-rprx-vision"
echo "协议     : VLESS + TCP + Reality + vision"
echo "===================================="
