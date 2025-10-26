#!/bin/bash
# =============================================
# ImmortalWrt DIY 脚本第一部分
# 功能：更新feeds，设置基础环境，集成自定义包
# 修复设备检测问题，支持 ASUS RT-AC42U
# =============================================

echo "开始执行 DIY 脚本第一部分..."

# 设置编译环境变量
export FORCE_UNSAFE_CONFIGURE=1

# 更新系统包列表
echo "更新系统包列表..."
sudo apt-get update -qq

# 安装必要的编译工具
echo "安装编译工具..."
sudo apt-get install -y -qq build-essential clang flex g++ gawk gcc-multilib \
gettext git libncurses5-dev libssl-dev python3 python3-distutils rsync \
unzip zlib1g-dev file wget

# 切换到 ImmortalWrt 主分支并更新
echo "更新 ImmortalWrt 源码..."
git pull origin master

# 修复设备支持检查 - ASUS RT-AC42U
echo "检查设备支持..."
if [ -d "target/linux/ipq40xx" ]; then
    echo "✅ 找到 ipq40xx 目标平台"
    
    # 检查 ASUS RT-AC42U 设备定义
    if [ -f "target/linux/ipq40xx/image/generic.mk" ]; then
        echo "检查 generic.mk 中的设备定义..."
        if grep -q "asus,rt-ac42u" target/linux/ipq40xx/image/generic.mk; then
            echo "✅ ASUS RT-AC42U 设备定义存在"
        else
            echo "⚠️  未找到 ASUS RT-AC42U 设备定义，检查其他位置..."
            # 检查设备树文件
            if [ -f "target/linux/ipq40xx/files/arch/arm/boot/dts/qcom-ipq4019-rt-ac42u.dts" ]; then
                echo "✅ 找到 ASUS RT-AC42U 设备树文件: qcom-ipq4019-rt-ac42u.dts"
            else
                echo "❌ 未找到 ASUS RT-AC42U 设备树文件"
            fi
        fi
    fi
else
    echo "❌ 未找到 ipq40xx 目标平台，请检查源码"
    exit 1
fi

# 更新 feeds
echo "更新并安装 feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

# 添加自定义包目录（GitHub files/packages）
echo "检查自定义包目录..."
if [ -d "../../files/packages" ]; then
    echo "✅ 找到自定义包目录，准备集成..."
    mkdir -p package/custom
    cp -rf ../../files/packages/* package/custom/ 2>/dev/null || true
    
    # 为每个自定义包创建索引
    if [ -d "package/custom" ]; then
        echo "集成自定义包到 feeds..."
        for pkg in package/custom/*; do
            if [ -d "$pkg" ]; then
                echo "添加包: $(basename $pkg)"
                ./scripts/feeds install -p custom $(basename $pkg) 2>/dev/null || true
            fi
        done
    fi
else
    echo "ℹ️  未找到自定义包目录，跳过"
fi

# 清理排除的组件 - 根据要求排除DDNS、带宽监控、网络唤醒
echo "清理排除的组件..."

# 清理DDNS相关残留
echo "清理DDNS相关组件..."
find . -name "*ddns*" -type d | head -10 | while read dir; do
    if [ -d "$dir" ]; then
        echo "移除DDNS目录: $dir"
        rm -rf "$dir" 2>/dev/null || true
    fi
done

# 清理带宽监控
echo "清理带宽监控组件..."
find . -name "*nlbwmon*" -type d | head -5 | while read dir; do
    [ -d "$dir" ] && rm -rf "$dir" 2>/dev/null || true
done

# 清理网络唤醒
echo "清理网络唤醒组件..."
find . -name "*wol*" -type d | head -5 | while read dir; do
    [ -d "$dir" ] && rm -rf "$dir" 2>/dev/null || true
done

# 确保所需组件存在
echo "检查所需组件..."
REQUIRED_PACKAGES=(
    "luci-app-arpbind"
    "luci-app-cpulimit" 
    "luci-app-diskman"
    "luci-app-eqosplus"
    "luci-app-hd-idle"
    "luci-app-parentcontrol"
    "luci-app-samba4"
    "luci-app-wechatpush"
    "luci-app-smartdns"
    "luci-app-turboacc"
    "luci-app-vlmcsd"
    "luci-app-vsftpd"
    "luci-app-ttyd"
    "luci-app-sqm-autorate"
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ./scripts/feeds list | grep -q "$pkg"; then
        echo "✅ 找到所需包: $pkg"
        ./scripts/feeds install "$pkg" 2>/dev/null || true
    else
        echo "⚠️  未找到包: $pkg"
    fi
done

echo "✅ DIY 脚本第一部分执行完成！"
