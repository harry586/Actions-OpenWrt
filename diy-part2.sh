#!/bin/bash
# =============================================
# OpenWrt DIY 脚本第二部分 - 最终修复版本
# 修复内容：
# 1. Overlay备份界面优化 - 按钮大小调整，列表内恢复按钮
# 2. USB自动挂载彻底修复
# =============================================

echo "开始应用 WNDR3800 最终修复配置..."

# ==================== 1. 彻底清理DDNS残留 ====================
echo "清理DDNS相关组件..."
mkdir -p files/etc/config
cat > files/etc/config/ddns << 'EOF'
# DDNS 配置已禁用
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

# ==================== 2. 内存释放功能 ====================
echo "配置定时内存释放..."
mkdir -p files/etc/crontabs
mkdir -p files/usr/bin

cat > files/usr/bin/freemem << 'EOF'
#!/bin/sh
sync
echo 1 > /proc/sys/vm/drop_caches
echo 2 > /proc/sys/vm/drop_caches  
echo 3 > /proc/sys/vm/drop_caches
logger "定时内存缓存清理完成"
EOF
chmod +x files/usr/bin/freemem

echo "0 3 * * * /usr/bin/freemem" >> files/etc/crontabs/root

# ==================== 3. 优化的Overlay备份系统 ====================
echo "创建优化的Overlay备份系统..."

mkdir -p files/usr/lib/lua/luci/controller/admin
mkdir -p files/usr/lib/lua/luci/view/admin_system
mkdir -p files/usr/bin

# 创建优化的控制器
cat > files/usr/lib/lua/luci/controller/admin/overlay-backup.lua << 'EOF'
module("luci.controller.admin.overlay-backup", package.seeall)

function index()
    entry({"admin", "system", "overlay-backup"}, template("admin_system/overlay_backup"), _("Overlay Backup"), 80)
    entry({"admin", "system", "overlay-backup", "create"}, call("create_backup")).leaf = true
    entry({"admin", "system", "overlay-backup", "restore"}, call("restore_backup")).leaf = true
    entry({"admin", "system", "overlay-backup", "download"}, call("download_backup")).leaf = true
    entry({"admin", "system", "overlay-backup", "delete"}, call("delete_backup")).leaf = true
    entry({"admin", "system", "overlay-backup", "list"}, call("list_backups")).leaf = true
end

function create_backup()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/bin/overlay-backup backup 2>&1")
    
    if result:match("备份成功") then
        http.prepare_content("application/json")
        http.write_json({success = true, message = result, filename = result:match("备份文件: ([^\n]+)")})
    else
        http.prepare_content("application/json")
        http.write_json({success = false, message = result})
    end
end

function restore_backup()
    local http = require "luci.http"
    local sys = require "luci.sys"
    local fs = require "nixio.fs"
    
    local filename = http.formvalue("filename")
    if not filename or filename == "" then
        http.prepare_content("application/json")
        http.write_json({success = false, message = "未选择备份文件"})
        return
    end
    
    local filepath = "/tmp/" .. filename
    if not fs.stat(filepath) then
        filepath = filename
    end
    
    if not fs.stat(filepath) then
        http.prepare_content("application/json")
        http.write_json({success = false, message = "备份文件不存在: " .. filename})
        return
    end
    
    local result = sys.exec("/usr/bin/overlay-backup restore '" .. filepath .. "' 2>&1")
    
    if result:match("恢复成功") then
        http.prepare_content("application/json")
        http.write_json({success = true, message = result})
    else
        http.prepare_content("application/json")
        http.write_json({success = false, message = result})
    end
end

function download_backup()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    local file = http.formvalue("file")
    
    if file and fs.stat(file) then
        http.header('Content-Disposition', 'attachment; filename="' .. fs.basename(file) .. '"')
        http.header('Content-Type', 'application/octet-stream')
        local f = io.open(file, "rb")
        if f then
            http.write(f:read("*a"))
            f:close()
            return
        end
    end
    http.status(404, "File not found")
end

function delete_backup()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    local file = http.formvalue("file")
    
    if file and fs.stat(file) then
        fs.unlink(file)
        http.prepare_content("application/json")
        http.write_json({success = true, message = "备份文件已删除"})
    else
        http.prepare_content("application/json")
        http.write_json({success = false, message = "文件不存在"})
    end
end

function list_backups()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    local backups = {}
    
    if fs.stat("/tmp") then
        for file in fs.dir("/tmp") do
            if file:match("backup%-.*%.tar%.gz") then
                local path = "/tmp/" .. file
                local stat = fs.stat(path)
                if stat then
                    table.insert(backups, {
                        name = file,
                        path = path,
                        size = stat.size,
                        mtime = stat.mtime,
                        formatted_time = os.date("%Y-%m-%d %H:%M:%S", stat.mtime)
                    })
                end
            end
        end
    end
    
    table.sort(backups, function(a, b) return a.mtime > b.mtime end)
    
    http.prepare_content("application/json")
    http.write_json(backups)
end
EOF

# 创建优化的Web界面模板 - 修复按钮大小和添加列表内恢复按钮
cat > files/usr/lib/lua/luci/view/admin_system/overlay_backup.htm << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:Overlay Backup%></h2>
    
    <div class="alert-message success" style="background: #d4edda; color: #155724; border: 1px solid #c3e6cb; padding: 15px; margin-bottom: 20px;">
        <h4 style="margin: 0 0 10px 0; color: #155724;">✅ 优化的Overlay备份系统</h4>
        <ul style="margin: 0; padding-left: 20px;">
            <li>每个备份文件旁边都有<strong>恢复按钮</strong>，一键恢复</li>
            <li>按钮大小优化，界面更协调</li>
            <li>恢复成功后<strong>明确提示</strong>，无需猜测</li>
            <li>详细的文件信息，方便选择</li>
        </ul>
    </div>
    
    <div class="cbi-section">
        <h3><%:备份操作%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title"><%:快速操作%></label>
            <div class="cbi-value-field">
                <button id="create-backup" class="cbi-button cbi-button-apply" style="min-width: 120px; padding: 5px 10px;">
                    ➕ <%:创建备份%>
                </button>
                <button id="refresh-list" class="cbi-button cbi-button-action" style="min-width: 80px; padding: 5px 10px; margin-left: 5px;">
                    🔄 <%:刷新%>
                </button>
            </div>
        </div>
    </div>

    <!-- 操作状态显示 -->
    <div id="status-message" style="margin: 15px 0;"></div>

    <!-- 备份文件列表 -->
    <div class="cbi-section">
        <h3><%:备份文件列表%> <small style="color: #666;">(保存在 /tmp 目录，重启后丢失)</small></h3>
        <div class="table" id="backup-table" style="min-height: 100px;">
            <div class="table-titles">
                <div class="table-cell" style="width: 30%;"><%:文件名%></div>
                <div class="table-cell" style="width: 12%;"><%:大小%></div>
                <div class="table-cell" style="width: 20%;"><%:备份时间%></div>
                <div class="table-cell" style="width: 28%;"><%:操作%></div>
            </div>
            <div class="table-row" id="no-backups" style="display: none;">
                <div class="table-cell" colspan="4" style="text-align: center; padding: 30px; color: #999;">
                    <%:暂无备份文件，点击"创建备份"按钮生成第一个备份%>
                </div>
            </div>
        </div>
    </div>

    <!-- 恢复确认对话框 -->
    <div id="restore-confirm" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 1000;">
        <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; padding: 20px; border-radius: 5px; min-width: 400px;">
            <h3 style="margin-top: 0; color: #d32f2f;">⚠️ 警告：恢复操作</h3>
            <p>您即将恢复备份文件：<strong id="confirm-filename"></strong></p>
            <p style="color: #d32f2f; font-weight: bold;">此操作将覆盖当前的所有配置！</p>
            <p>请输入 <strong>CONFIRM</strong> 确认恢复：</p>
            <input type="text" id="confirm-input" style="width: 100%; padding: 8px; margin: 10px 0; border: 1px solid #ccc; border-radius: 3px;">
            <div style="text-align: right; margin-top: 15px;">
                <button id="confirm-cancel" class="cbi-button cbi-button-reset" style="padding: 5px 15px;">取消</button>
                <button id="confirm-restore" class="cbi-button cbi-button-apply" style="padding: 5px 15px; margin-left: 10px;" disabled>确认恢复</button>
            </div>
        </div>
    </div>
</div>

<script>
// 全局变量
let currentRestoreFile = '';

// 加载备份文件列表
function loadBackupList() {
    fetch('<%=luci.dispatcher.build_url("admin/system/overlay-backup/list")%>')
        .then(response => response.json())
        .then(backups => {
            const table = document.getElementById('backup-table');
            const noBackups = document.getElementById('no-backups');
            
            // 清空表格内容（保留标题行和无备份提示）
            const rows = table.querySelectorAll('.table-row:not(.table-titles):not(#no-backups)');
            rows.forEach(row => row.remove());
            
            if (backups.length === 0) {
                noBackups.style.display = '';
                return;
            }
            
            noBackups.style.display = 'none';
            
            // 填充表格
            backups.forEach(backup => {
                const row = document.createElement('div');
                row.className = 'table-row';
                row.innerHTML = `
                    <div class="table-cell" style="width: 30%;">
                        <div style="font-weight: bold;">${backup.name}</div>
                        <div style="font-size: 11px; color: #666;">${backup.path}</div>
                    </div>
                    <div class="table-cell" style="width: 12%;">
                        <span style="font-family: monospace;">${formatFileSize(backup.size)}</span>
                    </div>
                    <div class="table-cell" style="width: 20%;">
                        <div>${backup.formatted_time}</div>
                    </div>
                    <div class="table-cell" style="width: 28%;">
                        <button class="cbi-button cbi-button-apply restore-btn" 
                                data-file="${backup.name}" 
                                style="padding: 3px 8px; margin-right: 3px; min-width: 60px;">
                            🔄 恢复
                        </button>
                        <button class="cbi-button cbi-button-action download-btn" 
                                data-file="${backup.path}" 
                                style="padding: 3px 8px; margin-right: 3px; min-width: 60px;">
                            📥 下载
                        </button>
                        <button class="cbi-button cbi-button-reset delete-btn" 
                                data-file="${backup.path}" 
                                data-name="${backup.name}" 
                                style="padding: 3px 8px; min-width: 60px;">
                            🗑️ 删除
                        </button>
                    </div>
                `;
                table.appendChild(row);
            });
            
            // 重新绑定事件
            bindTableEvents();
        })
        .catch(error => {
            showStatus('加载备份列表失败: ' + error, 'error');
        });
}

// 格式化文件大小
function formatFileSize(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

// 显示状态信息
function showStatus(message, type = 'info') {
    const statusDiv = document.getElementById('status-message');
    const className = type === 'error' ? 'alert-message error' : 
                     type === 'success' ? 'alert-message success' : 'alert-message info';
    
    statusDiv.innerHTML = `<div class="${className}">${message}</div>`;
    
    if (type === 'success' || type === 'error') {
        setTimeout(() => {
            statusDiv.innerHTML = '';
        }, 8000);
    }
}

// 绑定表格事件
function bindTableEvents() {
    // 恢复按钮
    document.querySelectorAll('.restore-btn').forEach(btn => {
        btn.addEventListener('click', function() {
            const filename = this.getAttribute('data-file');
            showRestoreConfirm(filename);
        });
    });
    
    // 下载按钮
    document.querySelectorAll('.download-btn').forEach(btn => {
        btn.addEventListener('click', function() {
            const file = this.getAttribute('data-file');
            window.location.href = '<%=luci.dispatcher.build_url("admin/system/overlay-backup/download")%>?file=' + encodeURIComponent(file);
        });
    });
    
    // 删除按钮
    document.querySelectorAll('.delete-btn').forEach(btn => {
        btn.addEventListener('click', function() {
            const file = this.getAttribute('data-file');
            const name = this.getAttribute('data-name');
            
            if (confirm('确定删除备份文件: ' + name + ' 吗？')) {
                fetch('<%=luci.dispatcher.build_url("admin/system/overlay-backup/delete")%>?file=' + encodeURIComponent(file))
                    .then(response => response.json())
                    .then(result => {
                        if (result.success) {
                            showStatus('✅ ' + result.message, 'success');
                            loadBackupList();
                        } else {
                            showStatus('❌ ' + result.message, 'error');
                        }
                    });
            }
        });
    });
}

// 显示恢复确认对话框
function showRestoreConfirm(filename) {
    currentRestoreFile = filename;
    document.getElementById('confirm-filename').textContent = filename;
    document.getElementById('confirm-input').value = '';
    document.getElementById('confirm-restore').disabled = true;
    document.getElementById('restore-confirm').style.display = 'block';
    
    // 聚焦输入框
    document.getElementById('confirm-input').focus();
}

// 隐藏恢复确认对话框
function hideRestoreConfirm() {
    document.getElementById('restore-confirm').style.display = 'none';
    currentRestoreFile = '';
}

// 执行恢复操作
function performRestore() {
    if (!currentRestoreFile) return;
    
    hideRestoreConfirm();
    showStatus('🔄 正在恢复备份，请稍候...', 'info');
    
    const formData = new FormData();
    formData.append('filename', currentRestoreFile);
    
    fetch('<%=luci.dispatcher.build_url("admin/system/overlay-backup/restore")%>', {
        method: 'POST',
        body: formData
    })
    .then(response => response.json())
    .then(result => {
        if (result.success) {
            showStatus('✅ ' + result.message + ' 建议重启路由器使更改生效。', 'success');
        } else {
            showStatus('❌ ' + result.message, 'error');
        }
    })
    .catch(error => {
        showStatus('❌ 恢复失败: ' + error, 'error');
    });
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    // 加载备份列表
    loadBackupList();
    
    // 创建备份按钮
    document.getElementById('create-backup').addEventListener('click', function() {
        this.disabled = true;
        this.textContent = '创建中...';
        
        fetch('<%=luci.dispatcher.build_url("admin/system/overlay-backup/create")%>')
            .then(response => response.json())
            .then(result => {
                if (result.success) {
                    showStatus('✅ ' + result.message, 'success');
                    loadBackupList();
                } else {
                    showStatus('❌ ' + result.message, 'error');
                }
            })
            .finally(() => {
                this.disabled = false;
                this.textContent = '➕ 创建备份';
            });
    });
    
    // 刷新列表按钮
    document.getElementById('refresh-list').addEventListener('click', function() {
        loadBackupList();
        showStatus('🔄 备份列表已刷新', 'info');
    });
    
    // 恢复确认对话框事件
    document.getElementById('confirm-input').addEventListener('input', function() {
        document.getElementById('confirm-restore').disabled = 
            this.value.toUpperCase() !== 'CONFIRM';
    });
    
    document.getElementById('confirm-cancel').addEventListener('click', hideRestoreConfirm);
    document.getElementById('confirm-restore').addEventListener('click', performRestore);
    
    // 按Enter键确认恢复
    document.getElementById('confirm-input').addEventListener('keypress', function(e) {
        if (e.key === 'Enter' && !document.getElementById('confirm-restore').disabled) {
            performRestore();
        }
    });
    
    // 点击背景关闭对话框
    document.getElementById('restore-confirm').addEventListener('click', function(e) {
        if (e.target === this) {
            hideRestoreConfirm();
        }
    });
});
</script>
<%+footer%>
EOF

# 创建优化的备份主脚本
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh
# 优化的Overlay备份工具 - 最终版本

ACTION="$1"
FILE="$2"

create_backup() {
    echo "正在创建Overlay备份..."
    
    # 生成带时间戳的唯一文件名
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="backup-${timestamp}-overlay.tar.gz"
    local backup_path="/tmp/${backup_file}"
    
    echo "开始备份过程..."
    
    # 使用sysupgrade创建系统兼容备份
    if sysupgrade -b "${backup_path}" >/dev/null 2>&1; then
        local size=$(du -h "${backup_path}" | cut -f1)
        echo "备份成功！"
        echo "备份文件: ${backup_file}"
        echo "文件大小: ${size}"
        echo "保存位置: /tmp/"
        echo "文件格式: 系统兼容格式"
        return 0
    else
        # 备用方法：直接打包overlay
        echo "使用备用方法创建备份..."
        if tar -czf "${backup_path}" -C / overlay etc/passwd etc/shadow etc/group etc/config 2>/dev/null; then
            local size=$(du -h "${backup_path}" | cut -f1)
            echo "备份成功！"
            echo "备份文件: ${backup_file}"
            echo "文件大小: ${size}"
            echo "保存位置: /tmp/"
            echo "文件格式: 标准tar.gz格式"
            return 0
        else
            echo "备份失败！请检查系统日志。"
            return 1
        fi
    fi
}

restore_backup() {
    local backup_file="$1"
    
    [ -z "$backup_file" ] && { 
        echo "错误：请指定备份文件"
        return 1
    }
    
    # 自动添加路径
    if [ "$(dirname "$backup_file")" = "." ]; then
        backup_file="/tmp/${backup_file}"
    fi
    
    [ ! -f "$backup_file" ] && { 
        echo "错误：找不到备份文件 '${backup_file}'"
        return 1
    }
    
    echo "开始恢复备份: $(basename "${backup_file}")"
    echo "备份文件路径: ${backup_file}"
    
    # 验证备份文件
    if ! tar -tzf "${backup_file}" >/dev/null 2>&1; then
        echo "错误：备份文件损坏或格式不正确"
        return 1
    fi
    
    echo "备份文件验证通过"
    echo "正在停止服务..."
    
    # 停止服务
    /etc/init.d/uhttpd stop 2>/dev/null || true
    /etc/init.d/firewall stop 2>/dev/null || true
    /etc/init.d/dnsmasq stop 2>/dev/null || true
    sleep 3
    
    # 恢复备份
    echo "正在恢复文件..."
    if tar -xzf "${backup_file}" -C / ; then
        echo "文件恢复完成"
        echo "正在启动服务..."
        
        # 重新启动服务
        /etc/init.d/dnsmasq start 2>/dev/null || true
        /etc/init.d/firewall start 2>/dev/null || true
        /etc/init.d/uhttpd start 2>/dev/null || true
        
        echo ""
        echo "恢复成功！"
        echo "✅ 所有配置已从备份文件恢复"
        echo "💡 建议：重启路由器以确保所有更改生效"
        return 0
    else
        echo "恢复失败！"
        echo "正在尝试恢复服务..."
        
        # 尝试重新启动服务
        /etc/init.d/dnsmasq start 2>/dev/null || true
        /etc/init.d/firewall start 2>/dev/null || true
        /etc/init.d/uhttpd start 2>/dev/null || true
        
        return 1
    fi
}

case "$ACTION" in
    backup) 
        create_backup 
        ;;
    restore) 
        restore_backup "$FILE" 
        ;;
    *)
        echo "Overlay备份工具"
        echo "用法: $0 {backup|restore <file>}"
        exit 1
        ;;
esac
EOF
chmod +x files/usr/bin/overlay-backup

# ==================== 4. 彻底修复USB自动挂载 ====================
echo "彻底修复USB自动挂载..."

# 创建USB自动挂载配置
mkdir -p files/etc/hotplug.d/block
cat > files/etc/hotplug.d/block/10-mount << 'EOF'
#!/bin/sh
# USB设备自动挂载脚本 - 增强版本

[ -z "$DEVNAME" ] && exit 0

logger "USB存储设备事件: ACTION=$ACTION, DEVICE=$DEVNAME, TYPE=$MDEV"

case "$ACTION" in
    add)
        # 设备添加
        logger "检测到存储设备: /dev/$DEVNAME"
        
        # 等待设备就绪
        sleep 3
        
        # 尝试获取文件系统类型
        TYPE=""
        if command -v blkid >/dev/null 2>&1; then
            TYPE=$(blkid -s TYPE -o value "/dev/$DEVNAME" 2>/dev/null)
        fi
        
        if [ -n "$TYPE" ]; then
            logger "设备 /dev/$DEVNAME 文件系统类型: $TYPE"
            
            # 创建挂载点
            MOUNT_POINT="/mnt/$DEVNAME"
            mkdir -p "$MOUNT_POINT"
            
            # 尝试挂载
            case "$TYPE" in
                ext4|ext3|ext2|vfat|ntfs|exfat|f2fs)
                    logger "尝试挂载 /dev/$DEVNAME 到 $MOUNT_POINT"
                    
                    # 设置挂载选项
                    case "$TYPE" in
                        vfat) MOUNT_OPTS="umask=000,utf8=true" ;;
                        ntfs) MOUNT_OPTS="umask=000" ;;
                        *) MOUNT_OPTS="" ;;
                    esac
                    
                    if mount -t "$TYPE" -o "$MOUNT_OPTS" "/dev/$DEVNAME" "$MOUNT_POINT" 2>/dev/null; then
                        logger "成功挂载 $DEVNAME ($TYPE) 到 $MOUNT_POINT"
                        
                        # 创建符号链接到 /mnt/usb
                        if [ ! -L "/mnt/usb" ] && [ ! -e "/mnt/usb" ]; then
                            ln -sf "$MOUNT_POINT" "/mnt/usb"
                            logger "创建符号链接: $MOUNT_POINT -> /mnt/usb"
                        fi
                    else
                        logger "挂载 $DEVNAME ($TYPE) 失败"
                        rmdir "$MOUNT_POINT" 2>/dev/null
                    fi
                    ;;
                *)
                    logger "不支持的文件系统: $TYPE (设备: $DEVNAME)"
                    ;;
            esac
        else
            logger "无法识别设备 /dev/$DEVNAME 的文件系统类型"
        fi
        ;;
        
    remove)
        # 设备移除
        MOUNT_POINT="/mnt/$DEVNAME"
        
        logger "设备移除: /dev/$DEVNAME"
        
        if mountpoint -q "$MOUNT_POINT"; then
            umount "$MOUNT_POINT"
            rmdir "$MOUNT_POINT" 2>/dev/null
            logger "已卸载存储设备: $DEVNAME"
        fi
        
        # 清理符号链接
        if [ -L "/mnt/usb" ] && [ "$(readlink /mnt/usb)" = "$MOUNT_POINT" ]; then
            rm -f "/mnt/usb"
            logger "移除符号链接: /mnt/usb"
        fi
        ;;
esac

exit 0
EOF
chmod +x files/etc/hotplug.d/block/10-mount

# 创建USB设备检测脚本
mkdir -p files/usr/bin
cat > files/usr/bin/usb-detect << 'EOF'
#!/bin/sh
# USB设备检测脚本

echo "=== USB设备检测 ==="
echo "扫描时间: $(date)"

echo ""
echo "1. 已连接的USB设备:"
lsusb 2>/dev/null || echo "lsusb命令不可用"

echo ""
echo "2. 块设备信息:"
lsblk 2>/dev/null || blkid 2>/dev/null || echo "无法获取块设备信息"

echo ""
echo "3. 挂载点信息:"
mount | grep -E "(/mnt/|/dev/sd)" || echo "没有找到USB设备挂载"

echo ""
echo "4. 内核USB消息:"
dmesg | grep -i usb | tail -10

echo ""
echo "检测完成"
EOF
chmod +x files/usr/bin/usb-detect

# 创建手动挂载脚本
cat > files/usr/bin/mount-usb << 'EOF'
#!/bin/sh
# 手动挂载USB设备脚本

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "用法: $0 [设备名]"
    echo "示例: $0 sda1"
    echo "如果不指定设备名，将列出所有可用设备"
    exit 0
fi

if [ -z "$1" ]; then
    echo "可用的USB存储设备:"
    echo "=================="
    blkid | grep -E "/dev/sd|/dev/mmc" | while read line; do
        DEVICE=$(echo "$line" | cut -d: -f1)
        TYPE=$(echo "$line" | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2)
        LABEL=$(echo "$line" | grep -o 'LABEL="[^"]*"' | cut -d'"' -f2)
        echo "设备: $DEVICE | 类型: $TYPE | 标签: $LABEL"
    done
    echo ""
    echo "请使用: $0 [设备名，如sda1] 来挂载设备"
    exit 0
fi

DEVICE="$1"
DEVICE_PATH="/dev/$DEVICE"

if [ ! -e "$DEVICE_PATH" ]; then
    echo "错误: 设备 $DEVICE_PATH 不存在"
    exit 1
fi

TYPE=$(blkid -s TYPE -o value "$DEVICE_PATH" 2>/dev/null)
if [ -z "$TYPE" ]; then
    echo "错误: 无法识别设备 $DEVICE_PATH 的文件系统类型"
    exit 1
fi

MOUNT_POINT="/mnt/$DEVICE"
mkdir -p "$MOUNT_POINT"

echo "挂载设备: $DEVICE_PATH"
echo "文件系统: $TYPE"
echo "挂载点: $MOUNT_POINT"

case "$TYPE" in
    ext4|ext3|ext2|vfat|ntfs|exfat|f2fs)
        if mount -t "$TYPE" "$DEVICE_PATH" "$MOUNT_POINT" 2>/dev/null; then
            echo "✅ 挂载成功!"
            echo "💡 设备已挂载到: $MOUNT_POINT"
            
            # 创建便捷访问链接
            if [ ! -L "/mnt/usb" ] && [ ! -e "/mnt/usb" ]; then
                ln -sf "$MOUNT_POINT" "/mnt/usb"
                echo "🔗 创建符号链接: /mnt/usb -> $MOUNT_POINT"
            fi
            
            # 显示使用情况
            df -h "$MOUNT_POINT"
        else
            echo "❌ 挂载失败!"
            rmdir "$MOUNT_POINT" 2>/dev/null
        fi
        ;;
    *)
        echo "❌ 不支持的文件系统: $TYPE"
        ;;
esac
EOF
chmod +x files/usr/bin/mount-usb

# ==================== 5. 初始化脚本 ====================
echo "设置初始化脚本..."
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-custom-setup << 'EOF'
#!/bin/sh
# 自定义初始化脚本

echo "执行自定义初始化..."

# 启用定时任务
/etc/init.d/cron enable
/etc/init.d/cron start

# 设置时区
echo "Asia/Shanghai" > /tmp/TZ

# 确保备份脚本可执行
[ -x "/usr/bin/overlay-backup" ] || chmod +x /usr/bin/overlay-backup
[ -x "/usr/bin/mount-usb" ] || chmod +x /usr/bin/mount-usb
[ -x "/usr/bin/usb-detect" ] || chmod +x /usr/bin/usb-detect

# 创建挂载点目录
mkdir -p /mnt/usb

# 重新启动自动挂载服务
/etc/init.d/automount enable
/etc/init.d/automount start

# 扫描并挂载现有的USB设备
echo "扫描现有USB设备..."
for device in /dev/sd*; do
    if [ -b "$device" ] && [ "$device" != "/dev/sda" ]; then
        echo "发现设备: $device"
        /usr/bin/mount-usb $(basename "$device") >/dev/null 2>&1 &
    fi
done

# 安装自定义IPK包
if [ -d "/packages" ]; then
    echo "安装自定义IPK包..."
    for ipk in /packages/*.ipk; do
        if [ -f "$ipk" ]; then
            echo "安装: $(basename "$ipk")"
            opkg install "$ipk" >/dev/null 2>&1 && echo "成功" || echo "失败"
        fi
    done
    rm -rf /packages
fi

echo "自定义初始化完成"
exit 0
EOF
chmod +x files/etc/uci-defaults/99-custom-setup

# ==================== 6. 复制自定义IPK包 ====================
if [ -d "../../files/packages" ]; then
    echo "复制自定义IPK包..."
    mkdir -p files/packages
    cp ../../files/packages/*.ipk files/packages/ 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "✅ WNDR3800 最终修复配置完成！"
echo "=========================================="
echo "📋 修复内容:"
echo ""
echo "🔧 Overlay备份系统优化:"
echo "  • ✅ 每个备份文件旁都有恢复按钮"
echo "  • ✅ 按钮大小优化，界面协调"
echo "  • ✅ 恢复确认对话框，防止误操作"
echo "  • ✅ 恢复成功明确提示"
echo "  • ✅ 详细文件信息显示"
echo ""
echo "🔌 USB自动挂载彻底修复:"
echo "  • ✅ 增强USB存储驱动支持"
echo "  • ✅ 改进的热插拔挂载脚本"
echo "  • ✅ 手动挂载工具 /usr/bin/mount-usb"
echo "  • ✅ 设备检测工具 /usr/bin/usb-detect"
echo "  • ✅ 自动创建 /mnt/usb 符号链接"
echo ""
echo "💡 使用说明:"
echo "  • 备份恢复: 系统 → Overlay Backup"
echo "  • USB挂载: 插入U盘自动挂载到 /mnt/ 目录"
echo "  • 手动挂载: 运行 mount-usb 命令"
echo "  • 设备检测: 运行 usb-detect 命令"
echo "=========================================="
