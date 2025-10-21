#!/bin/bash
# =============================================
# OpenWrt DIY 脚本第一部分 - 修复版本
# 功能：更新feeds，确保基础环境
# =============================================

echo "开始执行 DIY 脚本第一部分..."

# 更新系统包列表
echo "更新系统包列表..."
sudo apt-get update -qq

# 安装必要的编译工具
echo "安装编译工具..."
sudo apt-get install -y -qq build-essential clang flex g++ gawk gcc-multilib \
gettext git libncurses5-dev libssl-dev python3 python3-distutils rsync \
unzip zlib1g-dev file wget

# 更新 feeds
echo "更新并安装 feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

# 添加自定义包目录
if [ -d "../../files/packages" ]; then
    echo "找到自定义包目录，准备集成..."
    mkdir -p package/custom
    cp -r ../../files/packages/* package/custom/ 2>/dev/null || true
fi

# 清理可能存在的DDNS残留
echo "清理DDNS相关残留..."
find . -name "*ddns*" -type d | head -5 | while read dir; do
    if [ -d "$dir" ]; then
        echo "发现DDNS目录: $dir"
    fi
done

echo "DIY 脚本第一部分执行完成！"
