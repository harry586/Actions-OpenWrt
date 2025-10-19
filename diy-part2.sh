#!/bin/bash

# OpenWrt DIY 脚本第二部分 - 修复备份功能

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

# 2. 创建修复的 Overlay 备份功能
echo "创建修复的 Overlay 备份功能..."
mkdir -p files/usr/lib/lua/luci/controller/admin
mkdir -p files/usr/lib/lua/luci/model/cbi/admin_system
mkdir -p files/usr/lib/lua/luci/view/admin_system

# 创建 Overlay 备份控制器 - 只保留一个菜单项
cat > files/usr/lib/lua/luci/controller/admin/overlay-backup.lua << 'EOF'
module("luci.controller.admin.overlay-backup", package.seeall)

function index()
    entry({"admin", "system", "overlay-backup"}, cbi("admin_system/overlay-backup"), _("Overlay Backup"), 80)
end

-- 下载备份文件（不显示在菜单中）
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

-- 删除备份文件（不显示在菜单中）
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

-- 备份按钮
backup_btn = s:option(Button, "backup", translate("Create Overlay Backup"))
backup_btn.inputtitle = translate("Create Backup Now")
backup_btn.inputstyle = "apply"
function backup_btn.write(self, section)
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
        luci.http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?backup_success=1&file=" .. luci.http.urlencode(filename))
    else
        luci.http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?backup_success=0")
    end
end

-- 显示备份结果消息
local success_msg = s:option(DummyValue, "_success_msg", "")
success_msg.rawhtml = true
success_msg.cfgvalue = function(self, section)
    local success = luci.http.formvalue("backup_success")
    local file = luci.http.formvalue("file")
    
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

# 创建备份列表显示模板
mkdir -p files/usr/lib/lua/luci/view/admin_system
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
            <div class="table-cell" style="width: 45%; word-break: break-all;"><%=backup.name%></div>
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
});
</script>
<%+footer%>
EOF

# 创建 Overlay 备份主脚本
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
    
    # 创建备份
    echo "Backing up overlay to: $backup_path"
    if tar -czf "$backup_path" -C /overlay . 2>/dev/null; then
        local file_size=$(du -h "$backup_path" | cut -f1)
        echo "Backup created: $backup_file"
        echo "Backup location: $backup_path"
        echo "File size: $file_size"
        logger "Overlay backup created: $backup_path ($file_size)"
        return 0
    else
        echo "Error: Backup creation failed!"
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
    echo "WARNING: This will overwrite current configuration."
    read -p "Continue? [y/N] " confirm
    case "$confirm" in
        y|Y|yes|YES)
            # 停止服务
            echo "Stopping services..."
            /etc/init.d/uhttpd stop
            /etc/init.d/firewall stop
            /etc/init.d/dnsmasq stop
            sleep 2
            
            # 恢复备份
            echo "Restoring overlay..."
            tar -xzf "$backup_file" -C /overlay
            
            # 重启服务
            echo "Starting services..."
            /etc/init.d/dnsmasq start
            /etc/init.d/firewall start
            /etc/init.d/uhttpd start
            
            echo "Backup restored successfully!"
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

# 3. 创建 Overlay 备份配置文件
mkdir -p files/etc/config
cat > files/etc/config/overlay-backup << 'EOF'
config overlay-backup
    option enabled '1'
EOF

# 4. 添加下载和删除处理的路由
cat >> files/usr/lib/lua/luci/controller/admin/overlay-backup.lua << 'EOF'

-- 添加子路由处理下载和删除
function index()
    entry({"admin", "system", "overlay-backup"}, cbi("admin_system/overlay-backup"), _("Overlay Backup"), 80)
    entry({"admin", "system", "overlay-backup", "download-backup"}, call("download_backup")).leaf = true
    entry({"admin", "system", "overlay-backup", "delete-backup"}, call("delete_backup")).leaf = true
end
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
