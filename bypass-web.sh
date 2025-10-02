#!/bin/bash
# Script auto reverse proxy bằng Caddy trên Ubuntu
# Fixed GPG key import issue

echo "=== Reverse Proxy Setup (Caddy) ==="

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then 
    echo "Vui lòng chạy với sudo hoặc root"
    exit 1
fi

# Hỏi domain của bạn
read -p "Nhập domain của bạn (ví dụ: mydomain.com): " MY_DOMAIN
# Hỏi trang web cần bỏ chặn
read -p "Nhập URL trang web bị chặn (ví dụ: https://target.example): " TARGET_URL

echo "Đang cập nhật hệ thống..."
apt update -y 

echo "Đang cài đặt dependencies..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg2

echo "Đang thêm GPG key của Caddy..."
# Cách mới: Import GPG key đúng format
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

echo "Đang thêm repository Caddy..."
# Cách mới: Sử dụng signed-by
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list

# Sửa file sources.list để thêm signed-by
sed -i 's|deb |deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] |' /etc/apt/sources.list.d/caddy-stable.list

echo "Đang cập nhật package list..."
apt update -y

echo "Đang cài đặt Caddy..."
apt install -y caddy

# Kiểm tra cài đặt thành công
if ! command -v caddy &> /dev/null; then
    echo "❌ Lỗi: Không thể cài đặt Caddy"
    exit 1
fi

echo "✅ Caddy đã được cài đặt: $(caddy version)"

# Backup cấu hình cũ nếu có
if [ -f /etc/caddy/Caddyfile ]; then
    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup.$(date +%s)
    echo "📦 Đã backup cấu hình cũ"
fi

# Tạo file cấu hình Caddy
echo "Đang tạo cấu hình Caddy..."
cat > /etc/caddy/Caddyfile <<EOF
$MY_DOMAIN {
    reverse_proxy $TARGET_URL {
        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF

# Validate cấu hình
echo "Đang kiểm tra cấu hình..."
if ! caddy validate --config /etc/caddy/Caddyfile; then
    echo "❌ Lỗi: Cấu hình Caddy không hợp lệ"
    exit 1
fi

# Restart Caddy để áp dụng
echo "Đang khởi động Caddy..."
systemctl enable caddy
systemctl restart caddy

# Kiểm tra trạng thái
sleep 2
if systemctl is-active --quiet caddy; then
    echo "=========================================="
    echo "✅ Hoàn tất!"
    echo "Domain:  https://$MY_DOMAIN"
    echo "Proxy tới: $TARGET_URL"
    echo "SSL được cấp tự động bởi Let's Encrypt."
    echo ""
    echo "Kiểm tra trạng thái: systemctl status caddy"
    echo "Xem logs: journalctl -u caddy -f"
    echo "=========================================="
else
    echo "❌ Lỗi: Caddy không chạy được"
    echo "Xem logs: journalctl -u caddy -xe"
    exit 1
fi
