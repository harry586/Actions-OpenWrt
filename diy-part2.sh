#!/bin/bash
# =============================================
# OpenWrt DIY 脚本第二部分 - 完整修复版本
# 修复内容：
# 1. 彻底解决DDNS警告问题
# 2. 优化Overlay备份界面和功能
# 3. 增强USB自动挂载支持
# 设备：Netgear WNDR3800
# =============================================

echo "开始应用 WNDR3800 完整修复配置..."

# ==================== 1. 彻底清理DDNS残留 ====================
echo "彻底清理DDNS相关组件和配置..."

# 删除DDNS相关配置文件
mkdir -p files/etc/config
cat > files/etc/config/ddns << 'EOF'
# DDNS 配置已禁用
# 此文件为空以防止DDNS服务启动
EOF

# 禁用DDNS初始化脚本
mkdir -p files/etc/init.d
cat > files/etc/init.d/ddns << 'EOF'
#!/bin/sh /etc/rc.common
# 禁用的DDNS服务脚本
START=99
STOP=99

boot() {
    return 0
}

start() {
    echo "DDNS服务已被禁用"
    return 0
}

stop() {
    return 0
}
EOF
chmod +x files/etc/init.d/ddns

# ==================== 2. 内存释放功能 ====================
echo "配置定时内存释放..."
mkdir -p files/etc/crontabs
mkdir -p files/usr/bin

cat > files/usr/bin/freemem << 'EOF'
#!/bin/sh
# 内存释放脚本 - 每天凌晨3点自动执行
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

# 创建备份主目录
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
        http.write_json({success = true, message = result})
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
    
    -- 确保文件路径正确
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
                        mtime = stat.mtime
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

# 创建优化的Web界面模板
cat > files/usr/lib/lua/luci/view/admin_system/overlay_backup.htm << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:Overlay Backup%></h2>
    
    <div class="alert-message success" style="background: #d4edda; color: #155724; border: 1px solid #c3e6cb; padding: 15px; margin-bottom: 20px;">
        <h4 style="margin: 0 0 10px 0; color: #155724;">✅ 优化的Overlay备份系统</h4>
        <ul style="margin: 0; padding-left: 20px;">
            <li>每次备份生成独立文件，避免覆盖</li>
            <li>恢复时使用下拉菜单选择，无需手动输入</li>
            <li>按钮大小优化，界面更协调</li>
            <li>自动刷新备份文件列表</li>
        </ul>
    </div>
    
    <div class="cbi-section">
        <h3><%:备份操作%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title"><%:创建备份%></label>
            <div class="cbi-value-field">
                <button id="create-backup" class="cbi-button cbi-button-apply" style="min-width: 150px;">
                    ➕ <%:创建新备份%>
                </button>
                <button id="refresh-list" class="cbi-button cbi-button-action" style="min-width: 100px; margin-left: 10px;">
                    🔄 <%:刷新列表%>
                </button>
            </div>
        </div>
        
        <div class="cbi-value">
            <label class="cbi-value-title"><%:恢复备份%></label>
            <div class="cbi-value-field">
                <select id="backup-files" style="min-width: 200px; padding: 5px;">
                    <option value="">-- 选择备份文件 --</option>
                </select>
                <button id="restore-backup" class="cbi-button cbi-button-reset" style="min-width: 100px; margin-left: 10px;">
                    🔄 <%:恢复%>
                </button>
            </div>
        </div>
    </div>

    <!-- 操作状态显示 -->
    <div id="status-message" style="margin: 15px 0;"></div>

    <!-- 备份文件列表 -->
    <div class="cbi-section">
        <h3><%:备份文件列表%> <small>(保存在 /tmp 目录，重启后丢失)</small></h3>
        <div class="table" id="backup-table" style="min-height: 100px;">
            <div class="table-titles">
                <div class="table-cell" style="width: 40%;"><%:文件名%></div>
                <div class="table-cell" style="width: 15%;"><%:大小%></div>
                <div class="table-cell" style="width: 25%;"><%:修改时间%></div>
                <div class="table-cell" style="width: 20%;"><%:操作%></div>
            </div>
            <div class="table-row" id="no-backups" style="display: none;">
                <div class="table-cell" colspan="4" style="text-align: center; padding: 30px;">
                    <%:没有找到备份文件%>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
// 加载备份文件列表
function loadBackupList() {
    fetch('<%=luci.dispatcher.build_url("admin/system/overlay-backup/list")%>')
        .then(response => response.json())
        .then(backups => {
            const select = document.getElementById('backup-files');
            const table = document.getElementById('backup-table');
            const noBackups = document.getElementById('no-backups');
            
            // 清空现有选项（保留第一个）
            while (select.children.length > 1) {
                select.removeChild(select.lastChild);
            }
            
            // 清空表格内容（保留标题行和无备份提示）
            const rows = table.querySelectorAll('.table-row:not(.table-titles):not(#no-backups)');
            rows.forEach(row => row.remove());
            
            if (backups.length === 0) {
                noBackups.style.display = '';
                return;
            }
            
            noBackups.style.display = 'none';
            
            // 填充下拉菜单和表格
            backups.forEach(backup => {
                // 添加到下拉菜单
                const option = document.createElement('option');
                option.value = backup.name;
                option.textContent = backup.name;
                select.appendChild(option);
                
                // 添加到表格
                const row = document.createElement('div');
                row.className = 'table-row';
                row.innerHTML = `
                    <div class="table-cell" style="width: 40%;">${backup.name}</div>
                    <div class="table-cell" style="width: 15%;">${formatFileSize(backup.size)}</div>
                    <div class="table-cell" style="width: 25%;">${new Date(backup.mtime * 1000).toLocaleString()}</div>
                    <div class="table-cell" style="width: 20%;">
                        <button class="cbi-button cbi-button-apply download-btn" data-file="${backup.path}" style="padding: 3px 8px; margin-right: 5px;">下载</button>
                        <button class="cbi-button cbi-button-reset delete-btn" data-file="${backup.path}" data-name="${backup.name}" style="padding: 3px 8px;">删除</button>
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
    
    if (type === 'success') {
        setTimeout(() => {
            statusDiv.innerHTML = '';
        }, 5000);
    }
}

// 绑定表格事件
function bindTableEvents() {
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
                            showStatus(result.message, 'success');
                            loadBackupList();
                        } else {
                            showStatus(result.message, 'error');
                        }
                    });
            }
        });
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
                    showStatus(result.message, 'success');
                    loadBackupList();
                } else {
                    showStatus(result.message, 'error');
                }
            })
            .finally(() => {
                this.disabled = false;
                this.textContent = '➕ 创建新备份';
            });
    });
    
    // 刷新列表按钮
    document.getElementById('refresh-list').addEventListener('click', function() {
        loadBackupList();
        showStatus('备份列表已刷新', 'info');
    });
    
    // 恢复备份按钮
    document.getElementById('restore-backup').addEventListener('click', function() {
        const selectedFile = document.getElementById('backup-files').value;
        
        if (!selectedFile) {
            showStatus('请选择要恢复的备份文件', 'error');
            return;
        }
        
        if (!confirm('⚠️  警告：这将覆盖当前的所有配置！\n\n确定要恢复备份文件：' + selectedFile + ' 吗？')) {
            return;
        }
        
        const formData = new FormData();
        formData.append('filename', selectedFile);
        
        fetch('<%=luci.dispatcher.build_url("admin/system/overlay-backup/restore")%>', {
            method: 'POST',
            body: formData
        })
        .then(response => response.json())
        .then(result => {
            if (result.success) {
                showStatus(result.message + ' 建议重启路由器使更改生效。', 'success');
            } else {
                showStatus(result.message, 'error');
            }
        });
    });
});
</script>
<%+footer%>
EOF

# 创建优化的备份主脚本
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh
# 优化的Overlay备份工具 - 修复版本

ACTION="$1"
FILE="$2"

create_backup() {
    echo "正在创建Overlay备份..."
    
    # 生成带时间戳的唯一文件名
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="backup-${timestamp}-overlay.tar.gz"
    local backup_path="/tmp/${backup_file}"
    
    echo "备份文件: ${backup_file}"
    
    # 创建备份
    if sysupgrade -b "${backup_path}" >/dev/null 2>&1; then
        local size=$(du -h "${backup_path}" | cut -f1)
        echo "备份成功！"
        echo "文件: ${backup_file}"
        echo "大小: ${size}"
        echo "位置: ${backup_path}"
        echo ""
        echo "✅ 此备份可通过以下方式恢复："
        echo "   - 系统 → 备份/升级（系统自带功能）"
        echo "   - 本页面恢复功能（推荐）"
        return 0
    else
        # 备用方法
        echo "使用备用方法创建备份..."
        if tar -czf "${backup_path}" -C / overlay etc/passwd etc/shadow etc/group etc/config 2>/dev/null; then
            local size=$(du -h "${backup_path}" | cut -f1)
            echo "备份成功！"
            echo "文件: ${backup_file}"
            echo "大小: ${size}"
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
    
    # 验证备份文件
    if ! tar -tzf "${backup_file}" >/dev/null 2>&1; then
        echo "错误：备份文件损坏或格式不正确"
        return 1
    fi
    
    echo "验证备份文件格式..."
    
    # 停止服务
    echo "停止相关服务..."
    /etc/init.d/uhttpd stop 2>/dev/null || true
    /etc/init.d/firewall stop 2>/dev/null || true
    /etc/init.d/dnsmasq stop 2>/dev/null || true
    sleep 2
    
    # 恢复备份
    echo "恢复备份文件..."
    if tar -xzf "${backup_file}" -C / ; then
        echo "恢复成功！"
        
        # 重新启动服务
        echo "启动服务..."
        /etc/init.d/dnsmasq start 2>/dev/null || true
        /etc/init.d/firewall start 2>/dev/null || true
        /etc/init.d/uhttpd start 2>/dev/null || true
        
        echo ""
        echo "✅ 恢复完成！建议重启路由器"
        return 0
    else
        echo "恢复失败！"
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
        echo "优化的Overlay备份工具"
        echo "用法: $0 {backup|restore <file>}"
        echo ""
        echo "特点："
        echo "  • 每次备份生成唯一文件名"
        echo "  • 支持系统兼容格式"
        echo "  • 优化的错误处理"
        exit 1
        ;;
esac
EOF
chmod +x files/usr/bin/overlay-backup

# ==================== 4. 增强USB自动挂载支持 ====================
echo "增强USB自动挂载支持..."

# 创建USB自动挂载配置
mkdir -p files/etc/hotplug.d/block
cat > files/etc/hotplug.d/block/10-mount << 'EOF'
#!/bin/sh
# USB设备自动挂载脚本

[ -z "$DEVNAME" ] && exit 0

case "$ACTION" in
    add)
        # 设备添加
        logger "检测到存储设备: $DEVNAME"
        
        # 等待设备就绪
        sleep 2
        
        # 获取设备信息
        eval $(blkid "/dev/${DEVNAME}" | grep -o 'TYPE="[^"]*"')
        
        if [ -n "$TYPE" ]; then
            # 创建挂载点
            MOUNT_POINT="/mnt/${DEVNAME}"
            mkdir -p "$MOUNT_POINT"
            
            # 尝试挂载
            case "$TYPE" in
                ext4|ext3|ext2|vfat|ntfs|exfat)
                    if mount -t "$TYPE" "/dev/${DEVNAME}" "$MOUNT_POINT" 2>/dev/null; then
                        logger "成功挂载 $DEVNAME ($TYPE) 到 $MOUNT_POINT"
                    else
                        logger "挂载 $DEVNAME ($TYPE) 失败"
                        rmdir "$MOUNT_POINT" 2>/dev/null
                    fi
                    ;;
                *)
                    logger "不支持的文件系统: $TYPE (设备: $DEVNAME)"
                    ;;
            esac
        fi
        ;;
        
    remove)
        # 设备移除
        MOUNT_POINT="/mnt/${DEVNAME}"
        
        if mountpoint -q "$MOUNT_POINT"; then
            umount "$MOUNT_POINT"
            rmdir "$MOUNT_POINT" 2>/dev/null
            logger "已卸载存储设备: $DEVNAME"
        fi
        ;;
esac

exit 0
EOF
chmod +x files/etc/hotplug.d/block/10-mount

# ==================== 5. IPK自动安装功能 ====================
echo "设置IPK包自动安装..."
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

# 安装自定义IPK包
if [ -d "/packages" ]; then
    echo "发现自定义IPK包..."
    for ipk in /packages/*.ipk; do
        if [ -f "$ipk" ]; then
            echo "安装: $(basename "$ipk")"
            opkg install "$ipk" >/dev/null 2>&1 && echo "成功" || echo "失败"
        fi
    done
    rm -rf /packages
fi

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
echo "✅ WNDR3800 完整修复配置完成！"
echo "=========================================="
echo "📋 修复内容:"
echo "  • 🔇 彻底解决DDNS警告问题"
echo "  • 💾 优化的Overlay备份系统"
echo "    - 每次备份生成唯一文件"
echo "    - 下拉菜单选择恢复文件"
echo "    - 优化的按钮大小和布局"
echo "    - 自动刷新文件列表"
echo "  • 🔌 增强USB自动挂载支持"
echo "    - 自动识别多种文件系统"
echo "    - 热插拔自动挂载/卸载"
echo "  • 📦 IPK包自动安装"
echo "  • 🕒 定时内存释放"
echo "=========================================="
