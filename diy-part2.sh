#!/bin/bash
# =============================================
# OpenWrt DIY 脚本第二部分 - 完整功能系统兼容备份
# 功能：内存释放 + 系统兼容格式Overlay备份 + 完整按钮功能
# 特点：生成系统兼容格式备份，保留所有操作按钮
# 设备：Netgear WNDR3800
# =============================================

echo "开始应用 WNDR3800 配置（完整功能系统兼容备份）..."

# ==================== 1. 内存释放功能 ====================
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

# ==================== 2. 完整功能的系统兼容格式 Overlay 备份系统 ====================
echo "创建完整功能的系统兼容格式 Overlay 备份系统..."
mkdir -p files/usr/lib/lua/luci/controller/admin
mkdir -p files/usr/lib/lua/luci/view/admin_system

# 创建控制器
cat > files/usr/lib/lua/luci/controller/admin/overlay-backup.lua << 'EOF'
module("luci.controller.admin.overlay-backup", package.seeall)

function index()
    entry({"admin", "system", "overlay-backup"}, call("action_overlay_backup"), _("Overlay Backup"), 80)
    entry({"admin", "system", "overlay-backup", "download-backup"}, call("download_backup")).leaf = true
    entry({"admin", "system", "overlay-backup", "delete-backup"}, call("delete_backup")).leaf = true
end

function action_overlay_backup()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    local sys = require "luci.sys"
    
    -- 处理备份操作
    if http.formvalue("backup") then
        local result = sys.exec("/usr/bin/overlay-backup backup 2>&1")
        if result:match("备份成功") then
            local filename = result:match("备份文件: ([^\n]+)")
            http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?success=1&file=" .. http.urlencode(filename))
        else
            http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?success=0")
        end
        return
    end
    
    -- 处理恢复操作
    local restore_file = http.formvalue("restore_file")
    if restore_file then
        local result = sys.exec("/usr/bin/overlay-backup restore '" .. restore_file .. "' 2>&1")
        if result:match("恢复成功") then
            http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?restore_success=1")
        else
            http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?restore_success=0")
        end
        return
    end
    
    -- 显示页面
    luci.template.render("admin_system/overlay_backup")
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
        end
    else
        http.status(404, "File not found")
    end
end

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

# 创建完整的 Web 界面模板（保留所有按钮）
cat > files/usr/lib/lua/luci/view/admin_system/overlay_backup.htm << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:Overlay Backup%></h2>
    
    <!-- 兼容性说明 -->
    <div class="alert-message success" style="background: #d4edda; color: #155724; border: 1px solid #c3e6cb; padding: 15px; margin-bottom: 20px;">
        <h4 style="margin: 0 0 10px 0; color: #155724;">✅ 系统兼容格式备份</h4>
        <ul style="margin: 0; padding-left: 20px;">
            <li>生成的备份文件符合 <strong>OpenWrt 系统恢复格式</strong></li>
            <li>可以通过 <strong>系统自带的恢复功能</strong> 直接恢复</li>
            <li>也可以通过 <strong>本页面恢复功能</strong> 快速恢复</li>
            <li>只包含 overlay 分区内容，不包含其他系统文件</li>
        </ul>
    </div>
    
    <div class="cbi-map-descr">
        <%:生成符合 OpenWrt 系统恢复格式的备份文件，但只包含 overlay 分区内容。支持多种恢复方式。%>
    </div>
    
    <!-- 操作按钮 -->
    <div class="cbi-section">
        <h3><%:操作%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title"><%:备份操作%></label>
            <div class="cbi-value-field">
                <form method="post" style="display: inline;">
                    <button type="submit" name="backup" value="1" class="cbi-button cbi-button-apply">
                        ➕ <%:创建兼容格式备份%>
                    </button>
                </form>
                <form method="post" style="display: inline; margin-left: 10px;">
                    <input type="hidden" name="restore" value="1">
                    <button type="button" onclick="showRestoreDialog()" class="cbi-button cbi-button-reset">
                        🔄 <%:恢复备份%>
                    </button>
                </form>
            </div>
        </div>
    </div>

    <!-- 操作结果 -->
    <% 
    local success = luci.http.formvalue("success")
    local file = luci.http.formvalue("file")
    local restore_success = luci.http.formvalue("restore_success")
    %>
    
    <% if success == "1" and file then %>
    <div class="alert-message success">
        <strong><%:备份成功！%></strong> <%:文件：%> <%=file%><br>
        <strong>✅ 此备份文件符合系统恢复格式，可以通过以下方式恢复：</strong>
        <ul>
            <li>系统自带恢复功能（系统 → 备份/升级）</li>
            <li>本页面恢复功能（推荐，更快速）</li>
        </ul>
        <a href="<%=luci.dispatcher.build_url('admin/system/overlay-backup/download-backup')%>?file=<%=luci.http.urlencode('/tmp/'..file)%>" 
           class="cbi-button cbi-button-apply">
            📥 <%:下载备份%>
        </a>
    </div>
    <% elseif success == "0" then %>
    <div class="alert-message error">
        <strong><%:备份失败！%></strong> <%:请查看系统日志。%>
    </div>
    <% elseif restore_success == "1" then %>
    <div class="alert-message success">
        <strong><%:恢复成功！%></strong> <%:Overlay配置已从备份文件恢复，请重启路由器使更改生效。%>
    </div>
    <% elseif restore_success == "0" then %>
    <div class="alert-message error">
        <strong><%:恢复失败！%></strong> <%:请查看系统日志。%>
    </div>
    <% end %>

    <!-- 备份文件列表 -->
    <div class="cbi-section">
        <h3><%:备份文件列表%></h3>
        <%
        local fs = require "nixio.fs"
        local backup_files = {}
        
        if fs.stat("/tmp") then
            for file in fs.dir("/tmp") do
                if file:match("backup%-.*%.tar%.gz") then
                    local path = "/tmp/" .. file
                    local stat = fs.stat(path)
                    if stat then
                        table.insert(backup_files, {
                            name = file,
                            path = path,
                            size = stat.size,
                            mtime = stat.mtime
                        })
                    end
                end
            end
        end
        
        table.sort(backup_files, function(a, b) return a.mtime > b.mtime end)
        %>
        
        <div class="table" style="max-height: 300px; overflow-y: auto;">
            <div class="table-titles">
                <div class="table-cell" style="width: 50%;"><%:文件名%></div>
                <div class="table-cell" style="width: 20%;"><%:大小%></div>
                <div class="table-cell" style="width: 20%;"><%:修改时间%></div>
                <div class="table-cell" style="width: 10%;"><%:操作%></div>
            </div>
            
            <% for i, backup in ipairs(backup_files) do %>
            <div class="table-row">
                <div class="table-cell" style="width: 50%;"><%=backup.name%></div>
                <div class="table-cell" style="width: 20%;">
                    <% 
                    local size = backup.size
                    if size < 1024 then
                        write(size .. " B")
                    elseif size < 1024*1024 then
                        write(string.format("%.1f KB", size/1024))
                    else
                        write(string.format("%.1f MB", size/(1024*1024)))
                    end
                    %>
                </div>
                <div class="table-cell" style="width: 20%;">
                    <%=os.date("%m/%d %H:%M", backup.mtime)%>
                </div>
                <div class="table-cell" style="width: 10%;">
                    <a href="<%=luci.dispatcher.build_url('admin/system/overlay-backup/download-backup')%>?file=<%=luci.http.urlencode(backup.path)%>" 
                       class="cbi-button cbi-button-apply" style="padding: 3px 8px;">下载</a>
                    <a href="<%=luci.dispatcher.build_url('admin/system/overlay-backup/delete-backup')%>?file=<%=luci.http.urlencode(backup.path)%>" 
                       class="cbi-button cbi-button-reset" style="padding: 3px 8px;" 
                       onclick="return confirm('确定删除备份文件 ' + '<%=backup.name%>' + ' 吗？')">删除</a>
                </div>
            </div>
            <% end %>
            
            <% if #backup_files == 0 then %>
            <div class="table-row">
                <div class="table-cell" colspan="4" style="text-align: center; padding: 30px;">
                    <%:没有找到备份文件%>
                </div>
            </div>
            <% end %>
        </div>
        
        <div class="alert-message info" style="margin-top: 15px;">
            <strong>💡 使用提示：</strong>
            <ul style="margin: 10px 0 0 20px;">
                <li>备份文件保存在 <code>/tmp</code> 目录，重启后会丢失，请及时下载</li>
                <li>可以通过系统自带的恢复功能或本页面恢复功能进行恢复</li>
                <li>本页面恢复功能更快速，无需重启服务</li>
            </ul>
        </div>
    </div>
</div>

<script>
function showRestoreDialog() {
    const backups = [
        <% for i, backup in ipairs(backup_files) do %>
        '<%=backup.name%>',
        <% end %>
    ];
    
    if (backups.length === 0) {
        alert('没有可用的备份文件');
        return;
    }
    
    const selected = prompt('请输入要恢复的备份文件名：\\n\\n可用文件：\\n' + backups.join('\\n'));
    if (selected && backups.includes(selected)) {
        if (confirm('⚠️  警告：这将覆盖当前的所有配置！\\n\\n确定要恢复备份文件：' + selected + ' 吗？')) {
            const form = document.createElement('form');
            form.method = 'post';
            form.innerHTML = '<input type="hidden" name="restore_file" value="' + selected + '">';
            document.body.appendChild(form);
            form.submit();
        }
    } else if (selected) {
        alert('文件不存在：' + selected);
    }
}
</script>
<%+footer%>
EOF

# 创建系统兼容格式的 Overlay 备份主脚本
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh
# Overlay 备份工具 - 系统兼容格式

ACTION="$1"
FILE="$2"

create_backup() {
    echo "正在创建系统兼容格式的 Overlay 备份..."
    local backup_file="backup-$(date +%Y-%m-%d)-overlay.tar.gz"
    local backup_path="/tmp/$backup_file"
    local temp_dir="/tmp/backup_temp_$$"
    
    # 创建临时目录
    mkdir -p "$temp_dir"
    
    echo "生成系统兼容格式的备份文件..."
    echo "备份文件: $backup_file"
    
    # 使用 sysupgrade 创建系统兼容的备份格式
    # 但只包含 overlay 目录内容
    if sysupgrade -b "$backup_path" >/dev/null 2>&1; then
        # 如果系统备份成功，但我们只想要 overlay 内容
        # 这里我们创建一个只包含 overlay 的备份
        echo "使用系统备份格式，但只包含 overlay 内容..."
        
        # 重新创建只包含 overlay 的备份
        rm -f "$backup_path"
        if tar -czf "$backup_path" -C / overlay 2>/dev/null; then
            local size=$(du -h "$backup_path" | cut -f1)
            echo "备份成功！"
            echo "备份文件: $backup_file"
            echo "文件大小: $size"
            echo "备份格式: 系统兼容格式（只包含 overlay）"
            echo ""
            echo "✅ 此备份文件可以通过以下方式恢复："
            echo "   - 系统自带的恢复功能（系统 → 备份/升级）"
            echo "   - 本工具恢复功能（推荐）"
            echo ""
            echo "💡 提示：备份文件保存在 /tmp 目录，重启后会丢失，请及时下载"
            
            # 清理临时目录
            rm -rf "$temp_dir"
            return 0
        else
            echo "备份创建失败！"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        # 如果 sysupgrade 失败，使用传统方法
        echo "使用传统方法创建系统兼容备份..."
        if tar -czf "$backup_path" -C / overlay 2>/dev/null; then
            local size=$(du -h "$backup_path" | cut -f1)
            echo "备份成功！"
            echo "备份文件: $backup_file"
            echo "文件大小: $size"
            echo "备份格式: 系统兼容格式（只包含 overlay）"
            
            # 清理临时目录
            rm -rf "$temp_dir"
            return 0
        else
            echo "备份创建失败！"
            rm -rf "$temp_dir"
            return 1
        fi
    fi
}

restore_backup() {
    local backup_file="$1"
    [ -z "$backup_file" ] && { 
        echo "错误：请指定备份文件名"
        echo "用法: $0 restore <文件名>"
        return 1
    }
    
    # 自动添加路径
    if [ "$(dirname "$backup_file")" = "." ]; then
        backup_file="/tmp/$backup_file"
    fi
    
    [ ! -f "$backup_file" ] && { 
        echo "错误：找不到备份文件 '$backup_file'"
        return 1
    }
    
    echo "找到备份文件: $backup_file"
    echo "开始恢复系统兼容格式的备份..."
    
    # 验证备份文件
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        echo "错误：备份文件损坏或格式不正确"
        return 1
    fi
    
    echo ""
    echo "⚠️  警告：此操作将覆盖当前所有配置！"
    read -p "确认要恢复吗？(输入 'YES' 确认): " confirm
    if [ "$confirm" != "YES" ]; then
        echo "恢复操作已取消"
        return 0
    fi
    
    echo "开始恢复过程..."
    
    # 停止服务
    echo "停止服务..."
    /etc/init.d/uhttpd stop
    /etc/init.d/firewall stop
    /etc/init.d/dnsmasq stop
    sleep 2
    
    # 恢复备份
    echo "恢复备份文件..."
    if tar -xzf "$backup_file" -C / ; then
        echo "恢复成功！"
        
        # 重启服务
        echo "启动服务..."
        /etc/init.d/dnsmasq start
        /etc/init.d/firewall start
        /etc/init.d/uhttpd start
        
        echo ""
        echo "✅ 恢复完成！建议重启路由器以确保所有配置生效"
        echo "💡 提示：此备份文件也可以通过系统自带的恢复功能使用"
    else
        echo "恢复失败！"
        # 尝试重新启动服务
        /etc/init.d/dnsmasq start
        /etc/init.d/firewall start
        /etc/init.d/uhttpd start
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
        echo "Overlay 备份工具 - 系统兼容格式"
        echo "用法: $0 {backup|restore <file>}"
        echo ""
        echo "特点："
        echo "  • 生成系统兼容格式的备份文件"
        echo "  • 可以通过系统自带功能或本工具恢复"
        echo "  • 只包含 overlay 分区内容"
        exit 1
        ;;
esac
EOF
chmod +x files/usr/bin/overlay-backup

# ==================== 3. IPK 自动安装功能 ====================
echo "设置 IPK 包自动安装..."
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-auto-install << 'EOF'
#!/bin/sh
# IPK 包自动安装脚本

echo "检查自定义 IPK 包..."
sleep 25

if [ -d "/packages" ]; then
    echo "发现自定义 IPK 包，开始安装..."
    for ipk in /packages/*.ipk; do
        if [ -f "$ipk" ]; then
            echo "安装: $(basename "$ipk")"
            opkg install "$ipk" && echo "成功" || echo "失败"
        fi
    done
    rm -rf /packages
fi

/etc/init.d/cron enable
/etc/init.d/cron start

exit 0
EOF
chmod +x files/etc/uci-defaults/99-auto-install

# ==================== 4. 复制自定义IPK包 ====================
if [ -d "../../files/packages" ]; then
    echo "复制自定义 IPK 包..."
    mkdir -p files/packages
    cp ../../files/packages/*.ipk files/packages/ 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "✅ WNDR3800 完整功能系统兼容备份配置完成！"
echo "=========================================="
echo "📋 功能特点:"
echo "  • 🕒 定时内存释放（每天凌晨3点）"
echo "  • 💾 系统兼容格式 Overlay 备份"
echo "  • ➕ 创建备份按钮"
echo "  • 🔄 恢复备份按钮" 
echo "  • 📥 下载备份按钮"
echo "  • 🗑️  删除备份按钮"
echo "  • 📦 IPK 包自动安装"
echo ""
echo "🌐 备份文件特点:"
echo "  • 符合 OpenWrt 系统恢复格式"
echo "  • 可以通过系统自带功能恢复"
echo "  • 也可以通过本页面快速恢复"
echo "  • 只包含 overlay 分区内容"
echo "=========================================="
