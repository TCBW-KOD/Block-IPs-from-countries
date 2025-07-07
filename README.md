# Block-IPs-from-countries (交互式端口版)

一个 **一键封锁 / 解除 指定国家 IP 段** 的 bash 脚本。  
与原版相比，本仓库新增了 *交互式端口输入*，可在运行时灵活选择要阻断的端口，而非写死在脚本里。  
适用于 CentOS、Debian、Ubuntu 等主流发行版。

## 功能亮点
- 拉取 IPdeny 最新 **国家/地区 IPv4 列表** 并写入 `ipset`  
- 通过 `iptables` **仅对指定端口** 发起封锁，避免误伤整机  
- 支持一次输入 **多个端口**（用逗号分隔）  
- 内置菜单：封锁 / 解除 均可一键完成  
- 兼容 TCP 与 UDP；可持久化规则以便重启后自动生效  

## 快速开始

```bash
# 下载脚本
wget -O block-ips.sh https://raw.githubusercontent.com/你的仓库/Block-IPs-from-countries/master/block-ips.sh
chmod +x block-ips.sh

# 运行脚本（交互式）
sudo ./block-ips.sh
```

交互示例：

```
Country code: cn
Port(s): 25,465
```

完成后，所有来自中国大陆的 IP 将被 **DROP TCP 25/465**，其他流量不受影响。

## 使用方法

### 1. 封锁指定国家
1. 运行脚本并选择菜单 `1) 封锁指定国家`
2. 输入两项信息  
   - 国家代码（小写 ISO 3166-1 alpha-2，如 `cn`、`ru`）  
   - 端口号（单端口或 `80,443,3306` 形式的多端口）
3. 脚本会：  
   - 下载国家 IP 段 → 创建/更新同名 `ipset` 集合  
   - 为每个端口插入一条 `iptables -I INPUT -p tcp --dport  -m set --match-set  src -j DROP`

### 2. 解除封禁
选择菜单 `2) 解除封禁`，输入相同的国家代码即可：  
- 销毁对应 `ipset` 集合  
- 删除所有关联的 `iptables` 规则

### 3. 持久化规则
- CentOS（iptables-services）：  
  ```bash
  service iptables save
  systemctl enable iptables --now
  ```
- Debian/Ubuntu：  
  ```bash
  iptables-save > /etc/iptables.rules
  # 在 /etc/rc.local 或 systemd unit 中加载：
  iptables-restore /dev/null 2>&1

## 致谢
- 原脚本作者 **Moerats** 提供的基础实现  
- IPdeny 提供公开的世界各国 IP 段数据  

**Enjoy!** 若有问题欢迎提 Issue 或 PR。
