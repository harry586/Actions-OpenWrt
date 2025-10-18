#!/bin/bash

# 修改 root 密码
sed -i 's/root::0:0:99999:7:::/root:$1$harry586$X5X6X7X8X9X0X1X2X3X4X5:0:0:99999:7:::/g' package/base-files/files/etc/shadow

# 修改主机名为 WNDR3800
sed -i 's/OpenWrt/WNDR3800/g' package/base-files/files/bin/config_generate

# 修改 WiFi 设置
sed -i 's/option ssid.*/option ssid WNDR3800_2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
sed -i '/set wireless.radio${devidx}.disabled=1/d' package/kernel/mac80211/files/lib/wifi/mac80211.sh

# 添加 5GHz WiFi 配置
cat >> package/kernel/mac80211/files/lib/wifi/mac80211.sh << 'EOF'

config wifi-iface
    option device   radio1
    option network  lan
    option mode     ap
    option ssid     WNDR3800_5G
    option encryption psk2
    option key      harry586586
EOF

# 修改 2.4GHz WiFi 密码
sed -i 's/option key.*/option key harry586586/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh

# 限制 LuCI 仅 LAN 访问
sed -i "s/option listen_http.*/option listen_http 'lan'/g" package/network/services/uhttpd/files/uhttpd.config
sed -i "s/option listen_https.*/option listen_https 'lan'/g" package/network/services/uhttpd/files/uhttpd.config

# 创建开机自动安装脚本
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-packages << 'EOF'
#!/bin/sh

# 等待网络就绪
sleep 30

# 安装自定义 IPK 包
if [ -d "/packages" ]; then
    for ipk in /packages/*.ipk; do
        if [ -f "$ipk" ]; then
            echo "Installing $ipk..."
            opkg install "$ipk"
        fi
    done
fi

# 清理
rm -rf /packages

exit 0
EOF

chmod +x files/etc/uci-defaults/99-custom-packages

# 复制自定义 IPK 包到固件中
if [ -d "../files/packages" ]; then
    mkdir -p files/packages
    cp -r ../files/packages/*.ipk files/packages/ 2>/dev/null || true
fi

# 确保配置正确
echo "WNDR3800" > files/etc/hostname
