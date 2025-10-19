#!/bin/bash

# OpenWrt DIY 脚本第二部分 - 在配置之后执行

# 修改 root 密码 - 使用更可靠的方法
echo "修改 root 密码..."
cat > package/base-files/files/etc/shadow << 'EOF'
root:$1$harry586$V5h3l.6dPz8Rq6k4F1d9E0:19689:0:99999:7:::
daemon:*:0:0:99999:7:::
ftp:*:0:0:99999:7:::
network:*:0:0:99999:7:::
nobody:*:0:0:99999:7:::
EOF

# 修改主机名 - 使用更彻底的方法
echo "修改主机名..."
sed -i 's/OpenWrt/WNDR3800/g' package/base-files/files/bin/config_generate
sed -i 's/openwrt/wndr3800/g' package/base-files/files/bin/config_generate

# 创建 hostname 文件
mkdir -p files/etc
echo "WNDR3800" > files/etc/hostname

# 修改系统提示符
sed -i 's/OpenWrt/WNDR3800/g' package/base-files/files/etc/banner

# 修改 WiFi 设置 - 使用更彻底的方法
echo "修改 WiFi 设置..."
# 备份原文件
cp package/kernel/mac80211/files/lib/wifi/mac80211.sh package/kernel/mac80211/files/lib/wifi/mac80211.sh.backup

# 完全重写无线配置部分
cat > package/kernel/mac80211/files/lib/wifi/mac80211.sh << 'EOF'
#!/bin/sh
. /lib/functions.sh
. /lib/functions/system.sh

get_phy_type() {
	local phy="$1"
	[ -n "$phy" ] || return
	iwinfo "$phy" info 2>/dev/null | grep -q '802.11' || return
	iwinfo "$phy" info | grep type | cut -d\" -f2
}

get_phy_info() {
	local phy="$1"
	[ -n "$phy" ] || return
	iwinfo "$phy" info
}

ucidef_set_interface_loopback() {
	uci batch <<EOF
set network.loopback='interface'
set network.loopback.ifname='lo'
set network.loopback.proto='static'
set network.loopback.ipaddr='127.0.0.1'
set network.loopback.netmask='255.0.0.0'
set network.loopback.ip6assign='128'
EOF
}

ucidef_set_interface_raw() {
	local cfg=$1
	local ifname=$2

	uci batch <<EOF
set network.$cfg='interface'
set network.$cfg.ifname="$ifname"
set network.$cfg.proto='none'
set network.$cfg.auto='1'
EOF
}

ucidef_set_interface_lan() {
	local ifname=$1

	uci batch <<EOF
set network.lan='interface'
set network.lan.type='bridge'
set network.lan.ifname='$ifname'
set network.lan.proto='static'
set network.lan.ipaddr='192.168.1.1'
set network.lan.netmask='255.255.255.0'
set network.lan.ip6assign='60'
EOF
}

ucidef_set_interface_wan() {
	local ifname=$1

	uci batch <<EOF
set network.wan='interface'
set network.wan.ifname='$ifname'
set network.wan.proto='dhcp'
set network.wan.ip6assign='60'
EOF
}

ucidef_add_switch() {
	local name="$1"
	local reset="$2"
	local enable="$3"
	uci batch <<EOF
add network switch
set network.@switch[-1].name='$name'
set network.@switch[-1].reset='$reset'
set network.@switch[-1].enable_vlan='$enable'
EOF
}

ucidef_add_switch_vlan() {
	local device="$1"
	local vlan="$2"
	local ports="$3"
	uci batch <<EOF
add network switch_vlan
set network.@switch_vlan[-1].device='$device'
set network.@switch_vlan[-1].vlan='$vlan'
set network.@switch_vlan[-1].ports='$ports'
EOF
}

wndr3800_prepare_config() {
    # 设置无线配置
    uci -q batch << EOI
delete wireless.radio0
set wireless.radio0=wifi-device
set wireless.radio0.type='mac80211'
set wireless.radio0.path='pci0000:00/0000:00:00.0'
set wireless.radio0.channel='6'
set wireless.radio0.band='2g'
set wireless.radio0.hwmode='11g'
set wireless.radio0.htmode='HT20'
set wireless.radio0.country='US'
set wireless.radio0.txpower='20'
set wireless.radio0.disabled='0'

delete wireless.@wifi-iface[0]
add wireless wifi-iface
set wireless.@wifi-iface[-1].device='radio0'
set wireless.@wifi-iface[-1].network='lan'
set wireless.@wifi-iface[-1].mode='ap'
set wireless.@wifi-iface[-1].ssid='WNDR3800_2.4G'
set wireless.@wifi-iface[-1].encryption='none'
set wireless.@wifi-iface[-1].key=''

# 5GHz 配置（即使设备不支持也设置）
delete wireless.radio1
set wireless.radio1=wifi-device
set wireless.radio1.type='mac80211'
set wireless.radio1.path='pci0000:00/0000:00:00.0+1'
set wireless.radio1.channel='36'
set wireless.radio1.band='5g'
set wireless.radio1.hwmode='11a'
set wireless.radio1.htmode='VHT80'
set wireless.radio1.country='US'
set wireless.radio1.txpower='20'
set wireless.radio1.disabled='0'

add wireless wifi-iface
set wireless.@wifi-iface[-1].device='radio1'
set wireless.@wifi-iface[-1].network='lan'
set wireless.@wifi-iface[-1].mode='ap'
set wireless.@wifi-iface[-1].ssid='WNDR3800_5G'
set wireless.@wifi-iface[-1].encryption='none'
set wireless.@wifi-iface[-1].key=''
EOI
}

board_config_update() {
    wndr3800_prepare_config
}

EOF

# 创建强制应用配置的脚本
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/10-custom-config << 'EOF'
#!/bin/sh

# 强制设置主机名
uci set system.@system[0].hostname='WNDR3800'
echo 'WNDR3800' > /proc/sys/kernel/hostname

# 强制设置 root 密码（如果shadow文件没生效）
echo 'root:$1$harry586$V5h3l.6dPz8Rq6k4F1d9E0:19689:0:99999:7:::' > /etc/shadow

# 强制应用无线配置
uci set wireless.radio0.channel='6'
uci set wireless.radio0.disabled='0'
uci set wireless.@wifi-iface[0].ssid='WNDR3800_2.4G'
uci set wireless.@wifi-iface[0].encryption='none'
uci set wireless.@wifi-iface[0].key=''

# 提交所有更改
uci commit system
uci commit wireless
/etc/init.d/system restart
/etc/init.d/network restart
wifi reload

exit 0
EOF
chmod +x files/etc/uci-defaults/10-custom-config

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

echo "自定义配置完成"
