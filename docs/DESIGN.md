# 设计与扩展边界

## 分层结构

```text
install.sh
└── scripts/install.sh

bin/serverctl
├── src/core/runtime.sh
├── src/core/ui.sh
├── src/core/platform.sh
├── src/core/backup.sh
├── src/core/catalog.sh
├── src/features/*.sh
├── src/features/apps/docker.sh
└── config/software.tsv
```

- `bin/` 只放用户直接执行的程序，负责参数解析、加载模块和顶层导航。
- `src/core/` 提供通用能力，不出现某个功能中心专属的交互流程。
- `src/features/` 按领域组织完整操作；只有“应用与容器”这类明确领域允许使用子目录。
- `config/` 存放声明式数据，不包含可执行代码。
- `scripts/` 存放安装、检查等项目维护脚本，不在运行时自动加载。
- 根目录只保留项目元数据和稳定入口，不放业务实现。

依赖方向必须保持为 `bin → core → features/config`。功能模块可以调用 core；core 不应反向加载 feature。

## 交互模型

顶层按依赖关系展示八个功能中心：系统概览、系统、网络、安全、服务、软件、应用、备份。进入中心后直接列出动作；Docker 等独立应用可以放在“应用与容器”下一层，但不允许增加“高级”“更多工具”“常用配置”等模糊层级。一个修改动作采用统一流程：

1. 读取并展示当前状态。
2. 收集一个明确目标。
3. 校验输入和系统前置条件。
4. 展示变更摘要并请求确认。
5. 备份将被修改的配置。
6. 执行或以 `--dry-run` 输出命令。
7. 验证结果并写入操作记录。

纯查询动作不要求 root；真正修改系统前才调用 `require_root`。

## 软件目录规则

格式：

```text
id|category|name|description|apt packages|handler
```

规则：

1. ID 全局唯一，只使用小写字母、数字和短横线。
2. 普通条目的 `apt packages` 必须精确为一个包名，`handler` 必须为空。
3. 只有无法通过一个系统包正确安装的独立产品才允许专用 handler。
4. handler 只安装该产品不可分割的官方组件，不联动防火墙、SSH 或其他软件。
5. CLI 和交互界面共用 `catalog_install` / `catalog_remove`，避免行为分叉。
6. `serverctl install` 和 `remove` 必须且只能接收一个 ID。

## 配置与恢复

所有由项目持久化的配置应带有 `Managed by Server Toolkit` 注释，优先写入独立 drop-in。修改现有文件前调用 `backup_file`。恢复只能选择快照清单中记录的绝对路径，不能接受任意拼接路径。

新增修改动作时，至少考虑：输入校验、确认、dry-run、root 边界、备份、应用后验证、失败恢复、审计记录。

## 新增功能

新增一个功能中心：

1. 在 `src/features/<name>.sh` 实现查询和修改动作；独立应用放在 `src/features/apps/`。
2. 菜单保持一层，不跳转到另一套导航系统。
3. 在 `bin/serverctl` 加载文件并加入顶层入口。
4. 为输入校验、分发或安全边界补充离线测试。
5. 更新 README 功能表和 CHANGELOG。

如果只是现有领域中的一个动作，应加入对应 feature，而不是新建模糊的 `tools.sh`、`common.sh` 或 `misc.sh`。

## 明确不做

- profiles、无人值守安装、`--yes`、软件套餐、全选或多选。
- 为旧目录和旧命令保留兼容包装层。
- 自动升级整个系统或自动删除用户数据。
- 卸载时猜测性删除软件或回滚无法确认所有权的系统设置。
- 安装 Web、容器或数据库时自动修改防火墙。
- 没有明确恢复路径的内核与网络“优化大全”。
- 未经 CI 和真实系统验证的跨发行版兼容声明。
