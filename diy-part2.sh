#!/bin/bash

# 修改 root 密码 - 使用正确的密码哈希
# 修复：使用正确的密码设置方法
PASSWORD_HASH=$(echo -e "harry586586\nharry586586" | openssl passwd -1 -stdin)
sed -i "s|root::0:0:99999:7:::|root:${PASSWORD_HASH}:0:0:99999:7:::|g" package/base-files/files/etc/shadow

# 修改主机名为 WNDR3800
sed -i 's/OpenWrt/WNDR3800/g' package/base-files/files/bin/config_generate
sed -i 's/openwrt/WNDR3800/g' package/base-files/files/bin/config_generate

# 修复：修改 WiFi 设置 - 使用更安全的方法
# 修改 2.4GHz WiFi 配置
sed -i 's/set wireless\.radio\${devidx}\.ssid=.*/set wireless.radio\${devidx}.ssid=WNDR3800_2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
sed -i 's/set wireless\.radio\${devidx}\.encryption=.*/set wireless.radio\${devidx}.encryption=psk2/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
sed -i 's/set wireless\.\${name}\.key=.*/set wireless.\${name}.key=harry586586/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh

# 修复：添加 5GHz WiFi 配置（如果设备支持）
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
set wireless.wifinet2.encryption='psk2'
set wireless.wifinet2.key='harry586586'
EOI
}
EOF

# 修复：限制 LuCI 仅 LAN 访问 - 使用正确的方法
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-luci-lan-only << 'EOF'
#!/bin/sh

# 限制 LuCI 仅 LAN 访问
uci set uhttpd.main.listen_http='0.0.0.0:80'
uci set uhttpd.main.listen_https='0.0.0.0:443'
uci set uhttpd.main.rfc1918_filter='1'
uci commit uhttpd

# 设置防火墙规则，仅允许 LAN 访问
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-LAN-LuCI'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='80 443'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall

exit 0
EOF

chmod +x files/etc/uci-defaults/99-luci-lan-only

# 修复：创建开机自动安装脚本 - 使用正确的方法
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

# 修复：复制自定义 IPK 包到固件中 - 使用正确的路径
if [ -d "../../files/packages" ]; then
    echo "复制自定义 IPK 包到固件..."
    mkdir -p files/packages
    cp -r ../../files/packages/*.ipk files/packages/ 2>/dev/null || true
fi

# 设置主机名
echo "WNDR3800" > files/etc/hostname

# 修复：创建网络配置
cat > files/etc/config/network << 'EOF'
config interface 'loopback'
    option ifname 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config globals 'globals'
    option ula_prefix 'fd4e:8d25:12b6::/48'

config interface 'lan'
    option type 'bridge'
    option ifname 'eth0'
    option proto 'static'
    option ipaddr '192.168.1.1'
    option netmask '255.255.255.0'
    option ip6assign '60'

config interface 'wan'
    option ifname 'eth1'
    option proto 'dhcp'

config interface 'wan6'
    option ifname 'eth1'
    option proto 'dhcpv6'
EOF

echo "自定义配置完成"
