#!/bin/bash
# Script auto reverse proxy bằng Caddy trên Ubuntu
# Tác giả: ChatGPT

# Yêu cầu: chạy với user root hoặc sudo

echo "=== Reverse Proxy Setup (Caddy) ==="

# Hỏi domain của bạn
read -p "Nhập domain của bạn (ví dụ: mydomain.com): " MY_DOMAIN
# Hỏi trang web cần bỏ chặn
read -p "Nhập URL trang web bị chặn (ví dụ: https://target.example): " TARGET_URL

# Cập nhật hệ thống
apt update -y 

# Cài Caddy (repo chính thức)
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | tee /etc/apt/trusted.gpg.d/caddy-stable.asc
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update -y
apt install -y caddy

# Tạo file cấu hình Caddy
cat > /etc/caddy/Caddyfile <<EOF
$MY_DOMAIN {
    reverse_proxy $TARGET_URL {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF

# Restart Caddy để áp dụng
systemctl enable caddy
systemctl restart caddy

echo "=========================================="
echo "Hoàn tất!"
echo "Domain:  https://$MY_DOMAIN"
echo "Proxy tới: $TARGET_URL"
echo "SSL được cấp tự động bởi Let's Encrypt."
echo "=========================================="
