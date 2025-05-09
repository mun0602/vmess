#!/bin/bash

# Colors for better readability
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# Current date for documentation
CURRENT_DATE="2025-05-09"
CURRENT_USER="mun0602"

# Cập nhật danh sách gói phần mềm (KHÔNG upgrade)
apt update

# Định nghĩa biến
XRAY_URL="https://dtdp.bio/wp-content/apk/Xray-linux-64.zip"
INSTALL_DIR="/usr/local/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"
CERT_DIR="/usr/local/xray/cert"
CAMOUFLAGE_DOMAIN="www.microsoft.com"  # Sử dụng domain uy tín là microsoft.com

# Cài đặt các gói cần thiết
apt install -y unzip curl jq qrencode uuid-runtime imagemagick openssl

# Kiểm tra xem Xray đã được cài đặt chưa
if [[ -f "${INSTALL_DIR}/xray" ]]; then
    echo -e "${YELLOW}Xray đã được cài đặt. Bỏ qua bước cài đặt.${PLAIN}"
else
    echo -e "${BLUE}Cài đặt Xray...${PLAIN}"
    mkdir -p ${INSTALL_DIR}
    curl -L ${XRAY_URL} -o xray.zip
    unzip xray.zip -d ${INSTALL_DIR}
    chmod +x ${INSTALL_DIR}/xray
    rm xray.zip
fi

# Tạo thư mục chứa chứng chỉ
mkdir -p ${CERT_DIR}

# Nhận địa chỉ IP máy chủ
SERVER_IP=$(curl -s ifconfig.me)

# Tạo chứng chỉ self-signed với bing.cn làm Common Name
echo -e "${BLUE}Tạo chứng chỉ self-signed với ${CAMOUFLAGE_DOMAIN} làm tên miền...${PLAIN}"
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
  -keyout ${CERT_DIR}/private.key -out ${CERT_DIR}/cert.crt \
  -subj "/CN=${CAMOUFLAGE_DOMAIN}" \
  -addext "subjectAltName=DNS:${CAMOUFLAGE_DOMAIN}"

chmod 644 ${CERT_DIR}/cert.crt
chmod 600 ${CERT_DIR}/private.key

# Chọn port ngẫu nhiên trong khoảng cao để tránh xung đột
PORT=$((RANDOM % 20000 + 30000))  # Random port từ 30000 đến 50000

# Nhập User ID, Path WebSocket, và tên người dùng
UUID=$(uuidgen)
WS_PATH=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)  # Random path
read -p "Nhập tên người dùng: " USERNAME
USERNAME=${USERNAME:-"user"}

# Tạo file cấu hình cho Xray (Vmess + WebSocket + TLS với DNS và routing tối ưu)
cat > ${CONFIG_FILE} <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "${INSTALL_DIR}/access.log",
    "error": "${INSTALL_DIR}/error.log"
  },
  "dns": {
    "servers": [
      "localhost",
      "1.1.1.1",
      "8.8.8.8"
    ],
    "queryStrategy": "UseIPv4",
    "disableCache": false,
    "disableFallback": false
  },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0,
            "security": "auto"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_DIR}/cert.crt",
              "keyFile": "${CERT_DIR}/private.key"
            }
          ],
          "serverName": "${CAMOUFLAGE_DOMAIN}",
          "alpn": ["http/1.1", "h2"]
        },
        "wsSettings": {
          "path": "/${WS_PATH}",
          "headers": {
            "Host": "${CAMOUFLAGE_DOMAIN}"
          }
        },
        "sockopt": {
          "mark": 255,
          "tcpFastOpen": true,
          "tproxy": "off"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    },
    {
      "protocol": "dns",
      "tag": "dns-out"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["dns-in"],
        "outboundTag": "dns-out"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

# Kiểm tra và tạo service systemd nếu chưa có
if [[ ! -f "${SERVICE_FILE}" ]]; then
    echo -e "${BLUE}Tạo service Xray...${PLAIN}"
    cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Xray VMess Service
After=network.target nss-lookup.target

[Service]
ExecStart=${INSTALL_DIR}/xray run -config ${CONFIG_FILE}
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=512000

[Install]
WantedBy=multi-user.target
EOF
fi

# Khởi động Xray
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# Kiểm tra status
sleep 2
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}Xray đã khởi động thành công!${PLAIN}"
else
    echo -e "${RED}Xray không khởi động được. Kiểm tra logs: journalctl -u xray -f${PLAIN}"
    systemctl status xray
fi

# Cài đặt các gói cần thiết bổ sung
apt install -y dnsutils net-tools htop iftop

# Mở cổng firewall
echo -e "${BLUE}Cấu hình firewall...${PLAIN}"
apt install -y ufw
ufw allow ${PORT}/tcp
ufw allow ${PORT}/udp
ufw allow 22/tcp  # Đảm bảo SSH luôn được mở
ufw --force enable

# Tối ưu kernel cho hiệu suất mạng tốt hơn
cat > /etc/sysctl.d/99-network-performance.conf <<EOF
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.core.rmem_default = 26214400
net.core.wmem_default = 26214400
net.ipv4.tcp_rmem = 4096 87380 26214400
net.ipv4.tcp_wmem = 4096 16384 26214400
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
EOF
sysctl --system

# Tạo cấu hình Vmess dạng JSON
VMESS_JSON="{
  \"v\": \"2\",
  \"ps\": \"${USERNAME}-VMess-WebSocket-TLS\",
  \"add\": \"${SERVER_IP}\",
  \"port\": \"${PORT}\",
  \"id\": \"${UUID}\",
  \"aid\": \"0\",
  \"scy\": \"auto\",
  \"net\": \"ws\",
  \"type\": \"none\",
  \"host\": \"${CAMOUFLAGE_DOMAIN}\",
  \"path\": \"/${WS_PATH}\",
  \"tls\": \"tls\",
  \"sni\": \"${CAMOUFLAGE_DOMAIN}\",
  \"alpn\": \"h2,http/1.1\"
}"

# Tạo URL Vmess theo định dạng chuẩn
VMESS_URL="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"

# Tạo mã QR với tên ở dưới
QR_FILE="/root/vmess_qr_${USERNAME}.png"
qrencode -o ${QR_FILE} -s 5 -m 2 "${VMESS_URL}"
convert ${QR_FILE} -gravity south -fill black -pointsize 20 -annotate +0+10 "**${USERNAME}**" ${QR_FILE}

# Hiển thị thông tin cấu hình
echo -e "${GREEN}=======================================${PLAIN}"
echo -e "${GREEN}    Cài đặt VMess TLS hoàn tất!${PLAIN}"
echo -e "${GREEN}=======================================${PLAIN}"
echo -e "${YELLOW}Thông tin VMess:${PLAIN}"
echo -e "${YELLOW}Tên người dùng: ${GREEN}${USERNAME}${PLAIN}"
echo -e "${YELLOW}Server IP: ${GREEN}${SERVER_IP}${PLAIN}"
echo -e "${YELLOW}Port: ${GREEN}${PORT}${PLAIN}"
echo -e "${YELLOW}ID (UUID): ${GREEN}${UUID}${PLAIN}"
echo -e "${YELLOW}AlterID: ${GREEN}0${PLAIN}"
echo -e "${YELLOW}Security: ${GREEN}auto${PLAIN}"
echo -e "${YELLOW}Network: ${GREEN}ws${PLAIN}"
echo -e "${YELLOW}Path: ${GREEN}/${WS_PATH}${PLAIN}"
echo -e "${YELLOW}TLS: ${GREEN}Bật${PLAIN}"
echo -e "${YELLOW}SNI (ngụy trang): ${GREEN}${CAMOUFLAGE_DOMAIN}${PLAIN}"
echo -e "${GREEN}=======================================${PLAIN}"
echo -e "${YELLOW}VMess URL:${PLAIN} ${GREEN}${VMESS_URL}${PLAIN}"
echo -e "${GREEN}=======================================${PLAIN}"
echo -e "${YELLOW}Mã QR được lưu tại: ${GREEN}${QR_FILE}${PLAIN}"
echo -e "${YELLOW}Quét mã QR dưới đây để sử dụng:${PLAIN}"
qrencode -t ANSIUTF8 "${VMESS_URL}"
echo -e "${GREEN}=======================================${PLAIN}"

# Lưu thông tin cấu hình cho người dùng
CONFIG_SAVE_FILE="/root/vmess_config_${USERNAME}.json"
cat > ${CONFIG_SAVE_FILE} <<EOF
{
  "Thông tin cấu hình VMess": {
    "Tên người dùng": "${USERNAME}",
    "Giao thức": "VMess",
    "Server IP": "${SERVER_IP}",
    "Port": "${PORT}",
    "UUID": "${UUID}",
    "AlterID": "0",
    "Security": "auto",
    "Network": "ws",
    "Path": "/${WS_PATH}",
    "TLS": "Bật",
    "SNI (ngụy trang)": "${CAMOUFLAGE_DOMAIN}"
  },
  "VMess URL": "${VMESS_URL}",
  "Thời gian tạo": "$(date)"
}
EOF

echo -e "${BLUE}Thông tin cấu hình đã được lưu vào: ${GREEN}${CONFIG_SAVE_FILE}${PLAIN}"
echo -e ""
echo -e "${YELLOW}HƯỚNG DẪN SỬ DỤNG:${PLAIN}"
echo -e "1. Cài đặt ứng dụng khách v2rayN (Windows), v2rayNG (Android), Shadowrocket (iOS)"
echo -e "2. Quét mã QR hoặc nhập URL VMess"
echo -e "3. QUAN TRỌNG: Đảm bảo giá trị SNI được đặt là '${CAMOUFLAGE_DOMAIN}'"
echo -e "4. Khi kết nối, lưu lượng sẽ được ngụy trang như đang kết nối đến ${CAMOUFLAGE_DOMAIN}"
echo -e ""
echo -e "${RED}KHẮC PHỤC SỰ CỐ:${PLAIN}"
echo -e "• Nếu không kết nối được, kiểm tra:"
echo -e "  - Port ${PORT} đã được mở: ${GREEN}ufw status${PLAIN}"
echo -e "  - Xray đang chạy: ${GREEN}systemctl status xray${PLAIN}"
echo -e "  - Logs: ${GREEN}journalctl -u xray -f${PLAIN}"
echo -e "  - DNS có hoạt động: ${GREEN}dig +short google.com @localhost${PLAIN}"
echo -e "  - Kết nối Internet: ${GREEN}ping google.com${PLAIN}"
echo -e "  - Kiểm tra chất lượng mạng: ${GREEN}mtr google.com${PLAIN}"
echo -e "  - Kiểm tra tải tài nguyên: ${GREEN}htop${PLAIN}"
echo -e ""
echo -e "${BLUE}Thiết lập cho các máy khách:${PLAIN}"
echo -e "• Đặt Host/SNI là '${CAMOUFLAGE_DOMAIN}'"
echo -e "• Đảm bảo TLS được bật"
echo -e "• Đảm bảo đường dẫn WebSocket là '/${WS_PATH}'"
echo -e "• Nếu vẫn không kết nối được, thử đổi DNS trong client sang 1.1.1.1 hoặc 8.8.8.8"
echo -e ""
echo -e "${GREEN}Cài đặt thành công bởi: ${CURRENT_USER} vào ${CURRENT_DATE}${PLAIN}"
echo -e "${GREEN}=======================================${PLAIN}"
