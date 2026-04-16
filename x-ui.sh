#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

SCRIPT_NAME="x-ui"
PANEL_BIN="/usr/local/x-ui/x-ui"
SERVICE_FILE="/etc/systemd/system/x-ui.service"
INSTALL_SH_URL="https://raw.githubusercontent.com/xsmzdd/FranzKafkaYu-x-ui/main/install.sh"
SCRIPT_URL="https://raw.githubusercontent.com/xsmzdd/FranzKafkaYu-x-ui/main/x-ui.sh"
DB_PATH="/etc/x-ui/x-ui.db"

LOGI() {
    echo -e "${GREEN}[INFO]${PLAIN} $*"
}

LOGE() {
    echo -e "${RED}[ERROR]${PLAIN} $*"
}

LOGW() {
    echo -e "${YELLOW}[WARN]${PLAIN} $*"
}

confirm() {
    local msg="$1"
    local default="${2:-y}"
    local prompt
    local ans

    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -r -p "${msg} ${prompt}: " ans
    ans="${ans,,}"

    if [[ -z "$ans" ]]; then
        ans="$default"
    fi

    [[ "$ans" == "y" ]]
}

before_show_menu() {
    echo ""
    read -n 1 -s -r -p "按回车返回主菜单: "
    echo ""
    show_menu
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        LOGE "请使用 root 用户运行"
        exit 1
    fi
}

check_status() {
    if [[ ! -f "${SERVICE_FILE}" ]]; then
        return 2
    fi

    if systemctl is-active --quiet x-ui; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    if systemctl is-enabled --quiet x-ui 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

db_ready() {
    command -v sqlite3 >/dev/null 2>&1 && [[ -f "${DB_PATH}" ]]
}

db_table_exists() {
    local table="$1"
    sqlite3 "${DB_PATH}" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='${table}' LIMIT 1;" 2>/dev/null | grep -q 1
}

db_get_first() {
    local sql="$1"
    sqlite3 "${DB_PATH}" "${sql}" 2>/dev/null | head -n 1
}

get_setting_value() {
    local key="$1"
    if ! db_ready; then
        return 1
    fi

    if db_table_exists "settings"; then
        db_get_first "SELECT value FROM settings WHERE key='${key}' LIMIT 1;"
        return 0
    fi

    return 1
}

get_panel_username() {
    local username=""

    if ! db_ready; then
        return 1
    fi

    if db_table_exists "users"; then
        username=$(db_get_first "SELECT username FROM users ORDER BY id ASC LIMIT 1;")
    elif db_table_exists "user"; then
        username=$(db_get_first "SELECT username FROM user ORDER BY id ASC LIMIT 1;")
    fi

    [[ -n "${username}" ]] && echo "${username}"
}

get_panel_port() {
    local port=""
    port=$(get_setting_value "webPort")
    if [[ -n "${port}" ]]; then
        echo "${port}"
        return 0
    fi

    # fallback 默认端口
    echo "54321"
}

get_panel_listen() {
    local listen=""
    listen=$(get_setting_value "webListen")
    if [[ -n "${listen}" ]]; then
        echo "${listen}"
    else
        echo "0.0.0.0"
    fi
}

get_panel_basepath() {
    local basepath=""
    basepath=$(get_setting_value "webBasePath")
    if [[ -n "${basepath}" ]]; then
        echo "${basepath}"
    else
        echo "/"
    fi
}

get_panel_cert_file() {
    get_setting_value "webCertFile"
}

get_panel_key_file() {
    get_setting_value "webKeyFile"
}

get_runtime_port_from_ss() {
    local pid
    pid=$(systemctl show -p MainPID --value x-ui 2>/dev/null)

    if [[ -n "${pid}" && "${pid}" != "0" ]]; then
        ss -lntp 2>/dev/null | awk -v pid="${pid}" '
            $0 ~ ("pid=" pid ",") {
                split($4, a, ":")
                print a[length(a)]
                exit
            }
        '
    fi
}

get_xray_status() {
    if pgrep -af '/usr/local/x-ui/bin/xray([[:space:]]|$)' >/dev/null 2>&1; then
        echo "运行"
        return 0
    fi

    if pgrep -af '/usr/local/x-ui/bin/xray-linux-(amd64|arm64)([[:space:]]|$)' >/dev/null 2>&1; then
        echo "运行"
        return 0
    fi

    if pgrep -af 'xray-linux-amd64|xray-linux-arm64|/usr/local/x-ui/bin/xray' >/dev/null 2>&1; then
        echo "运行"
        return 0
    fi

    echo "未运行"
}

show_panel_status() {
    check_status
    case $? in
        0) echo "已运行" ;;
        1) echo "未运行" ;;
        2) echo "未安装" ;;
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? -eq 0 ]]; then
        echo "是"
    else
        echo "否"
    fi
}

install() {
    if ! confirm "确定安装 x-ui 吗？" "y"; then
        [[ $# == 0 ]] && before_show_menu
        return 0
    fi

    bash <(curl -Ls "${INSTALL_SH_URL}")
    local ret=$?

    if [[ $ret -eq 0 ]]; then
        LOGI "安装完成"
        exit 0
    else
        LOGE "安装失败"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi
}

update() {
    if ! confirm "该操作会升级到最新版本，是否继续？" "n"; then
        LOGW "已取消"
        [[ $# == 0 ]] && before_show_menu
        return 0
    fi

    bash <(curl -Ls "${INSTALL_SH_URL}")
    local ret=$?

    if [[ $ret -eq 0 ]]; then
        LOGI "更新完成"
        exit 0
    else
        LOGE "更新失败"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi
}

uninstall() {
    if ! confirm "确定要卸载 x-ui 吗？" "n"; then
        [[ $# == 0 ]] && before_show_menu
        return 0
    fi

    systemctl stop x-ui >/dev/null 2>&1
    systemctl disable x-ui >/dev/null 2>&1

    rm -f /etc/systemd/system/x-ui.service
    systemctl daemon-reload

    rm -rf /usr/local/x-ui
    rm -f /usr/bin/x-ui

    LOGI "卸载完成"
    exit 0
}

reset_user() {
    if [[ ! -x "${PANEL_BIN}" ]]; then
        LOGE "x-ui 未安装"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi

    echo ""
    read -r -p "请输入新的用户名: " username
    read -r -p "请输入新的密码: " password

    if [[ -z "$username" || -z "$password" ]]; then
        LOGE "用户名和密码不能为空"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi

    "${PANEL_BIN}" setting -username "$username" -password "$password"
    if [[ $? -eq 0 ]]; then
        LOGI "用户名和密码已重置"
    else
        LOGE "重置失败"
    fi

    [[ $# == 0 ]] && before_show_menu
}

reset_config() {
    if [[ ! -x "${PANEL_BIN}" ]]; then
        LOGE "x-ui 未安装"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi

    if ! confirm "确定重置面板所有设置吗？" "n"; then
        [[ $# == 0 ]] && before_show_menu
        return 0
    fi

    "${PANEL_BIN}" setting -reset
    if [[ $? -eq 0 ]]; then
        LOGI "面板设置已重置"
    else
        LOGE "重置失败"
    fi

    [[ $# == 0 ]] && before_show_menu
}

set_port() {
    if [[ ! -x "${PANEL_BIN}" ]]; then
        LOGE "x-ui 未安装"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi

    echo ""
    read -r -p "请输入新的面板端口: " port

    if [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]]; then
        LOGE "端口格式错误"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi

    "${PANEL_BIN}" setting -port "${port}"
    if [[ $? -eq 0 ]]; then
        LOGI "端口已设置为 ${port}"
        confirm_restart
    else
        LOGE "设置端口失败"
        [[ $# == 0 ]] && before_show_menu
    fi
}

show_setting() {
    local username=""
    local db_port=""
    local runtime_port=""
    local listen=""
    local basepath=""
    local cert_file=""
    local key_file=""

    echo ""
    echo "当前面板设置"
    echo "----------------------------------------------"
    echo "面板状态: $(show_panel_status)"
    echo "是否开机自启: $(show_enable_status)"
    echo "xray 状态: $(get_xray_status)"

    if db_ready; then
        username=$(get_panel_username)
        db_port=$(get_panel_port)
        listen=$(get_panel_listen)
        basepath=$(get_panel_basepath)
        cert_file=$(get_panel_cert_file)
        key_file=$(get_panel_key_file)

        [[ -z "${username}" ]] && username="读取失败或未设置"
        [[ -z "${db_port}" ]] && db_port="54321"
        [[ -z "${listen}" ]] && listen="0.0.0.0"
        [[ -z "${basepath}" ]] && basepath="/"
        [[ -z "${cert_file}" ]] && cert_file="未设置"
        [[ -z "${key_file}" ]] && key_file="未设置"

        echo "面板用户名: ${username}"
        echo "面板端口: ${db_port}"
        echo "监听地址: ${listen}"
        echo "基础路径: ${basepath}"
        echo "证书文件: ${cert_file}"
        echo "密钥文件: ${key_file}"
        echo "数据库路径: ${DB_PATH}"
    else
        runtime_port=$(get_runtime_port_from_ss)
        [[ -z "${runtime_port}" ]] && runtime_port="读取失败"

        echo "面板用户名: 当前脚本无法读取"
        echo "面板端口: ${runtime_port}"
        echo "监听地址: 当前脚本无法读取"
        echo "基础路径: 当前脚本无法读取"
        echo "证书文件: 当前脚本无法读取"
        echo "密钥文件: 当前脚本无法读取"
        echo "数据库路径: ${DB_PATH} (不存在或未安装 sqlite3)"
        echo ""
        LOGW "如需完整显示面板设置，请安装 sqlite3，且确保数据库文件存在"
    fi

    echo "----------------------------------------------"
    [[ $# == 0 ]] && before_show_menu
}

start() {
    check_status
    if [[ $? -eq 0 ]]; then
        echo ""
        LOGI "x-ui 已在运行，无需重复启动"
    else
        systemctl start x-ui
        sleep 2
        check_status
        if [[ $? -eq 0 ]]; then
            LOGI "启动成功"
        else
            LOGE "启动失败，请检查日志"
        fi
    fi

    [[ $# == 0 ]] && before_show_menu
}

stop() {
    check_status
    if [[ $? -eq 1 ]]; then
        echo ""
        LOGI "x-ui 已停止，无需重复停止"
    else
        systemctl stop x-ui
        sleep 2
        check_status
        if [[ $? -eq 1 ]]; then
            LOGI "停止成功"
        else
            LOGE "停止失败，请检查日志"
        fi
    fi

    [[ $# == 0 ]] && before_show_menu
}

restart() {
    systemctl restart x-ui
    sleep 2
    check_status
    if [[ $? -eq 0 ]]; then
        LOGI "重启成功"
    else
        LOGE "重启失败，请检查日志"
    fi

    [[ $# == 0 ]] && before_show_menu
}

status() {
    systemctl status x-ui --no-pager -l
    [[ $# == 0 ]] && before_show_menu
}

show_log() {
    journalctl -u x-ui.service -e --no-pager -f
    [[ $# == 0 ]] && before_show_menu
}

enable() {
    systemctl enable x-ui
    if [[ $? -eq 0 ]]; then
        LOGI "已设置开机自启"
    else
        LOGE "设置开机自启失败"
    fi

    [[ $# == 0 ]] && before_show_menu
}

disable() {
    systemctl disable x-ui
    if [[ $? -eq 0 ]]; then
        LOGI "已取消开机自启"
    else
        LOGE "取消开机自启失败"
    fi

    [[ $# == 0 ]] && before_show_menu
}

install_bbr() {
    bash <(curl -L -s https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
    echo ""
    before_show_menu
}

install_acme() {
    if command -v acme.sh >/dev/null 2>&1; then
        LOGI "acme.sh 已安装"
    else
        curl https://get.acme.sh | sh
        source ~/.bashrc >/dev/null 2>&1
    fi

    LOGI "acme.sh 安装/检查完成"
    before_show_menu
}

update_shell() {
    wget -O /usr/bin/x-ui -N --no-check-certificate "${SCRIPT_URL}"
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "更新脚本失败，请检查网络或仓库地址"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "脚本更新成功"
        exit 0
    fi
}

confirm_restart() {
    if confirm "是否现在重启 x-ui？" "y"; then
        restart no_menu
    else
        [[ $# == 0 ]] && before_show_menu
    fi
}

show_menu() {
    clear
    echo "  x-ui 面板管理脚本"
    echo "  0. 退出脚本"
    echo "————————————————"
    echo "  1. 安装 x-ui"
    echo "  2. 更新 x-ui"
    echo "  3. 卸载 x-ui"
    echo "————————————————"
    echo "  4. 重置用户名密码"
    echo "  5. 重置面板设置"
    echo "  6. 设置面板端口"
    echo "  7. 查看当前面板设置"
    echo "————————————————"
    echo "  8. 启动 x-ui"
    echo "  9. 停止 x-ui"
    echo "  10. 重启 x-ui"
    echo "  11. 查看 x-ui 状态"
    echo "  12. 查看 x-ui 日志"
    echo "————————————————"
    echo "  13. 设置 x-ui 开机自启"
    echo "  14. 取消 x-ui 开机自启"
    echo "————————————————"
    echo "  15. 一键安装 bbr (最新内核)"
    echo "  16. 一键申请SSL证书(acme申请)"
    echo "  17. 更新管理脚本"
    echo ""

    echo -e "面板状态: $(show_panel_status)"
    echo -e "是否开机自启: $(show_enable_status)"
    echo -e "xray 状态: $(get_xray_status)"
    echo ""

    read -r -p "请输入选择 [0-17]: " num
    case "$num" in
        0) exit 0 ;;
        1) install ;;
        2) update ;;
        3) uninstall ;;
        4) reset_user ;;
        5) reset_config ;;
        6) set_port ;;
        7) show_setting ;;
        8) start ;;
        9) stop ;;
        10) restart ;;
        11) status ;;
        12) show_log ;;
        13) enable ;;
        14) disable ;;
        15) install_bbr ;;
        16) install_acme ;;
        17) update_shell ;;
        *) LOGW "无效选择"; sleep 1; show_menu ;;
    esac
}

handle_args() {
    case "$1" in
        start) start no_menu ;;
        stop) stop no_menu ;;
        restart) restart no_menu ;;
        status) status no_menu ;;
        enable) enable no_menu ;;
        disable) disable no_menu ;;
        log) show_log no_menu ;;
        settings) show_setting no_menu ;;
        update) update no_menu ;;
        install) install no_menu ;;
        uninstall) uninstall no_menu ;;
        *)
            show_menu
            ;;
    esac
}

require_root
handle_args "$1"
