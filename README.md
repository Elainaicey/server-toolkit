# Server Toolkit

Server Toolkit 是一个面向 Debian / Ubuntu VPS 的中文交互式运维工具。它把常用检查与管理操作组织成清晰的一层功能中心，同时坚持“一个动作只做一件事、修改前说明、执行前确认、配置可恢复”。

当前版本：`0.1.0`

> 这是一次从底层重新设计的版本，不兼容旧目录、旧命令或旧 profile。

## 能做什么

| 功能中心 | 能力 |
| --- | --- |
| 系统仪表盘 | 系统、CPU、内存、Swap、磁盘、负载、运行时间、关键服务、监听端口、可更新软件概览 |
| 系统管理 | 环境检查、进程排行、用户会话、计划任务、重启状态、软件包健康、磁盘、主机名、时区、Swap、时间同步与清理 |
| 网络与端口 | 地址、路由、网卡流量、目标诊断、IPv4/IPv6 连通性、监听端口、端口进程、BBR、地址优先级 |
| 安全中心 | 安全基线、公网监听、UFW、SSH 安全向导、登录事件与 Fail2ban 状态 |
| 服务与日志 | 运行/失败服务、启动错误、Timer、Journal、内核警告、服务控制与操作记录 |
| 软件管理 | 按名称、ID 或说明搜索；查看安装状态；一次安装或移除一个软件 |
| 应用与容器 | 常见应用状态；Docker 容器、镜像、资源、Compose、存储卷、网络和安全清理 |
| 备份与恢复 | 浏览自动配置快照、检查备份清单、选择并恢复单个配置文件 |

软件目录涵盖常用基础工具、命令行工具、网络诊断、监控、备份、安全、开发环境、运行时、服务与容器工具。普通条目精确映射一个 APT 包；Docker 和 Caddy 使用独立的官方仓库安装器。

Docker 与 Caddy 安装流程分别遵循其[官方 Docker APT 文档](https://docs.docker.com/engine/install/)和[Caddy 安装文档](https://caddyserver.com/docs/install)。

## 设计原则

- 单项安装：`install` 和 `remove` 一次只接收一个软件 ID，不提供套餐、多选或“全部安装”。
- 人工确认：没有 profiles、`--yes` 或无人值守安装；所有修改动作都需要明确确认。
- 副作用透明：安装软件不会顺便开放端口、修改 SSH、调整内核或配置其他服务。
- 先验证再应用：端口、服务名、路径和 SSH 配置都经过校验。
- 可预览、可追踪、可恢复：支持 `--dry-run`，记录 root 修改动作，并在改配置前建立快照。
- 结构有边界：入口、核心能力、业务功能和数据配置彼此分离。

## 支持范围

- Debian 11、12、13
- Ubuntu 22.04、24.04
- amd64、arm64
- 使用 systemd 的常见 KVM / LXC VPS

当前不支持 RHEL 系、Alpine 或非 systemd 系统。项目优先把明确支持的范围做稳，不保留未经验证的兼容分支。

## 安装

root 用户一键安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/refs/heads/main/install.sh)
```

非 root 用户可使用：

```bash
sudo bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/refs/heads/main/install.sh)'
```

安装器可能使用临时暂存目录完成下载和原子替换，但会自动清理；最终项目只安装到 `/opt/server-toolkit`。

也可以克隆仓库后安装本地代码：

```bash
git clone https://github.com/Elainaicey/server-toolkit.git
cd server-toolkit
sudo bash install.sh
```

安装器会显示目标并等待确认，随后原子替换程序目录：

| 内容 | 默认路径 |
| --- | --- |
| 程序 | `/opt/server-toolkit` |
| 命令入口 | `/usr/local/bin/serverctl` |
| 配置备份 | `/var/backups/server-toolkit` |
| 操作记录 | `/var/log/server-toolkit/actions.log` |

指定分支、标签或安装位置：

```bash
sudo bash install.sh --ref v0.1.0
sudo bash install.sh --dir /opt/server-toolkit --bin /usr/local/bin/serverctl
```

查看安装计划而不写入：

```bash
sudo bash install.sh --dry-run
```

## 使用

打开交互控制台：

```bash
sudo serverctl
```

常用非交互查询命令：

```bash
serverctl status
serverctl doctor
serverctl ports
serverctl system
serverctl network
serverctl security
serverctl services
serverctl apps
serverctl list
serverctl list python
serverctl uninstall
serverctl version
```

安装或移除一个软件：

```bash
sudo serverctl install jq
sudo serverctl install docker
sudo serverctl remove jq
```

即使从命令行发起，实际修改前仍会要求确认。`serverctl install curl jq` 会被拒绝。

预览系统修改：

```bash
sudo serverctl --dry-run install docker
sudo serverctl --dry-run
```

## 安全与恢复

- SSH 向导会检查端口占用和公钥，写入独立 drop-in，并用 `sshd -t` 验证；验证失败立即恢复。
- UFW 向导会先识别并放行当前 SSH 端口，降低远程锁死风险。
- BBR 只在当前内核支持时启用，不写入激进的“万能优化”参数。
- 软件安装、服务控制和配置修改会写入审计日志。
- 被修改的现有配置会保存在带清单的时间戳快照中，可在交互界面恢复单个文件。
- 安装器拒绝危险宽泛目录、符号链接安装目录和属于其他程序的命令入口。
- Docker 发布的容器端口可能绕过 UFW 规则；项目会在 Docker 中心提示这一点，但不会替用户自动改写 Docker 防火墙策略。

修改 SSH、防火墙或网络参数前，仍建议保留 VPS 服务商控制台并创建实例快照。

## 项目结构

```text
server-toolkit/
├── bin/serverctl          # 唯一运行入口
├── config/software.tsv    # 单项软件目录
├── scripts/install.sh     # 完整安装与卸载逻辑
├── src/core/              # 运行时、UI、平台、备份、软件目录
├── src/features/          # 独立功能中心
│   └── apps/docker.sh     # 应用与容器下的 Docker 实现
├── tests/                 # 离线单元与边界测试
├── install.sh             # 稳定的下载/安装引导器
└── VERSION                # 唯一版本号
```

为什么根目录仍有 `install.sh`？因为远程安装需要一个长期稳定、容易记忆的 URL。它只负责定位本地安装器或下载 `scripts/install.sh`，不包含业务逻辑。`serverctl` 属于可执行程序，所以放在 `bin/`；功能实现全部位于 `src/`。

详细边界与扩展方法见 [设计文档](docs/DESIGN.md)。

## 卸载

可在 `系统管理 → 卸载本项目` 中选择，也可以直接执行：

```bash
sudo serverctl uninstall
```

卸载提供两种模式：

- 仅卸载程序：删除 `/opt/server-toolkit` 和属于本项目的命令链接，保留日志与备份。
- 彻底清除项目数据：额外删除 `/var/backups/server-toolkit`、`/var/log/server-toolkit` 和 `/var/lib/server-toolkit`。

为了避免破坏业务，卸载不会自动删除通过项目安装的软件，也不会猜测性回滚主机名、SSH、防火墙、Swap 等系统设置。需要恢复配置时，应先在备份中心选择明确快照。

## 开发与检查

```bash
bash scripts/check.sh
```

检查包括 Bash 语法、ShellCheck（若已安装）、单元测试、软件目录格式和 CLI 冒烟测试。贡献约定见 [CONTRIBUTING.md](CONTRIBUTING.md)。
