<div align="center">

# Server Toolkit

**面向 Debian / Ubuntu VPS 的中文交互式运维控制台**

以清晰的信息架构组织系统、网络、安全、服务、软件、容器与配置恢复；每一次系统修改都强调可见、可确认与可追踪。

[![Version](.github/assets/badges/version.svg)](VERSION)
[![Checks](https://github.com/Elainaicey/server-toolkit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Elainaicey/server-toolkit/actions/workflows/ci.yml)
![Shell](.github/assets/badges/shell.svg)
![Platform](.github/assets/badges/platform.svg)
![Language](.github/assets/badges/language.svg)
[![License](.github/assets/badges/license.svg)](LICENSE)

[快速开始](#快速开始) · [功能矩阵](#功能矩阵) · [命令参考](#命令参考) · [安全模型](#安全模型) · [项目结构](#项目结构)

</div>

---

## 项目概览

Server Toolkit 面向由单一 root 管理员维护的 Linux VPS，提供从状态观察、故障定位到常规配置变更的统一终端入口。

项目不追求无边界地收集脚本，而是遵循以下约束：

- **清晰分层**：系统能力优先于软件与应用，Docker 等独立应用归入应用中心。
- **单项操作**：软件一次安装、更新或移除一个条目，不提供套餐、全选和隐式依赖组合。
- **人工确认**：不存在 `--yes`、profiles 或无人值守系统修改。
- **完全按需**：命令退出后不保留项目进程，不创建 Cron、systemd Timer 或后台监控。
- **副作用透明**：软件安装不会自动开放端口、修改 SSH 或套用网络调优模板。
- **恢复优先**：配置变更前创建清单化快照；高风险配置先验证，再加载。
- **最小运行依赖**：核心控制台使用 Bash 与 Debian/Ubuntu 标准系统工具实现。

## 快速开始

### 一键安装

root 会话：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/refs/heads/main/install.sh)
```

安装器将程序原子部署到 `/opt/server-toolkit`，并创建 `/usr/local/bin/serverctl`。下载或暂存目录会在流程结束后自动清理。

### 启动控制台

```bash
serverctl
```

控制台主导航按系统依赖层级排列：

```text
系统仪表盘 → 系统管理 → 网络与端口 → 安全中心
            → 服务与日志 → 软件管理 → 应用与容器 → 备份与恢复
```

## 功能矩阵

| 中心 | 能力 |
| --- | --- |
| **系统仪表盘** | 主机环境、负载、内存/Swap/磁盘进度、systemd、TCP 监听、软件更新、Docker、UFW、Fail2ban 与时间同步状态 |
| **系统管理** | 故障快速排查、资源压力、进程、内核与重启状态、软件包健康、APT 安全更新、依赖修复、存储分析、Swap、时间设置，以及运行环境和项目完整性检查 |
| **网络与端口** | 接口地址与单接口下钻、路由与策略规则、DNS 诊断、IPv4/IPv6 连通性、TCP 端点探测、mtr/traceroute 链路、套接字压力、网卡错误、连接会话、监听端口、BBR 与地址优先级 |
| **安全中心** | 扩展安全基线、公网暴露分析、SSH 登录活动与失败来源聚合、Fail2ban/UFW 来源处置、UFW 生命周期与批量规则、SSH 配置/会话/密钥、安全向导、Fail2ban Jail 管理及 TLS 证书检查 |
| **服务与日志** | failed/active 服务浏览、资源与退出结果、正反依赖、启动关键链、失败诊断、经验证的 service 生命周期，以及 Journal 条件查询、完整性验证、按时间/容量维护、内核警告和操作审计 |
| **软件管理** | 168 个单项软件；按分类、来源、安装状态、ID、名称和用途浏览；发行版仓库与项目官方渠道分层管理；版本检查、来源切换、SHA-256 完整性、修复、安装、更新与移除 |
| **应用与容器** | Docker、Web、数据库、缓存和 3x-ui 的版本、运行健康、PID、重启次数、关联监听、配置/数据资产、日志与 systemd 生命周期；支持官方配置检查、检查通过后的安全 reload，以及跳转到单项软件更新；Docker 另提供容器、Compose、网络、安全清理和可校验卷备份 |
| **备份与恢复** | 自动配置快照、手动 `/etc` 文件快照、备注与保护、完整性校验、当前配置差异、总占用统计、单项删除、保留最近 N 份、按创建天数清理与单文件恢复 |

系统组件精确映射一个 Debian/Ubuntu 软件包；Docker 与 Caddy 使用项目官方 APT 仓库，Oh My Zsh 与提示符使用经过验证的官方渠道。适合独立分发的 CLI 使用项目 GitHub Release，安装器只接受 `latest` 稳定版、精确架构资产和 GitHub API 提供的 SHA-256 digest。

## 命令参考

### 查询与导航

```bash
serverctl status                 # 系统仪表盘
serverctl doctor                 # 运行环境、项目文件和权限完整性检查
serverctl triage                # 只读故障快速排查
serverctl updates                # 系统软件包更新清单
serverctl storage                # 只读存储概览
serverctl swap                   # Swap 状态与生命周期管理
serverctl process 1234           # 查看并管理指定 PID
serverctl sources                # 按维护来源浏览软件
serverctl official-updates       # 检查已托管官方 Release 更新
serverctl exposure               # 分析公网监听、进程、容器与 UFW
serverctl ports                  # 监听端口
serverctl dns example.com        # DNS 解析器与记录诊断
serverctl probe example.com 443  # DNS、路由与 TCP 握手探测
serverctl trace example.com      # mtr/traceroute 链路路径
serverctl interface ens3         # 单个网络接口详情
serverctl system                 # 系统管理中心
serverctl network                # 网络与端口中心
serverctl security               # 安全中心
serverctl auth-activity          # 最近 24 小时 SSH 登录活动
serverctl services               # 服务与日志中心
serverctl service nginx.service  # 直接管理一个 systemd 服务
serverctl service nginx.service restart
serverctl journal                # Journal 验证与空间维护
serverctl logs nginx.service     # 直接查看服务最近日志
serverctl apps                   # 应用与容器中心
serverctl app nginx              # Nginx 应用详情、健康、资产与安全 reload
serverctl compose my-project     # 管理现有 Compose 项目
serverctl backups                # 备份与恢复中心
serverctl backup-delete SNAPSHOT # 删除一个明确选择的项目快照
serverctl backup-cleanup         # 交互式清理历史配置快照
serverctl about                  # 版本和安装路径
serverctl version                # 版本号
serverctl self-update            # 检查并原子更新项目自身
```

### 软件管理

```bash
serverctl list                   # 完整软件目录
serverctl list python            # 按关键词查询
serverctl install jq             # 安装一个软件
serverctl update jq              # 更新一个已安装软件
serverctl remove jq              # 移除一个软件
serverctl install oh-my-zsh      # 为 root 安装 Oh My Zsh
serverctl install starship       # 安装并启用 Starship 提示符
serverctl install oh-my-posh     # 安装并切换到 Oh My Posh
serverctl install ripgrep        # 选择官方稳定版或发行版软件包
serverctl update ripgrep         # 检查并更新当前安装来源
```

`install`、`update` 与 `remove` 只接受一个软件 ID。APT 软件在执行点刷新索引，并安装当前系统软件源与 APT 优先级策略选出的最新候选版本；安装后会重新读取 dpkg 版本进行验证。这里的“最新”不表示绕过发行版软件源强制安装上游测试版。软件中心不会批量更新整个系统；所有实际修改仍需人工确认。

### 应用服务管理

应用中心识别 Docker、Nginx、Caddy、Apache、Redis、Memcached、PostgreSQL、MariaDB 与 3x-ui。每个已安装应用都有独立详情页，汇总软件版本、systemd 状态、主进程、重启次数、进程关联监听，以及固定配置和数据路径。

Nginx、Caddy、Apache 与 Docker 可调用各自的官方只读配置检查；Nginx、Caddy 与 Apache 只有在配置检查通过且 systemd 声明 reload 能力后，才允许重新加载。应用详情还可进入对应的软件条目检查候选版本和来源。3x-ui 没有声明可验证的安装来源，因此项目不会猜测下载地址或自动升级。

健康检查、日志查询和数据占用统计均由用户手动触发一次。整个 Server Toolkit 都不会创建监控进程、Cron、systemd Timer，不会周期扫描目录，也不会隐式开放防火墙端口。配置资产页只列出路径和文件名，不输出配置内容；数据占用只在用户明确进入该页面时对声明路径运行一次 `du`。

### 软件来源策略

| 来源 | 适用范围 | 更新与完整性 |
| --- | --- | --- |
| Debian / Ubuntu 仓库 | 系统组件、库、内核相关工具与大多数服务 | 刷新 APT 索引，安装候选版本并回读 dpkg 状态 |
| 项目官方 APT 仓库 | Docker、Caddy 等长期运行服务 | 使用仓库签名、稳定通道与 systemd 状态验证 |
| 项目官方 GitHub Release | 更新频繁且提供独立二进制的 CLI | 查询 latest stable，匹配 amd64/arm64 资产并验证 SHA-256 digest |
| 项目官方 Git 仓库 | Oh My Zsh、Spaceship 等框架或主题 | 验证远端地址，只允许 fast-forward 或官方升级流程 |
| 项目官方安装渠道 | Starship、Oh My Posh 等专用安装器 | 固定官方 URL、独立状态标记和安装后版本验证 |

官方 Release 当前覆盖 ripgrep、fd、bat、fzf、eza、zoxide、Fastfetch、bottom、dust、duf、hyperfine 与 just。对于同时存在发行版包的条目，安装时可以选择来源，详情页可随时切换；切换到官方版时保留底层系统包，并在 `/usr/local/bin` 部署优先命令。移除软件会清理工具明确管理的官方命令及对应系统包。

每个官方二进制都会记录版本、仓库、资产名称、资产 digest、命令路径和二进制 SHA-256。更新或删除前会重新验证本机文件；检测到人为修改时自动操作会停止，可在详情页选择“修复官方安装”，先备份现有命令再部署可信版本。

Oh My Zsh 安装到 `SUDO_USER` 对应的 `~/.oh-my-zsh`（直接以 root 登录时为 `/root/.oh-my-zsh`），使用官方 Git 仓库并在修改前备份已有 `.zshrc`。是否切换默认 Shell 会单独询问；卸载仅删除经校验的官方仓库和工具托管的配置块，保留 Zsh、Git、其他用户配置与默认 Shell。

提示符中心提供 Starship、Oh My Posh 与 Spaceship Prompt。同一时间只激活一个由工具托管的提示符；安装另一个提示符会安全替换 `.zshrc` 中的活动配置块，但保留其他已安装引擎。对已经安装但未启用的提示符再次执行 `install ID` 即可切换。检测到用户自行维护的提示符初始化代码时会拒绝覆盖。图标显示依赖 SSH 客户端终端启用 Nerd Font。

相关上游：[Starship](https://github.com/starship/starship)、[Oh My Posh](https://github.com/JanDeDobbeleer/oh-my-posh)、[Spaceship Prompt](https://github.com/spaceship-prompt/spaceship-prompt)。Powerlevel10k 因上游已明确进入有限支持状态，暂不纳入正式托管目录。

### 操作预览

```bash
serverctl --dry-run
serverctl --dry-run install docker
```

`--dry-run` 展示将执行的系统命令，不写入配置、不安装软件，也不创建审计记录。

## 安全模型

| 边界 | 行为 |
| --- | --- |
| 定位 | 面向单一 root 管理员的 VPS，不提供多账户与提权工作流 |
| 运行方式 | 仅在前台按需执行；命令结束后无项目常驻进程、Cron、Timer 或后台监控 |
| 权限 | 查询不会修改系统；所有写操作仍在执行点验证 root 权限 |
| 确认 | 修改前显示目标和影响范围，默认答案为拒绝 |
| 配置备份 | 修改已有文件前写入 `/var/backups/server-toolkit/<snapshot>/` 并生成 manifest |
| 备份清理 | 只删除格式和目录均可验证的项目快照；支持保留最近数量或按创建天数清理，当前操作和人工保护的快照始终跳过 |
| Docker 卷 | 独立目录保存；备份只读挂载源卷并校验 SHA-256，恢复前拒绝运行中占用并自动创建安全备份 |
| SSH | 使用优先加载的独立 drop-in，执行 `sshd -t` 并核对最终生效值；root 公钥不存在时拒绝关闭其密码入口，验证或服务重启失败时恢复旧配置 |
| 进程 | PID、nice 和信号严格校验；PID 1、工具自身与父进程不可控制；SIGKILL 单独标记为危险操作 |
| 防火墙 | 启用 UFW 前保留当前 SSH 端口；其他端口必须显式添加 |
| 来源处置 | 只接受登录失败清单中的明确 IP；拒绝阻止当前 SSH 来源，UFW 持续拒绝与 Fail2ban 临时封禁分开展示 |
| 审计 | root 修改记录到 `/var/log/server-toolkit/actions.log` |
| 官方 Release | 只接受项目 GitHub Release、支持的 CPU 架构和有效 SHA-256 digest；不覆盖未托管的 `/usr/local/bin` 文件 |
| 安装升级 | 解压前检查源码归档路径、类型与体积，在同一父目录暂存并原子替换；失败时恢复上一安装目录 |
| 卸载 | 只删除能够确认属于项目的路径，不猜测性删除业务软件或系统设置 |

> [!WARNING]
> 修改 SSH、防火墙、路由或存储前，应保留 VPS 服务商控制台并创建实例快照。Docker 发布的容器端口可能绕过 UFW，需要结合云防火墙与 `DOCKER-USER` 链评估实际暴露面。

## 数据与路径

| 内容 | 默认位置 |
| --- | --- |
| 程序目录 | `/opt/server-toolkit` |
| 命令入口 | `/usr/local/bin/serverctl` |
| 配置快照 | `/var/backups/server-toolkit` |
| Docker 卷备份 | `/var/backups/server-toolkit-docker` |
| 操作审计 | `/var/log/server-toolkit/actions.log` |
| 项目状态 | `/var/lib/server-toolkit` |
| 官方 Release 状态 | `/var/lib/server-toolkit/software-releases` |

安装器会将实际安装路径写入 `config/installation.conf`，以确保自定义路径也能被正确升级和卸载。

## 项目结构

```text
server-toolkit/
├── .gitattributes               # 跨平台文本与 LF 换行规则
├── .github/                     # CI、发布流程、社区规范与徽章资源
├── .gitignore                   # Git 忽略规则
├── bin/
│   └── serverctl                # CLI、参数解析与顶层导航
├── config/
│   ├── software.tsv             # 声明式单项软件目录
│   └── official-releases.tsv    # 官方 Release、架构资产与项目主页
├── docs/                        # 设计、变更记录与发布文档
├── scripts/
│   ├── install.sh               # 安装、原子升级与卸载
│   └── check.sh                 # 本地和 CI 检查入口
├── src/
│   ├── core/                    # 运行时、输入校验、UI、平台与备份
│   └── features/
│       ├── apps/
│       │   ├── services.sh      # 应用服务领域入口
│       │   ├── services/        # 元数据、资产检查、安全操作与菜单
│       │   ├── docker.sh        # Docker 领域入口
│       │   └── docker/          # 资产、Compose、容器、卷备份与菜单
│       ├── maintenance/         # 项目安装与文件完整性检查
│       ├── network.sh           # 网络领域入口
│       ├── network/             # 概览、调优、接口、端点、链路、套接字与菜单
│       ├── security.sh          # 安全中心入口
│       ├── security/            # 基线、登录活动、暴露分析、Fail2ban、证书、防火墙与 SSH
│       ├── services.sh          # 服务中心入口
│       ├── services/            # 服务概览、Journal、Unit 与审计
│       ├── software/
│       │   ├── catalog.sh       # 软件目录模块入口
│       │   ├── catalog/         # 查询、展示、写操作与交互页面
│       │   ├── oh-my-zsh.sh     # Oh My Zsh 安装、更新与安全移除
│       │   ├── prompts.sh       # 现代提示符安装、切换与生命周期
│       │   └── releases.sh      # GitHub Release 校验、安装、修复与来源管理
│       ├── system/
│       │   ├── diagnostics.sh   # 单次资源压力与重启状态
│       │   ├── menu.sh          # root-only 系统管理导航
│       │   ├── packages.sh      # dpkg、APT 更新、hold、来源、修复与清理
│       │   ├── storage.sh       # 分类占用、文件、挂载、fstab 与维护导航
│       │   ├── triage.sh        # 资源、服务、日志、网络、容器与恢复快速排查
│       │   ├── processes.sh     # 进程下钻、资源与安全控制
│       │   └── settings.sh      # 主机名、时区、Swap 与维护设置
│       └── *.sh                 # 系统、网络、安全、服务等功能中心
├── tests/                       # 离线单元测试与安全边界测试
├── install.sh                   # 稳定的一键安装引导入口
├── LICENSE                      # MIT 许可证
├── README.md                    # 项目主页
└── VERSION                      # 唯一版本来源
```

完整设计约束与扩展规范见 [`docs/DESIGN.md`](docs/DESIGN.md)，变更记录见 [`docs/CHANGELOG.md`](docs/CHANGELOG.md)，漏洞报告流程见 [`.github/SECURITY.md`](.github/SECURITY.md)，版本发布流程见 [`docs/RELEASE.md`](docs/RELEASE.md)。

## 支持范围

| 系统 | 版本 |
| --- | --- |
| Debian | 11 / 12 / 13 |
| Ubuntu | 22.04 LTS / 24.04 LTS |
| 架构 | amd64 / arm64 |
| Init | systemd |

当前不提供 RHEL 系、Alpine、非 systemd 系统或衍生发行版的兼容承诺。

## 更新

在控制台中选择“系统管理 → 更新本项目”，或直接运行：

```bash
serverctl self-update
```

也可以重新运行安装命令完成原子升级：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/refs/heads/main/install.sh)
```

软件中心中的“更新”只更新当前选中的软件，不会升级整个系统。

## 卸载

```bash
serverctl uninstall
```

卸载模式：

1. **仅卸载程序**：删除程序目录和项目命令入口，保留日志与配置快照。
2. **彻底清除项目数据**：额外删除项目日志、配置快照、Docker 卷备份和状态目录。

通过 Server Toolkit 安装的软件，以及主机名、SSH、UFW、Swap 等系统状态不会被自动删除或猜测性回滚。需要恢复配置时，应先从备份中心选择明确快照。

## 开发

```bash
git clone https://github.com/Elainaicey/server-toolkit.git
cd server-toolkit
bash scripts/check.sh
```

开发检查需要 Bash 与 Python 3.8+；推荐安装 ShellCheck 和 yamllint，以获得与 CI 一致的完整结果。

检查流程分为 `repository-files`、`shell` 和 `tests` 三个独立任务。所有 Git 跟踪文件必须归入明确类别，并接受 UTF-8、LF、尾随空白和 Git 属性检查；Markdown、工作流 YAML、SVG、软件目录、许可证与版本元数据还会执行对应的专项验证。未归类的新文件会直接使 CI 失败。贡献要求见 [`.github/CONTRIBUTING.md`](.github/CONTRIBUTING.md)。

## 许可证

Server Toolkit 依据 [MIT License](LICENSE) 开放源代码。你可以自由使用、修改与分发本项目，但必须保留原始版权声明和许可证文本。

---

<div align="center">
  <sub>Server Toolkit 0.3.0 · Built for deliberate VPS operations</sub>
</div>
