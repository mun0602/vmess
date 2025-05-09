#!/bin/bash

# Cài đặt các gói cần thiết
apt update
apt install -y unzip curl uuid-runtime

# Biến
XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
INSTALL_DIR="/usr/local/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"

# Tải và cài đặt Xray
mkdir -p ${INSTALL_DIR}
curl -L ${XRAY_URL} -o xray.zip
unzip xray.zip -d ${INSTALL_DIR}
chmod +x ${INSTALL_DIR}/xray
rm xray.zip

# Sinh UUID và port
UUID=$(uuidgen)
PORT=10086

# Tạo file cấu hình Xray (VMess TCP đơn giản)
cat > ${CONFIG_FILE} <<EOF
{
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# Tạo systemd service
cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Xray VMess Simple Service
After=network.target nss-lookup.target

[Service]
ExecStart=${INSTALL_DIR}/xray run -config ${CONFIG_FILE}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# Lấy IP server
SERVER_IP=$(curl -s ifconfig.me)

# In thông tin cấu hình cho client
echo "==== VMess TCP Đơn giản ===="
echo "Address: $SERVER_IP"
echo "Port: $PORT"
echo "UUID: $UUID"
echo "AlterID: 0"
echo "Network: tcp"
echo "Security: none"
echo "============================"

# Tạo cấu hình VMess JSON cho client
VMESS_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "VMess-TCP-Test",
  "add": "${SERVER_IP}",
  "port": "${PORT}",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": ""
}
EOF
)

VMESS_URL="vmess://$(echo -n "$VMESS_JSON" | base64 | tr -d '\n')"
echo "VMess URL: $VMESS_URL"
