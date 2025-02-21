#!/bin/bash

# Thông tin tác giả
author="233boy"
# github=https://github.com/233boy/v2ray

# Màu sắc terminal
red='\e[31m'
yellow='\e[33m'
green='\e[92m'
blue='\e[94m'
none='\e[0m'

# Hàm in màu
_red() { echo -e "${red}$@${none}"; }
_green() { echo -e "${green}$@${none}"; }
_yellow() { echo -e "${yellow}$@${none}"; }
_red_bg() { echo -e "\e[41m$@${none}"; }

# Biến thông báo lỗi và cảnh báo
is_err=$(_red_bg "Lỗi!")
is_warn=$(_red_bg "Cảnh báo!")

# Hàm báo lỗi và thoát
err() {
    echo -e "\n$is_err $@\n" && exit 1
}

# Hàm cảnh báo
warn() {
    echo -e "\n$is_warn $@\n"
}

# Kiểm tra quyền root
[[ $EUID != 0 ]] && err "Vui lòng chạy script với quyền ${yellow}ROOT${none}."

# Kiểm tra hệ điều hành (Ubuntu/Debian/CentOS)
cmd=$(type -P apt-get || type -P yum)
[[ ! $cmd ]] && err "Script chỉ hỗ trợ ${yellow}(Ubuntu, Debian, CentOS)${none}."

# Kiểm tra systemd
[[ ! $(type -P systemctl) ]] && err "Hệ thống thiếu systemctl. Thử chạy: ${yellow}${cmd} update -y; ${cmd} install systemd -y${none} để sửa lỗi."

# Kiểm tra kiến trúc CPU (chỉ hỗ trợ 64-bit)
case $(uname -m) in
    amd64 | x86_64 | *aarch64* | *armv8*) ;;
    *) err "Script chỉ hỗ trợ hệ thống 64-bit." ;;
esac

# Biến cài đặt
is_core="v2ray"
is_core_dir="/etc/$is_core"
is_config_json="$is_core_dir/config.json"
is_pkg="wget unzip qrencode imagemagick"

# Nhập tên người dùng
read -p "Nhập tên mong muốn cho mã VMess: " user_name
[[ -z "$user_name" ]] && user_name="v233 boy"

# Hàm tạo cấu hình VMess
generate_vmess() {
    uuid=$(cat /proc/sys/kernel/random/uuid)
    port=10086
    ip_address=$(curl -s ifconfig.me)

    # Tạo file cấu hình JSON
    cat > "$is_config_json" <<EOF
{
    "inbounds": [{
        "port": $port,
        "protocol": "vmess",
        "settings": {
            "clients": [{
                "id": "$uuid",
                "alterId": 64,
                "email": "$user_name"
            }]
        }
    }],
    "outbounds": [{
        "protocol": "freedom",
        "settings": {}
    }]
}
EOF

    # Tạo link VMess
    vmess_link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$user_name\",\"add\":\"$ip_address\",\"port\":\"$port\",\"id\":\"$uuid\",\"aid\":\"64\",\"net\":\"tcp\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"tls\":\"\"}" | base64 -w 0)"
    echo "Link VMess: $vmess_link"
}

# Cài đặt các gói phụ thuộc
install_dependencies() {
    for pkg in $is_pkg; do
        if ! command -v $pkg &>/dev/null; then
            echo "Đang cài đặt $pkg..."
            $cmd update -y && $cmd install -y $pkg
        fi
    done
}

# Hàm tạo mã QR
generate_qr() {
    qr_file="$is_core_dir/vmess_qr.png"
    
    # Tạo mã QR từ link VMess
    echo -n "$vmess_link" | qrencode -o "$qr_file" -s 10
    
    # Thêm tên người dùng vào dưới mã QR
    convert "$qr_file" -gravity South -splice 0x50 -pointsize 20 -fill black -annotate +0+10 "$user_name" "$qr_file"
    
    # Hiển thị mã QR trên terminal
    echo "Mã QR của bạn:"
    qrencode -t ANSIUTF8 <<< "$vmess_link"
    
    echo "Mã QR đã được lưu tại: $qr_file"
}

# Kiểm tra trạng thái
check_status() {
    [[ ! -f "$is_config_json" ]] && err "Tạo file cấu hình thất bại."
}

# Hàm chính để cài đặt
install_v2ray() {
    # Tạo thư mục cho V2Ray
    mkdir -p "$is_core_dir"
    
    # Cài đặt các gói cần thiết
    install_dependencies
    
    # Tạo cấu hình VMess
    generate_vmess
    
    # Tạo mã QR
    generate_qr
    
    # Kiểm tra trạng thái
    check_status
    
    # Thông báo hoàn tất
    _green "✅ Cài đặt hoàn tất!"
}

# Chạy script
install_v2ray
