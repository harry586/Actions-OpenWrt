#!/bin/bash
# =============================================
# OpenWrt DIY 脚本第二部分 - 完全重写恢复功能
# 使用最简单可靠的方法解决参数传递问题
# =============================================

echo "开始应用完全重写的Overlay备份系统..."

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

# ==================== 3. 完全重写的Overlay备份系统 ====================
echo "创建完全重写的Overlay备份系统..."

mkdir -p files/usr/lib/lua/luci/controller/admin
mkdir -p files/usr/lib/lua/luci/view/admin_system
mkdir -p files/usr/bin

# 创建极度简化的控制器 - 只使用文件名
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
    
    -- 极度简化的参数获取 - 只使用文件名
    local filename = http.formvalue("filename")
    
    -- 记录调试信息
    sys.exec("logger '恢复调试 - 收到文件名: " .. (filename or "nil") .. "'")
    
    if not filename or filename == "" then
        http.prepare_content("application/json")
        http.write_json({success = false, message = "未选择恢复文件"})
        return
    end
    
    -- 构建完整路径
    local filepath = "/tmp/" .. filename
    
    -- 检查文件是否存在
    if not fs.stat(filepath) then
        http.prepare_content("application/json")
        http.write_json({success = false, message = "备份文件不存在: " .. filepath})
        return
    end
    
    sys.exec("logger '开始恢复文件: " .. filepath .. "'")
    
    -- 执行恢复
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

# 创建完全重写的Web界面 - 使用最简单的方法
cat > files/usr/lib/lua/luci/view/admin_system/overlay_backup.htm << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:系统配置备份与恢复%></h2>
    
    <div class="alert-message info">
        <h4><%:系统配置备份与恢复%></h4>
        <ul>
            <li>备份：保存当前系统配置和已安装软件</li>
            <li>恢复：从备份文件还原系统配置</li>
            <li>注意：恢复后系统会自动重启</li>
        </ul>
    </div>
    
    <div class="cbi-section">
        <h3><%:备份操作%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title"><%:快速操作%></label>
            <div class="cbi-value-field">
                <button id="create-backup" class="btn cbi-button cbi-button-apply">创建备份</button>
                <button id="refresh-list" class="btn cbi-button cbi-button-reset">刷新列表</button>
            </div>
        </div>
    </div>

    <!-- 操作状态显示 -->
    <div id="status-message"></div>

    <!-- 备份文件列表 -->
    <div class="cbi-section">
        <h3><%:备份文件列表%> <small>(保存在 /tmp 目录，重启后丢失)</small></h3>
        <div class="cbi-section-node">
            <div id="backup-list">
                <div class="table" style="width: 100%">
                    <div class="tr table-titles">
                        <div class="th" style="width: 40%">文件名</div>
                        <div class="th" style="width: 15%">大小</div>
                        <div class="th" style="width: 25%">备份时间</div>
                        <div class="th" style="width: 20%">操作</div>
                    </div>
                    <div id="backup-items"></div>
                </div>
            </div>
        </div>
    </div>
</div>

<script type="text/javascript">
// 全局变量
var currentRestoreFile = '';

// 加载备份文件列表
function loadBackupList() {
    XHR.get('<%=luci.dispatcher.build_url("admin/system/overlay-backup/list")%>', null, 
        function(x, data) {
            var items = document.getElementById('backup-items');
            items.innerHTML = '';
            
            if (!data || data.length === 0) {
                items.innerHTML = '<div class="tr"><div class="td" colspan="4" style="text-align: center; padding: 20px;">暂无备份文件</div></div>';
                return;
            }
            
            data.forEach(function(backup) {
                var row = document.createElement('div');
                row.className = 'tr cbi-rowstyle-1';
                row.innerHTML = 
                    '<div class="td" style="width: 40%">' +
                        '<div style="font-weight: bold">' + backup.name + '</div>' +
                        '<div style="font-size: 11px; color: #666">/tmp/' + backup.name + '</div>' +
                    '</div>' +
                    '<div class="td" style="width: 15%; text-align: center">' + formatFileSize(backup.size) + '</div>' +
                    '<div class="td" style="width: 25%">' + backup.formatted_time + '</div>' +
                    '<div class="td" style="width: 20%">' +
                        '<div style="display: flex; gap: 5px">' +
                            '<button class="btn cbi-button cbi-button-apply restore-btn" data-filename="' + backup.name + '" style="padding: 4px 8px; font-size: 12px">恢复</button>' +
                            '<button class="btn cbi-button cbi-button-download download-btn" data-file="' + backup.path + '" style="padding: 4px 8px; font-size: 12px">下载</button>' +
                            '<button class="btn cbi-button cbi-button-remove delete-btn" data-file="' + backup.path + '" data-name="' + backup.name + '" style="padding: 4px 8px; font-size: 12px">删除</button>' +
                        '</div>' +
                    '</div>';
                
                items.appendChild(row);
            });
            
            // 绑定事件
            bindTableEvents();
        }
    );
}

// 格式化文件大小
function formatFileSize(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

// 显示状态信息
function showStatus(message, type) {
    var statusDiv = document.getElementById('status-message');
    var className = 'alert-message';
    
    switch(type) {
        case 'success':
            className += ' success';
            break;
        case 'error':
            className += ' error';
            break;
        default:
            className += ' info';
    }
    
    statusDiv.innerHTML = '<div class="' + className + '">' + message + '</div>';
}

// 绑定表格事件
function bindTableEvents() {
    // 恢复按钮
    var restoreBtns = document.querySelectorAll('.restore-btn');
    for (var i = 0; i < restoreBtns.length; i++) {
        restoreBtns[i].onclick = function() {
            var filename = this.getAttribute('data-filename');
            if (confirm('确定要恢复备份文件: ' + filename + ' 吗？\n\n恢复后系统将自动重启！')) {
                restoreBackup(filename);
            }
        };
    }
    
    // 下载按钮
    var downloadBtns = document.querySelectorAll('.download-btn');
    for (var i = 0; i < downloadBtns.length; i++) {
        downloadBtns[i].onclick = function() {
            var file = this.getAttribute('data-file');
            window.location.href = '<%=luci.dispatcher.build_url("admin/system/overlay-backup/download")%>?file=' + encodeURIComponent(file);
        };
    }
    
    // 删除按钮
    var deleteBtns = document.querySelectorAll('.delete-btn');
    for (var i = 0; i < deleteBtns.length; i++) {
        deleteBtns[i].onclick = function() {
            var file = this.getAttribute('data-file');
            var name = this.getAttribute('data-name');
            if (confirm('确定删除备份文件: ' + name + ' 吗？')) {
                XHR.get('<%=luci.dispatcher.build_url("admin/system/overlay-backup/delete")%>?file=' + encodeURIComponent(file), null,
                    function(x, data) {
                        if (data && data.success) {
                            showStatus('备份文件已删除', 'success');
                            loadBackupList();
                        } else {
                            showStatus('删除失败: ' + (data ? data.message : '未知错误'), 'error');
                        }
                    }
                );
            }
        };
    }
}

// 恢复备份 - 使用最简单的方法
function restoreBackup(filename) {
    showStatus('正在恢复备份，请稍候...', 'info');
    
    // 使用LuCI原生的XHR方法，确保参数正确传递
    XHR.post('<%=luci.dispatcher.build_url("admin/system/overlay-backup/restore")%>', 
        { filename: filename },
        function(x, data) {
            if (data && data.success) {
                showStatus('恢复成功！系统将在5秒后自动重启...', 'success');
                
                // 显示重启倒计时
                var countdown = 5;
                var countdownInterval = setInterval(function() {
                    showStatus('恢复成功！系统将在' + countdown + '秒后自动重启...', 'success');
                    countdown--;
                    
                    if (countdown < 0) {
                        clearInterval(countdownInterval);
                        rebootRouter();
                    }
                }, 1000);
            } else {
                showStatus('恢复失败: ' + (data ? data.message : '未知错误'), 'error');
            }
        }
    );
}

// 重启路由器
function rebootRouter() {
    XHR.post('<%=luci.dispatcher.build_url("admin/system/overlay-backup/reboot")%>', null,
        function(x, data) {
            showStatus('路由器正在重启，请等待约1分钟后重新访问...', 'info');
        }
    );
}

// 页面加载完成后初始化
window.onload = function() {
    // 加载备份列表
    loadBackupList();
    
    // 创建备份按钮
    document.getElementById('create-backup').onclick = function() {
        var btn = this;
        btn.disabled = true;
        var originalText = btn.innerHTML;
        btn.innerHTML = '创建中...';
        
        XHR.get('<%=luci.dispatcher.build_url("admin/system/overlay-backup/create")%>', null,
            function(x, data) {
                if (data && data.success) {
                    showStatus('备份创建成功: ' + data.filename, 'success');
                    loadBackupList();
                } else {
                    showStatus('备份失败: ' + (data ? data.message : '未知错误'), 'error');
                }
                btn.disabled = false;
                btn.innerHTML = originalText;
            }
        );
    };
    
    // 刷新列表按钮
    document.getElementById('refresh-list').onclick = function() {
        loadBackupList();
        showStatus('备份列表已刷新', 'info');
    };
};
</script>

<style type="text/css">
.alert-message {
    padding: 10px 15px;
    margin: 10px 0;
    border-radius: 4px;
    border: 1px solid;
}

.alert-message.info {
    background: #d9edf7;
    border-color: #bce8f1;
    color: #31708f;
}

.alert-message.success {
    background: #dff0d8;
    border-color: #d6e9c6;
    color: #3c763d;
}

.alert-message.error {
    background: #f2dede;
    border-color: #ebccd1;
    color: #a94442;
}

.table {
    border-collapse: collapse;
    width: 100%;
}

.tr {
    display: table-row;
}

.th, .td {
    display: table-cell;
    padding: 8px 12px;
    border-bottom: 1px solid #ddd;
    vertical-align: top;
}

.table-titles {
    background: #f5f5f5;
    font-weight: bold;
}

.cbi-rowstyle-1 {
    background: #fff;
}

.cbi-rowstyle-1:hover {
    background: #f9f9f9;
}

.btn {
    display: inline-block;
    padding: 6px 12px;
    margin-bottom: 0;
    font-size: 14px;
    font-weight: normal;
    line-height: 1.42857143;
    text-align: center;
    white-space: nowrap;
    vertical-align: middle;
    cursor: pointer;
    border: 1px solid transparent;
    border-radius: 4px;
    text-decoration: none;
}

.cbi-button-apply {
    color: #fff;
    background-color: #5cb85c;
    border-color: #4cae4c;
}

.cbi-button-reset {
    color: #333;
    background-color: #fff;
    border-color: #ccc;
}

.cbi-button-download {
    color: #fff;
    background-color: #5bc0de;
    border-color: #46b8da;
}

.cbi-button-remove {
    color: #fff;
    background-color: #d9534f;
    border-color: #d43f3a;
}
</style>
<%+footer%>
EOF

# 创建优化的备份主脚本
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh
# Overlay备份工具

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

echo ""
echo "=========================================="
echo "Overlay备份系统完全重写完成"
echo "=========================================="
echo "【完全重写】恢复功能解决方案:"
echo ""
echo "问题分析:"
echo "  - 前端JavaScript事件绑定可能有问题"
echo "  - 参数传递方式过于复杂导致失败"
echo "  - 需要回归最简单可靠的方法"
echo ""
echo "解决方案:"
echo "  1. 极度简化前端:"
echo "     - 使用LuCI原生XHR方法替代fetch"
echo "     - 移除所有复杂的事件绑定"
echo "     - 使用最简单的参数传递方式"
echo ""
echo "  2. 简化后端:"
echo "     - 使用明确的参数名 'filename'"
echo "     - 移除复杂的参数获取逻辑"
echo "     - 只处理文件名，在后台构建完整路径"
echo ""
echo "  3. 简化用户交互:"
echo "     - 使用confirm对话框替代自定义模态框"
echo "     - 简化状态显示"
echo "     - 使用LuCI原生样式"
echo ""
echo "关键改变:"
echo "  - 恢复按钮: data-filename='仅文件名'"
echo "  - 后端参数: http.formvalue('filename')"
echo "  - 请求方法: XHR.post() 替代 fetch()"
echo "  - 文件路径: 后端自动构建 '/tmp/文件名'"
echo ""
echo "预期效果:"
echo "  ✓ 参数应该能正确传递到后端"
echo "  ✓ 系统日志应该显示正确的文件名"
echo "  ✓ 恢复功能应该能正常工作"
echo "=========================================="
