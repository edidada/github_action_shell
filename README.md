# github_action_shell

> **Public CI Driver** —— 用公开仓库的免费 Actions Runner，拉取并执行**私有仓库**的脚本与构建，再把结果归档回来。

私有仓库 `edidada/cpp_ecshop`（C++ / CMake / vcpkg）的 GitHub Actions 分钟已耗尽（原 CI 是 macOS + Ubuntu + Windows × crow/httplib 六矩阵，macOS 按 10 倍计费）。本仓库把「算力」搬到 public 仓库（免费无限），把「代码」留在私有仓库。

📄 **[完整设计方案见 docs/DESIGN.md](docs/DESIGN.md)**
📄 **[分支策略见 docs/BRANCHING.md](docs/BRANCHING.md)** · **[仓库台账见 docs/REPO-MATRIX.md](docs/REPO-MATRIX.md)**

```
PRIVATE cpp_ecshop  ──(只读 PAT)──▶  PUBLIC github_action_shell
只用代码，不再跑 CI                  免费 Runner + 流程 + results/ 归档
```

## 快速开始

```bash
# 1) 各账号下创建同名 public 仓库
bash scripts/bootstrap-accounts.sh --yes

# 2) 每个仓库各自配置 secret
gh auth switch --user edidada
gh secret set SOURCE_REPO_TOKEN --repo edidada/github_action_shell --body '<PAT>'

# 3) 推送到全部账号（edidada / edidadaoutlook / wiseism / wdidada126）
bash scripts/push-all-remotes.sh

# 4) 触发一次
bash scripts/trigger.sh driver cpp_ecshop main
```

## 触发方式

| 方式 | 命令 / 操作 |
|---|---|
| 手动 | `bash scripts/trigger.sh driver cpp_ecshop main` 或页面 Run workflow |
| 定时 | `cron: '23 2 * * *'`（北京时间 10:23），**仅主账号 edidada 生效** |
| 远程派发 | `bash scripts/trigger.sh dispatch cpp_ecshop main` |

## 多账号设计

同一个 workflow 同步到 4 个账号，**无需改任何配置**。源仓库 owner 由 `github.repository_owner` 自动推导：

- `edidada` 的 driver → 拉 `edidada/cpp_ecshop`
- `wiseism` 的 driver → 拉 `wiseism/cpp_ecshop`

同名但不同用途的仓库因此天然隔离。要改映射关系，编辑 `config/sources.env`。

### 分支策略

4 个账号下的同名仓库**互不 fork**，当前共用一条 `main` 强推同步 —— 一旦某份副本要做不同的事，
下一次同步就会被覆盖。因此采用两层分支：

```
main                     公共引擎基线（driver / scripts / docs）
 ├── acct/edidada        各账号长期分支，设为该仓库的 default branch
 ├── acct/edidadaoutlook
 ├── acct/wiseism
 └── acct/wdidada126
```

GitHub Actions 只跑 default branch 上的 workflow，所以切换 default branch 后用途隔离自动生效。

```bash
bash scripts/sync-branches.sh --init         # 创建 4 条 acct 分支
bash scripts/sync-branches.sh --set-default  # 各仓库切到自己的 default branch
bash scripts/sync-branches.sh                # 日常：main -> acct/*（merge）
```

📄 **[完整策略见 docs/BRANCHING.md](docs/BRANCHING.md)** · **[仓库台账见 docs/REPO-MATRIX.md](docs/REPO-MATRIX.md)**

## Secrets / Variables

| 名称 | 范围 | 说明 |
|---|---|---|
| `SOURCE_REPO_TOKEN` | 4 个仓库都要 | 读取本账号私有源；fine-grained PAT，单仓库 Contents=Read |
| `MIRROR_TOKEN` | 仅主账号 | 推送到其余 3 个账号的仓库 |
| `VARIANTS` | 可选变量 | JSON 数组，多套构建参数，如 crow / httplib |

## 结果在哪

每次运行生成 `results/<账号>/<源仓库>/<变体>/run-<编号>/summary.md`，同时上传 90 天 Artifact。

> ⚠️ 本仓库是 public：Actions 日志、`results/` 归档、workflow 文件**所有人都看得到**，脚本输出请勿包含敏感信息。合规风险请阅读 [docs/DESIGN.md §5](docs/DESIGN.md)。
