# Server Toolkit

Server Toolkit 是一个面向 Debian / Ubuntu VPS 的小型中文运维工具。它的目标不是包办所有初始化，而是把少量高频操作做得清楚、安全、可预览。

`0.1.0` 是一次从零开始的实现，不兼容旧版结构和命令。

## 设计原则

- 扁平：主界面直接显示所有系统动作，不在多个子菜单之间跳转。
- 单项：软件安装一次只接受一个软件 ID，不提供套餐、批量选择或“全部安装”。
- 人工确认：没有 profiles、`--yes` 或无人值守配置；所有修改动作执行前都要确认。
- 少依赖：普通软件项只映射一个系统包；Docker、Caddy 仅安装产品自身不可分割的官方依赖。
- 不隐藏副作用：安装软件不会顺便修改防火墙、SSH、内核参数或其他服务。
- 可恢复：系统配置修改前保存原文件；安装目录升级时整体替换，不残留旧代码。

## 支持范围

- Debian 11、12、13
- Ubuntu 22.04、24.04
- amd64、arm64
- 使用 systemd 的常见 KVM / LXC VPS

当前版本不支持 RHEL、CentOS、AlmaLinux、Rocky Linux 或 Alpine。与其保留未经充分验证的分支，不如先把 Debian / Ubuntu 做稳定。

## 安装

推荐先下载再执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/main/install.sh -o /tmp/server-toolkit-install.sh
bash -n /tmp/server-toolkit-install.sh
sudo bash /tmp/server-toolkit-install.sh
```

安装器会显示目标路径并要求确认。默认只安装运行时文件：

| 内容 | 路径 |
| --- | --- |
| 程序 | `/opt/server-toolkit` |
| 命令 | `/usr/local/bin/serverctl` |
| 配置备份 | `/var/backups/server-toolkit` |

安装或升级会完整替换程序目录，因此旧版的 `modules/`、`profiles/`、测试文件和其他残留不会进入运行环境。

## 使用

打开扁平主界面：

```bash
sudo serverctl
```

主界面直接提供：

1. 系统概览
2. 环境检查
3. 安装一个软件
4. 修改主机名
5. 修改时区
6. 创建 Swap
7. 查看网络信息
8. 启用 BBR
9. 设置 IP 地址优先级
10. 启用基础防火墙
11. 配置 SSH 安全

不存在二级系统菜单、工具中心、维护中心或 profile 入口。

### 单项软件安装

查看所有软件：

```bash
serverctl list
```

按关键词筛选：

```bash
serverctl list python
serverctl list 网络
```

一次安装一个软件：

```bash
sudo serverctl install jq
sudo serverctl install python-venv
sudo serverctl install docker
```

即使从命令行安装，也必须人工确认。以下写法会被拒绝：

```bash
sudo serverctl install curl jq
```

在交互软件界面中，输入 `python` 会自动筛选，输入准确的软件 ID（例如 `python-venv`）则直接进入安装确认。不需要记搜索前缀，也不需要先选择“运行时”“开发工具”等分类。

### 预览操作

```bash
sudo serverctl --dry-run
sudo serverctl install docker --dry-run
```

`--dry-run` 仍然保留人工确认，但只显示将运行的系统命令。

### 环境检查

```bash
serverctl doctor
```

检查内容包括系统类型、APT/dpkg、磁盘空间、DNS、GitHub 连通性以及低内存 VPS 的 Swap 状态。

## 安全说明

- SSH 修改会先验证端口、检查公钥、备份配置并运行 `sshd -t`，验证失败时恢复原 drop-in。
- 启用防火墙时会自动保留当前 SSH 端口，避免直接锁死现有连接。
- 安装 Docker、Caddy 不会自动开放端口或修改防火墙。
- BBR 仅在内核支持或能加载模块时写入配置。
- 安装器拒绝覆盖其他程序的命令入口，也拒绝删除 `/opt`、`/var` 等宽泛目录。

修改 SSH、防火墙前仍建议保留 VPS 服务商控制台，并创建实例快照。

## 卸载

```bash
sudo /opt/server-toolkit/install.sh --uninstall
```

卸载会要求确认，只删除程序目录和属于本项目的命令链接。配置备份不会自动删除。

## 开发

```bash
bash scripts/check.sh
```

项目边界和扩展规则见 [设计文档](docs/DESIGN.md)。
