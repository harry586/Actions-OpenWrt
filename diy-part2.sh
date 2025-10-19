#!/bin/bash

# OpenWrt DIY 脚本第二部分 - 简化修复版

echo "开始自定义配置..."

# 1. 修改 root 密码
echo "修改 root 密码..."
mkdir -p files/etc
cat > files/etc/shadow << 'EOF'
root:$1$harry586$V5h3l.6dPz8Rq6k4F1d9E0:19689:0:99999:7:::
daemon:*:0:0:99999:7:::
ftp:*:0:0:99999:7:::
network:*:0:0:99999:7:::
nobody:*:0:0:99999:7:::
EOF

# 2. 修改主机名
echo "修改主机名..."
sed -i 's/OpenWrt/WNDR3800/g' package/base-files/files/bin/config_generate
sed -i 's/openwrt/wndr3800/g' package/base-files/files/bin/config_generate
echo "WNDR3800" > files/etc/hostname

# 3. 修改 WiFi 设置
echo "修改 WiFi 设置..."
# 创建无线配置脚本
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/20-wifi-config << 'EOF'
#!/bin/sh

# 设置无线网络
uci delete wireless.radio0
uci delete wireless.@wifi-iface[0]

uci set wireless.radio0=wifi-device
uci set wireless.radio0.type='mac80211'
uci set wireless.radio0.channel='6'
uci set wireless.radio0.hwmode='11g'
uci set wireless.radio0.path='platform/ahb/18100000.wmac'
uci set wireless.radio0.htmode='HT20'
uci set wireless.radio0.disabled='0'

uci set wireless.@wifi-iface[0]=wifi-iface
uci set wireless.@wifi-iface[0].device='radio0'
uci set wireless.@wifi-iface[0].network='lan'
uci set wireless.@wifi-iface[0].mode='ap'
uci set wireless.@wifi-iface[0].ssid='WNDR3800_2.4G'
uci set wireless.@wifi-iface[0].encryption='none'

# 尝试设置 5GHz（如果硬件支持）
uci set wireless.radio1=wifi-device
uci set wireless.radio1.type='mac80211'
uci set wireless.radio1.channel='36'
uci set wireless.radio1.hwmode='11a'
uci set wireless.radio1.path='pci0000:00/0000:00:00.0'
uci set wireless.radio1.htmode='VHT80'
uci set wireless.radio1.disabled='0'

uci set wireless.@wifi-iface[1]=wifi-iface
uci set wireless.@wifi-iface[1].device='radio1'
uci set wireless.@wifi-iface[1].network='lan'
uci set wireless.@wifi-iface[1].mode='ap'
uci set wireless.@wifi-iface[1].ssid='WNDR3800_5G'
uci set wireless.@wifi-iface[1].encryption='none'

uci commit wireless
wifi reload

exit 0
EOF
chmod +x files/etc/uci-defaults/20-wifi-config

# 4. IPK 自动安装
echo "设置 IPK 自动安装..."
cat > files/etc/uci-defaults/99-custom-packages << 'EOF'
#!/bin/sh

# 等待网络就绪
sleep 30

# 安装自定义 IPK 包
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

# 5. 复制 IPK 包
if [ -d "../../files/packages" ]; then
    echo "复制 IPK 包..."
    mkdir -p files/packages
    cp ../../files/packages/*.ipk files/packages/ 2>/dev/null || true
fi

echo "自定义配置完成"
