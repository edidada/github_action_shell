# 多账号分支策略

> 4 个 GitHub 账号下有**同名**仓库 `github_action_shell`，但各自的**用途**可能不同。
> 本文定义如何用分支让它们既共享同一套引擎，又能各自演化而互不覆盖。

配套文档：[设计方案](DESIGN.md) · [仓库台账](REPO-MATRIX.md)

---

## 1. 现状与问题

四个仓库经实测**互相不是 fork 关系**（`fork=false`），纯粹靠本机 `git push` 同步：

| 仓库 | fork | visibility | default branch |
|---|---|---|---|
| `edidada/github_action_shell` | false | public | `main` |
| `edidadaoutlook/github_action_shell` | false | public | `main` |
| `wiseism/github_action_shell` | false | public | `main` |
| `wdidada126/github_action_shell` | false | public | `main` |

单条 `main` + 强制推送，在下面三种情形下会失效：

| 失效场景 | 后果 |
|---|---|
| 某账号的副本要跑**不同的流程**（换构建方式、换报告模板） | 下一次全量同步把改动覆盖掉 |
| 某账号的副本对应**另一个私有源**（同名而已，业务无关） | `config/sources.env` 共享基线被反复改回 |
| 主仓 CI 自动提交 `results/` 归档 | 主仓历史领先镜像仓，必须 `--force`，镜像仓本地改动被丢弃 |

最后一条已经真实发生过 —— 你现在看到的 `chore(results): edidada/cpp_ecshop@main run #7` 就是 CI 自己提交的。

---

## 2. 分支模型

```
main                       公共引擎基线：driver 代码 / scripts / workflow 骨架 / docs
│                          唯一的「上游」，所有账号从它继承
│
├── acct/edidada           主账号长期分支  = edidada        仓库的 default branch
├── acct/edidadaoutlook    镜像账号长期分支 = edidadaoutlook 仓库的 default branch
├── acct/wiseism           镜像账号长期分支 = wiseism        仓库的 default branch
└── acct/wdidada126        镜像账号长期分支 = wdidada126     仓库的 default branch
     │
     └── purpose/<用途名>  短期用途分支（可选），合并回 acct/* 后删除
```

**核心机制**：GitHub Actions 只运行 **default branch** 上的 workflow 文件。
因此把 `acct/wiseism` 设为 `wiseism/github_action_shell` 的默认分支后，
该仓库跑的就是 `acct/wiseism` 上的 workflow —— 用途隔离自动生效，无需改任何代码。

### 分支命名

| 前缀 | 生命周期 | 谁改 | 示例 |
|---|---|---|---|
| `main` | 永久 | 所有人提 PR | `main` |
| `acct/<owner>` | 永久 | 该账号本人 | `acct/wiseism` |
| `purpose/<名词>` | 用完即删 | 该账号本人 | `purpose/buildkit-migration` |
| `hotfix/<名词>` | 合并后删 | 先合进 `main` 再向下同步 | `hotfix/token-expiry` |

> `acct/` 分支的名字必须与 `config/accounts.env` 里的账号名完全一致，脚本靠它推导仓库。

---

## 3. 「同名不同用途」分三种情形

先判断你属于哪一种，再决定要不要切分支 —— **A 不需要，B/C 需要**：

### 情形 A：同源同用途（当前默认）

四个账号下都有同名私有源，且是同一个项目的不同副本。

→ **不需要分支**。当前方案已解决：owner 由 `github.repository_owner` 自动推导，
各账号用自己的 PAT 读自己的私有仓，`config/sources.env` 一份即可。

### 情形 B：同名，但业务无关

`wiseism/cpp_ecshop` 和 `edidada/cpp_ecshop` 只是碰巧同名，实际是两个项目。

→ **需要 `acct/` 分支**。差异体现在该账号自己的 workflow / scripts / 报告模板上。
配置差异走 **§5 的 owner overlay**，避免和 `main` 冲突。

### 情形 C：一个账号要驱动多个私有源

`edidada` 除了 `cpp_ecshop`，还有第二个私有项目也要用这套 driver。

→ 两条路，任选：

| 做法 | 适用 | 代价 |
|---|---|---|
| 一条 `purpose/<源名>` 分支一个源，各自设为该账号另一仓库的 default branch | 源之间流程差异大 | 分支多，需多次同步 |
| `config/sources.edidada.env` 里配多行 + workflow 里显式列举 | 流程一致，只是源不同 | 一次流程要 checkout 多份代码 |

> ⚠️ 若走第二条，不要再碰 `strategy.matrix` —— 本仓库已踩过坑：
> matrix 元素里出现空字符串时，GitHub 会**静默跳过整个 job**，run 直接判失败且日志无任何报错。

---

## 4. 什么改动该走 `main`，什么走 `acct/*`

| 内容 | 分支 | 理由 |
|---|---|---|
| `scripts/lib.sh`（公共函数） | **必须 `main`** | 所有账号依赖，改错全体挂 |
| `scripts/push-all-remotes.sh` | **必须 `main`** | 同步链路本身 |
| `docs/`、`README.md` | **必须 `main`** | 单一事实来源 |
| `scripts/run-source.sh` 的通用执行逻辑 | **必须 `main`** | 共享能力 |
| `.github/workflows/` 的步骤编排 | `acct/*` 可覆盖 | 用途差异的主要落点 |
| `config/sources.<owner>.env` | **只该账号改** | overlay，见 §5 |
| `results/` 归档内容 | **永远不要手改** | CI 自动写 |

一句话：**能力与工具进 `main`，业务流程与编排进 `acct/*`。**

---

## 5. Owner 级配置 Overlay

为了避免 `acct/*` 分支改动 `config/` 时和 `main` 冲突，配置采用**两级 lookup**：

```
config/sources.<owner>.env     ← 账号私有 overlay，优先级最高（仅该账号分支维护）
config/sources.env             ← 共享基线（仅 main 维护）
```

`lib.sh` 的 `resolve_source` 先查 overlay，查不到才回退基线。
两个文件互不重叠 → 从 `main` 合并到 `acct/*` 时**永不会产生配置冲突**。

```bash
# acct/wiseism 分支上：只写自己这行，不用碰共享的 sources.env
echo 'wiseism=cpp_ecshop@develop' > config/sources.wiseism.env
```

> overlay 文件必须命名为 `sources.<owner>.env`，owner 取 `github.repository_owner`。

---

## 6. 落地步骤

```bash
# 1) 在各 acct 分支上初始化（从当前 main 拉出，内容完全一致）
bash scripts/sync-branches.sh --init

# 2) 把每个仓库的 default branch 切到对应 acct 分支
bash scripts/sync-branches.sh --set-default

# 3) 验证
for u in edidada edidadaoutlook wiseism wdidada126; do
  gh api "repos/$u/github_action_shell" --jq '.name + " -> " + .default_branch'
done
# 期望：xxx -> acct/xxx

# 4) 此后日常：改动先合到 main，再向下同步
git switch main && git commit ...
bash scripts/sync-branches.sh          # main -> 4 条 acct/* (merge + push)
```

**同步为什么用 merge 不用 rebase**：`acct/*` 分支已经是各仓库的公开 default branch，
rebase 会重写已推送的历史，导致其他人的本地副本错乱。merge 是唯一安全选项。

---

## 7. 已知痛点：`results/` 导致的历史分叉

主仓跑 CI 会自行 commit `results/` 归档，使 `main` 持续领先镜像仓，
因此同步镜像仓必须 `--force`。

**推荐改进**（Phase 2，暂未实施）：让 CI 把归档提交到独立的 `results` 分支，
`main` 保持只有代码提交。这样：

- 同步不再需要强推
- `main` 的 git log 干净，归档不会淹没代码提交
- `results` 分支可配置独立的保留策略

代价是 workflow 里 checkout/commit 的目标分支要多加一处参数。

---

## 8. 红线（本仓库是 PUBLIC）

| 禁止 | 原因 |
|---|---|
| 任何分支出现 PAT / token 明文 | 全网可见，秒被盗刷 |
| 把私有仓的路径、依赖清单写进 `acct/*` 分支的日志输出 | Actions 日志公开 |
| 在 `acct/*` 上直接修改 `scripts/lib.sh` | 会与 `main` 冲突，且能力不一致难排查 |
| 给 `acct/*` 配 Branch Protection 的 required status check 依赖私有资源 | 镜像仓库拿不到对应 secret |

---

## 9. 速查

```bash
bash scripts/sync-branches.sh --dry-run     # 看将要做什么
bash scripts/sync-branches.sh --init        # 首次创建 4 条 acct 分支并推送
bash scripts/sync-branches.sh --set-default # 切换各仓库 default branch
bash scripts/sync-branches.sh               # 日常：main -> acct/*

git switch acct/wiseism                     # 切到某账号分支做定制
echo 'wiseism=cpp_ecshop@main' > config/sources.wiseism.env
git add -A && git commit -m "wiseism: 独立指向自己的私有源"
git push wiseism acct/wiseism
```
