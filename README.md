# Server Toolkit

Server Toolkit 是一个面向 Debian、Ubuntu 与主流 RHEL 系 VPS 的中文初始化、运维和修复工具。它同时提供交互菜单与可组合的命令行入口，默认先检测、危险操作单独确认、关键配置修改前备份。

当前版本重点解决“为了一个工具却安装整套依赖”的问题：软件目录中的每一项都能单独查询、预览和安装；工具集合与 profile 只有在明确选择后才会展开。

## 主要能力

- 单项软件目录：基础工具、现代 CLI、网络、监控、备份、安全、编译环境、运行时与数据库
- 精确 CLI 安装：`serverctl install curl jq` 只处理指定项目
- 基础初始化：时区、时间同步、hosts、Swap、安全自动更新
- 系统设置：主机名、Locale、管理员用户
- 网络优化：IPv4 / IPv6、IP 优先级、BBR、TCP profile
- SSH、防火墙与端口管理
- Docker、Caddy/Nginx、Redis/PostgreSQL/MariaDB/SQLite
- 环境自检、系统报告、修复、配置备份与回滚
- 可审计的无人值守 profiles

## 支持环境

- Debian 11 / 12 / 13
- Ubuntu 20.04 / 22.04 / 24.04
- Rocky Linux / AlmaLinux / Fedora 等使用 DNF/YUM 的系统（部分软件取决于发行版仓库）
- amd64 / arm64
- KVM / LXC / OpenVZ 基础识别
- IPv4、IPv6 和 IPv6-only 基础检测

## 安装

一行交互安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh)
```

非 root shell：

```bash
curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh | sudo bash -s --
```

更稳妥的方式是先下载并检查语法：

```bash
curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh -o /tmp/server-toolkit-install.sh
bash -n /tmp/server-toolkit-install.sh
sudo bash /tmp/server-toolkit-install.sh
```

默认路径：

| 项目 | 路径 |
| --- | --- |
| 程序目录 | `/opt/server-toolkit` |
| 命令入口 | `/usr/local/bin/serverctl` |
| 日志目录 | `/var/log/server-toolkit` |
| 备份目录 | `/var/backups/server-toolkit` |

## 推荐用法

打开主菜单或先运行只读自检：

```bash
sudo serverctl
sudo serverctl doctor
```

查看软件目录：

```bash
serverctl list                 # 全部项目与安装状态
serverctl list runtime         # 只看开发运行时
serverctl list python          # 按 ID 或说明搜索
```

精确安装一个或多个项目：

```bash
sudo serverctl install go
sudo serverctl install curl jq tmux
sudo serverctl install python-venv --dry-run
```

这里的参数是稳定的目录 ID，不一定等于发行版软件包名。例如 `fd` 会在 Debian/Ubuntu 上映射为 `fd-find`。如需直接使用原始包名，可在“软件安装中心 → 自定义包名”中安装。

## 常用命令

```bash
sudo serverctl detect           # 系统检测与建议
sudo serverctl doctor           # 项目和运行环境自检
sudo serverctl report           # 生成系统报告
sudo serverctl base             # 快速初始化
sudo serverctl system           # 系统设置
sudo serverctl software         # 单项软件与集合安装中心
sudo serverctl network          # 网络 / IPv6 / BBR
sudo serverctl ssh              # SSH 安全配置
sudo serverctl firewall         # 防火墙与端口
sudo serverctl docker           # Docker 环境
sudo serverctl web              # Web 服务
sudo serverctl database         # 数据库与缓存
sudo serverctl tools            # 监控、排障与备份工具
sudo serverctl repair           # 系统修复
sudo serverctl rollback         # 回滚配置备份
sudo serverctl uninstall        # 卸载
```

所有安装命令均支持 `--dry-run` 预览；`--skip-update` 可跳过本次软件源刷新。

## Profiles

Profiles 用于可重复的无人值守配置：

```bash
sudo serverctl install --profile minimal --yes
sudo serverctl install --profile docker --yes
sudo serverctl install --profile proxy --yes
sudo serverctl install --profile web --yes
```

| Profile | 内容摘要 |
| --- | --- |
| `minimal` | CA 证书与 curl，不安装历史基础工具集合 |
| `docker` | Docker / Compose；仅在合并已有配置确有需要时安装 jq |
| `web` | 原生 Caddy Web 服务，不再隐式安装 Docker 和监控套件 |
| `proxy` | Docker、Caddy、BBR 与少量明确列出的排障工具 |
| `dev` | Git、常用 CLI、Docker 与 SQLite |
| `full` | 明确列出的综合示例环境 |

内置 profile 都设置了 `PROFILE_INSTALL_BASE=0`。旧的自定义 profile 如果没有这个字段，仍保留原先“先安装基础集合”的兼容行为；建议迁移时显式声明并核对 `PROFILE_PACKAGES`。

安装器也可直接执行 profile：

```bash
sudo bash /tmp/server-toolkit-install.sh --profile docker --yes --no-menu
```

## 安全与回滚

- `/etc` 下的关键配置修改前会保存到 `/var/backups/server-toolkit/<时间>/`。
- Docker 日志配置会合并已有的有效 `daemon.json`；缺少 `jq` 时只单独安装 `jq`，配置无效或无法合并时保留原文件并停止。
- SSH、防火墙和卸载等高影响操作要求单独确认，除非明确传入 `--yes`。
- `--dry-run` 适合在新 VPS 或新 profile 上先检查动作，但不能替代快照和供应商控制台访问。

## 项目结构

```text
server-toolkit/
  serverctl.sh
  install.sh
  catalog/
    packages.tsv          # 软件 ID、分类与发行版包名映射
  lib/                    # 检测、包管理、目录、UI、备份等公共能力
  modules/                # 系统、网络、安全和服务领域模块
  profiles/               # 无人值守组合
  scripts/check.sh        # 语法、静态分析与测试统一入口
  tests/                  # 不修改系统的离线测试
  docs/ARCHITECTURE.md    # 扩展约定与依赖原则
```

开发检查：

```bash
bash scripts/check.sh
```

更详细的边界和新增软件项方法见 [项目结构与扩展约定](docs/ARCHITECTURE.md)。

## 卸载

```bash
sudo serverctl uninstall
sudo serverctl uninstall --purge --yes
```

交互卸载可选择仅删除命令入口、同时删除程序目录、日志，或连备份一起清理。`--purge` 会删除日志和备份，请确认不再需要回滚数据后使用。
