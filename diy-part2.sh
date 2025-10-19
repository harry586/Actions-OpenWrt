#!/bin/bash

# OpenWrt DIY 脚本第二部分 - 添加内存释放和备份配置

echo "开始应用自定义配置..."

# 1. 添加定时释放内存脚本
echo "添加内存释放配置..."
mkdir -p files/etc/crontabs
mkdir -p files/usr/bin

# 创建内存释放脚本
cat > files/usr/bin/freemem << 'EOF'
#!/bin/sh
# 内存释放脚本
sync
echo 1 > /proc/sys/vm/drop_caches
echo 2 > /proc/sys/vm/drop_caches
echo 3 > /proc/sys/vm/drop_caches
logger "内存缓存已清理"
EOF
chmod +x files/usr/bin/freemem

# 添加到定时任务（每天凌晨3点释放内存）
echo "0 3 * * * /usr/bin/freemem" >> files/etc/crontabs/root

# 2. 创建自定义备份脚本（只备份/overlay）
mkdir -p files/etc/hotplug.d/block
cat > files/etc/backup-overlay.sh << 'EOF'
#!/bin/sh
# 只备份/overlay分区的配置

BACKUP_DEVICE="$1"
BACKUP_MOUNT="/mnt/backup"
BACKUP_FILE="openwrt-overlay-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

[ -z "$BACKUP_DEVICE" ] && exit 1

# 挂载备份设备
mkdir -p "$BACKUP_MOUNT"
mount "$BACKUP_DEVICE" "$BACKUP_MOUNT" || exit 1

# 创建备份
tar -czf "$BACKUP_MOUNT/$BACKUP_FILE" -C /overlay . 

# 卸载设备
umount "$BACKUP_MOUNT"
rmdir "$BACKUP_MOUNT"

logger "Overlay配置已备份到: $BACKUP_FILE"
EOF
chmod +x files/etc/backup-overlay.sh

# 3. 创建自定义升级脚本（只恢复/overlay）
cat > files/etc/restore-overlay.sh << 'EOF'
#!/bin/sh
# 只恢复/overlay分区的配置

RESTORE_DEVICE="$1"
RESTORE_FILE="$2"
RESTORE_MOUNT="/mnt/restore"

[ -z "$RESTORE_DEVICE" ] || [ -z "$RESTORE_FILE" ] && {
    echo "用法: $0 <设备> <备份文件>"
    exit 1
}

# 挂载恢复设备
mkdir -p "$RESTORE_MOUNT"
mount "$RESTORE_DEVICE" "$RESTORE_MOUNT" || exit 1

# 检查备份文件是否存在
[ ! -f "$RESTORE_MOUNT/$RESTORE_FILE" ] && {
    echo "备份文件不存在: $RESTORE_FILE"
    umount "$RESTORE_MOUNT"
    exit 1
}

# 停止服务
/etc/init.d/uhttpd stop
/etc/init.d/firewall stop
/etc/init.d/dnsmasq stop
sleep 2

# 恢复备份
tar -xzf "$RESTORE_MOUNT/$RESTORE_FILE" -C /overlay

# 卸载设备
umount "$RESTORE_MOUNT"
rmdir "$RESTORE_MOUNT"

# 重启服务
/etc/init.d/dnsmasq start
/etc/init.d/firewall start
/etc/init.d/uhttpd start

logger "Overlay配置已从 $RESTORE_FILE 恢复"
EOF
chmod +x files/etc/restore-overlay.sh

# 4. 创建LuCI备份页面配置
mkdir -p files/etc/config
cat > files/etc/config/backup << 'EOF'
config overlay_backup
    option enabled '1'
    option backup_path '/mnt/backup'
    option include_overlay '1'
    option exclude_root '1'
EOF

# 5. IPK 自动安装功能
cat > files/etc/uci-defaults/99-custom-packages << 'EOF'
#!/bin/sh

# 等待网络就绪
sleep 20

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

# 启用cron服务
/etc/init.d/cron enable
/etc/init.d/cron start

exit 0
EOF
chmod +x files/etc/uci-defaults/99-custom-packages

# 6. 复制自定义 IPK 包到固件中
if [ -d "../../files/packages" ]; then
    echo "复制自定义 IPK 包到固件..."
    mkdir -p files/packages
    cp -r ../../files/packages/*.ipk files/packages/ 2>/dev/null || true
fi

echo "自定义配置完成"
