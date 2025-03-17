#!/bin/bash
# pi节点V2Ray高级安全增强版脚本
# 版本：6.0 | 更新：2025-03-18
# 功能：WebSocket+TLS + 端口映射 + 抗封锁伪装 + 管理功能

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# 配置文件路径
CONFIG_FILE="/etc/v2ray-config.json"

# 初始化配置参数
init_config() {
    if [ -f "$CONFIG_FILE" ]; then
        DOMAIN=$(jq -r .domain $CONFIG_FILE)
        WS_PATH=$(jq -r .ws_path $CONFIG_FILE)
        PORT_MAIN=$(jq -r .port_main $CONFIG_FILE)
        PORT_RANGE=$(jq -r .port_range $CONFIG_FILE)
        UUID=$(jq -r .uuid $CONFIG_FILE)
    else
        DOMAIN=""
        WS_PATH="/$(openssl rand -hex 8)"
        PORT_MAIN=2868
        PORT_RANGE="31400-31409"
        UUID=$(cat /proc/sys/kernel/random/uuid)
    fi
}

# 错误处理
exiterr() { echo -e "${RED}错误: $1${NC}" >&2; exit 1; }

# 检查root
check_root() {
    [ "$EUID" -ne 0 ] && exiterr "需要root权限"
}

# 保存配置
save_config() {
    cat > $CONFIG_FILE <<EOF
{
    "domain": "$DOMAIN",
    "ws_path": "$WS_PATH",
    "port_main": $PORT_MAIN,
    "port_range": "$PORT_RANGE",
    "uuid": "$UUID"
}
EOF
}

# 显示配置
show_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}未找到配置文件，请先安装服务${NC}"
        exit 1
    fi
    
    init_config
    echo -e "${GREEN}\n=============================================="
    echo " V2Ray 当前配置信息"
    echo "=============================================="
    echo -e "域名: ${YELLOW}$DOMAIN${GREEN}"
    echo -e "WebSocket路径: ${YELLOW}$WS_PATH${GREEN}"
    echo -e "主监听端口: ${YELLOW}$PORT_MAIN${GREEN}"
    echo -e "端口映射范围: ${YELLOW}$PORT_RANGE/TCP${GREEN}"
    echo -e "用户UUID: ${YELLOW}$UUID${GREEN}"
    echo -e "==============================================${NC}"
    
    echo -e "${YELLOW}客户端配置(V2RayN)：${NC}"
    echo "地址(Address): $DOMAIN"
    echo "端口(Port): 443"
    echo "用户ID(UUID): $UUID"
    echo "额外ID(AlterId): 0"
    echo "加密方式(Security): auto"
    echo "传输协议(Network): ws"
    echo "伪装域名(Host): $DOMAIN"
    echo "路径(Path): $WS_PATH"
    echo "TLS设置: 启用"
}

# 卸载服务
uninstall() {
    echo -e "${RED}确定要完全卸载V2Ray服务吗？(y/N)${NC}"
    read confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "卸载已取消"
        exit 0
    fi

    echo -e "${BLUE}[1/5] 停止运行服务...${NC}"
    systemctl stop v2ray nginx port-forward 2>/dev/null
    systemctl disable v2ray nginx port-forward 2>/dev/null

    echo -e "${BLUE}[2/5] 删除系统服务...${NC}"
    rm -f /etc/systemd/system/port-forward.service
    systemctl daemon-reload

    echo -e "${BLUE}[3/5] 移除软件包...${NC}"
    if grep -Eqi "ubuntu|debian" /etc/os-release; then
        apt remove -y -qq nginx certbot redir >/dev/null
    else
        yum remove -y -q nginx certbot redir >/dev/null
    fi
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --remove

    echo -e "${BLUE}[4/5] 清理配置文件...${NC}"
    rm -rf /etc/nginx/conf.d/v2ray.conf
    rm -rf /usr/local/etc/v2ray
    rm -rf /etc/letsencrypt/live/$DOMAIN
    rm -f $CONFIG_FILE

    echo -e "${BLUE}[5/5] 重置防火墙规则...${NC}"
    if command -v ufw >/dev/null; then
        ufw delete allow 80/tcp
        ufw delete allow 443/tcp
        ufw delete allow $PORT_RANGE/tcp
        ufw reload
    elif command -v firewall-cmd >/dev/null; then
        firewall-cmd --permanent --remove-port=80/tcp
        firewall-cmd --permanent --remove-port=443/tcp
        firewall-cmd --permanent --remove-port=$PORT_RANGE/tcp
        firewall-cmd --reload
    else
        iptables -D INPUT -p tcp --dport 80 -j ACCEPT
        iptables -D INPUT -p tcp --dport 443 -j ACCEPT
        iptables -D INPUT -p tcp -m multiport --dports $PORT_RANGE -j ACCEPT
        iptables-save > /etc/iptables/rules.v4
    fi

    echo -e "${GREEN}卸载完成，所有相关配置已清理！${NC}"
}

# 安装系统依赖
install_deps() {
    echo -e "${BLUE}[1/7] 安装系统依赖...${NC}"
    if grep -Eqi "ubuntu|debian" /etc/os-release; then
        apt update -qq && apt install -y -qq \
            curl wget unzip nginx certbot python3-certbot-nginx redir jq >/dev/null || exiterr "依赖安装失败"
    elif grep -Eqi "centos|redhat" /etc/os-release; then
        yum install -y -q epel-release && yum install -y -q \
            curl wget unzip nginx certbot redir jq >/dev/null || exiterr "依赖安装失败"
    else
        exiterr "不支持的操作系统"
    fi
}

# 申请TLS证书
get_certificate() {
    echo -e "${BLUE}[2/7] 获取SSL证书...${NC}"
    systemctl stop nginx
    certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN || exiterr "证书获取失败"
}

# 配置Nginx反向代理
configure_nginx() {
    echo -e "${BLUE}[3/7] 配置Nginx...${NC}"
    cat > /etc/nginx/conf.d/v2ray.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

    location $WS_PATH {
        proxy_pass http://127.0.0.1:$PORT_MAIN;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
    systemctl restart nginx || exiterr "Nginx配置失败"
}

# 安装V2Ray核心
install_v2ray() {
    echo -e "${BLUE}[4/7] 安装V2Ray...${NC}"
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) || exiterr "V2Ray安装失败"
}

# 配置V2Ray服务
configure_v2ray() {
    echo -e "${BLUE}[5/7] 生成V2Ray配置...${NC}"
    mkdir -p /usr/local/etc/v2ray
    cat > /usr/local/etc/v2ray/config.json <<EOF
{
  "log": {"loglevel": "warning"},
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [
      {"type": "field", "outboundTag": "direct", "domain": ["geosite:cn"]},
      {"type": "field", "outboundTag": "blocked", "ip": ["geoip:private"]}
    ]
  },
  "inbounds": [
    {
      "port": $PORT_MAIN,
      "protocol": "vmess",
      "settings": {
        "clients": [{
          "id": "$UUID",
          "alterId": 0,
          "security": "auto"
        }]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "$WS_PATH",
          "headers": {
            "Host": "$DOMAIN"
          }
        }
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ]
}
EOF
}

# 配置端口转发
setup_forwarding() {
    echo -e "${BLUE}[6/7] 配置端口映射...${NC}"
    cat > /etc/systemd/system/port-forward.service <<EOF
[Unit]
Description=TCP Port Forwarding Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/redir --laddr=0.0.0.0 --lport=$PORT_RANGE --caddr=127.0.0.1 --cport=$PORT_RANGE -t
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now port-forward || exiterr "端口映射启动失败"
}

# 配置防火墙
setup_firewall() {
    echo -e "${BLUE}[7/7] 配置防火墙...${NC}"
    if command -v ufw >/dev/null; then
        ufw allow 80/tcp comment "HTTP"
        ufw allow 443/tcp comment "HTTPS"
        ufw allow $PORT_RANGE/tcp comment "Port Forwarding"
        ufw reload
    elif command -v firewall-cmd >/dev/null; then
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --permanent --add-port=$PORT_RANGE/tcp
        firewall-cmd --reload
    else
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        iptables -A INPUT -p tcp -m multiport --dports $PORT_RANGE -j ACCEPT
        iptables-save > /etc/iptables/rules.v4
    fi
}

# 安装流程
install() {
    check_root
    init_config
    
    echo -e "${GREEN}请输入您的域名（例如：example.com）：${NC}"
    read -r DOMAIN
    [[ -z "$DOMAIN" ]] && exiterr "域名不能为空"
    WS_PATH="/$(openssl rand -hex 8)"
    save_config

    install_deps
    get_certificate
    configure_nginx
    install_v2ray
    configure_v2ray
    setup_forwarding
    setup_firewall
    
    systemctl restart v2ray
    show_config
}

# 主流程
case "$1" in
    install)
        install
        ;;
    --config|-c)
        show_config
        ;;
    --uninstall|-u)
        uninstall
        ;;
    *)
        echo -e "${GREEN}使用方法:${NC}"
        echo "  $0 install         安装V2Ray服务"
        echo "  $0 --config | -c   查看当前配置"
        echo "  $0 --uninstall | -u 完全卸载服务"
        exit 0
        ;;
esac
