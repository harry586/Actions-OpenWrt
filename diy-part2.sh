#!/bin/bash

# OpenWrt DIY 脚本第二部分 - 在配置之后执行

# 修改 root 密码（使用固定哈希）
sed -i 's/root::0:0:99999:7:::/root:$1$harry586$V5h3l.6dPz8Rq6k4F1d9E0:0:0:99999:7:::/g' package/base-files/files/etc/shadow

# 修改主机名
sed -i 's/OpenWrt/WNDR3800/g' package/base-files/files/bin/config_generate
sed -i 's/openwrt/wndr3800/g' package/base-files/files/bin/config_generate

# 修改 WiFi 设置 - 开放网络，无密码
# 2.4GHz WiFi 配置
sed -i 's/set wireless\.radio0\.ssid=.*/set wireless.radio0.ssid=WNDR3800_2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
sed -i 's/set wireless\.radio0\.encryption=.*/set wireless.radio0.encryption=none/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
sed -i '/set wireless\.\${name}\.key=.*/d' package/kernel/mac80211/files/lib/wifi/mac80211.sh

# 5GHz WiFi 配置（保留，即使设备可能不支持）
cat >> package/kernel/mac80211/files/lib/wifi/mac80211.sh << 'EOF'

[ "$(config_get radio1 type)" = "mac80211" ] && {
    uci -q batch << EOI
set wireless.radio1.channel='36'
set wireless.radio1.disabled='0'
set wireless.wifinet2=wifi-iface
set wireless.wifinet2.device='radio1'
set wireless.wifinet2.mode='ap'
set wireless.wifinet2.network='lan'
set wireless.wifinet2.ssid='WNDR3800_5G'
set wireless.wifinet2.encryption='none'
EOI
}
EOF

# 限制 LuCI 仅 LAN 访问
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-luci-lan-only << 'EOF'
#!/bin/sh
uci set uhttpd.main.listen_http='0.0.0.0:80'
uci set uhttpd.main.listen_https='0.0.0.0:443' 
uci set uhttpd.main.rfc1918_filter='1'
uci commit uhttpd
exit 0
EOF
chmod +x files/etc/uci-defaults/99-luci-lan-only

# IPK 自动安装功能
cat > files/etc/uci-defaults/99-custom-packages << 'EOF'
#!/bin/sh

# 等待网络就绪
sleep 30

# 安装自定义 IPK 包
if [ -d "/packages" ]; then
    for ipk in /packages/*.ipk; do
        if [ -f "$ipk" ]; then
            echo "正在安装 $ipk..."
            opkg install "$ipk" || echo "安装 $ipk 失败"
        fi
    done
fi

# 清理安装包
rm -rf /packages

# 重启服务
/etc/init.d/uhttpd restart 2>/dev/null

exit 0
EOF
chmod +x files/etc/uci-defaults/99-custom-packages

# 复制自定义 IPK 包到固件中
if [ -d "../../files/packages" ]; then
    echo "复制自定义 IPK 包到固件..."
    mkdir -p files/packages
    cp -r ../../files/packages/*.ipk files/packages/ 2>/dev/null || true
fi

# 设置主机名
echo "WNDR3800" > files/etc/hostname

echo "自定义配置完成"
