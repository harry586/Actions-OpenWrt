#!/bin/bash

# OpenWrt DIY 脚本第一部分 - 在更新feeds之前执行

# 更新并安装 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 添加自定义包目录（如果有）
if [ -d "../../files/packages" ]; then
    echo "找到自定义包目录..."
    mkdir -p package/custom
    # 这里可以添加自定义包的编译逻辑
fi

echo "Feeds 更新完成"
