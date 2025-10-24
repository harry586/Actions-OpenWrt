#!/bin/bash
# =============================================
# OpenWrt DIY 脚本第二部分 - 简约风格完整实现
# 采用简约风格的界面设计，包括按钮、布局和整体样式
# =============================================

echo "开始应用简约风格的Overlay备份系统..."

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

# ==================== 3. 简约风格的Overlay备份系统 ====================
echo "创建简约风格的Overlay备份系统..."

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
    entry({"admin", "system", "overlay-backup", "reboot"}, call("reboot_router")).leaf = true
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
    
    -- 使用GET参数获取文件名
    local filename = http.getenv("QUERY_STRING")
    if filename then
        filename = filename:match("filename=([^&]*)")
        if filename then
            -- URL解码
            filename = filename:gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end)
        end
    end
    
    -- 备用方法：从POST获取
    if not filename or filename == "" then
        filename = http.formvalue("filename")
    end
    
    if not filename or filename == "" then
        http.prepare_content("application/json")
        http.write_json({success = false, message = "未选择恢复文件"})
        return
    end
    
    -- 关键修复：正确处理文件路径
    local filepath = "/tmp/" .. filename
    if not fs.stat(filepath) then
        filepath = filename  -- 如果已经是完整路径
    end
    
    if not fs.stat(filepath) then
        http.prepare_content("application/json")
        http.write_json({success = false, message = "备份文件不存在: " .. filepath})
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

function reboot_router()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "路由器重启命令已发送"})
    
    -- 延迟执行重启，让响应先返回
    os.execute("sleep 2 && reboot &")
end
EOF

# 创建简约风格的Web界面模板
cat > files/usr/lib/lua/luci/view/admin_system/overlay_backup.htm << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:系统配置备份与恢复%></h2>
    
    <div class="alert-message info" style="background: #e8f4fd; color: #0c5460; border: 1px solid #bee5eb; padding: 15px; margin-bottom: 20px; border-radius: 6px;">
        <h4 style="margin: 0 0 10px 0; color: #0c5460;">系统配置备份与恢复</h4>
        <ul style="margin: 0; padding-left: 20px;">
            <li>备份：保存当前系统配置和已安装软件</li>
            <li>恢复：从备份文件还原系统配置</li>
            <li>注意：恢复后系统会自动重启</li>
        </ul>
    </div>
    
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:备份操作%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:快速操作%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 12px; flex-wrap: wrap;">
                    <button id="create-backup" class="btn-primary" style="padding: 10px 20px; min-width: 120px;">
                        创建备份
                    </button>
                    <button id="refresh-list" class="btn-secondary" style="padding: 10px 20px; min-width: 120px;">
                        刷新列表
                    </button>
                </div>
            </div>
        </div>
    </div>

    <!-- 操作状态显示 -->
    <div id="status-message" style="margin: 15px 0;"></div>

    <!-- 备份文件列表 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:备份文件列表%> <small style="color: #7f8c8d;">(保存在 /tmp 目录，重启后丢失)</small></h3>
        <div class="backup-table" id="backup-table" style="min-height: 100px;">
            <div class="table-header">
                <div class="table-cell" style="width: 45%;">文件名</div>
                <div class="table-cell" style="width: 15%;">大小</div>
                <div class="table-cell" style="width: 25%;">备份时间</div>
                <div class="table-cell" style="width: 15%;">操作</div>
            </div>
            <div class="table-row" id="no-backups" style="display: none;">
                <div class="table-cell" colspan="4" style="text-align: center; padding: 30px; color: #95a5a6;">
                    <%:暂无备份文件，点击"创建备份"按钮生成第一个备份%>
                </div>
            </div>
        </div>
    </div>

    <!-- 恢复确认对话框 -->
    <div id="restore-confirm" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 1000;">
        <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; padding: 25px; border-radius: 8px; min-width: 450px; box-shadow: 0 10px 30px rgba(0,0,0,0.2);">
            <h3 style="margin-top: 0; color: #e74c3c; border-bottom: 1px solid #eee; padding-bottom: 10px;">⚠️ 确认恢复操作</h3>
            <p style="margin: 15px 0;">您即将恢复备份文件：</p>
            <div style="background: #f8f9fa; padding: 10px; border-radius: 4px; margin: 10px 0;">
                <strong id="confirm-filename" style="color: #2c3e50;"></strong>
            </div>
            <p style="color: #e74c3c; font-weight: 600; margin: 15px 0;">此操作将覆盖当前的所有配置！</p>
            <p style="margin: 15px 0;">恢复成功后系统将<strong>自动重启</strong>以确保配置完全生效。</p>
            <div style="text-align: right; margin-top: 25px; display: flex; gap: 10px; justify-content: flex-end;">
                <button id="confirm-cancel" class="btn-neutral" style="padding: 8px 16px;">取消</button>
                <button id="confirm-restore" class="btn-primary" style="padding: 8px 16px;">确认恢复</button>
            </div>
        </div>
    </div>

    <!-- 重启倒计时对话框 -->
    <div id="reboot-countdown" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.7); z-index: 1001;">
        <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; padding: 30px; border-radius: 12px; min-width: 500px; text-align: center; box-shadow: 0 15px 35px rgba(0,0,0,0.3);">
            <h2 style="color: #27ae60; margin-top: 0; margin-bottom: 20px;">✅ 恢复成功</h2>
            <div style="font-size: 48px; color: #2ecc71; margin: 20px 0; font-weight: bold;" id="countdown-number">5</div>
            <p style="font-size: 16px; margin: 10px 0; color: #34495e;">系统将在 <span id="countdown-display" style="color: #3498db; font-weight: bold;">5秒</span> 后自动重启</p>
            <div style="background: #f8f9fa; padding: 15px; border-radius: 6px; margin: 20px 0; text-align: left;">
                <h4 style="margin: 0 0 10px 0; color: #3498db;">重启的重要性：</h4>
                <ul style="margin: 0; padding-left: 20px; color: #7f8c8d;">
                    <li>确保所有服务使用恢复后的配置启动</li>
                    <li>清理内存中旧配置的缓存数据</li>
                    <li>避免运行中程序配置不一致的问题</li>
                    <li>保证网络服务的稳定运行</li>
                </ul>
            </div>
            <div style="display: flex; gap: 12px; justify-content: center;">
                <button id="reboot-now" class="btn-primary" style="padding: 10px 20px;">
                    立即重启
                </button>
                <button id="cancel-reboot" class="btn-neutral" style="padding: 10px 20px;">
                    取消重启
                </button>
            </div>
        </div>
    </div>
</div>

<script>
// 全局变量
let currentRestoreFile = '';
let countdownTimer = null;
let countdownTime = 5; // 5秒倒计时

// 加载备份文件列表
function loadBackupList() {
    fetch('<%=luci.dispatcher.build_url("admin/system/overlay-backup/list")%>')
        .then(response => response.json())
        .then(backups => {
            const table = document.getElementById('backup-table');
            const noBackups = document.getElementById('no-backups');
            
            // 清空表格内容（保留标题行）
            const rows = table.querySelectorAll('.table-row:not(.table-header):not(#no-backups)');
            rows.forEach(row => row.remove());
            
            if (backups.length === 0) {
                noBackups.style.display = '';
                return;
            }
            
            noBackups.style.display = 'none';
            
            // 填充表格 - 简约风格
            backups.forEach(backup => {
                const row = document.createElement('div');
                row.className = 'table-row';
                row.innerHTML = `
                    <div class="table-cell" style="width: 45%;">
                        <div style="font-weight: 600; word-break: break-all; font-size: 13px; line-height: 1.4; color: #2c3e50;">
                            ${backup.name}
                        </div>
                        <div style="font-size: 11px; color: #7f8c8d; margin-top: 4px;">
                            路径: /tmp/${backup.name}
                        </div>
                    </div>
                    <div class="table-cell" style="width: 15%;">
                        <div style="font-family: 'Courier New', monospace; white-space: nowrap; font-size: 12px; text-align: center; color: #34495e; font-weight: 500;">
                            ${formatFileSize(backup.size)}
                        </div>
                    </div>
                    <div class="table-cell" style="width: 25%;">
                        <div style="font-size: 12px; white-space: nowrap; color: #34495e;">
                            ${backup.formatted_time}
                        </div>
                    </div>
                    <div class="table-cell" style="width: 15%;">
                        <div style="display: flex; gap: 6px; flex-wrap: nowrap; justify-content: center; align-items: center;">
                            <button class="btn-primary btn-small restore-btn" 
                                    data-file="${backup.name}" 
                                    title="恢复此备份">
                                恢复
                            </button>
                            <button class="btn-secondary btn-small download-btn" 
                                    data-file="${backup.path}" 
                                    title="下载备份文件">
                                下载
                            </button>
                            <button class="btn-danger btn-small delete-btn" 
                                    data-file="${backup.path}" 
                                    data-name="${backup.name}" 
                                    title="删除此备份">
                                删除
                            </button>
                        </div>
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
    let className, bgColor, textColor, borderColor;
    
    switch(type) {
        case 'success':
            className = 'alert-message success';
            bgColor = '#d4edda';
            textColor = '#155724';
            borderColor = '#c3e6cb';
            break;
        case 'error':
            className = 'alert-message error';
            bgColor = '#f8d7da';
            textColor = '#721c24';
            borderColor = '#f5c6cb';
            break;
        default:
            className = 'alert-message info';
            bgColor = '#d1ecf1';
            textColor = '#0c5460';
            borderColor = '#bee5eb';
    }
    
    statusDiv.innerHTML = `<div class="${className}" style="background: ${bgColor}; color: ${textColor}; border: 1px solid ${borderColor}; padding: 12px 15px; border-radius: 6px; margin: 10px 0;">${message}</div>`;
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
                            showStatus('备份文件已删除', 'success');
                            loadBackupList();
                        } else {
                            showStatus(result.message, 'error');
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
    document.getElementById('restore-confirm').style.display = 'block';
}

// 隐藏恢复确认对话框
function hideRestoreConfirm() {
    document.getElementById('restore-confirm').style.display = 'none';
    currentRestoreFile = '';
}

// 执行恢复操作 - 使用GET参数传递文件名
function performRestore() {
    if (!currentRestoreFile) {
        showStatus('未选择恢复文件', 'error');
        return;
    }
    
    hideRestoreConfirm();
    showStatus('正在恢复备份，请稍候...', 'info');
    
    // 使用GET参数传递文件名
    const url = '<%=luci.dispatcher.build_url("admin/system/overlay-backup/restore")%>?filename=' + encodeURIComponent(currentRestoreFile);
    
    fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
        }
    })
    .then(response => {
        if (!response.ok) {
            throw new Error('网络响应不正常');
        }
        return response.json();
    })
    .then(result => {
        if (result.success) {
            // 恢复成功，显示重启倒计时
            showRebootCountdown();
        } else {
            showStatus(result.message, 'error');
        }
    })
    .catch(error => {
        showStatus('恢复失败: ' + error.message, 'error');
    });
}

// 显示重启倒计时
function showRebootCountdown() {
    const rebootDialog = document.getElementById('reboot-countdown');
    const countdownNumber = document.getElementById('countdown-number');
    const countdownDisplay = document.getElementById('countdown-display');
    
    rebootDialog.style.display = 'block';
    countdownTime = 5; // 重置为5秒
    
    // 更新显示
    countdownNumber.textContent = countdownTime;
    countdownDisplay.textContent = countdownTime + '秒';
    
    // 开始倒计时
    countdownTimer = setInterval(() => {
        countdownTime--;
        countdownNumber.textContent = countdownTime;
        countdownDisplay.textContent = countdownTime + '秒';
        
        if (countdownTime <= 0) {
            clearInterval(countdownTimer);
            rebootRouter();
        }
    }, 1000);
}

// 隐藏重启倒计时
function hideRebootCountdown() {
    const rebootDialog = document.getElementById('reboot-countdown');
    rebootDialog.style.display = 'none';
    if (countdownTimer) {
        clearInterval(countdownTimer);
        countdownTimer = null;
    }
}

// 重启路由器
function rebootRouter() {
    hideRebootCountdown();
    showStatus('正在重启路由器，请等待约1分钟后重新访问...', 'info');
    
    fetch('<%=luci.dispatcher.build_url("admin/system/overlay-backup/reboot")%>', {
        method: 'POST'
    })
    .then(response => response.json())
    .then(result => {
        if (result.success) {
            showStatus('路由器重启命令已发送', 'success');
        } else {
            showStatus('重启失败，请手动重启', 'error');
        }
    })
    .catch(error => {
        // 请求可能因为重启而中断，这是正常的
        showStatus('路由器正在重启，请等待约1分钟后重新访问...', 'info');
    });
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    // 加载备份列表
    loadBackupList();
    
    // 创建备份按钮
    const createBackupBtn = document.getElementById('create-backup');
    createBackupBtn.addEventListener('click', function() {
        this.disabled = true;
        const originalText = this.textContent;
        this.textContent = '创建中...';
        
        fetch('<%=luci.dispatcher.build_url("admin/system/overlay-backup/create")%>')
            .then(response => response.json())
            .then(result => {
                if (result.success) {
                    showStatus('备份创建成功', 'success');
                    loadBackupList();
                } else {
                    showStatus(result.message, 'error');
                }
            })
            .finally(() => {
                this.disabled = false;
                this.textContent = originalText;
            });
    });
    
    // 刷新列表按钮
    document.getElementById('refresh-list').addEventListener('click', function() {
        loadBackupList();
        showStatus('备份列表已刷新', 'info');
    });
    
    // 恢复确认对话框事件
    document.getElementById('confirm-cancel').addEventListener('click', hideRestoreConfirm);
    document.getElementById('confirm-restore').addEventListener('click', performRestore);
    
    // 点击背景关闭对话框
    document.getElementById('restore-confirm').addEventListener('click', function(e) {
        if (e.target === this) {
            hideRestoreConfirm();
        }
    });
    
    // 重启对话框事件
    document.getElementById('reboot-now').addEventListener('click', rebootRouter);
    document.getElementById('cancel-reboot').addEventListener('click', hideRebootCountdown);
});
</script>

<style>
/* 简约按钮样式 */
.btn-primary, .btn-secondary, .btn-danger, .btn-neutral {
    padding: 8px 16px;
    border: none;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.3s ease;
    text-align: center;
    min-width: 80px;
    text-decoration: none;
    display: inline-block;
}

.btn-primary {
    background: #4CAF50;
    color: white;
}

.btn-secondary {
    background: #2196F3;
    color: white;
}

.btn-danger {
    background: #f44336;
    color: white;
}

.btn-neutral {
    background: #607D8B;
    color: white;
}

.btn-small {
    padding: 6px 12px;
    font-size: 12px;
    min-width: 60px;
}

.btn-primary:hover, .btn-secondary:hover, .btn-danger:hover, .btn-neutral:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 8px rgba(0, 0, 0, 0.15);
    opacity: 0.9;
}

/* 简约表格样式 */
.backup-table {
    border: 1px solid #e1e8ed;
    border-radius: 8px;
    overflow: hidden;
    background: white;
}

.table-header {
    display: flex;
    background: #f8f9fa;
    border-bottom: 1px solid #e1e8ed;
    font-weight: 600;
    color: #2c3e50;
}

.table-row {
    display: flex;
    border-bottom: 1px solid #f1f1f1;
    align-items: center;
    min-height: 60px;
    transition: background-color 0.2s ease;
}

.table-row:hover {
    background-color: #f8f9fa;
}

.table-row:last-child {
    border-bottom: none;
}

.table-cell {
    padding: 12px 15px;
    display: flex;
    flex-direction: column;
    justify-content: center;
}

/* 响应式设计 */
@media (max-width: 768px) {
    .table-header, .table-row {
        flex-wrap: wrap;
    }
    
    .table-cell {
        width: 100% !important;
        padding: 8px 12px;
    }
    
    .table-cell:last-child {
        border-top: 1px dashed #e1e8ed;
        padding-top: 12px;
    }
}

/* 状态消息样式 */
.alert-message {
    padding: 12px 15px;
    border-radius: 6px;
    margin: 10px 0;
    font-size: 14px;
}

.alert-message.success {
    background: #d4edda;
    color: #155724;
    border: 1px solid #c3e6cb;
}

.alert-message.error {
    background: #f8d7da;
    color: #721c24;
    border: 1px solid #f5c6cb;
}

.alert-message.info {
    background: #d1ecf1;
    color: #0c5460;
    border: 1px solid #bee5eb;
}

/* 整体页面样式优化 */
.cbi-map {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
}

.cbi-section {
    margin-bottom: 20px;
}

.cbi-value-title {
    color: #34495e;
    font-weight: 600;
}
</style>
<%+footer%>
EOF

# 创建优化的备份主脚本
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh
# 简约风格的Overlay备份工具

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
    
    # 停止服务（更彻底）
    /etc/init.d/uhttpd stop 2>/dev/null || true
    /etc/init.d/firewall stop 2>/dev/null || true
    /etc/init.d/dnsmasq stop 2>/dev/null || true
    /etc/init.d/network stop 2>/dev/null || true
    sleep 3
    
    # 清理可能存在的临时配置
    echo "清理临时配置..."
    rm -rf /tmp/luci-* 2>/dev/null || true
    rm -rf /tmp/.uci 2>/dev/null || true
    
    # 恢复备份
    echo "正在恢复文件..."
    if tar -xzf "${backup_file}" -C / ; then
        echo "文件恢复完成"
        
        # 强制重新加载所有配置
        echo "重新加载配置..."
        uci commit 2>/dev/null || true
        
        # 重新启动服务
        echo "正在启动服务..."
        /etc/init.d/network start 2>/dev/null || true
        sleep 2
        /etc/init.d/dnsmasq start 2>/dev/null || true
        /etc/init.d/firewall start 2>/dev/null || true
        /etc/init.d/uhttpd start 2>/dev/null || true
        
        echo ""
        echo "恢复成功！"
        echo "所有配置已从备份文件恢复"
        echo ""
        echo "重要提示：系统将自动重启以确保："
        echo "   所有服务使用恢复后的配置重新启动"
        echo "   清理内存中旧配置的缓存数据"
        echo "   避免运行中程序配置不一致的问题"
        echo "   保证网络服务的稳定运行"
        echo ""
        echo "请等待系统自动重启..."
        return 0
    else
        echo "恢复失败！"
        echo "正在尝试恢复基本服务..."
        
        # 尝试重新启动服务
        /etc/init.d/network start 2>/dev/null || true
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

# ==================== 4. 简约风格的USB自动挂载 ====================
echo "配置简约风格的USB自动挂载..."

# 创建USB自动挂载配置
mkdir -p files/etc/hotplug.d/block
cat > files/etc/hotplug.d/block/10-mount << 'EOF'
#!/bin/sh
# USB设备自动挂载脚本 - 简约版本

[ -z "$DEVNAME" ] && exit 0

logger "USB存储设备事件: ACTION=$ACTION, DEVICE=$DEVNAME"

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
            echo "挂载成功!"
            echo "设备已挂载到: $MOUNT_POINT"
            
            # 创建便捷访问链接
            if [ ! -L "/mnt/usb" ] && [ ! -e "/mnt/usb" ]; then
                ln -sf "$MOUNT_POINT" "/mnt/usb"
                echo "创建符号链接: /mnt/usb -> $MOUNT_POINT"
            fi
            
            # 显示使用情况
            df -h "$MOUNT_POINT"
        else
            echo "挂载失败!"
            rmdir "$MOUNT_POINT" 2>/dev/null
        fi
        ;;
    *)
        echo "不支持的文件系统: $TYPE"
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

echo ""
echo "=========================================="
echo "✅ 简约风格Overlay备份系统完成！"
echo "=========================================="
echo "🎨 设计特点:"
echo ""
echo "🔹 简约按钮设计:"
echo "  • 主按钮：创建备份 (绿色)、刷新列表 (蓝色)"
echo "  • 操作按钮：恢复 (绿色)、下载 (蓝色)、删除 (红色)"
echo "  • 对话框按钮：确认 (绿色)、取消 (灰色)"
echo ""
echo "🔹 优雅的表格布局:"
echo "  • 文件名 (45%)：主文件名 + 路径信息"
echo "  • 文件大小 (15%)：居中对齐，使用等宽字体"
echo "  • 备份时间 (25%)：完整时间格式"
echo "  • 操作按钮 (15%)：三个小按钮水平排列"
echo ""
echo "🔹 现代化界面元素:"
echo "  • 圆角设计，柔和阴影"
echo "  • 悬停效果，交互反馈"
echo "  • 响应式布局，适配移动设备"
echo "  • 统一的色彩方案"
echo ""
echo "🔹 功能完整性:"
echo "  • 恢复功能彻底修复"
echo "  • 所有按钮文字清晰可见"
echo "  • 状态提示明确直观"
echo "  • 对话框设计专业"
echo ""
echo "💡 使用说明:"
echo "  • 备份恢复: 系统 → Overlay Backup"
echo "  • 恢复功能现在可以正常使用"
echo "  • 界面简洁美观，操作直观"
echo "=========================================="
