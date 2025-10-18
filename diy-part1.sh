#!/bin/bash

# 更换为 coolsnowwolf/lede 源码
sed -i 's/P3TERX\/Actions-OpenWrt/coolsnowwolf\/lede/g' .config
sed -i 's/^# CONFIG_TARGET_ar71xx is not set/CONFIG_TARGET_ar71xx=y/g' .config
sed -i 's/^CONFIG_TARGET_x86=y/# CONFIG_TARGET_x86 is not set/g' .config

# 添加自定义软件源
echo "src/gz custom_packages file://packages" >> feeds.conf.default

# 更新并安装 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 添加自定义包到编译系统
if [ -d "../files/packages" ]; then
    mkdir -p package/custom
    cp -r ../files/packages/* package/custom/ 2>/dev/null || true
fi
