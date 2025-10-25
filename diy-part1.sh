#!/bin/bash
# =============================================
# ImmortalWrt DIY 脚本第一部分
# 功能：更新feeds，设置基础环境，集成自定义包
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

# 更新 feeds
echo "更新并安装 feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

# 添加自定义包目录（GitHub files/packages）
echo "检查自定义包目录..."
if [ -d "../../files/packages" ]; then
    echo "找到自定义包目录，准备集成..."
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
fi

# 清理可能存在的DDNS残留
echo "清理DDNS相关残留..."
find . -name "*ddns*" -type d | head -10 | while read dir; do
    if [ -d "$dir" ]; then
        echo "发现DDNS目录: $dir"
        rm -rf "$dir" 2>/dev/null || true
    fi
done

# 清理其他排除的组件
echo "清理排除的组件..."
find . -name "*nlbwmon*" -type d | head -5 | while read dir; do
    [ -d "$dir" ] && rm -rf "$dir" 2>/dev/null || true
done

find . -name "*wol*" -type d | head -5 | while read dir; do
    [ -d "$dir" ] && rm -rf "$dir" 2>/dev/null || true
done

echo "DIY 脚本第一部分执行完成！"
