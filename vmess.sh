#!/bin/bash

# Màu sắc cho thông báo
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

CURRENT_DATE="$(date +%Y-%m-%d)"
CURRENT_USER="$(whoami)"

# Cập nhật và cài đặt các gói cần thiết
apt update
apt install -y unzip curl jq uuid-runtime qrencode imagemagick openssl dnsutils net-tools htop iftop ufw

# Đường dẫn và biến
XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
INSTALL_DIR="/usr/local/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"

# Tải và cài đặt Xray
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

# Sinh key Reality
KEYS=$(${INSTALL_DIR}/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep 'Private' | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep 'Public' | awk '{print $3}')

# Sinh UUID, port, short_id
UUID=$(uuidgen)
PORT=$((RANDOM % 20000 + 30000))
SHORT_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 8 | head -n 1)
SERVER_NAME="www.cloudflare.com"

# Nhập tên người dùng
read -p "Nhập tên người dùng: " USERNAME
USERNAME=${USERNAME:-"user"}

# Tạo file cấu hình Xray (VMess + Reality)
cat > ${CONFIG_FILE} <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "${INSTALL_DIR}/access.log",
    "error": "${INSTALL_DIR}/error.log"
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
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SERVER_NAME}:443",
          "xver": 0,
          "serverNames": [
            "${SERVER_NAME}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ]
}
EOF

# Tạo systemd service nếu chưa có
if [[ ! -f "${SERVICE_FILE}" ]]; then
    echo -e "${BLUE}Tạo service Xray...${PLAIN}"
    cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Xray VMess Reality Service
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

# Mở cổng firewall
echo -e "${BLUE}Cấu hình firewall...${PLAIN}"
ufw allow ${PORT}/tcp
ufw allow 22/tcp
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

# Lấy IP server
SERVER_IP=$(curl -s ifconfig.me)

# Tạo cấu hình VMess Reality dạng JSON cho client
VMESS_JSON="{\n  \"v\": \"2\",\n  \"ps\": \"${USERNAME}-VMess-Reality\",\n  \"add\": \"${SERVER_IP}\",\n  \"port\": \"${PORT}\",\n  \"id\": \"${UUID}\",\n  \"aid\": \"0\",\n  \"scy\": \"auto\",\n  \"net\": \"tcp\",\n  \"type\": \"none\",\n  \"host\": \"${SERVER_NAME}\",\n  \"tls\": \"reality\",\n  \"sni\": \"${SERVER_NAME}\",\n  \"alpn\": \"\",\n  \"fp\": \"chrome\",\n  \"pbk\": \"${PUBLIC_KEY}\",\n  \"sid\": \"${SHORT_ID}\"\n}"

# Tạo URL VMess Reality
VMESS_URL="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"

# Tạo mã QR với tên ở dưới
QR_FILE="/root/vmess_reality_qr_${USERNAME}.png"
qrencode -o ${QR_FILE} -s 5 -m 2 "${VMESS_URL}"
convert ${QR_FILE} -gravity south -fill black -pointsize 20 -annotate +0+10 "**${USERNAME}**" ${QR_FILE}

# Hiển thị thông tin cấu hình
echo -e "${GREEN}=======================================${PLAIN}"
echo -e "${GREEN}    Cài đặt VMess Reality hoàn tất!${PLAIN}"
echo -e "${GREEN}=======================================${PLAIN}"
echo -e "${YELLOW}Thông tin VMess Reality:${PLAIN}"
echo -e "${YELLOW}Tên người dùng: ${GREEN}${USERNAME}${PLAIN}"
echo -e "${YELLOW}Server IP: ${GREEN}${SERVER_IP}${PLAIN}"
echo -e "${YELLOW}Port: ${GREEN}${PORT}${PLAIN}"
echo -e "${YELLOW}ID (UUID): ${GREEN}${UUID}${PLAIN}"
echo -e "${YELLOW}Public Key: ${GREEN}${PUBLIC_KEY}${PLAIN}"
echo -e "${YELLOW}Short ID: ${GREEN}${SHORT_ID}${PLAIN}"
echo -e "${YELLOW}Security: ${GREEN}reality${PLAIN}"
echo -e "${YELLOW}Network: ${GREEN}tcp${PLAIN}"
echo -e "${YELLOW}SNI (ngụy trang): ${GREEN}${SERVER_NAME}${PLAIN}"
echo -e "${GREEN}=======================================${PLAIN}"
echo -e "${YELLOW}VMess Reality URL:${PLAIN} ${GREEN}${VMESS_URL}${PLAIN}"
echo -e "${GREEN}=======================================${PLAIN}"
echo -e "${YELLOW}Mã QR được lưu tại: ${GREEN}${QR_FILE}${PLAIN}"
echo -e "${YELLOW}Quét mã QR dưới đây để sử dụng:${PLAIN}"
qrencode -t ANSIUTF8 "${VMESS_URL}"
echo -e "${GREEN}=======================================${PLAIN}"

# Lưu thông tin cấu hình cho người dùng
CONFIG_SAVE_FILE="/root/vmess_reality_config_${USERNAME}.json"
cat > ${CONFIG_SAVE_FILE} <<EOF
{
  "Thông tin cấu hình VMess Reality": {
    "Tên người dùng": "${USERNAME}",
    "Giao thức": "VMess",
    "Server IP": "${SERVER_IP}",
    "Port": "${PORT}",
    "UUID": "${UUID}",
    "Public Key": "${PUBLIC_KEY}",
    "Short ID": "${SHORT_ID}",
    "Security": "reality",
    "Network": "tcp",
    "SNI (ngụy trang)": "${SERVER_NAME}"
  },
  "VMess Reality URL": "${VMESS_URL}",
  "Thời gian tạo": "$(date)"
}
EOF

echo -e "${BLUE}Thông tin cấu hình đã được lưu vào: ${GREEN}${CONFIG_SAVE_FILE}${PLAIN}"
echo -e ""
echo -e "${YELLOW}HƯỚNG DẪN SỬ DỤNG:${PLAIN}"
echo -e "1. Cài đặt ứng dụng khách v2rayN (Windows), v2rayNG (Android), Shadowrocket (iOS) bản mới nhất."
echo -e "2. Quét mã QR hoặc nhập URL VMess Reality."
echo -e "3. QUAN TRỌNG: Đảm bảo các trường Public Key, Short ID, SNI đúng như trên."
echo -e "4. Khi kết nối, lưu lượng sẽ được ngụy trang như đang kết nối đến ${SERVER_NAME} qua Reality."
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
echo -e "• Đảm bảo nhập đúng Public Key, Short ID, SNI, port, UUID."
echo -e "• Đảm bảo chọn security là reality, network là tcp."
echo -e "• Nếu vẫn không kết nối được, thử đổi DNS trong client sang 1.1.1.1 hoặc 8.8.8.8"
echo -e ""
echo -e "${GREEN}Cài đặt thành công bởi: ${CURRENT_USER} vào ${CURRENT_DATE}${PLAIN}"
echo -e "${GREEN}=======================================${PLAIN}"
