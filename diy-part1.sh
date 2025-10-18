#!/bin/bash

# 修复：删除对不存在的 .config 文件的修改操作
# 更换为 coolsnowwolf/lede 源码（已在 workflow 中设置，这里不需要重复操作）

# 修复 feeds.conf.default 语法错误 - 使用正确的格式添加自定义源
echo "src-git custom_packages https://github.com/$(git config --get remote.origin.url | sed 's|https://github.com/||' | sed 's|\.git||')/tree/main/files/packages" >> feeds.conf.default

# 更新并安装 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 修复：添加自定义包到编译系统 - 使用正确的相对路径
if [ -d "../../files/packages" ]; then
    echo "找到自定义包目录，正在复制..."
    mkdir -p package/custom
    find ../../files/packages -name "*.ipk" -exec cp {} package/custom/ \; 2>/dev/null || true
fi

# 修复：确保 feeds 配置正确
if [ -f feeds.conf.default ]; then
    # 移除可能存在的语法错误行
    sed -i '/^src-gz.*file:\/\/packages/d' feeds.conf.default
fi
