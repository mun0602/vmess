#!/bin/bash
# Script auto reverse proxy bằng Nginx trên Ubuntu
# Author: Fixed version for @mun0602

echo "=== Reverse Proxy Setup (Nginx) ==="

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Vui lòng chạy với sudo"
    exit 1
fi

# Dọn dẹp Caddy repository bị lỗi
echo "🧹 Dọn dẹp Caddy cũ..."
rm -f /etc/apt/sources.list.d/caddy-stable.list
rm -f /etc/apt/trusted.gpg.d/caddy-stable.asc
rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg

# Thu thập thông tin
read -p "📝 Nhập domain của bạn (ví dụ: proxy.mydomain.com): " MY_DOMAIN
read -p "📝 Nhập URL đích (ví dụ: https://blocked-site.com): " TARGET_URL

# Validate input
if [[ -z "$MY_DOMAIN" ]] || [[ -z "$TARGET_URL" ]]; then
    echo "❌ Domain và URL không được để trống!"
    exit 1
fi

# Cập nhật hệ thống
echo "📦 Cập nhật hệ thống..."
apt update -y

# Cài đặt Nginx và Certbot
echo "📦 Cài đặt Nginx và Certbot..."
apt install -y nginx certbot python3-certbot-nginx

# Kiểm tra cài đặt
if ! command -v nginx &> /dev/null; then
    echo "❌ Lỗi: Không thể cài đặt Nginx"
    exit 1
fi

echo "✅ Nginx đã được cài đặt: $(nginx -v 2>&1)"

# Tạo cấu hình Nginx
NGINX_CONF="/etc/nginx/sites-available/$MY_DOMAIN"
echo "📝 Tạo cấu hình Nginx..."

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $MY_DOMAIN;

    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $MY_DOMAIN;

    # SSL certificates (sẽ được Certbot tự động thêm)
    # ssl_certificate /etc/letsencrypt/live/$MY_DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$MY_DOMAIN/privkey.pem;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Proxy settings
    location / {
        proxy_pass $TARGET_URL;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Logs
    access_log /var/log/nginx/${MY_DOMAIN}_access.log;
    error_log /var/log/nginx/${MY_DOMAIN}_error.log;
}
EOF

# Tạo symlink
echo "🔗 Kích hoạt site..."
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

# Xóa default site nếu tồn tại
rm -f /etc/nginx/sites-enabled/default

# Test cấu hình Nginx
echo "🔍 Kiểm tra cấu hình Nginx..."
if ! nginx -t; then
    echo "❌ Lỗi: Cấu hình Nginx không hợp lệ"
    cat "$NGINX_CONF"
    exit 1
fi

# Reload Nginx
echo "🔄 Khởi động lại Nginx..."
systemctl enable nginx
systemctl restart nginx

# Kiểm tra Nginx chạy
sleep 2
if ! systemctl is-active --quiet nginx; then
    echo "❌ Lỗi: Nginx không chạy được"
    systemctl status nginx
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ Nginx đã được cấu hình!"
echo "Domain: http://$MY_DOMAIN (HTTP)"
echo "Proxy tới: $TARGET_URL"
echo "=========================================="
echo ""

# Hỏi có muốn cài SSL không
read -p "🔒 Bạn có muốn cài SSL miễn phí (Let's Encrypt)? (y/n): " INSTALL_SSL

if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then
    echo ""
    echo "📧 QUAN TRỌNG: Certbot cần email để:"
    echo "   - Gửi thông báo gia hạn SSL"
    echo "   - Khôi phục tài khoản nếu mất"
    read -p "Nhập email của bạn: " CERTBOT_EMAIL
    
    if [[ -z "$CERTBOT_EMAIL" ]]; then
        echo "⚠️  Bỏ qua cài SSL (chưa có email)"
    else
        echo "🔒 Đang cài đặt SSL với Let's Encrypt..."
        echo "⚠️  Lưu ý: Domain $MY_DOMAIN phải trỏ về IP server này!"
        
        # Chạy Certbot
        certbot --nginx -d "$MY_DOMAIN" --non-interactive --agree-tos -m "$CERTBOT_EMAIL" --redirect
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "=========================================="
            echo "🎉 HOÀN TẤT!"
            echo "Domain: https://$MY_DOMAIN (HTTPS với SSL)"
            echo "Proxy tới: $TARGET_URL"
            echo "SSL: Tự động gia hạn mỗi 60 ngày"
            echo "=========================================="
        else
            echo ""
            echo "⚠️  Lỗi cài SSL. Có thể do:"
            echo "   1. Domain chưa trỏ về IP server này"
            echo "   2. Port 80/443 bị firewall chặn"
            echo "   3. Domain không hợp lệ"
            echo ""
            echo "Bạn vẫn có thể dùng HTTP: http://$MY_DOMAIN"
        fi
    fi
else
    echo "⚠️  Bỏ qua cài SSL. Chỉ dùng HTTP."
fi

echo ""
echo "📋 Các lệnh hữu ích:"
echo "   Xem logs: tail -f /var/log/nginx/${MY_DOMAIN}_error.log"
echo "   Reload Nginx: systemctl reload nginx"
echo "   Kiểm tra status: systemctl status nginx"
echo "   Test cấu hình: nginx -t"
echo ""
