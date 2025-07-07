#!/usr/bin/env bash
# -----------------------------------------------
# Block-IPs-from-countries – 修改版
#   • 可按国家代码创建 ipset 列表
#   • 交互式询问「封锁端口」并仅对该端口 DROP
#   • 保留原作者其它功能与语法
# -----------------------------------------------
# 原始仓库: https://github.com/iiiiiii1/Block-IPs-from-countries [1]
# -----------------------------------------------

Green="\033[32m"; Red="\033[31m"; Font="\033[0m"
PM=""      # 包管理器 (yum|apt)

# ---------- 基础检测 ----------
root_need() {
  [[ $EUID -ne 0 ]] && { echo -e "${Red}必须以 root 身份运行！${Font}"; exit 1; }
}

system_check() {
  if   command -v yum >/dev/null 2>&1 ; then PM="yum"
  elif command -v apt >/dev/null 2>&1 ; then PM="apt"
  else
    echo -e "${Red}暂不支持的发行版 (仅支持 yum/apt)。${Font}"; exit 1
  fi
}

install_deps() {
  if ! command -v ipset >/dev/null 2>&1 ; then
    echo -e "${Green}安装依赖…${Font}"
    [[ $PM == "yum" ]] && yum -y install ipset iptables-services wget >/dev/null
    [[ $PM == "apt" ]] && apt  update -qq \
                       && DEBIAN_FRONTEND=noninteractive apt -y install ipset iptables wget >/dev/null
  fi
}

# ---------- 持久化 ----------
persist_rules() {
  echo -e "${Green}正在持久化防火墙规则…${Font}"

  if [[ $PM == "yum" ]]; then
    service iptables save
    ipset save > /etc/sysconfig/ipset

    # 如系统无原生 ipset.service，则创建一个
    if [[ ! -f /usr/lib/systemd/system/ipset.service ]]; then
cat > /usr/lib/systemd/system/ipset.service <<'EOF'
[Unit]
Description=Restore ipset rules
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ipset restore < /etc/sysconfig/ipset
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    fi
    systemctl enable iptables ipset >/dev/null

  else   # Debian / Ubuntu
    DEBIAN_FRONTEND=noninteractive apt -y install iptables-persistent >/dev/null   # 自动保存 v4/v6 规则
    iptables-save > /etc/iptables/rules.v4
    ipset   save > /etc/ipset.conf

    # 自建 ipset-restore.service
cat > /etc/systemd/system/ipset-restore.service <<'EOF'
[Unit]
Description=Restore ipset rules
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ipset restore < /etc/ipset.conf
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable netfilter-persistent ipset-restore >/dev/null   # netfilter-persistent = iptables-persistent wrapper
  fi

  echo -e "${Green}持久化完成！重启后规则将自动恢复。${Font}"
}

# ---------- 主要功能 ----------
block_ipset() {
  # ① 国家代码
  echo -e "${Green}输入要封禁的国家代码（小写，如 cn）：${Font}"
  read -rp "Country code: " GEOIP

  # ② 端口，可多端口用逗号
  echo -e "${Green}输入要封锁的端口（如 25,465）：${Font}"
  read -rp "Port(s): " PORTS

  # ③ 下载 IP 段
  echo -e "${Green}下载 ${GEOIP} IP 列表…${Font}"
  wget -qO "/tmp/${GEOIP}.zone" "https://www.ipdeny.com/ipblocks/data/countries/${GEOIP}.zone"
  [[ ! -s /tmp/${GEOIP}.zone ]] && { echo -e "${Red}下载失败，请检查代码！${Font}"; exit 1; }

  # ④ 创建 / 更新 ipset
  ipset destroy "$GEOIP" 2>/dev/null
  ipset create  "$GEOIP" hash:net
  while read -r ip; do
    ipset add -exist "$GEOIP" "$ip"
  done < "/tmp/${GEOIP}.zone"
  rm -f "/tmp/${GEOIP}.zone"

  # ⑤ 写入 iptables（仅指定端口）
  IFS=',' read -ra P_ARR <<< "$PORTS"
  for p in "${P_ARR[@]}"; do
    # 先检查是否已存在规则，避免重复插入
    if ! iptables -C INPUT -p tcp --dport "$p" -m set --match-set "$GEOIP" src -j DROP 2>/dev/null; then
      iptables -I INPUT -p tcp --dport "$p" -m set --match-set "$GEOIP" src -j DROP
    fi
  done

  echo -e "${Green}${GEOIP} IP 已封禁端口 ${PORTS}！${Font}"
  persist_rules
}

unblock_ipset() {
  echo -e "${Green}输入要解除封禁的国家代码（小写）：${Font}"
  read -rp "Country code: " GEOIP

  echo -e "${Green}输入要解除封禁的端口（可多个逗号分隔）：${Font}"
  read -rp "Port(s): " PORTS

  # 删除 iptables 规则时针对每个端口删除对应规则
  IFS=',' read -ra P_ARR <<< "$PORTS"
  for p in "${P_ARR[@]}"; do
    # 循环删除所有匹配规则，直到无此规则为止
    while iptables -C INPUT -p tcp --dport "$p" -m set --match-set "$GEOIP" src -j DROP 2>/dev/null; do
      iptables -D INPUT -p tcp --dport "$p" -m set --match-set "$GEOIP" src -j DROP
    done
  done

  # 删除 ipset 集合
  ipset destroy "$GEOIP" 2>/dev/null

  # 持久化保存规则
  persist_rules

  echo -e "${Green}已解除 ${GEOIP} 端口 ${PORTS} 的封禁规则。${Font}"
}

# ---------- 菜单 ----------
menu() {
  clear
  echo -e "
${Green}一键封锁 / 解除 指定国家 IP 段${Font}
----------------------------------------
1) 封锁指定国家（交互式）
2) 解除封禁（交互式）
0) 退出
"
  read -rp "请选择 [0-2]: " num
  case "$num" in
    1) root_need; system_check; install_deps; block_ipset ;;
    2) root_need; system_check; install_deps; unblock_ipset ;;
    0) exit 0 ;;
    *) echo -e "${Red}请输入正确数字！${Font}" ; sleep 1 ; menu ;;
  esac
}

menu
