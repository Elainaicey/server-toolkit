# 发布流程

Server Toolkit 使用语义化版本号，并以 `v<版本>` 作为 Git 标签。`VERSION` 是运行时和发布流程的唯一版本来源。

## 发布前检查

1. 确认 `VERSION` 与 `CHANGELOG.md` 的发布章节一致。
2. 确认目标提交已合并到 `main`，工作区没有未提交修改。
3. 确认发行归档包含 MIT `LICENSE` 和版权声明。
4. 执行发布检查：

```bash
bash scripts/release-check.sh v0.1.0
```

## 创建 0.1.0 发布

```bash
git switch main
git pull --ff-only origin main
git tag -a v0.1.0 -m "Server Toolkit 0.1.0"
git push origin v0.1.0
```

标签推送后，GitHub Actions 将再次运行语法检查、ShellCheck、单元测试和冒烟测试，随后创建：

- `server-toolkit-0.1.0.tar.gz`
- `server-toolkit-0.1.0.tar.gz.sha256`
- GitHub Release 与自动生成的变更说明

如果工作流失败，应修复问题并发布新的版本号；不要移动已经公开使用的版本标签。

## 发布后验证

在一台全新的 Debian 或 Ubuntu VPS 上运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Elainaicey/server-toolkit/refs/tags/v0.1.0/install.sh)
serverctl version
serverctl status
```

验证安装目录、命令入口、软件详情、更新检查和卸载流程后，再将 README 中的推荐安装通道切换到稳定标签。
