# Server Toolkit

Server Toolkit 是一个面向 Debian / Ubuntu VPS 的中文初始化、运维与修复工具。

它的设计目标是：先检测，再建议；危险操作单独确认；关键配置先备份；同时支持交互菜单和无人值守 profile。

## 功能特性

- 中文交互式终端面板
- 系统信息检测与风险建议
- 基础初始化：依赖、时区、时间同步、hosts、自动更新等
- 系统设置：主机名、Locale、Swap、管理员用户等
- 软件安装中心：基础工具、现代 CLI、开发运行时、服务组件
- 网络优化：IPv4 / IPv6 检测、IP 优先级、BBR、TCP profile
- SSH 与登录安全配置
- 防火墙与端口管理
- Docker / Web / 数据库 / 监控工具模块
- 系统修复、回滚备份、系统报告
- 安装器和本体都支持卸载

## 支持环境

- Debian 11 / 12 / 13
- Ubuntu 20.04 / 22.04 / 24.04
- amd64 / arm64
- KVM / LXC / OpenVZ 基础识别
- IPv4 / IPv6 / IPv6-only 基础检测

## 安装

一行交互安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh)
```

非 root 环境：

```bash
curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh | sudo bash -s --
```

稳妥安装：

```bash
curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh -o /tmp/server-toolkit-install.sh
bash -n /tmp/server-toolkit-install.sh
sudo bash /tmp/server-toolkit-install.sh
```

默认安装位置：

| 项目 | 路径 |
| --- | --- |
| 程序目录 | `/opt/server-toolkit` |
| 命令入口 | `/usr/local/bin/serverctl` |
| 日志目录 | `/var/log/server-toolkit` |
| 备份目录 | `/var/backups/server-toolkit` |

## 常用命令

```bash
sudo serverctl                  # 打开中文主菜单
sudo serverctl detect           # 系统检测
sudo serverctl report           # 生成系统报告
sudo serverctl system           # 系统设置中心
sudo serverctl software         # 软件安装中心
sudo serverctl network          # 网络 / IPv6 / BBR
sudo serverctl ssh              # SSH 安全配置
sudo serverctl firewall         # 防火墙与端口
sudo serverctl docker           # Docker 环境
sudo serverctl web              # Web 服务
sudo serverctl repair           # 系统修复
sudo serverctl rollback         # 回滚备份
sudo serverctl uninstall        # 卸载
```

## Profile

无人值守执行：

```bash
sudo serverctl install --profile minimal --yes
sudo serverctl install --profile docker --yes
sudo serverctl install --profile proxy --yes
sudo serverctl install --profile web --yes
```

安装器直接执行 profile：

```bash
sudo bash /tmp/server-toolkit-install.sh --profile docker --yes --no-menu
```

可用 profile：

| Profile | 说明 |
| --- | --- |
| `minimal` | 最小初始化与基础工具 |
| `proxy` | 代理节点常用配置、BBR、Docker、Web、监控工具 |
| `docker` | Docker / Compose 与常用工具 |
| `web` | Web 服务、Docker、防火墙、监控工具 |
| `dev` | 开发环境、Docker、SQLite、监控工具 |
| `full` | 全功能示例配置 |

## 卸载

交互式卸载：

```bash
sudo serverctl uninstall
```

卸载时可选择范围：

| 选项 | 删除内容 |
| --- | --- |
| `1` | 仅删除 `serverctl` 命令入口 |
| `2` | 删除命令入口和安装目录 |
| `3` | 删除命令入口、安装目录和日志 |
| `4` | 全部删除，包括日志和备份 |

无人值守卸载：

```bash
sudo serverctl uninstall --yes
sudo serverctl uninstall --purge --yes
```

安装器卸载：

```bash
sudo bash /tmp/server-toolkit-install.sh --uninstall
sudo bash /tmp/server-toolkit-install.sh --uninstall --purge --yes
```

## 项目结构

```text
server-toolkit/
  install.sh
  serverctl.sh
  lib/
    core.sh
    ui.sh
    backup.sh
    detect.sh
    package.sh
  modules/
    base.sh
    network.sh
    firewall.sh
    ssh.sh
    software.sh
    docker.sh
    web.sh
    database.sh
    monitor.sh
    repair.sh
    system.sh
  profiles/
    minimal.conf
    proxy.conf
    docker.conf
    web.conf
    dev.conf
    full.conf
```
