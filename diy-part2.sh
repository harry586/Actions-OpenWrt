#!/bin/bash

# OpenWrt DIY 脚本第二部分 - 专注修复root密码和无线配置

echo "开始应用自定义配置..."

# 1. 修复 root 密码 - 使用简单可靠的方法
echo "设置 root 密码..."
# 直接修改base-files中的shadow模板
sed -i 's/root::0:0:99999:7:::/root:$1$V5h3l.6d$Pz8Rq6k4F1d9E0V5h3l.6:0:0:99999:7:::/g' package/base-files/files/etc/shadow

# 2. 修改主机名
echo "设置主机名..."
sed -i 's/OpenWrt/WNDR3800/g' package/base-files/files/bin/config_generate
sed -i 's/openwrt/wndr3800/g' package/base-files/files/bin/config_generate
mkdir -p files/etc
echo "WNDR3800" > files/etc/hostname

# 3. 修复无线配置 - 使用WNDR3800正确的配置
echo "配置无线网络..."
mkdir -p files/etc/uci-defaults

# 创建无线配置脚本
cat > files/etc/uci-defaults/30-wndr3800-wifi << 'EOF'
#!/bin/sh

echo "配置 WNDR3800 无线..."

# 删除默认无线配置
uci delete wireless.radio0 >/dev/null 2>&1
uci delete wireless.default_radio0 >/dev/null 2>&1

# WNDR3800 2.4GHz 无线配置
uci set wireless.radio0=wifi-device
uci set wireless.radio0.type='mac80211'
uci set wireless.radio0.channel='6'
uci set wireless.radio0.hwmode='11g'
uci set wireless.radio0.path='pci0000:00/0000:00:00.0'
uci set wireless.radio0.htmode='HT20'
uci set wireless.radio0.txpower='20'
uci set wireless.radio0.country='US'
uci set wireless.radio0.disabled='0'

uci set wireless.default_radio0=wifi-iface  
uci set wireless.default_radio0.device='radio0'
uci set wireless.default_radio0.network='lan'
uci set wireless.default_radio0.mode='ap'
uci set wireless.default_radio0.ssid='WNDR3800_2.4G'
uci set wireless.default_radio0.encryption='none'

# WNDR3800 5GHz 无线配置（设备支持双频）
uci set wireless.radio1=wifi-device
uci set wireless.radio1.type='mac80211'
uci set wireless.radio1.channel='36'
uci set wireless.radio1.hwmode='11a'
uci set wireless.radio1.path='pci0000:00/0000:00:00.0+1'
uci set wireless.radio1.htmode='VHT80'
uci set wireless.radio1.txpower='20'
uci set wireless.radio1.country='US'
uci set wireless.radio1.disabled='0'

uci set wireless.default_radio1=wifi-iface
uci set wireless.default_radio1.device='radio1'
uci set wireless.default_radio1.network='lan'
uci set wireless.default_radio1.mode='ap'
uci set wireless.default_radio1.ssid='WNDR3800_5G'
uci set wireless.default_radio1.encryption='none'

# 提交无线配置
uci commit wireless

echo "无线配置完成"
exit 0
EOF
chmod +x files/etc/uci-defaults/30-wndr3800-wifi

# 4. 创建root密码验证脚本
cat > files/etc/uci-defaults/10-root-password << 'EOF'
#!/bin/sh

echo "验证root密码设置..."

# 检查shadow文件中的root密码
if grep -q 'root::' /etc/shadow; then
    echo "检测到root密码未设置，正在设置..."
    echo 'root:$1$V5h3l.6d$Pz8Rq6k4F1d9E0V5h3l.6:0:0:99999:7:::' > /etc/shadow.tmp
    cat /etc/shadow | grep -v '^root:' >> /etc/shadow.tmp
    mv /etc/shadow.tmp /etc/shadow
    echo "root密码已设置"
else
    echo "root密码已正确设置"
fi

exit 0
EOF
chmod +x files/etc/uci-defaults/10-root-password

# 5. IPK 自动安装功能
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

# 6. 复制 IPK 包
if [ -d "../../files/packages" ]; then
    echo "复制自定义 IPK 包..."
    mkdir -p files/packages
    cp ../../files/packages/*.ipk files/packages/ 2>/dev/null || true
fi

echo "自定义配置完成"
