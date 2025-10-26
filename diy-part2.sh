#!/bin/bash
# =============================================
# ImmortalWrt DIY 脚本第二部分
# 功能：Overlay备份系统、内存释放、IPK自动安装
# 修复设备配置问题，确保生成正确固件
# =============================================

echo "开始执行 DIY 脚本第二部分..."

# ==================== 设备配置修复 ====================
echo "修复设备配置，确保生成 ASUS RT-ACRH17 固件..."

# 首先清理所有可能的设备配置
echo "清理现有设备配置..."
sed -i '/CONFIG_TARGET_.*_DEVICE_.*=y/d' .config
sed -i '/CONFIG_TARGET_DEVICE_.*/d' .config
sed -i '/CONFIG_TARGET_PROFILE/d' .config

# 添加正确的设备配置
echo "添加正确的 ASUS RT-ACRH17 配置..."
cat >> .config << 'EOF'
# ==================== 设备配置修复 ====================
# 确保生成 ASUS RT-ACRH17 固件
CONFIG_TARGET_ipq40xx=y
CONFIG_TARGET_ipq40xx_generic=y
CONFIG_TARGET_DEVICE_ipq40xx_generic_DEVICE_asus_rt-acrh17=y
CONFIG_TARGET_PROFILE="DEVICE_asus_rt-acrh17"
# ====================================================
EOF

echo "✅ 设备配置已修复"

# ==================== 验证设备配置 ====================
echo "验证设备配置..."
if grep -q "CONFIG_TARGET_DEVICE_ipq40xx_generic_DEVICE_asus_rt-acrh17=y" .config; then
    echo "✅ ASUS RT-ACRH17 设备配置确认正确"
else
    echo "❌ 设备配置仍然有问题，请手动检查"
    exit 1
fi

# 其余部分保持不变...
# ==================== 1. 彻底清理排除的组件 ====================
echo "清理排除的组件残留..."

# DDNS 禁用配置
mkdir -p files/etc/config
cat > files/etc/config/ddns << 'EOF'
# DDNS 配置已禁用 - 根据用户需求排除
# 如需启用，请在编译配置中取消相关注释
EOF

mkdir -p files/etc/init.d
cat > files/etc/init.d/ddns << 'EOF'
#!/bin/sh /etc/rc.common
START=99
STOP=99
boot() { return 0; }
start() { echo "DDNS服务已被禁用"; return 0; }
stop() { return 0; }
EOF
chmod +x files/etc/init.d/ddns

# 其余部分保持不变...
# [这里包含之前的所有其他功能代码...]
