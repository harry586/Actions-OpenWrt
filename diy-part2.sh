#!/bin/bash

# OpenWrt DIY 脚本第二部分 - 仅保留IPK安装功能

echo "开始应用自定义配置..."

# 仅保留IPK自动安装功能
cat > files/etc/uci-defaults/99-custom-packages << 'EOF'
#!/bin/sh

sleep 20

if [ -d "/packages" ]; then
    for ipk in /packages/*.ipk; do
        if [ -f "$ipk" ]; then
            echo "安装 $ipk..."
            opkg install "$ipk" || echo "安装失败: $ipk"
        fi
    done
    rm -rf /packages
fi

/etc/init.d/uhttpd restart

exit 0
EOF
chmod +x files/etc/uci-defaults/99-custom-packages

# 复制 IPK 包
if [ -d "../../files/packages" ]; then
    echo "复制自定义 IPK 包..."
    mkdir -p files/packages
    cp ../../files/packages/*.ipk files/packages/ 2>/dev/null || true
fi

echo "自定义配置完成"
