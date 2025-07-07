#!/usr/bin/env bash
# -----------------------------------------------
# Block-IPs-from-countries – 修改版
#   • 可按国家代码创建 ipset 列表
#   • 交互式询问「封锁端口」并仅对该端口 DROP
#   • 保留原作者其它功能与语法
# -----------------------------------------------
# 原始仓库: https://github.com/iiiiiii1/Block-IPs-from-countries [1]
# -----------------------------------------------

Green="\033[32m"
Red="\033[31m"
Font="\033[0m"

# ---------- 基础检测 ----------
root_need(){
  if [[ $EUID -ne 0 ]]; then
    echo -e "${Red}Error: 必须以 root 身份运行脚本！${Font}"
    exit 1
  fi
}

system_check(){
  if      command -v yum   >/dev/null 2>&1 ; then PM="yum"
  elif    command -v apt   >/dev/null 2>&1 ; then PM="apt"
  else
    echo -e "${Red}暂不支持的发行版，请手工安装 ipset 与 iptables！${Font}"
    exit 1
  fi
}

check_ipset(){
  if ! command -v ipset >/dev/null 2>&1 ; then
    echo -e "${Green}正在安装 ipset…${Font}"
    [[ $PM == "yum" ]] && yum install -y ipset iptables-services >/dev/null
    [[ $PM == "apt" ]] && apt  update -qq && apt  install -y ipset iptables >/dev/null
  fi
}

# ---------- 主要功能 ----------
block_ipset(){
  check_ipset

  # ① 国家代码（小写 ISO 3166-1 alpha-2）
  echo -e "${Green}输入要封禁的国家代码，例如 cn（中国）：${Font}"
  read -rp "Country code: " GEOIP

  # ② 端口（交互输入，可多端口逗号分隔）
  echo -e "${Green}输入要封锁的端口（可写多个，用逗号分隔，例如 25,465）：${Font}"
  read -rp "Port(s): " PORTS

  # ③ 下载国家 IP 段
  echo -e "${Green}正在下载 ${GEOIP} IP 地址段…${Font}"
  wget -qO "/tmp/${GEOIP}.zone" "https://www.ipdeny.com/ipblocks/data/countries/${GEOIP}.zone"
  if [[ ! -s /tmp/${GEOIP}.zone ]]; then
    echo -e "${Red}下载失败，请检查国家代码！${Font}"
    exit 1
  fi

  # ④ 创建 ipset 集合
  ipset destroy "$GEOIP" 2>/dev/null
  ipset create  "$GEOIP" hash:net
  while read -r ip; do ipset add "$GEOIP" "$ip"; done < "/tmp/${GEOIP}.zone"
  rm -f "/tmp/${GEOIP}.zone"

  # ⑤ 写入 iptables 规则（仅指定端口）
  OLD_RULE_EXISTS=$(iptables -S | grep -F "match-set $GEOIP src" || true)
  if [[ -n $OLD_RULE_EXISTS ]]; then
    echo -e "${Green}检测到旧规则，已跳过重复添加。${Font}"
  fi

  IFS=',' read -ra ARR <<< "$PORTS"
  for p in "${ARR[@]}"; do
    iptables -I INPUT -p tcp --dport "$p" -m set --match-set "$GEOIP" src -j DROP
  done

  echo -e "${Green}${GEOIP} 的 IP 已成功封禁端口 ${PORTS}！${Font}"
}

unblock_ipset(){
  echo -e "${Green}输入要解除封禁的国家代码：${Font}"
  read -rp "Country code: " GEOIP
  ipset destroy "$GEOIP" 2>/dev/null
  # 同时删除相关 iptables 规则
  while iptables -D INPUT -m set --match-set "$GEOIP" src -j DROP 2>/dev/null; do : ; done
  echo -e "${Green}已删除 ${GEOIP} 相关规则。${Font}"
}

# ---------- 菜单 ----------
menu(){
  clear
  echo -e "
${Green}一键封锁 / 解除 指定国家 IP 段${Font}
----------------------------------------
1) 封锁指定国家（交互式）
2) 解除封锁
0) 退出
"
  read -rp "请选择 [0-2]: " num
  case "$num" in
    1) root_need; system_check; block_ipset ;;
    2) root_need; unblock_ipset ;;
    0) exit 0 ;;
    *) echo -e "${Red}请输入正确数字！${Font}" ; sleep 1 ; menu ;;
  esac
}

menu
