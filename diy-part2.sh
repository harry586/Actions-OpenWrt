#!/bin/bash

# OpenWrt DIY 脚本第二部分 - 改进备份结构和添加恢复功能

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

# 2. 创建改进的 Overlay 备份功能
echo "创建改进的 Overlay 备份功能..."
mkdir -p files/usr/lib/lua/luci/controller/admin
mkdir -p files/usr/lib/lua/luci/model/cbi/admin_system
mkdir -p files/usr/lib/lua/luci/view/admin_system

# 创建 Overlay 备份控制器
cat > files/usr/lib/lua/luci/controller/admin/overlay-backup.lua << 'EOF'
module("luci.controller.admin.overlay-backup", package.seeall)

function index()
    entry({"admin", "system", "overlay-backup"}, cbi("admin_system/overlay-backup"), _("Overlay Backup"), 80)
    entry({"admin", "system", "overlay-backup", "download-backup"}, call("download_backup")).leaf = true
    entry({"admin", "system", "overlay-backup", "delete-backup"}, call("delete_backup")).leaf = true
end

-- 下载备份文件
function download_backup()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    local file = http.formvalue("file")
    
    if file and fs.stat(file) then
        http.header('Content-Disposition', 'attachment; filename="' .. fs.basename(file) .. '"')
        http.header('Content-Type', 'application/octet-stream')
        
        local f = io.open(file, "rb")
        if f then
            local content = f:read("*a")
            f:close()
            http.write(content)
        else
            http.status(500, "Cannot read file")
        end
    else
        http.status(404, "File not found")
    end
end

-- 删除备份文件
function delete_backup()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    local file = http.formvalue("file")
    
    if file and fs.stat(file) then
        fs.unlink(file)
    end
    http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup"))
end
EOF

# 创建 Overlay 备份配置页面
cat > files/usr/lib/lua/luci/model/cbi/admin_system/overlay-backup.lua << 'EOF'
require("luci.sys")
require("luci.fs")
require("luci.http")

m = Map("overlay-backup", translate("Overlay Backup"), 
    translate("Backup and restore only the overlay partition (user configurations). Backups are saved to /tmp and should be downloaded immediately."))

s = m:section(TypedSection, "overlay-backup", "")
s.addremove = false
s.anonymous = true

-- 创建两列布局的按钮
local btn_section = s:option(DummyValue, "_buttons", "")
btn_section.template = "admin_system/backup_buttons"

-- 显示备份结果消息
local success_msg = s:option(DummyValue, "_success_msg", "")
success_msg.rawhtml = true
success_msg.cfgvalue = function(self, section)
    local success = luci.http.formvalue("backup_success")
    local file = luci.http.formvalue("file")
    local restore_success = luci.http.formvalue("restore_success")
    
    if success == "1" and file then
        file = luci.http.urldecode(file)
        local download_url = luci.dispatcher.build_url("admin/system/overlay-backup") .. "?download=" .. luci.http.urlencode("/tmp/" .. file)
        return '<div class="alert-message success" style="background: #d4edda; color: #155724; padding: 10px; border-radius: 4px; margin: 10px 0;">' ..
               '<strong>备份成功!</strong> 备份文件: ' .. file .. '<br>' ..
               '<a href="' .. download_url .. '" class="btn" style="background: #28a745; color: white; padding: 5px 10px; text-decoration: none; border-radius: 3px; margin-top: 5px; display: inline-block;">下载备份文件</a>' ..
               '</div>'
    elseif success == "0" then
        return '<div class="alert-message error" style="background: #f8d7da; color: #721c24; padding: 10px; border-radius: 4px; margin: 10px 0;">' ..
               '<strong>备份失败!</strong> 请检查系统日志获取详细信息。' ..
               '</div>'
    elseif restore_success == "1" then
        return '<div class="alert-message success" style="background: #d4edda; color: #155724; padding: 10px; border-radius: 4px; margin: 10px 0;">' ..
               '<strong>恢复成功!</strong> Overlay配置已从备份文件恢复，请重启路由器使更改生效。' ..
               '</div>'
    elseif restore_success == "0" then
        return '<div class="alert-message error" style="background: #f8d7da; color: #721c24; padding: 10px; border-radius: 4px; margin: 10px 0;">' ..
               '<strong>恢复失败!</strong> 请检查系统日志获取详细信息。' ..
               '</div>'
    end
    
    -- 处理下载请求
    local download_file = luci.http.formvalue("download")
    if download_file then
        download_file = luci.http.urldecode(download_file)
        if luci.fs.stat(download_file) then
            luci.http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup/download-backup") .. "?file=" .. luci.http.urlencode(download_file))
        end
    end
    
    return ""
end

-- 显示备份文件列表
local backup_list = s:option(DummyValue, "_backup_list", translate("Available Backups"))
backup_list.template = "admin_system/backup_list"

return m
EOF

# 创建按钮模板
mkdir -p files/usr/lib/lua/luci/view/admin_system
cat > files/usr/lib/lua/luci/view/admin_system/backup_buttons.htm << 'EOF'
<%+header%>
<div class="cbi-section">
    <div class="cbi-section-descr" style="margin-bottom: 15px;">
        <%=translate("Create a backup of the overlay partition or restore from an existing backup.")%>
    </div>
    
    <div class="cbi-value">
        <label class="cbi-value-title"><%=translate("Backup Actions")%></label>
        <div class="cbi-value-field">
            <div style="display: flex; gap: 10px;">
                <!-- 备份按钮 -->
                <form method="post" action="<%=luci.dispatcher.build_url('admin/system/overlay-backup')%>" style="margin: 0;">
                    <input type="hidden" name="cbi.submit" value="1">
                    <input type="hidden" name="cbi.cbe.overlay-backup._buttons.backup" value="1">
                    <button type="submit" name="cbi.apply" class="cbi-button cbi-button-apply" style="padding: 8px 16px;">
                        ➕ <%=translate("Create Backup")%>
                    </button>
                </form>
                
                <!-- 恢复按钮 -->
                <form method="post" action="<%=luci.dispatcher.build_url('admin/system/overlay-backup')%>" style="margin: 0;">
                    <input type="hidden" name="cbi.submit" value="1">
                    <input type="hidden" name="cbi.cbe.overlay-backup._buttons.restore" value="1">
                    <button type="submit" name="cbi.apply" class="cbi-button cbi-button-reset" style="padding: 8px 16px;">
                        🔄 <%=translate("Restore Backup")%>
                    </button>
                </form>
            </div>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // 处理恢复按钮点击
    const restoreBtn = document.querySelector('button[name="cbi.apply"][value="1"]');
    if (restoreBtn && restoreBtn.closest('form').querySelector('input[name="cbi.cbe.overlay-backup._buttons.restore"]')) {
        restoreBtn.addEventListener('click', function(e) {
            const backupFiles = document.querySelectorAll('.backup-file-item');
            if (backupFiles.length === 0) {
                e.preventDefault();
                alert('<%=translate("No backup files available for restoration.")%>');
                return false;
            }
            
            const selectedFile = prompt('<%=translate("Please enter the backup filename to restore:")%>\\n\\n<%=translate("Available files:")%>\\n' + 
                Array.from(backupFiles).map(f => ' - ' + f.textContent).join('\\n'));
            
            if (!selectedFile) {
                e.preventDefault();
                return false;
            }
            
            // 添加文件名到表单
            const form = this.closest('form');
            const input = document.createElement('input');
            input.type = 'hidden';
            input.name = 'restore_file';
            input.value = selectedFile;
            form.appendChild(input);
        });
    }
});
</script>
<%+footer%>
EOF

# 创建备份列表显示模板
cat > files/usr/lib/lua/luci/view/admin_system/backup_list.htm << 'EOF'
<%+header%>
<div class="cbi-section">
    <h3><%:Available Backup Files%></h3>
    <div class="table" style="max-height: 300px; overflow-y: auto;">
        <div class="table-row table-titles">
            <div class="table-cell" style="width: 45%;"><%:Filename%></div>
            <div class="table-cell" style="width: 20%;"><%:Size%></div>
            <div class="table-cell" style="width: 20%;"><%:Date%></div>
            <div class="table-cell" style="width: 15%;"><%:Actions%></div>
        </div>
        <%
        local fs = require "nixio.fs"
        local http = require "luci.http"
        local backup_files = {}
        
        -- 扫描/tmp目录中的备份文件
        if fs.stat("/tmp") then
            for file in fs.dir("/tmp") do
                if file:match("openwrt%-overlay%-backup%-.*%.tar%.gz") then
                    local full_path = "/tmp/" .. file
                    local stat = fs.stat(full_path)
                    if stat then
                        table.insert(backup_files, {
                            name = file,
                            path = full_path,
                            size = stat.size,
                            mtime = stat.mtime
                        })
                    end
                end
            end
        end
        
        -- 按修改时间排序
        table.sort(backup_files, function(a, b) return a.mtime > b.mtime end)
        
        for i, backup in ipairs(backup_files) do
        %>
        <div class="table-row">
            <div class="table-cell backup-file-item" style="width: 45%; word-break: break-all;"><%=backup.name%></div>
            <div class="table-cell" style="width: 20%;">
                <%
                local size = backup.size
                if size < 1024 then
                    write(string.format("%d B", size))
                elseif size < 1024 * 1024 then
                    write(string.format("%.1f KB", size / 1024))
                else
                    write(string.format("%.1f MB", size / (1024 * 1024)))
                end
                %>
            </div>
            <div class="table-cell" style="width: 20%;">
                <%=os.date("%m/%d %H:%M", backup.mtime)%>
            </div>
            <div class="table-cell" style="width: 15%;">
                <%
                local download_url = luci.dispatcher.build_url("admin/system/overlay-backup") .. "?download=" .. http.urlencode(backup.path)
                local delete_url = luci.dispatcher.build_url("admin/system/overlay-backup") .. "?delete=" .. http.urlencode(backup.path)
                %>
                <a href="<%=download_url%>" class="btn cbi-button cbi-button-apply" style="padding: 3px 8px; margin: 2px;">下载</a>
                <a href="<%=delete_url%>" class="btn cbi-button cbi-button-reset" style="padding: 3px 8px; margin: 2px;" onclick="return confirm('确定要删除这个备份文件吗？')">删除</a>
            </div>
        </div>
        <% end %>
        
        <% if #backup_files == 0 then %>
        <div class="table-row">
            <div class="table-cell" colspan="4" style="text-align: center; padding: 20px;"><%:No backup files found in /tmp directory%></div>
        </div>
        <% end %>
    </div>
    
    <div class="alert-message warning" style="background: #fff3cd; color: #856404; padding: 10px; border-radius: 4px; margin: 10px 0;">
        <strong>注意:</strong> 备份文件保存在 /tmp 目录中，重启后会丢失。请及时下载重要的备份文件到本地计算机。
    </div>
</div>

<script>
// 处理下载和删除操作
document.addEventListener('DOMContentLoaded', function() {
    // 检查URL参数，处理下载和删除
    const urlParams = new URLSearchParams(window.location.search);
    
    // 处理下载
    if (urlParams.has('download')) {
        const file = urlParams.get('download');
        window.location.href = '<%=luci.dispatcher.build_url("admin/system/overlay-backup/download-backup")%>?file=' + encodeURIComponent(file);
    }
    
    // 处理删除
    if (urlParams.has('delete')) {
        const file = urlParams.get('delete');
        if (confirm('确定要删除备份文件 ' + file + ' 吗？')) {
            window.location.href = '<%=luci.dispatcher.build_url("admin/system/overlay-backup/delete-backup")%>?file=' + encodeURIComponent(file);
        } else {
            // 移除删除参数，刷新页面
            urlParams.delete('delete');
            const newUrl = window.location.pathname + '?' + urlParams.toString();
            window.history.replaceState({}, '', newUrl);
        }
    }
    
    // 处理恢复操作
    const restoreForm = document.querySelector('form input[name="cbi.cbe.overlay-backup._buttons.restore"]');
    if (restoreForm) {
        restoreForm.closest('form').addEventListener('submit', function(e) {
            const backupFiles = document.querySelectorAll('.backup-file-item');
            if (backupFiles.length === 0) {
                e.preventDefault();
                alert('没有可用的备份文件用于恢复。');
                return false;
            }
            
            const fileList = Array.from(backupFiles).map(f => f.textContent).join(', ');
            const selectedFile = prompt('请输入要恢复的备份文件名：\n\n可用文件:\n' + 
                Array.from(backupFiles).map(f => ' - ' + f.textContent).join('\n'));
            
            if (!selectedFile) {
                e.preventDefault();
                return false;
            }
            
            // 验证文件是否存在
            const fileExists = Array.from(backupFiles).some(f => f.textContent === selectedFile);
            if (!fileExists) {
                e.preventDefault();
                alert('指定的备份文件不存在: ' + selectedFile);
                return false;
            }
            
            // 添加确认
            if (!confirm('警告：这将覆盖当前的所有配置！\n确定要恢复备份文件: ' + selectedFile + ' 吗？')) {
                e.preventDefault();
                return false;
            }
            
            // 添加文件名到表单
            const input = document.createElement('input');
            input.type = 'hidden';
            input.name = 'restore_file';
            input.value = selectedFile;
            this.appendChild(input);
        });
    }
});
</script>
<%+footer%>
EOF

# 创建改进的 Overlay 备份主脚本（包含 overlay 目录结构）
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh

ACTION="$1"
PARAM="$2"

usage() {
    echo "Usage: $0 {backup|restore [backup_file]}"
    echo "  backup   - Create overlay backup in /tmp"
    echo "  restore  - Restore from backup file"
    exit 1
}

create_backup() {
    echo "Creating overlay backup in /tmp..."
    
    # 确保/tmp目录可写
    if [ ! -w "/tmp" ]; then
        echo "Error: /tmp directory is not writable!"
        return 1
    fi
    
    local backup_file="openwrt-overlay-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    local backup_path="/tmp/$backup_file"
    local temp_dir="/tmp/backup_temp_$$"
    
    # 创建临时目录
    mkdir -p "$temp_dir"
    
    # 复制 overlay 内容到临时目录的 overlay 子目录
    echo "Copying overlay to temporary directory..."
    mkdir -p "$temp_dir/overlay"
    cp -a /overlay/. "$temp_dir/overlay/"
    
    # 创建备份（包含 overlay 目录结构）
    echo "Creating backup archive..."
    if tar -czf "$backup_path" -C "$temp_dir" overlay 2>/dev/null; then
        local file_size=$(du -h "$backup_path" | cut -f1)
        echo "Backup created: $backup_file"
        echo "Backup location: $backup_path"
        echo "File size: $file_size"
        echo "Backup structure: Contains 'overlay/' directory"
        
        # 显示备份内容结构
        echo "Backup contents:"
        tar -tzf "$backup_path" | head -10
        echo "..."
        
        logger "Overlay backup created: $backup_path ($file_size)"
        
        # 清理临时目录
        rm -rf "$temp_dir"
        return 0
    else
        echo "Error: Backup creation failed!"
        # 清理临时文件和目录
        rm -rf "$temp_dir"
        if [ -f "$backup_path" ]; then
            rm -f "$backup_path"
        fi
        return 1
    fi
}

restore_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        echo "Error: Please specify backup file"
        return 1
    fi
    
    # 如果只提供了文件名，没有路径，假设在/tmp
    if [ "$(dirname "$backup_file")" = "." ]; then
        backup_file="/tmp/$backup_file"
    fi
    
    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file not found: $backup_file"
        return 1
    fi
    
    echo "Restoring from backup: $backup_file"
    echo "Checking backup structure..."
    
    # 检查备份文件结构
    if tar -tzf "$backup_file" | grep -q '^overlay/'; then
        echo "Backup structure: Contains 'overlay/' directory (correct format)"
    else
        echo "Warning: Backup does not contain 'overlay/' directory root"
        echo "This backup might be in old format, attempting to restore anyway..."
    fi
    
    echo "WARNING: This will overwrite current configuration!"
    read -p "Continue? [y/N] " confirm
    case "$confirm" in
        y|Y|yes|YES)
            # 停止服务
            echo "Stopping services..."
            /etc/init.d/uhttpd stop
            /etc/init.d/firewall stop
            /etc/init.d/dnsmasq stop
            sleep 2
            
            # 清空当前 overlay（保留必要的结构）
            echo "Clearing current overlay..."
            find /overlay -mindepth 1 -maxdepth 1 -exec rm -rf {} \; 2>/dev/null || true
            
            # 恢复备份
            echo "Restoring overlay..."
            if tar -xzf "$backup_file" -C / --strip-components=1 2>/dev/null; then
                echo "Backup restored using strip-components method"
            else
                # 尝试直接解压到 overlay
                echo "Trying alternative restore method..."
                tar -xzf "$backup_file" -C /overlay 2>/dev/null
            fi
            
            # 重启服务
            echo "Starting services..."
            /etc/init.d/dnsmasq start
            /etc/init.d/firewall start
            /etc/init.d/uhttpd start
            
            echo "Backup restored successfully!"
            echo "Please reboot the router to ensure all changes take effect."
            logger "Overlay backup restored from: $backup_file"
            ;;
        *)
            echo "Restore cancelled."
            ;;
    esac
}

case "$ACTION" in
    backup)
        create_backup
        ;;
    restore)
        restore_backup "$PARAM"
        ;;
    *)
        usage
        ;;
esac
EOF
chmod +x files/usr/bin/overlay-backup

# 3. 修改 LuCI 控制器以处理恢复操作
cat >> files/usr/lib/lua/luci/controller/admin/overlay-backup.lua << 'EOF'

-- 处理备份和恢复操作
function index()
    entry({"admin", "system", "overlay-backup"}, call("action_overlay_backup"), _("Overlay Backup"), 80)
    entry({"admin", "system", "overlay-backup", "download-backup"}, call("download_backup")).leaf = true
    entry({"admin", "system", "overlay-backup", "delete-backup"}, call("delete_backup")).leaf = true
end

function action_overlay_backup()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    
    -- 处理恢复操作
    local restore_file = http.formvalue("restore_file")
    if restore_file then
        -- 如果只提供了文件名，没有路径，假设在/tmp
        if restore_file:match("^[^/]+$") then
            restore_file = "/tmp/" .. restore_file
        end
        
        if fs.stat(restore_file) then
            local cmd = "/usr/bin/overlay-backup restore '" .. restore_file .. "' 2>&1"
            local result = os.execute(cmd)
            
            if result == 0 then
                http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?restore_success=1")
            else
                http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?restore_success=0")
            end
        else
            http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?restore_success=0")
        end
        return
    end
    
    -- 处理备份操作
    local backup_action = http.formvalue("cbi.cbe.overlay-backup._buttons.backup")
    if backup_action then
        local cmd = "/usr/bin/overlay-backup backup"
        local result = luci.sys.exec(cmd)
        
        -- 解析备份结果
        local filename = nil
        for line in result:gmatch("[^\r\n]+") do
            if line:match("Backup created:") then
                filename = line:match("Backup created: ([^%s]+)")
                break
            end
        end
        
        if filename then
            http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?backup_success=1&file=" .. luci.http.urlencode(filename))
        else
            http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?backup_success=0")
        end
        return
    end
    
    -- 显示配置页面
    luci.template.render("admin_system/overlay_backup")
end
EOF

# 4. 创建主页面模板
cat > files/usr/lib/lua/luci/view/admin_system/overlay_backup.htm << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:Overlay Backup%></h2>
    <div class="cbi-map-descr">
        <%:Backup and restore only the overlay partition (user configurations). Backups are saved to /tmp and should be downloaded immediately.%>
    </div>
    
    <!-- 操作按钮 -->
    <div class="cbi-section">
        <div class="cbi-section-descr" style="margin-bottom: 15px;">
            <%:Create a backup of the overlay partition or restore from an existing backup.%>
        </div>
        
        <div class="cbi-value">
            <label class="cbi-value-title"><%:Backup Actions%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 10px;">
                    <!-- 备份按钮 -->
                    <form method="post" action="<%=luci.dispatcher.build_url('admin/system/overlay-backup')%>" style="margin: 0;">
                        <input type="hidden" name="cbi.cbe.overlay-backup._buttons.backup" value="1">
                        <button type="submit" class="cbi-button cbi-button-apply" style="padding: 8px 16px;">
                            ➕ <%:Create Backup%>
                        </button>
                    </form>
                    
                    <!-- 恢复按钮 -->
                    <form method="post" action="<%=luci.dispatcher.build_url('admin/system/overlay-backup')%>" style="margin: 0;">
                        <input type="hidden" name="cbi.cbe.overlay-backup._buttons.restore" value="1">
                        <button type="submit" class="cbi-button cbi-button-reset" style="padding: 8px 16px;">
                            🔄 <%:Restore Backup%>
                        </button>
                    </form>
                </div>
            </div>
        </div>
    </div>
    
    <!-- 显示操作结果 -->
    <% 
    local success = luci.http.formvalue("backup_success")
    local file = luci.http.formvalue("file")
    local restore_success = luci.http.formvalue("restore_success")
    
    if success == "1" and file then
        file = luci.http.urldecode(file)
        local download_url = luci.dispatcher.build_url("admin/system/overlay-backup") .. "?download=" .. luci.http.urlencode("/tmp/" .. file)
    %>
    <div class="alert-message success" style="background: #d4edda; color: #155724; padding: 10px; border-radius: 4px; margin: 10px 0;">
        <strong><%:备份成功!%></strong> <%:备份文件:%> <%=file%><br>
        <a href="<%=download_url%>" class="btn" style="background: #28a745; color: white; padding: 5px 10px; text-decoration: none; border-radius: 3px; margin-top: 5px; display: inline-block;"><%:下载备份文件%></a>
    </div>
    <% elseif success == "0" then %>
    <div class="alert-message error" style="background: #f8d7da; color: #721c24; padding: 10px; border-radius: 4px; margin: 10px 0;">
        <strong><%:备份失败!%></strong> <%:请检查系统日志获取详细信息。%>
    </div>
    <% elseif restore_success == "1" then %>
    <div class="alert-message success" style="background: #d4edda; color: #155724; padding: 10px; border-radius: 4px; margin: 10px 0;">
        <strong><%:恢复成功!%></strong> <%:Overlay配置已从备份文件恢复，请重启路由器使更改生效。%>
    </div>
    <% elseif restore_success == "0" then %>
    <div class="alert-message error" style="background: #f8d7da; color: #721c24; padding: 10px; border-radius: 4px; margin: 10px 0;">
        <strong><%:恢复失败!%></strong> <%:请检查系统日志获取详细信息。%>
    </div>
    <% end %>
    
    <!-- 备份文件列表 -->
    <%+admin_system/backup_list%>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // 处理恢复按钮点击
    const restoreBtn = document.querySelector('form input[name="cbi.cbe.overlay-backup._buttons.restore"]');
    if (restoreBtn) {
        restoreBtn.closest('form').addEventListener('submit', function(e) {
            const backupFiles = document.querySelectorAll('.backup-file-item');
            if (backupFiles.length === 0) {
                e.preventDefault();
                alert('<%:No backup files available for restoration.%>');
                return false;
            }
            
            const fileList = Array.from(backupFiles).map(f => f.textContent).join(', ');
            const selectedFile = prompt('<%:Please enter the backup filename to restore:%>\n\n<%:Available files:%>\n' + 
                Array.from(backupFiles).map(f => ' - ' + f.textContent).join('\n'));
            
            if (!selectedFile) {
                e.preventDefault();
                return false;
            }
            
            // 验证文件是否存在
            const fileExists = Array.from(backupFiles).some(f => f.textContent === selectedFile);
            if (!fileExists) {
                e.preventDefault();
                alert('<%:The specified backup file does not exist:%> ' + selectedFile);
                return false;
            }
            
            // 添加确认
            if (!confirm('<%:Warning: This will overwrite all current configurations!%>\n<%:Are you sure you want to restore backup file:%> ' + selectedFile + '?')) {
                e.preventDefault();
                return false;
            }
            
            // 添加文件名到表单
            const input = document.createElement('input');
            input.type = 'hidden';
            input.name = 'restore_file';
            input.value = selectedFile;
            this.appendChild(input);
        });
    }
    
    // 处理下载和删除操作
    const urlParams = new URLSearchParams(window.location.search);
    
    // 处理下载
    if (urlParams.has('download')) {
        const file = urlParams.get('download');
        window.location.href = '<%=luci.dispatcher.build_url("admin/system/overlay-backup/download-backup")%>?file=' + encodeURIComponent(file);
    }
    
    // 处理删除
    if (urlParams.has('delete')) {
        const file = urlParams.get('delete');
        if (confirm('<%:Are you sure you want to delete this backup file?%>')) {
            window.location.href = '<%=luci.dispatcher.build_url("admin/system/overlay-backup/delete-backup")%>?file=' + encodeURIComponent(file);
        } else {
            urlParams.delete('delete');
            const newUrl = window.location.pathname + '?' + urlParams.toString();
            window.history.replaceState({}, '', newUrl);
        }
    }
});
</script>
<%+footer%>
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
