#!/bin/bash
set -e

# ========= 用户可选择端口 =========
read -p "请输入 Xray Reality 端口（默认 443）: " INPUT_PORT
if [ -z "$INPUT_PORT" ]; then
  XRAY_PORT=443
else
  XRAY_PORT=$INPUT_PORT
fi

# ========= 固定参数 =========
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

# ========= 生成 UUID =========
UUID=$(xray uuid)

# ========= 生成 Reality 密钥 =========
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep '^PrivateKey:' | cut -d':' -f2 | tr -d ' ')
PUBLIC_KEY=$(echo "$KEYS" | grep '^Password:'   | cut -d':' -f2 | tr -d ' ')

# ========= 生成 shortIds（官方规范：空字符串 + 随机 hex） =========
SHORT_ID=$(openssl rand -hex 4)  # 8 hex 字符
SHORT_IDS_JSON="[\"\", \"$SHORT_ID\"]"

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
echo "shortIds  : $SHORT_IDS_JSON"
echo "SNI      : $SERVER_NAME"
echo "flow     : xtls-rprx-vision"
echo "协议     : VLESS + TCP + Reality + vision"
echo "===================================="
