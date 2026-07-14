# Server Toolkit

Server Toolkit 是一个模块化 VPS 初始化与维护工具。它的目标不是“一键乱改系统”，而是：

- 先检测，再建议
- 默认保守，不自动改 SSH、不默认升级内核
- 所有关键配置先备份
- 支持交互菜单和无人值守 profile
- 支持 GitHub 远程安装

## 支持范围

- Debian 11/12/13
- Ubuntu 20.04/22.04/24.04
- amd64 / arm64
- KVM / LXC / OpenVZ 基础识别
- IPv4 / IPv6 / IPv6-only 基础检测

## 一行交互运行

默认会安装工具，然后直接打开中文交互菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh)
```

如果不是 root，推荐：

```bash
curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh | sudo bash -s --
```

## 稳妥安装方式

先下载、语法检查、再执行，然后打开中文菜单：

```bash
curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh -o /tmp/server-toolkit-install.sh
bash -n /tmp/server-toolkit-install.sh
sudo bash /tmp/server-toolkit-install.sh
```

安装后：

```bash
sudo serverctl
sudo serverctl detect
sudo serverctl report
```

## 无人值守执行 profile

```bash
curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh -o /tmp/server-toolkit-install.sh
bash -n /tmp/server-toolkit-install.sh
sudo bash /tmp/server-toolkit-install.sh --profile proxy --yes --no-menu
```

如果仓库名不同：

```bash
sudo bash /tmp/server-toolkit-install.sh --repo 你的用户名/server-toolkit --ref main
```

## 常用命令

```bash
sudo serverctl                  # 打开中文主菜单
sudo serverctl detect           # 系统检测
sudo serverctl report           # 生成 /root/server-report.txt
sudo serverctl install --profile proxy
sudo serverctl install --profile docker
sudo serverctl network
sudo serverctl ssh
sudo serverctl repair
sudo serverctl rollback
```

## Profiles / 配置档

| Profile | 说明 |
| --- | --- |
| `minimal` | 最小初始化，只安装 curl/wget/git/jq |
| `proxy` | 代理/VPS 常用：BBR、TCP proxy profile、Docker、Caddy、监控工具 |
| `docker` | Docker/Compose、基础工具、监控工具 |
| `web` | Docker、Caddy、80/443、防火墙、监控工具 |
| `dev` | 开发环境：基础工具、Docker、SQLite、监控工具 |
| `full` | 全功能示例：Docker、Caddy、Redis、SQLite、BBR、监控工具 |

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

## GitHub 发布步骤

```bash
git init
git add .
git commit -m "Initial Server Toolkit"
git branch -M main
git remote add origin git@github.com:你的用户名/server-toolkit.git
git push -u origin main
```

远程运行时，优先使用固定版本 tag：

```bash
git tag v0.2.0
git push origin v0.2.0
sudo bash /tmp/server-toolkit-install.sh --repo 你的用户名/server-toolkit --ref v0.2.0
```

## 安全提醒

- 不要把 SSH 私钥、Token、服务器 IP 列表放进仓库。
- 修改 SSH 前，保留当前连接，另开窗口测试新连接。
- 云厂商安全组需要手动同步放行端口。
- 数据库、Redis、Docker API 不建议直接暴露公网。
