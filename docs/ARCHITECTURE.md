# 项目结构与扩展约定

Server Toolkit 分为入口、公共能力、业务模块、软件目录和自动化配置五层。

```text
serverctl.sh             命令解析、模块加载、主菜单与 profile 编排
lib/                     无业务菜单的公共能力
  core.sh                参数、日志、执行与错误处理
  detect.sh              系统和网络检测
  package.sh             发行版包管理器适配
  catalog.sh             软件目录查询、映射和精确安装
modules/                 按运维领域划分的交互功能
catalog/packages.tsv     可独立安装的软件项及发行版包名映射
profiles/                明确声明的软件与模块组合
scripts/check.sh         本地与 CI 统一检查入口
tests/                   不修改系统的离线测试
```

## 依赖原则

1. 单项安装不得隐式展开成工具集合。比如 `python-venv` 只映射虚拟环境包，不顺带安装 pipx 或开发头文件。
2. 模块只安装完成自身功能必需的依赖。可选的排障、编辑和监控工具不得作为模块前置条件。
3. 集合必须由用户明确选择，名称和包含内容应在界面中可见。
4. 内置 profile 必须声明 `PROFILE_INSTALL_BASE=0`，其 `PROFILE_PACKAGES` 和 `PROFILE_MODULES` 是全部预期动作。
5. 修改系统配置前先调用 `backup_file`；已有配置无法安全合并时应停止并保留原文件。

## 添加一个软件项

在 `catalog/packages.tsv` 增加一行：

```text
id|category|中文说明|Debian/Ubuntu 包名|RHEL/Fedora 包名
```

一个概念需要多个不可分割的软件包时，可在对应字段用空格分隔。某个系统不支持时保留为空。提交前运行：

```bash
bash scripts/check.sh
```

只有涉及仓库配置、服务启停、配置文件修改或防火墙联动的功能，才应新增或扩展 `modules/` 中的函数。

## Profile 兼容性

旧的外部 profile 如果没有 `PROFILE_INSTALL_BASE`，仍默认安装历史基础集合，避免升级后行为突然缺失。内置 profile 使用精确模式，不再有这层隐式依赖。
