# 设计边界

## 结构

```text
serverctl.sh             唯一入口、参数解析和扁平主菜单
lib/core.sh              输入、确认、输出、执行与基础校验
lib/ui.sh                简单终端排版
lib/platform.sh          Debian/Ubuntu 检测与 APT 适配
lib/backup.sh            修改配置前的文件备份
lib/catalog.sh           软件目录读取、查询和单项分发
features/software.sh     Docker/Caddy 官方安装器
features/system.sh       系统信息与三个系统动作
features/network.sh      网络查看、BBR 和地址优先级
features/security.sh     UFW 与 SSH 引导配置
catalog/software.tsv     软件 ID 与单个 APT 包映射
```

`lib/` 不包含菜单，`features/` 不定义新的导航层。主界面是所有系统动作的唯一导航入口。

## 软件目录规则

目录格式：

```text
id|category|name|description|apt packages|handler
```

规则：

1. 普通项目的 `apt packages` 必须只有一个包名。
2. 普通项目的 `handler` 必须为空。
3. 只有一个产品无法通过单个系统包正确安装时才允许专用 handler。
4. handler 只安装该产品必需的仓库和组件，不联动其他功能。
5. CLI 和交互界面共用同一个 `catalog_install`，因此行为不能分叉。
6. `serverctl install` 必须且只能接收一个 ID。

## 不做的事情

- 不支持 profiles、无人值守安装或 `--yes`。
- 不提供软件套餐、全选或多选。
- 不为兼容旧命令保留包装函数。
- 不自动升级整个系统。
- 不提供未经验证的跨发行版兼容分支。
- 不在安装 Web、Docker 或数据库时自动修改防火墙。
- 不加入缺少明确恢复路径的激进内核调优。

新增功能前应先确认它是否属于高频 VPS 操作，能否用现有扁平动作表达，以及是否会引入隐藏副作用。
