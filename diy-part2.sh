#!/bin/bash
# =============================================
# OpenWrt DIY 脚本第二部分 - 彻底修复恢复功能
# 修复内容：
# 1. 彻底修复恢复功能文件传递问题
# 2. 恢复按钮文字加大并居中
# 3. 优化文件名和日期显示布局
# =============================================

echo "开始应用 WNDR3800 彻底修复配置..."

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

# ==================== 3. 彻底修复的Overlay备份系统 ====================
echo "创建彻底修复的Overlay备份系统..."

mkdir -p files/usr/lib/lua/luci/controller/admin
mkdir -p files/usr/lib/lua/luci/view/admin_system
mkdir -p files/usr/bin

# 创建优化的控制器 - 彻底修复文件传递问题
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
    
    -- 关键修复：多种方式获取文件名参数
    local filename
    
    -- 方法1：从POST表单获取
    filename = http.formvalue("filename")
    
    -- 方法2：从URL参数获取（备用）
    if not filename or filename == "" then
        filename = http.formvalue("file")
    end
    
    -- 方法3：从查询字符串获取（备用）
    if not filename or filename == "" then
        local query_string = os.getenv("QUERY_STRING")
        if query_string then
            for k, v in query_string:gmatch("([^&=]+)=([^&=]+)") do
                if k == "filename" then
                    filename = v
                    break
                end
            end
        end
    end
    
    -- 最终检查
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
    
    -- URL解码文件名（防止特殊字符问题）
    filepath = filepath:gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end)
    
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

# 创建彻底优化的Web界面模板 - 修复文件传递问题
cat > files/usr/lib/lua/luci/view/admin_system/overlay_backup.htm << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:Overlay Backup%></h2>
    
    <div class="alert-message success" style="background: #d4edda; color: #155724; border: 1px solid #c3e6cb; padding: 15px; margin-bottom: 20px;">
        <h4 style="margin: 0 0 10px 0; color: #155724;">Overlay备份系统 - 已修复</h4>
        <ul style="margin: 0; padding-left: 20px;">
            <li>恢复功能已彻底修复</li>
            <li>恢复按钮加大并居中显示</li>
            <li>文件名和日期显示优化</li>
        </ul>
    </div>
    
    <div class="cbi-section">
        <h3><%:备份操作%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title"><%:快速操作%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                    <button id="create-backup" class="cbi-button cbi-button-apply" style="padding: 8px 16px; min-width: 120px;">
                        创建备份
                    </button>
                    <button id="refresh-list" class="cbi-button cbi-button-action" style="padding: 8px 16px; min-width: 120px;">
                        刷新列表
                    </button>
                </div>
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
                <div class="table-cell" style="width: 45%;"><%:文件名和备份时间%></div>
                <div class="table-cell" style="width: 15%;"><%:大小%></div>
                <div class="table-cell" style="width: 40%;"><%:操作%></div>
            </div>
            <div class="table-row" id="no-backups" style="display: none;">
                <div class="table-cell" colspan="3" style="text-align: center; padding: 30px; color: #999;">
                    <%:暂无备份文件，点击"创建备份"按钮生成第一个备份%>
                </div>
            </div>
        </div>
    </div>

    <!-- 恢复确认对话框 -->
    <div id="restore-confirm" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 1000;">
        <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; padding: 20px; border-radius: 5px; min-width: 400px;">
            <h3 style="margin-top: 0; color: #d32f2f;">警告：恢复操作</h3>
            <p>您即将恢复备份文件：<strong id="confirm-filename"></strong></p>
            <p style="color: #d32f2f; font-weight: bold;">此操作将覆盖当前的所有配置！</p>
            <p>恢复成功后系统将自动重启以确保配置完全生效。</p>
            <div style="text-align: right; margin-top: 20px;">
                <button id="confirm-cancel" class="cbi-button cbi-button-reset" style="padding: 8px 16px;">取消</button>
                <button id="confirm-restore" class="cbi-button cbi-button-apply" style="padding: 8px 16px; margin-left: 10px;">确认恢复</button>
            </div>
        </div>
    </div>

    <!-- 重启倒计时对话框 -->
    <div id="reboot-countdown" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.7); z-index: 1001;">
        <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; padding: 30px; border-radius: 8px; min-width: 450px; text-align: center;">
            <h2 style="color: #1890ff; margin-top: 0;">恢复成功</h2>
            <div style="font-size: 48px; color: #52c41a; margin: 20px 0; font-weight: bold;" id="countdown-number">5</div>
            <p style="font-size: 16px; margin: 10px 0;">系统将在 <span id="countdown-display" style="color: #1890ff; font-weight: bold;">5秒</span> 后自动重启</p>
            <div style="background: #f0f8ff; padding: 15px; border-radius: 5px; margin: 15px 0; text-align: left;">
                <h4 style="margin: 0 0 10px 0; color: #1890ff;">重启的重要性：</h4>
                <ul style="margin: 0; padding-left: 20px; color: #666;">
                    <li>确保所有服务使用恢复后的配置启动</li>
                    <li>清理内存中旧配置的缓存数据</li>
                    <li>避免运行中程序配置不一致的问题</li>
                    <li>保证网络服务的稳定运行</li>
                </ul>
            </div>
            <div style="display: flex; gap: 10px; justify-content: center;">
                <button id="reboot-now" class="cbi-button cbi-button-apply" style="padding: 8px 16px;">
                    立即重启
                </button>
                <button id="cancel-reboot" class="cbi-button cbi-button-reset" style="padding: 8px 16px;">
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
            const rows = table.querySelectorAll('.table-row:not(.table-titles):not(#no-backups)');
            rows.forEach(row => row.remove());
            
            if (backups.length === 0) {
                noBackups.style.display = '';
                return;
            }
            
            noBackups.style.display = 'none';
            
            // 填充表格 - 优化布局
            backups.forEach(backup => {
                const row = document.createElement('div');
                row.className = 'table-row';
                row.innerHTML = `
                    <div class="table-cell" style="width: 45%;">
                        <div style="font-weight: bold; word-break: break-all; font-size: 13px; line-height: 1.3;">
                            ${backup.name}
                        </div>
                        <div style="font-size: 11px; color: #666; margin-top: 4px;">
                            备份时间: ${backup.formatted_time}
                        </div>
                    </div>
                    <div class="table-cell" style="width: 15%;">
                        <div style="font-family: monospace; white-space: nowrap; font-size: 12px; text-align: center;">${formatFileSize(backup.size)}</div>
                    </div>
                    <div class="table-cell" style="width: 40%;">
                        <div style="display: flex; gap: 6px; flex-wrap: nowrap; justify-content: center;">
                            <button class="cbi-button cbi-button-apply restore-btn" 
                                    data-file="${backup.name}" 
                                    style="padding: 6px 12px; font-size: 13px; min-width: 70px; text-align: center;"
                                    title="恢复此备份">
                                恢复
                            </button>
                            <button class="cbi-button cbi-button-action download-btn" 
                                    data-file="${backup.path}" 
                                    style="padding: 6px 12px; font-size: 13px; min-width: 70px; text-align: center;"
                                    title="下载备份文件">
                                下载
                            </button>
                            <button class="cbi-button cbi-button-reset delete-btn" 
                                    data-file="${backup.path}" 
                                    data-name="${backup.name}" 
                                    style="padding: 6px 12px; font-size: 13px; min-width: 70px; text-align: center;"
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
    const className = type === 'error' ? 'alert-message error' : 
                     type === 'success' ? 'alert-message success' : 'alert-message info';
    
    statusDiv.innerHTML = `<div class="${className}">${message}</div>`;
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

// 执行恢复操作 - 关键修复：使用URL参数而不是POST
function performRestore() {
    if (!currentRestoreFile) {
        showStatus('未选择恢复文件', 'error');
        return;
    }
    
    hideRestoreConfirm();
    showStatus('正在恢复备份，请稍候...', 'info');
    
    // 关键修复：使用URL参数传递文件名，与下载/删除保持一致
    const url = '<%=luci.dispatcher.build_url("admin/system/overlay-backup/restore")%>?filename=' + encodeURIComponent(currentRestoreFile);
    
    fetch(url, {
        method: 'POST'
    })
    .then(response => response.json())
    .then(result => {
        if (result.success) {
            // 恢复成功，显示重启倒计时
            showRebootCountdown();
        } else {
            showStatus(result.message, 'error');
        }
    })
    .catch(error => {
        showStatus('恢复失败: ' + error, 'error');
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
            showStatus(result.message, 'success');
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
                    showStatus(result.message, 'success');
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
/* 简化按钮样式 */
.cbi-button {
    border: 1px solid #ccc;
    border-radius: 4px;
    text-decoration: none;
    cursor: pointer;
    transition: all 0.2s;
    margin: 1px;
    font-weight: bold;
    text-align: center;
}

.cbi-button-apply {
    background: #4CAF50;
    color: white;
    border-color: #4CAF50;
    font-size: 13px;
}

.cbi-button-action {
    background: #2196F3;
    color: white;
    border-color: #2196F3;
    font-size: 13px;
}

.cbi-button-reset {
    background: #f44336;
    color: white;
    border-color: #f44336;
    font-size: 13px;
}

.cbi-button:hover {
    opacity: 0.9;
    transform: translateY(-1px);
}

/* 表格样式优化 */
.table {
    border: 1px solid #ddd;
    border-radius: 4px;
    width: 100%;
}

.table-titles {
    background: #f5f5f5;
    border-bottom: 1px solid #ddd;
    font-weight: bold;
    display: flex;
}

.table-cell {
    padding: 12px 8px;
    border-right: 1px solid #eee;
    display: flex;
    flex-direction: column;
    justify-content: center;
}

.table-cell:last-child {
    border-right: none;
}

.table-row {
    border-bottom: 1px solid #eee;
    display: flex;
    align-items: stretch;
    min-height: 60px;
}

.table-row:last-child {
    border-bottom: none;
}

.table-row:hover {
    background: #f9f9f9;
}

/* 状态消息样式 */
.alert-message {
    padding: 10px 15px;
    border-radius: 4px;
    margin: 10px 0;
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

/* 文件名显示优化 */
.file-name {
    font-weight: bold;
    word-break: break-all;
    line-height: 1.3;
}

.file-time {
    font-size: 11px;
    color: #666;
    margin-top: 4px;
}
</style>
<%+footer%>
EOF

# 创建优化的备份主脚本
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh
# 优化的Overlay备份工具 - 完整修复版本

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

# 其他部分保持不变...
# ==================== 4. 彻底修复USB自动挂载 ====================
echo "彻底修复USB自动挂载..."

# 创建USB自动挂载配置
mkdir -p files/etc/hotplug.d/block
cat > files/etc/hotplug.d/block/10-mount << 'EOF'
#!/bin/sh
# USB设备自动挂载脚本 - 增强版本

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

echo ""
echo "=========================================="
echo "✅ WNDR3800 彻底修复完成！"
echo "=========================================="
echo "📋 修复内容:"
echo ""
echo "🔧 恢复功能彻底修复:"
echo "  • ✅ 后端Lua控制器：多种方式获取文件名参数"
echo "  • ✅ 前端JavaScript：使用URL参数传递文件名"
echo "  • ✅ 统一参数传递方式：与下载/删除保持一致"
echo "  • ✅ 增加URL解码：处理特殊字符问题"
echo ""
echo "🎨 界面优化:"
echo "  • ✅ 恢复按钮文字加大并居中"
echo "  • ✅ 文件名显示区域增加到45%"
echo "  • ✅ 备份日期在文件名下方单独显示"
echo "  • ✅ 操作按钮区域增加到40%"
echo ""
echo "💡 技术说明:"
echo "  • 下载/删除：使用URL参数 ?file=xxx"
echo "  • 恢复功能：现在也使用URL参数 ?filename=xxx"
echo "  • 后端支持多种参数获取方式确保兼容性"
echo "=========================================="
