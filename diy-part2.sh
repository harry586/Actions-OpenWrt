#!/bin/bash
# =============================================
# ImmortalWrt DIY 脚本第二部分
# 功能：Overlay备份系统、内存释放、IPK自动安装
# =============================================

echo "开始执行 DIY 脚本第二部分..."

# ==================== 1. 彻底清理DDNS残留 ====================
echo "清理DDNS相关组件..."
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

# ==================== 2. 内存释放功能 ====================
echo "配置定时内存释放..."
mkdir -p files/etc/crontabs
mkdir -p files/usr/bin

# 创建内存释放脚本
cat > files/usr/bin/freemem << 'EOF'
#!/bin/sh
# 内存释放脚本 - 清理系统缓存
# 作者：ImmortalWrt DIY

logger "开始执行内存缓存清理..."

# 同步文件系统
sync

# 清理页面缓存、目录项和inodes
echo 1 > /proc/sys/vm/drop_caches 2>/dev/null
echo 2 > /proc/sys/vm/drop_caches 2>/dev/null  
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

# 显示清理后的内存状态
echo "内存清理完成，当前内存状态："
free -m

logger "定时内存缓存清理完成"
EOF
chmod +x files/usr/bin/freemem

# 添加定时任务 - 每天凌晨3点执行内存清理
echo "0 3 * * * /usr/bin/freemem >/dev/null 2>&1" >> files/etc/crontabs/root

# ==================== 3. IPK包自动安装功能 ====================
echo "配置IPK包自动安装功能..."
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-custom-ipk-install << 'EOF'
#!/bin/sh
# IPK包自动安装脚本
# 在首次启动时自动安装files/packages目录下的IPK包

INSTALL_DIR="/tmp/custom-ipk"
LOG_FILE="/tmp/ipk-install.log"

echo "开始检查自定义IPK包安装..." > $LOG_FILE

if [ -d "$INSTALL_DIR" ]; then
    echo "找到自定义IPK目录: $INSTALL_DIR" >> $LOG_FILE
    
    # 安装所有IPK包
    for ipk in $INSTALL_DIR/*.ipk; do
        if [ -f "$ipk" ]; then
            echo "正在安装: $(basename $ipk)" >> $LOG_FILE
            opkg install "$ipk" >> $LOG_FILE 2>&1
            if [ $? -eq 0 ]; then
                echo "安装成功: $(basename $ipk)" >> $LOG_FILE
                # 安装成功后删除IPK文件
                rm -f "$ipk"
            else
                echo "安装失败: $(basename $ipk)" >> $LOG_FILE
            fi
        fi
    done
    
    # 清理空目录
    rmdir "$INSTALL_DIR" 2>/dev/null
else
    echo "未找到自定义IPK目录" >> $LOG_FILE
fi

echo "自定义IPK包安装完成" >> $LOG_FILE

# 移除自己，只运行一次
rm -f /etc/uci-defaults/99-custom-ipk-install

exit 0
EOF
chmod +x files/etc/uci-defaults/99-custom-ipk-install

# 创建IPK安装目录
mkdir -p files/tmp/custom-ipk

# ==================== 4. 简约风格Overlay备份系统 ====================
echo "创建简约风格Overlay备份系统..."

mkdir -p files/usr/lib/lua/luci/controller/admin
mkdir -p files/usr/lib/lua/luci/view/admin_system
mkdir -p files/usr/bin

# 创建简约控制器
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
        http.write_json({success = false, message = "未选择恢复文件"})
        return
    end
    
    local filepath = "/tmp/" .. filename
    
    if not fs.stat(filepath) then
        http.prepare_content("application/json")
        http.write_json({success = false, message = "备份文件不存在: " .. filepath})
        return
    end
    
    local result = sys.exec("/usr/bin/overlay-backup restore '" .. filepath .. "' 2>&1")
    
    if result:match("恢复成功") then
        http.prepare_content("application/json")
        http.write_json({success = true, message = result})
        
        -- 延迟重启，确保响应先返回
        luci.sys.call("sleep 3 && reboot &")
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

# 创建简约风格Web界面
cat > files/usr/lib/lua/luci/view/admin_system/overlay_backup.htm << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:系统配置备份与恢复%></h2>
    
    <!-- 简约介绍信息 -->
    <div class="alert-message" style="background: #f8f9fa; border-left: 4px solid #007bff; padding: 12px 15px; margin-bottom: 20px;">
        <strong>功能说明：</strong> 备份当前系统配置和已安装软件，可在需要时恢复。
    </div>
    
    <!-- 操作按钮区域 - 简约风格 -->
    <div class="cbi-section" style="margin-bottom: 20px;">
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600;"><%:快速操作%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                    <button id="create-backup" class="cbi-button cbi-button-apply" style="min-width: 120px;">创建备份</button>
                    <button id="refresh-list" class="cbi-button cbi-button-reset" style="min-width: 120px;">刷新列表</button>
                </div>
            </div>
        </div>
    </div>

    <!-- 状态显示 -->
    <div id="status-message" style="margin: 15px 0;"></div>

    <!-- 备份文件列表 - 简约表格 -->
    <div class="cbi-section">
        <h3 style="margin-top: 0;"><%:备份文件列表%></h3>
        <div class="table" style="width: 100%; border-collapse: collapse;">
            <div class="table-row" style="background: #f8f9fa; font-weight: 600;">
                <div class="table-cell" style="padding: 12px; border-bottom: 2px solid #dee2e6; width: 40%;">文件名</div>
                <div class="table-cell" style="padding: 12px; border-bottom: 2px solid #dee2e6; width: 15%; text-align: center;">大小</div>
                <div class="table-cell" style="padding: 12px; border-bottom: 2px solid #dee2e6; width: 25%;">备份时间</div>
                <div class="table-cell" style="padding: 12px; border-bottom: 2px solid #dee2e6; width: 20%; text-align: center;">操作</div>
            </div>
            <div id="backup-list">
                <div class="table-row" id="no-backups" style="display: none;">
                    <div class="table-cell" colspan="4" style="padding: 40px; text-align: center; color: #6c757d;">
                        暂无备份文件<br>
                        <small>点击"创建备份"按钮生成第一个备份</small>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- 重启提示 -->
    <div id="reboot-notice" style="display: none; position: fixed; top: 20px; left: 50%; transform: translateX(-50%); background: #28a745; color: white; padding: 12px 20px; border-radius: 4px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); z-index: 1000;">
        <strong>恢复成功！</strong> 系统将在 <span id="countdown">5</span> 秒后重启...
    </div>
</div>

<script type="text/javascript">
// 简约JavaScript功能

function loadBackupList() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlay-backup/list")%>', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            try {
                var data = JSON.parse(xhr.responseText);
                displayBackupList(data);
            } catch (e) {
                showStatus('加载失败', 'error');
            }
        }
    };
    xhr.send();
}

function displayBackupList(backups) {
    var container = document.getElementById('backup-list');
    var noBackups = document.getElementById('no-backups');
    
    // 清空现有内容
    var rows = container.querySelectorAll('.backup-item');
    rows.forEach(function(row) {
        row.remove();
    });
    
    if (!backups || backups.length === 0) {
        noBackups.style.display = '';
        return;
    }
    
    noBackups.style.display = 'none';
    
    backups.forEach(function(backup) {
        var row = document.createElement('div');
        row.className = 'table-row backup-item';
        row.style.borderBottom = '1px solid #dee2e6';
        row.innerHTML = 
            '<div class="table-cell" style="padding: 12px; width: 40%;">' +
                '<div style="font-weight: 500;">' + backup.name + '</div>' +
            '</div>' +
            '<div class="table-cell" style="padding: 12px; width: 15%; text-align: center; font-family: monospace;">' + formatSize(backup.size) + '</div>' +
            '<div class="table-cell" style="padding: 12px; width: 25%;">' + backup.formatted_time + '</div>' +
            '<div class="table-cell" style="padding: 12px; width: 20%; text-align: center;">' +
                '<button onclick="restoreBackup(\'' + backup.name + '\')" class="cbi-button cbi-button-apply" style="padding: 6px 12px; margin: 2px;">恢复</button>' +
                '<button onclick="downloadBackup(\'' + backup.path + '\')" class="cbi-button cbi-button-download" style="padding: 6px 12px; margin: 2px;">下载</button>' +
                '<button onclick="deleteBackup(\'' + backup.path + '\')" class="cbi-button cbi-button-remove" style="padding: 6px 12px; margin: 2px;">删除</button>' +
            '</div>';
        
        container.appendChild(row);
    });
}

function formatSize(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1048576).toFixed(1) + ' MB';
}

function showStatus(message, type) {
    var statusDiv = document.getElementById('status-message');
    var className = type === 'success' ? 'success' : type === 'error' ? 'error' : 'info';
    statusDiv.innerHTML = '<div class="alert-message ' + className + '">' + message + '</div>';
}

function restoreBackup(filename) {
    if (!confirm('确定恢复备份：' + filename + '？\n系统将自动重启！')) return;
    
    showStatus('恢复中...', 'info');
    
    var formData = new FormData();
    formData.append('filename', filename);
    
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '<%=luci.dispatcher.build_url("admin/system/overlay-backup/restore")%>', true);
    
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        showRebootCountdown();
                    } else {
                        showStatus('恢复失败：' + data.message, 'error');
                    }
                } catch (e) {
                    showRebootCountdown();
                }
            } else {
                showRebootCountdown();
            }
        }
    };
    
    xhr.send(formData);
}

function downloadBackup(filepath) {
    window.location.href = '<%=luci.dispatcher.build_url("admin/system/overlay-backup/download")%>?file=' + encodeURIComponent(filepath);
}

function deleteBackup(filepath) {
    if (confirm('确定删除备份文件？')) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlay-backup/delete")%>?file=' + encodeURIComponent(filepath), true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                loadBackupList();
                showStatus('删除成功', 'success');
            }
        };
        xhr.send();
    }
}

function showRebootCountdown() {
    var notice = document.getElementById('reboot-notice');
    var countdown = document.getElementById('countdown');
    notice.style.display = 'block';
    
    var seconds = 5;
    var interval = setInterval(function() {
        countdown.textContent = seconds;
        seconds--;
        
        if (seconds < 0) {
            clearInterval(interval);
            notice.style.display = 'none';
        }
    }, 1000);
}

// 页面初始化
document.addEventListener('DOMContentLoaded', function() {
    loadBackupList();
    
    document.getElementById('create-backup').addEventListener('click', function() {
        var btn = this;
        btn.disabled = true;
        btn.innerHTML = '创建中...';
        
        var xhr = new XMLHttpRequest();
        xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlay-backup/create")%>', true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                btn.disabled = false;
                btn.innerHTML = '创建备份';
                
                try {
                    var data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        showStatus('备份创建成功', 'success');
                        loadBackupList();
                    } else {
                        showStatus('备份失败：' + data.message, 'error');
                    }
                } catch (e) {
                    showStatus('备份失败', 'error');
                }
            }
        };
        xhr.send();
    });
    
    document.getElementById('refresh-list').addEventListener('click', function() {
        loadBackupList();
        showStatus('列表已刷新', 'info');
    });
});

// 简约样式增强
var style = document.createElement('style');
style.textContent = `
.cbi-button { padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; }
.cbi-button-apply { background: #28a745; color: white; }
.cbi-button-reset { background: #6c757d; color: white; }
.cbi-button-download { background: #17a2b8; color: white; }
.cbi-button-remove { background: #dc3545; color: white; }
.cbi-button:hover { opacity: 0.8; }
.alert-message.success { background: #d4edda; color: #155724; border-left: 4px solid #28a745; }
.alert-message.error { background: #f8d7da; color: #721c24; border-left: 4px solid #dc3545; }
.alert-message.info { background: #d1ecf1; color: #0c5460; border-left: 4px solid #17a2b8; }
.table-cell { display: table-cell; vertical-align: middle; }
.table-row { display: table-row; }
.table { display: table; }
`;
document.head.appendChild(style);
</script>
<%+footer%>
EOF

# 创建优化的备份脚本
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh
# Overlay备份工具 - 简约版本

ACTION="$1"
FILE="$2"

create_backup() {
    echo "正在创建系统备份..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="backup-${timestamp}.tar.gz"
    local backup_path="/tmp/${backup_file}"
    
    # 使用sysupgrade创建备份
    if sysupgrade -b "${backup_path}" >/dev/null 2>&1; then
        local size=$(du -h "${backup_path}" | cut -f1)
        echo "备份成功"
        echo "文件: ${backup_file}"
        echo "大小: ${size}"
        echo "位置: /tmp/"
        return 0
    else
        # 备用方法
        echo "使用备用备份方法..."
        if tar -czf "${backup_path}" -C / overlay etc 2>/dev/null; then
            local size=$(du -h "${backup_path}" | cut -f1)
            echo "备份成功"
            echo "文件: ${backup_file}"
            echo "大小: ${size}"
            return 0
        else
            echo "备份失败"
            return 1
        fi
    fi
}

restore_backup() {
    local backup_file="$1"
    
    [ -z "$backup_file" ] && { 
        echo "错误：未指定文件"
        return 1
    }
    
    if [ "$(dirname "$backup_file")" = "." ]; then
        backup_file="/tmp/${backup_file}"
    fi
    
    [ ! -f "$backup_file" ] && { 
        echo "错误：文件不存在"
        return 1
    }
    
    echo "开始恢复：$(basename "${backup_file}")"
    
    # 验证文件
    if ! tar -tzf "${backup_file}" >/dev/null 2>&1; then
        echo "错误：文件损坏"
        return 1
    fi
    
    echo "文件验证通过"
    echo "停止服务..."
    
    # 停止服务
    /etc/init.d/uhttpd stop 2>/dev/null || true
    /etc/init.d/firewall stop 2>/dev/null || true
    sleep 2
    
    # 恢复文件
    echo "恢复文件中..."
    if tar -xzf "${backup_file}" -C / ; then
        echo "恢复完成"
        echo "重启系统..."
        return 0
    else
        echo "恢复失败"
        /etc/init.d/uhttpd start 2>/dev/null || true
        /etc/init.d/firewall start 2>/dev/null || true
        return 1
    fi
}

case "$ACTION" in
    backup) create_backup ;;
    restore) restore_backup "$FILE" ;;
    *)
        echo "用法: $0 {backup|restore <file>}"
        exit 1
        ;;
esac
EOF
chmod +x files/usr/bin/overlay-backup

echo ""
echo "=========================================="
echo "DIY 脚本第二部分执行完成"
echo "=========================================="
echo "包含功能："
echo "✅ Overlay备份系统（简约风格）"
echo "✅ 内存释放脚本和定时任务"
echo "✅ IPK包自动安装功能"
echo "✅ DDNS组件彻底禁用"
echo ""
echo "按钮样式特点："
echo "• 简约圆角设计"
echo "• 清晰的颜色区分"
echo "• 响应式布局"
echo "• 专业的视觉反馈"
echo "=========================================="
