#!/bin/bash
# =============================================
# OpenWrt DIY 脚本第二部分 - 完整功能版（带刷新按钮）
# 功能：内存释放 + Overlay备份Web界面 + IPK自动安装 + 刷新功能
# 设备：Netgear WNDR3800
# =============================================

echo "开始应用 WNDR3800 完整自定义配置..."

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

# ==================== 2. 完整的 Overlay 备份 Web 界面（带刷新按钮）====================
echo "创建完整的 Overlay 备份 Web 界面..."
mkdir -p files/usr/lib/lua/luci/controller/admin
mkdir -p files/usr/lib/lua/luci/model/cbi/admin_system
mkdir -p files/usr/lib/lua/luci/view/admin_system

# 创建控制器
cat > files/usr/lib/lua/luci/controller/admin/overlay-backup.lua << 'EOF'
module("luci.controller.admin.overlay-backup", package.seeall)

function index()
    entry({"admin", "system", "overlay-backup"}, call("action_overlay_backup"), _("Overlay Backup"), 80)
    entry({"admin", "system", "overlay-backup", "download-backup"}, call("download_backup")).leaf = true
    entry({"admin", "system", "overlay-backup", "delete-backup"}, call("delete_backup")).leaf = true
    entry({"admin", "system", "overlay-backup", "refresh"}, call("refresh_backups")).leaf = true
end

function action_overlay_backup()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    local sys = require "luci.sys"
    
    -- 处理备份操作
    if http.formvalue("backup") then
        local result = sys.exec("/usr/bin/overlay-backup backup 2>&1")
        local filename = result:match("Backup created: ([^\n]+)")
        if filename then
            http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?success=1&file=" .. http.urlencode(filename))
        else
            http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?success=0")
        end
        return
    end
    
    -- 处理恢复操作
    local restore_file = http.formvalue("restore_file")
    if restore_file then
        if restore_file:match("^[^/]+$") then
            restore_file = "/tmp/" .. restore_file
        end
        if fs.stat(restore_file) then
            local result = sys.exec("/usr/bin/overlay-backup restore '" .. restore_file .. "' 2>&1")
            if result:match("恢复成功") then
                http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?restore_success=1")
            else
                http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?restore_success=0")
            end
        end
        return
    end
    
    -- 处理刷新操作
    if http.formvalue("refresh") then
        http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?refreshed=1")
        return
    end
    
    -- 显示页面
    luci.template.render("admin_system/overlay_backup", {
        backup_files = get_backup_files()
    })
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

function refresh_backups()
    local http = require "luci.http"
    http.redirect(luci.dispatcher.build_url("admin/system/overlay-backup") .. "?refreshed=1")
end

function get_backup_files()
    local fs = require "nixio.fs"
    local files = {}
    
    -- 扫描多个可能的位置
    local scan_locations = {
        "/tmp",
        "/mnt/sda1",
        "/mnt/sdb1", 
        "/mnt/usb",
        "/mnt"
    }
    
    for _, location in ipairs(scan_locations) do
        if fs.stat(location) then
            for file in fs.dir(location) do
                if file:match("overlay%-backup%-.*%.tar%.gz") or file:match("openwrt%-overlay%-backup%-.*%.tar%.gz") then
                    local path = location .. "/" .. file
                    local stat = fs.stat(path)
                    if stat then
                        table.insert(files, {
                            name = file,
                            path = path,
                            location = location,
                            size = stat.size,
                            mtime = stat.mtime
                        })
                    end
                end
            end
        end
    end
    
    -- 按时间排序
    table.sort(files, function(a, b) return a.mtime > b.mtime end)
    return files
end
EOF

# 创建 Web 界面模板（带刷新按钮）
cat > files/usr/lib/lua/luci/view/admin_system/overlay_backup.htm << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:Overlay Backup%></h2>
    <div class="cbi-map-descr">
        <%:备份和恢复 overlay 分区配置。支持多个存储位置，点击刷新按钮重新扫描所有位置。%>
    </div>
    
    <!-- 操作按钮 -->
    <div class="cbi-section">
        <h3><%:操作%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title"><%:备份操作%></label>
            <div class="cbi-value-field">
                <form method="post" style="display: inline;">
                    <button type="submit" name="backup" value="1" class="cbi-button cbi-button-apply">
                        ➕ <%:创建备份%>
                    </button>
                </form>
                <form method="post" style="display: inline; margin-left: 10px;">
                    <input type="hidden" name="restore" value="1">
                    <button type="button" onclick="showRestoreDialog()" class="cbi-button cbi-button-reset">
                        🔄 <%:恢复备份%>
                    </button>
                </form>
                <form method="post" style="display: inline; margin-left: 10px;">
                    <button type="submit" name="refresh" value="1" class="cbi-button cbi-button-action">
                        🔃 <%:刷新列表%>
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
    local refreshed = luci.http.formvalue("refreshed")
    %>
    
    <% if refreshed == "1" then %>
    <div class="alert-message info">
        <strong><%:刷新完成！%></strong> <%:已重新扫描所有存储位置。%>
    </div>
    <% end %>
    
    <% if success == "1" and file then %>
    <div class="alert-message success">
        <strong><%:备份成功！%></strong> <%:文件：%> <%=file%><br>
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
        <strong><%:恢复成功！%></strong> <%:请重启路由器生效。%>
    </div>
    <% elseif restore_success == "0" then %>
    <div class="alert-message error">
        <strong><%:恢复失败！%></strong> <%:请查看系统日志。%>
    </div>
    <% end %>

    <!-- 备份文件列表 -->
    <div class="cbi-section">
        <h3><%:备份文件列表%> 
            <small style="font-weight: normal; color: #666;">
                （扫描位置: /tmp, /mnt/sda1, /mnt/sdb1, /mnt/usb, /mnt）
            </small>
        </h3>
        
        <div class="table" style="max-height: 400px; overflow-y: auto;">
            <div class="table-titles">
                <div class="table-cell" style="width: 40%;"><%:文件名%></div>
                <div class="table-cell" style="width: 15%;"><%:位置%></div>
                <div class="table-cell" style="width: 15%;"><%:大小%></div>
                <div class="table-cell" style="width: 20%;"><%:修改时间%></div>
                <div class="table-cell" style="width: 10%;"><%:操作%></div>
            </div>
            
            <% 
            local has_files = false
            for i, backup in ipairs(backup_files) do 
                has_files = true
            %>
            <div class="table-row">
                <div class="table-cell" style="width: 40%; word-break: break-all;">
                    <%=backup.name%>
                </div>
                <div class="table-cell" style="width: 15%;">
                    <span class="badge" style="background: #6c757d; color: white; padding: 2px 6px; border-radius: 3px; font-size: 12px;">
                        <%=backup.location%>
                    </span>
                </div>
                <div class="table-cell" style="width: 15%;">
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
                       class="cbi-button cbi-button-apply" style="padding: 3px 8px; margin: 1px;" 
                       title="下载备份文件">📥</a>
                    <a href="<%=luci.dispatcher.build_url('admin/system/overlay-backup/delete-backup')%>?file=<%=luci.http.urlencode(backup.path)%>" 
                       class="cbi-button cbi-button-reset" style="padding: 3px 8px; margin: 1px;" 
                       onclick="return confirm('确定删除备份文件 ' + '<%=backup.name%>' + ' 吗？')"
                       title="删除备份文件">🗑️</a>
                </div>
            </div>
            <% end %>
            
            <% if not has_files then %>
            <div class="table-row">
                <div class="table-cell" colspan="5" style="text-align: center; padding: 30px;">
                    <div style="color: #6c757d; font-style: italic;">
                        📭 <%:没有找到备份文件%>
                    </div>
                    <div style="margin-top: 10px; font-size: 14px;">
                        <%:请点击"创建备份"按钮创建第一个备份，或检查其他存储设备%>
                    </div>
                </div>
            </div>
            <% end %>
        </div>
        
        <div class="alert-message warning" style="margin-top: 15px;">
            <strong>💡 提示：</strong> 
            <%:系统会自动扫描多个位置查找备份文件。如果备份文件被移动到其他位置，请点击"刷新列表"按钮重新扫描。%>
            <br>
            <strong>📁 扫描位置：</strong> /tmp, /mnt/sda1, /mnt/sdb1, /mnt/usb, /mnt
        </div>
    </div>
</div>

<script>
function showRestoreDialog() {
    const backups = [
        <% for i, backup in ipairs(backup_files) do %>
        {
            name: '<%=backup.name%>',
            path: '<%=backup.path%>',
            location: '<%=backup.location%>'
        },
        <% end %>
    ];
    
    if (backups.length === 0) {
        alert('没有可用的备份文件');
        return;
    }
    
    let backupList = '可用备份文件：\\n\\n';
    backups.forEach(backup => {
        backupList += `📁 ${backup.name} (位置: ${backup.location})\\n`;
    });
    
    const selected = prompt('请输入要恢复的备份文件名：\\n\\n' + backupList + '\\n请输入完整文件名：');
    
    if (selected) {
        // 检查文件是否存在
        const fileExists = backups.some(backup => backup.name === selected);
        if (!fileExists) {
            alert('文件不存在：' + selected + '\\n\\n请检查文件名是否正确，或点击"刷新列表"重新扫描。');
            return;
        }
        
        if (confirm('⚠️  警告：这将覆盖当前的所有配置！\\n\\n确定要恢复备份文件：' + selected + ' 吗？')) {
            const form = document.createElement('form');
            form.method = 'post';
            form.innerHTML = '<input type="hidden" name="restore_file" value="' + selected + '">';
            document.body.appendChild(form);
            form.submit();
        }
    }
}

// 自动刷新功能（可选）
document.addEventListener('DOMContentLoaded', function() {
    // 如果有刷新参数，显示刷新提示
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.has('refreshed')) {
        // 可以添加自动滚动到列表等效果
        console.log('页面已刷新');
    }
    
    // 添加快捷键支持：按F5刷新列表
    document.addEventListener('keydown', function(e) {
        if (e.key === 'F5') {
            e.preventDefault();
            document.querySelector('button[name="refresh"]').click();
        }
    });
});
</script>

<style>
.badge {
    font-size: 11px;
    padding: 2px 6px;
    border-radius: 3px;
}
.table-cell {
    vertical-align: middle;
    padding: 8px 4px;
}
.alert-message.info {
    background: #d1ecf1;
    color: #0c5460;
    border: 1px solid #bee5eb;
}
</style>
<%+footer%>
EOF

# 创建增强的 Overlay 备份主脚本（支持多个位置）
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh
# Overlay 备份工具 - 支持备份和恢复，增强版

ACTION="$1"
FILE="$2"

# 备份文件扫描函数
scan_backup_locations() {
    echo "扫描备份文件位置..."
    local locations="/tmp /mnt/sda1 /mnt/sdb1 /mnt/usb /mnt"
    local found_files=0
    
    for location in $locations; do
        if [ -d "$location" ]; then
            echo "检查位置: $location"
            for file in "$location"/*.tar.gz; do
                if [ -f "$file" ] && (echo "$file" | grep -q "overlay-backup-\|openwrt-overlay-backup-"); then
                    local size=$(du -h "$file" 2>/dev/null | cut -f1)
                    local mtime=$(stat -c "%y" "$file" 2>/dev/null | cut -d'.' -f1)
                    echo "  📁 $(basename "$file") (大小: ${size:-未知}, 时间: ${mtime:-未知})"
                    found_files=$((found_files + 1))
                fi
            done
        fi
    done
    
    if [ $found_files -eq 0 ]; then
        echo "未在任何位置找到备份文件"
    else
        echo "总共找到 $found_files 个备份文件"
    fi
}

create_backup() {
    echo "正在创建 Overlay 备份..."
    local backup_file="overlay-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    local backup_path="/tmp/$backup_file"
    
    # 检查磁盘空间
    local available_space=$(df /tmp | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 50000 ]; then
        echo "错误：/tmp 空间不足，至少需要 50MB 可用空间"
        return 1
    fi
    
    echo "备份文件: $backup_file"
    echo "保存位置: /tmp/"
    echo "正在打包 overlay 分区..."
    
    if tar -czf "$backup_path" -C / overlay 2>/dev/null; then
        local size=$(du -h "$backup_path" | cut -f1)
        echo "✓ 备份成功创建！"
        echo "📊 文件大小: $size"
        echo "📍 文件路径: $backup_path"
        echo ""
        echo "💡 提示:"
        echo "  - 备份文件保存在 /tmp 目录，重启后会丢失"
        echo "  - 请及时通过Web界面下载备份文件到本地"
        echo "  - 支持的命令: $0 restore <文件名>"
        
        logger "Overlay backup created: $backup_file ($size)"
        return 0
    else
        echo "✗ 备份创建失败！"
        echo "可能的原因:"
        echo "  - 磁盘空间不足"
        echo "  - overlay 分区损坏"
        echo "  - 权限问题"
        return 1
    fi
}

restore_backup() {
    local backup_file="$1"
    [ -z "$backup_file" ] && { 
        echo "错误：请指定备份文件名"
        echo "用法: $0 restore <文件名>"
        echo ""
        echo "可用备份文件:"
        scan_backup_locations
        return 1
    }
    
    # 自动搜索文件位置
    local found_path=""
    local locations="/tmp /mnt/sda1 /mnt/sdb1 /mnt/usb /mnt"
    
    for location in $locations; do
        if [ -f "$location/$backup_file" ]; then
            found_path="$location/$backup_file"
            break
        fi
    done
    
    if [ -z "$found_path" ]; then
        echo "错误：找不到备份文件 '$backup_file'"
        echo "在以下位置搜索: $locations"
        echo ""
        echo "请检查:"
        echo "  1. 文件名是否正确"
        echo "  2. 备份文件是否存在于上述位置"
        echo "  3. 或者提供完整路径"
        return 1
    fi
    
    backup_file="$found_path"
    echo "找到备份文件: $backup_file"
    
    # 验证备份文件
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        echo "错误：备份文件损坏或格式不正确"
        return 1
    fi
    
    echo ""
    echo "⚠️  警告：此操作将覆盖当前所有配置！"
    echo "📋 恢复操作将:"
    echo "  - 停止网络和服务"
    echo "  - 清空当前 overlay 分区"
    echo "  - 从备份恢复配置"
    echo "  - 重启相关服务"
    echo ""
    
    read -p "确定要恢复备份吗？(输入 'YES' 确认): " confirm
    if [ "$confirm" != "YES" ]; then
        echo "恢复操作已取消"
        return 0
    fi
    
    echo "开始恢复过程..."
    
    # 停止服务
    echo "🛑 停止服务..."
    /etc/init.d/uhttpd stop
    /etc/init.d/firewall stop
    /etc/init.d/dnsmasq stop
    sleep 3
    
    # 恢复备份
    echo "📦 恢复备份文件..."
    if tar -xzf "$backup_file" -C / ; then
        echo "✓ 备份恢复成功！"
        
        # 重启服务
        echo "🔄 启动服务..."
        /etc/init.d/dnsmasq start
        /etc/init.d/firewall start
        /etc/init.d/uhttpd start
        
        echo ""
        echo "🎉 恢复完成！"
        echo "💡 建议重启路由器以确保所有配置生效: reboot"
        
        logger "Overlay restored from: $backup_file"
    else
        echo "✗ 备份恢复失败！"
        echo "可能文件损坏或权限问题"
        
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
    scan)
        scan_backup_locations
        ;;
    *)
        echo "Overlay 备份工具 - 增强版"
        echo "用法: $0 {backup|restore <file>|scan}"
        echo ""
        echo "命令说明:"
        echo "  backup    创建 overlay 分区备份"
        echo "  restore   从备份文件恢复 overlay 分区"
        echo "  scan      扫描所有位置的备份文件"
        echo ""
        echo "示例:"
        echo "  $0 backup                    # 创建备份"
        echo "  $0 restore my-backup.tar.gz  # 恢复备份"
        echo "  $0 scan                      # 扫描备份文件"
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

echo "=== 自定义 IPK 包自动安装 ==="
sleep 25

if [ -d "/packages" ]; then
    echo "发现自定义 IPK 包目录..."
    PACKAGE_COUNT=$(ls /packages/*.ipk 2>/dev/null | wc -l)
    echo "找到 $PACKAGE_COUNT 个 IPK 文件"
    
    for ipk in /packages/*.ipk; do
        if [ -f "$ipk" ]; then
            echo "正在安装: $(basename "$ipk")"
            if opkg install "$ipk" 2>/dev/null; then
                echo "✓ 安装成功: $(basename "$ipk")"
                logger "IPK auto-install: $(basename "$ipk") - SUCCESS"
            else
                echo "✗ 安装失败: $(basename "$ipk")"
                logger "IPK auto-install: $(basename "$ipk") - FAILED"
            fi
        fi
    done
    
    echo "清理安装包..."
    rm -rf /packages
    echo "自定义包安装完成"
else
    echo "未找到自定义 IPK 包目录 /packages"
fi

# 启用服务
echo "启用定时任务服务..."
/etc/init.d/cron enable
/etc/init.d/cron start

echo "=== 自动安装完成 ==="
exit 0
EOF
chmod +x files/etc/uci-defaults/99-auto-install

# ==================== 4. 复制自定义IPK包 ====================
if [ -d "../../files/packages" ]; then
    echo "复制自定义 IPK 包到固件..."
    mkdir -p files/packages
    cp ../../files/packages/*.ipk files/packages/ 2>/dev/null || true
    echo "已复制 $(ls files/packages/*.ipk 2>/dev/null | wc -w 2>/dev/null || echo 0) 个 IPK 文件"
else
    echo "未找到自定义 IPK 包目录，跳过复制"
fi

echo ""
echo "=========================================="
echo "✅ WNDR3800 完整功能配置完成！"
echo "=========================================="
echo "📋 已配置功能:"
echo "  1. 🕒 定时内存释放（每天凌晨3点）"
echo "  2. 💾 Overlay 备份系统（带Web界面）"
echo "  3. 🔃 备份文件刷新功能"
echo "  4. 📦 IPK 包自动安装"
echo "  5. 📁 多位置备份文件扫描"
echo ""
echo "🌐 Web界面位置: 系统 → Overlay Backup"
echo "⌨️  命令行工具: /usr/bin/overlay-backup"
echo "=========================================="
