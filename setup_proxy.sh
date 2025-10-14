#!/bin/bash

# ==============================================================================
# Script cài đặt Proxy VMess + WebSocket + TLS
# Tác giả: Jules
# Mô tả: Script này tự động hóa việc cài đặt một máy chủ proxy an toàn
# sử dụng Xray (VMess), Nginx (làm reverse proxy và máy chủ web),
# WebSocket để ngụy trang lưu lượng, và Certbot (Let's Encrypt) để mã hóa TLS.
# ==============================================================================

# Màu sắc để output dễ đọc hơn
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Hàm in thông báo
info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    error "Vui lòng chạy tập lệnh này với quyền sudo hoặc với tư cách là người dùng root."
    exit 1
fi

info "Bắt đầu quá trình cài đặt proxy nâng cao..."

# Dọn dẹp các cài đặt cũ có thể gây xung đột
info "Dọn dẹp các repository cũ (nếu có)..."
rm -f /etc/apt/sources.list.d/caddy-stable.list
rm -f /etc/apt/trusted.gpg.d/caddy-stable.asc
rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg

# Cập nhật hệ thống và cài đặt các gói cần thiết
info "Cập nhật hệ thống và cài đặt các gói phụ thuộc..."
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx curl unzip jq uuid-runtime qrencode

# Kiểm tra cài đặt thành công
if ! command -v nginx &> /dev/null || ! command -v certbot &> /dev/null || ! command -v jq &> /dev/null; then
    error "Không thể cài đặt các gói cần thiết (Nginx, Certbot, jq)."
    exit 1
fi

info "Đã cài đặt các gói phụ thuộc cần thiết."

# Thu thập thông tin từ người dùng
info "Vui lòng cung cấp các thông tin sau:"
read -p "Nhập tên miền của bạn (ví dụ: example.com): " DOMAIN
read -p "Nhập email của bạn (dùng cho thông báo gia hạn SSL): " EMAIL
read -p "Nhập đường dẫn ngụy trang (ví dụ: /my-secret-path, nhấn Enter để dùng giá trị ngẫu nhiên): " WS_PATH

# Xác thực đầu vào
if [[ -z "$DOMAIN" ]] || [[ -z "$EMAIL" ]]; then
    error "Tên miền và email không được để trống."
    exit 1
fi

# Tạo đường dẫn WebSocket ngẫu nhiên nếu người dùng không nhập
if [[ -z "$WS_PATH" ]]; then
    WS_PATH="/$(uuidgen | cut -d'-' -f1)"
    info "Đã tạo đường dẫn WebSocket ngẫu nhiên: ${WS_PATH}"
fi

# Biến toàn cục
XRAY_INSTALL_DIR="/usr/local/xray"
XRAY_CONFIG_FILE="${XRAY_INSTALL_DIR}/config.json"
XRAY_SERVICE_FILE="/etc/systemd/system/xray.service"
NGINX_CONF_FILE="/etc/nginx/sites-available/$DOMAIN"

UUID=$(uuidgen)
XRAY_PORT=$((RANDOM % 10000 + 10000)) # Port ngẫu nhiên từ 10000-19999

# --- Hàm cài đặt Xray ---
install_xray() {
    info "Đang cài đặt hoặc cập nhật Xray-core..."

    # Tìm phiên bản Xray mới nhất
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | jq -r '.tag_name')
    if [[ -z "$LATEST_VERSION" ]]; then
        error "Không thể tìm thấy phiên bản Xray mới nhất. Kiểm tra kết nối mạng."
        exit 1
    fi
    info "Phiên bản Xray mới nhất là: ${LATEST_VERSION}"

    # Tải xuống và giải nén
    XRAY_ZIP_NAME="Xray-linux-64.zip"
    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${LATEST_VERSION}/${XRAY_ZIP_NAME}"

    mkdir -p ${XRAY_INSTALL_DIR}
    info "Đang tải xuống từ ${DOWNLOAD_URL}..."
    if ! curl -L -o "${XRAY_INSTALL_DIR}/${XRAY_ZIP_NAME}" "${DOWNLOAD_URL}"; then
        error "Tải xuống Xray thất bại."
        exit 1
    fi

    info "Đang giải nén Xray..."
    unzip -o "${XRAY_INSTALL_DIR}/${XRAY_ZIP_NAME}" -d "${XRAY_INSTALL_DIR}"
    chmod +x "${XRAY_INSTALL_DIR}/xray"

    # Dọn dẹp
    rm "${XRAY_INSTALL_DIR}/${XRAY_ZIP_NAME}"

    info "Xray đã được cài đặt thành công tại ${XRAY_INSTALL_DIR}/xray"
}


# --- Hàm cấu hình Xray ---
configure_xray() {
    info "Đang cấu hình Xray..."

    cat > ${XRAY_CONFIG_FILE} <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": ${XRAY_PORT},
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
        "network": "ws",
        "wsSettings": {
          "path": "${WS_PATH}"
        }
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
    info "Đã tạo tệp cấu hình Xray."
}


# --- Hàm cấu hình Nginx ---
configure_nginx() {
    info "Đang cấu hình Nginx..."

    # Xóa cấu hình mặc định
    rm -f /etc/nginx/sites-enabled/default

    # Tạo cấu hình Nginx mới
    cat > ${NGINX_CONF_FILE} <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Dùng cho việc xác thực Certbot
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Chuyển hướng tất cả các yêu cầu khác sang HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # Đường dẫn SSL sẽ được Certbot thêm vào
    # ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256';

    # Ngụy trang bằng một trang web tĩnh mặc định
    location / {
        root /var/www/html;
        index index.html index.htm;
        # Trả về trang 404 để tránh bị quét
        try_files \$uri \$uri/ =404;
    }

    # Chuyển tiếp lưu lượng WebSocket đến Xray
    location ${WS_PATH} {
        if (\$http_upgrade != "websocket") {
            return 404;
        }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${XRAY_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    # Tạo trang web tĩnh mặc định để ngụy trang
    mkdir -p /var/www/html
    echo "<html><body><h1>Welcome to Nginx!</h1></body></html>" > /var/www/html/index.html

    # Kích hoạt cấu hình
    ln -sf ${NGINX_CONF_FILE} /etc/nginx/sites-enabled/
    info "Đã tạo tệp cấu hình Nginx."
}

# --- Hàm thiết lập SSL ---
setup_ssl() {
    info "Đang yêu cầu chứng chỉ SSL từ Let's Encrypt..."

    # Dừng Nginx tạm thời để certbot chạy ở chế độ standalone
    systemctl stop nginx

    # Yêu cầu chứng chỉ
    if ! certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos -m $EMAIL; then
        error "Không thể lấy chứng chỉ SSL. Vui lòng kiểm tra:"
        error "1. Tên miền '$DOMAIN' đã được trỏ đúng đến IP của máy chủ này."
        error "2. Cổng 80 không bị tường lửa chặn."
        exit 1
    fi

    # Chỉnh sửa cấu hình Nginx để sử dụng SSL
    sed -i "s|# ssl_certificate|ssl_certificate|g" ${NGINX_CONF_FILE}
    sed -i "s|# ssl_certificate_key|ssl_certificate_key|g" ${NGINX_CONF_FILE}
    # Certbot thường tự động xử lý việc này, nhưng chúng ta làm để chắc chắn
    if ! grep -q "ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;" ${NGINX_CONF_FILE}; then
        certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect
    fi

    info "Đã cài đặt và cấu hình SSL thành công."
}


# --- Hàm khởi động dịch vụ ---
start_services() {
    info "Đang tạo và khởi động dịch vụ Xray..."

    # Tạo tệp dịch vụ systemd cho Xray
    cat > ${XRAY_SERVICE_FILE} <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls/xray-core
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${XRAY_INSTALL_DIR}/xray run -config ${XRAY_CONFIG_FILE}
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

    # Tải lại, kích hoạt và khởi động các dịch vụ
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray

    info "Đang kiểm tra và khởi động lại Nginx..."
    if ! nginx -t; then
        error "Cấu hình Nginx không hợp lệ. Vui lòng kiểm tra lại."
        cat ${NGINX_CONF_FILE}
        exit 1
    fi
    systemctl enable nginx
    systemctl restart nginx

    # Kiểm tra trạng thái dịch vụ
    sleep 2
    if ! systemctl is-active --quiet xray; then
        error "Dịch vụ Xray không khởi động được."
        journalctl -u xray -n 20 --no-pager
        exit 1
    fi
    if ! systemctl is-active --quiet nginx; then
        error "Dịch vụ Nginx không khởi động được."
        journalctl -u nginx -n 20 --no-pager
        exit 1
    fi

    info "Các dịch vụ Nginx và Xray đã được khởi động."
}


# --- Hàm hiển thị kết quả ---
display_result() {
    info "🎉 Cài đặt hoàn tất! 🎉"

    SERVER_IP=$(curl -s ifconfig.me)

    # Tạo JSON cấu hình cho client
    VMESS_JSON=$(jq -n --arg ps "$DOMAIN" --arg add "$DOMAIN" --arg port "443" --arg id "$UUID" --arg path "$WS_PATH" \
    '{
      "v": "2",
      "ps": $ps,
      "add": $add,
      "port": $port,
      "id": $id,
      "aid": "0",
      "scy": "auto",
      "net": "ws",
      "type": "none",
      "host": $add,
      "path": $path,
      "tls": "tls"
    }')

    VMESS_URL="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"

    echo "--------------------------------------------------"
    echo -e "${GREEN}Thông tin cấu hình máy khách VMess:${NC}"
    echo -e "   ${YELLOW}Tên máy chủ (Address):${NC} $DOMAIN"
    echo -e "   ${YELLOW}Cổng (Port):${NC} 443"
    echo -e "   ${YELLOW}UUID:${NC} $UUID"
    echo -e "   ${YELLOW}AlterId:${NC} 0"
    echo -e "   ${YELLOW}Bảo mật (Security):${NC} auto"
    echo -e "   ${YELLOW}Mạng (Network):${NC} ws (WebSocket)"
    echo -e "   ${YELLOW}Host:${NC} $DOMAIN"
    echo -e "   ${YELLOW}Đường dẫn (Path):${NC} $WS_PATH"
    echo -e "   ${YELLOW}Bảo mật TLS:${NC} Bật (tls)"
    echo "--------------------------------------------------"
    echo -e "${GREEN}URL VMess (sao chép và dán vào máy khách):${NC}"
    echo "$VMESS_URL"
    echo "--------------------------------------------------"
    echo -e "${GREEN}Hoặc quét mã QR sau:${NC}"
    qrencode -t ANSIUTF8 "${VMESS_URL}"
    echo "--------------------------------------------------"
    info "Để xem log Xray, dùng lệnh: journalctl -u xray -f"
    info "Để xem log Nginx, dùng lệnh: tail -f /var/log/nginx/error.log"
}


# Gọi các hàm chính
install_xray
configure_xray
configure_nginx
setup_ssl
start_services
display_result