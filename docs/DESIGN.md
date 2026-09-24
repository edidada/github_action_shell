# github_action_shell 设计方案

**用 Public 仓库的免费 CI Runner，去拉取并执行私有仓库的脚本，然后把结果归档回 Public 仓库。**

- 驱动器仓库（Driver）：`github_action_shell` —— **Public**，本仓库
- 私有源仓库（Source）：`edidada/cpp_ecshop` —— **Private**，CI 时长已耗尽
- 部署范围：一份代码，同步到 **4 个 GitHub 账号**（`edidada` 主 + `edidadaoutlook` / `wiseism` / `wdidada126`）

---

## 1. 痛点到底出在哪

先看看 `cpp_ecshop` 现在跑的东西 —— 这是定位问题的关键：

```yaml
# cpp_ecshop/.github/workflows/ci.yml（现状）
strategy:
  matrix:
    os: [macos-latest, ubuntu-latest, windows-latest]   # ← 3 个 OS
    http_server: [crow, httplib]                        # ← 2 个后端，共 6 个 job
```

GitHub Actions 的分钟**不是**按墙钟时间计费，而是乘上 runner 倍率：

| Runner | 计费倍率 | 说明 |
|---|---|---|
| Linux 2-core | **1×** | 基准 |
| Windows | **2×** | 墙钟 10 分钟扣 20 分钟 |
| macOS | **10×** | 墙钟 10 分钟扣 **100 分钟** |

Free 计划私有仓库额度约 **2000 分钟/月**。按这套矩阵估算一次全量 push：

| OS | job 数 | 单 job 墙钟 | 倍率 | 扣减额度 |
|---|---|---|---|---|
| ubuntu-latest | 2 | ~10 min | 1× | 20 |
| windows-latest | 2 | ~12 min | 2× | 48 |
| macos-latest | 2 | ~12 min | **10×** | **240** |
| **合计** | 6 | | | **≈ 308 分钟** |

> **结论：全库 push 6~7 次，一个月额度就烧干净了，而其中 78% 是被 macOS 吃掉的。**

而 Public 仓库的 Actions **完全免费、无分钟上限**。本方案就是把「计算」搬到 Public 仓库，「代码」留在私有仓库。

<details>
<summary>实测快照（2026-09-24，<code>gh</code> 采集）</summary>

```
edidada/cpp_ecshop   私有 🔒 · C++ · 8019 KB · 默认分支 main
分支: crow / main / work
自带 workflow: ci [active]、ci-http-servers [active]
最近一次运行: ci #6 → failure @ 2026-09-19
最近提交: 2b7790a Merge #9 into main from work
```

采集脚本：`bash scripts/collect-repo-info.sh edidada/cpp_ecshop out/`

</details>仓库。

---

## 2. 架构：Driver / Source 分离

```
┌─────────────────────────────────────┐        ┌──────────────────────────────┐
│  PRIVATE  edidada/cpp_ecshop        │        │  PUBLIC  github_action_shell │
│  ───────────────────────────  │        │  ──────────────────────────  │
│  · 源码 / CMakeLists / vcpkg.json   │        │  · workflows / scripts       │
│  · scripts/*.sh                     │◀───────│  · 免费 Runner（Linux）      │
│  · ❌ 不再运行 Actions               │  token │  · results/ 归档结果          │
└─────────────────────────────────────┘ 只读   └──────────────────────────────┘
         只提供代码与脚本                    只提供算力与流程，公开可见
```

三个职责边界：

1. **Source 不再运行 CI**：把私有仓库的 `.github/workflows/*.yml` 删掉或改名禁用，防止双份消耗。
2. **Driver 负责全部执行**：checkout 私有源 → 探测构建方式 → 执行 → 采集信息 → 生成报告 → 归档。
3. **结果回落到 Driver**：`results/` 目录 committed 回 public 仓库 + Actions Artifact 双份保留。

---

## 3. 四账号部署拓扑

```
                 ┌──────────────── edidada (主) ────────────────┐
                 │  github_action_shell  (public)               │
                 │  → 用 edidada 的 PAT 拉 edidada/cpp_ecshop    │
                 │  → 执行 / 生成报告 / 提交归档 / 定时自动跑     │
                 └──────────────┬───────────────────────────────┘
           单向 mirror 同步     │  MIRROR_TOKEN
       ┌───────────────┬───────┴───────┬───────────────┐
       ▼               ▼               ▼               ▼
 edidadaoutlook     wiseism       wdidada126      (可扩展)
 同名 public 仓库    同名 public     同名 public
 → 自己的 PAT 拉自己账号下的 cpp_ecshop（同名、内容可以完全不同）
```

### 关键设计：owner 自动推导

同一个 workflow 文件，落到不同账号下，**不需要改一行配置**：

```yaml
repository: ${{ github.repository_owner }}/cpp_ecshop
```

`github.repository_owner` 在运行哪个仓库就是哪个 owner。于是：

- `edidada` 的 driver 自动拉 `edidada/cpp_ecshop`
- `wiseism` 的 driver 自动拉 `wiseism/cpp_ecshop`

这正好解决你说的「**同名但是不同用途的仓库**」——拓扑天然隔离，每个账号用自己的 token 访问自己的私有源，互不越权。想整体改城源仓库名，改 `config/sources.env` 一处即可。

### 为什么只有主账号自动跑

四个副本如果都开了定时/lint-like 触发，会同时跑四遍同样的构建，并且**同时向 `results/` 写入，导致 git 历史分叉冲突**。

因此约定：

| 账号 | 角色 | schedule | workspace_dispatch | repository_dispatch | 写归档 |
|---|---|---|---|---|---|
| `edidada` | primary | ✅ 自动跑 | ✅ | ✅ | ✅ 提交 `results/` |
| 其余 3 个 | mirror | ⏭️ 跳过 | ✅ 手动才跑 | ✅ | ⚠️ 视 `commit_results` 开关而定 |

判断逻辑写在 `.github/workflows/run-source.yml` 的 `prepare` job 里，规则：

- 没配 `SOURCE_REPO_TOKEN` → 优雅跳过（不是报错），并把原因写进 Job Summary
- `schedule` 且 owner ≠ primary → 跳过
- 手动/派发 → 任何副本都能跑

---

## 4. 三种触发方式（全支持）

| 方式 | 事件 | 适用场景 | 命令 |
|---|---|---|---|
| 手动 | `workflow_dispatch` | 调试、临时跑一次 | 页面 Run workflow，或 `bash scripts/trigger.sh driver cpp_ecshop main` |
| 定时 | `schedule` | 每日构建验证 | 默认 `cron: '23 2 * * *'`（北京时间 10:23），仅主账号生效 |
| 远程派发 | `repository_dispatch` | **私有源仓库已经没有 Actions 时长，无法自己触发** | `bash scripts/trigger.sh dispatch cpp_ecshop main` |

第三种是最贴合你现状的：私有仓库连「触发 CI」的能力都别留给 Actions，从外部发起即可。

```bash
# 等价的原始 API 调用（本地 gh 或任何能联网的机器都能发）
gh api repos/edidada/github_action_shell/dispatches \
   -f event_type=run-source-script \
   -f 'client_payload[source_repo]=cpp_ecshop' \
   -f 'client_payload[source_ref]=main'
```

---

## 5. 凭证与 Secrets

每个账号的 driver 副本，**各自配置自己的 secrets**（secret 只在所在仓库生效，天然隔离）：

| Secret | 谁需要 | 用途 | 最小权限建议 |
|---|---|---|---|
| `SOURCE_REPO_TOKEN` | **全部 4 个仓库** | 读取本账号私有源 | fine-grained PAT：单个仓库 + Contents=Read、Metadata=Read、Actions=Read |
| `MIRROR_TOKEN` | **仅主账号** | 推送到其余 3 个账号 | 对 3 个目标仓库 Contents=Read and write（或 classic PAT 勾 `repo`） |

> 不要用同一个 token 给 4 个仓库：一旦泄露，4 份私有源码同时暴露。每个账号发自己的 PAT。

### 已落实的安全处理

- `persist-credentials: false` —— checkout 私有源后不把 PAT 残留在 `.git/config`，后续步骤拿不到它
- `::add-mask::` —— 脚本对 token 做日志脱敏
- `scripts/run-source.sh` 支持 `GAS_REDACT_FILE`，可对日志做额外关键词替换
- checkout URL 里出现的 `x-access-token:` 由 GitHub 自动打码为 `***`

### ⚠️ Public 仓库的固有代价（务必读）

本仓库是 public，意味着**三样东西公开可见**：

1. Actions 运行日志全文（任何人都能读，包括失败堆栈）
2. `results/` 下所有归档 md
3. workflow 文件本身（能看到私有仓库的构建流程与目录结构）

规避手段：脚本里禁止 `echo` 敏感内容；日志走 artifact + 脱敏；真正机密的信息不要让它进 Workflow。

### ⚠️ 合规性提醒（诚实说，这是灰色地带）

GitHub 对 Public 仓库免费 Actions 的定位是「服务开源」，其可接受使用政策禁止"与仓库构建/测试/部署无关"的用法。把私有代码的 CI 搬到 public 仓库来规避分钟计费，严格讲踩在边界上。风险等级取决于使用强度，请自行判断：

| 方案 | 成本 | 合规性 | 备注 |
|---|---|---|---|
| 本文方案（public driver） | 0 | ⚠️ 灰色 | 轻量个人项目广泛使用 |
| **把 cpp_ecshop 转 public** | 0 | ✅ 完全合规 | 若代码本无保密需求，**这是最优解**：直接把原 CI 留在原仓，什么都不用改 |
| 自建 self-hosted runner | 主机成本 | ✅ 合规 | C++ 项目构建快，一台常开机器性价比很高 |
| 付费 Actions 分钟 | ≈ $0.008/min × N | ✅ 合规 | 低频使用其实很便宜 |

如果只是想把 macOS/Windows 的钱省下来，**更简单也更合规的做法是把矩阵砍到只剩 Linux**（倍率从 308 降到 20），本项目放在私有仓库里也完全够用。

---

## 6. 仓库结构

```
github_action_shell/
├── .github/workflows/
│   ├── run-source.yml        # 主流程：拉取 → 执行 → 采集 → 生成报告 → 归档
│   └── mirror.yml            # 主账号 → 其余 3 账号 单向镜像
├── config/
│   ├── accounts.env          # 4 个账号清单，第一行为主账号
│   └── sources.env           # owner → 私有源仓库 映射
├── scripts/
│   ├── lib.sh                # 公共函数：日志 / 计时 / 配置解析 / Actions 输出
│   ├── discover.sh           # 自动探测构建方式（cmake / make / npm / script）
│   ├── run-source.sh         # 分步执行 + 计时 + 日志落盘
│   ├── collect-repo-info.sh  # 用 gh 采集源仓库元信息、提交、workflow、配额
│   ├── gen-report.sh         # 生成 summary.md
│   ├── trigger.sh            # 本地触发（driver / dispatch）
│   ├── push-all-remotes.sh   # 本地推送到全部账号
│   ├── mirror-accounts.sh    # Actions 内使用的镜像同步
│   └── bootstrap-accounts.sh # 检查/创建各账号仓库并输出配置清单
├── results/                  # 归档目录（刻意提交，便于追溯）
│   └── <账号>/<源仓库>/<变体>/run-<编号>/
│       ├── summary.md        # 本次运行报告
│       ├── steps.tsv         # 步骤 / 状态 / 退出码 / 耗时
│       ├── status            # success | failure | skipped
│       ├── repo-info.md      # gh 采集的源仓库信息
│       └── logs/*.log        # 每步完整日志
└── docs/DESIGN.md            # 本文
```

---

## 7. 执行流程

```mermaid
run-source.yml
  └─ prepare  ── 解析源仓库 owner/repo@ref、构建矩阵、是否启用（token / 主账号判定）
       └─ run  ── matrix × variants  ─────────────────────────────────────┐
            1. checkout driver（本仓库）
            2. checkout 私有源 → ./source     ← 用 SOURCE_REPO_TOKEN
            3. checkout microsoft/vcpkg        ← 源仓库有 vcpkg.json 才做
            4. 恢复 ccache 缓存
            5. discover.sh 探测 profile        ← CMakeLists.txt → cmake
            6. run-source.sh 分步执行
                 cmake configure → cmake build → ctest
            7. collect-repo-info.sh 采集信息   ← gh api + 配额用量
            8. gen-report.sh 生成 summary.md
            9. 写入 Job Summary
           10. 上传 Artifact（90 天）
           11. 归档到 results/ 并提交
           12. 按 status 决定红绿
```

每一步失败**不会立刻中断**（流程用 `continue-on-error` 包裹执行步骤），这样即使 build 挂了，报告、元信息、日志照样能归档 —— 事后可从归档里还原完整现场。

---

## 8. 针对 cpp_ecshop 的具体落地配置

### 8.1 关掉私有仓库自己的 CI（重要）

```bash
# 保留文件但让 GitHub 不再识别（推荐，留作备份）
git mv .github/workflows/ci.yml .github/workflows-disabled/ci.yml.bak
git mv .github/workflows/ci_crow.yml .github/workflows-disabled/ci_crow.yml.bak
```

### 8.2 构建矩阵改为 Repository Variable

主仓库 Settings → Variables → `VARIANTS`，覆盖原来 crow / httplib 两个后端：

```json
[
  { "name": "crow",    "extra": "-DECSHOP_HTTP_SERVER=crow" },
  { "name": "httplib", "extra": "-DECSHOP_HTTP_SERVER=httplib" }
]
```

> Public 仓库 Linux runner 免费无限，跑两个 variant 零成本。如果想更省，只留一个即可。

### 8.3 OS 矩阵的处理建议

原矩阵含 macOS（10×）和 Windows（2×）。建议**在 driver 里只保留 Linux**：

- C++ / CMake 项目在 Linux 上验证最快，成本为 0
- 真的需要多平台发版再单独用一次性 manuall-run 矩阵验证
- 保留多平台则把 `runs-on` 改成矩阵并在 vars 里声明（本仓库已为单平台优化）

### 8.4 可选：跑完顺带做冒烟

源仓库里有 `scripts/curl_goods_example.sh`（启动服务后调 `/healthz`、`/api/v1/goods/*`）。在手动触发时填 `extra_script=scripts/curl_goods_example.sh` 即可在构建后追加执行，失败不影响主流程判定。

---

## 9. 落地 Checklist

按顺序执行，全部在本地完成：

```bash
# 0) 本机登录所有目标账号（已登录可跳过）
gh auth login

# 1) 各账号下创建同名 public 空白仓库（不要勾选 README/.gitignore/License）
bash scripts/bootstrap-accounts.sh --yes

# 2) 给每个仓库配置 secret（每个账号用自己的 PAT）
gh auth switch --user edidada
gh secret set SOURCE_REPO_TOKEN --repo edidada/github_action_shell --body '<edidada的只读PAT>'
gh secret set MIRROR_TOKEN      --repo edidada/github_action_shell --body '<跨账号写PAT>'
# ... 其余 3 个账号各配一次 SOURCE_REPO_TOKEN

# 3) 首次推送（会把代码推到 4 个账号）
bash scripts/push-all-remotes.sh

# 4) 手动触发一次验证
bash scripts/trigger.sh driver cpp_ecshop main auto auto

# 5) 确认跑通后，关掉私有仓库原 CI（见 8.1）
```

---

## 10. 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| Job Summary 显示「未配置 secret SOURCE_REPO_TOKEN，跳过」 | 该账号仓库没配 PAT | 切到对应账号配 `SOURCE_REPO_TOKEN`；secret 只在单个仓库生效，不会因为镜像同步过去 |
| `GraphQL: Could not resolve to a Repository` | token 无权访问该私有仓，或 PAT 是 fine-grained 但没勾选这个仓库 | 检查 PAT 的 resource owner 和仓库授权 |
| workflow 不存在、无法 `gh workflow run` | 首次 push 后 GitHub 才识别 workflow | 先 push 到远端，再触发 |
| 归档步骤 push 失败 | 多副本同时写 `results/` 造成历史分叉 | 脚本已做 `pull --rebase` + 3 次重试；确认非主仓的 schedule 已被自动跳过 |
| vcpkg 构建特别慢 | 每次都从源码编译 | 已启用 ccache；可进一步配 `VCPKG_BINARY_SOURCES=clear;files,<path>;readwrite` |
| `bash: scripts/xxx.sh: No such file` | push 时文件可执行位丢失 | `git update-index --chmod=+x scripts/*.sh` |
| `CONNECT tunnel failed, response 502` / `schannel: server closed abruptly` | 本机设了 `HTTPS_PROXY`，git 的 HTTPS 推流被代理拒绝 | 改用 SSH 推送，见 §12 |
| `Permission denied (publickey)` | SSH 别名用错密钥 | `ssh -T git@<别名>` 看返回的 `Hi <账号>!` 对不对 |

---

## 11. 常用命令速查

```bash
bash scripts/trigger.sh driver  cpp_ecshop main          # 手动触发一次
bash scripts/trigger.sh dispatch cpp_ecshop main         # 远程派发（推荐日常用）
bash scripts/push-all-remotes.sh                         # 推送到 4 个账号
bash scripts/push-all-remotes.sh --dry-run               # 先看会做什么
bash scripts/bootstrap-accounts.sh --yes                 # 建仓库 + 打印配置清单

gh run list --repo edidada/github_action_shell --limit 5
gh run watch <run-id> --repo edidada/github_action_shell
gh api repos/edidada/cpp_ecshop --jq '{private:.private, default_branch:.default_branch}'
gh api users/edidada/settings/billing/actions --jq '.total_minutes_used'
```

---

## 12. 本机多账号推送（踩坑记录）

实测环境：Windows + Git Bash，本机设了 `HTTPS_PROXY`、`~/.ssh` 里每个 GitHub 账号各有一把密钥。

### 坑 1：HTTPS 推送走代理直接 502

```bash
git push https://github.com/wiseism/github_action_shell.git main
# fatal: unable to access '...': CONNECT tunnel failed, response 502
```

git 会读取 `HTTPS_PROXY` 环境变量，代理不放行 github.com:443。而 `gh` CLI 不受影响，所以会出现「`gh repo view` 正常但 `git push` 失败」的诡异现象。

### 解法：走 SSH 别名（443 端口）

GitHub 提供 `ssh.github.com:443`，可以同时绕开 22 端口封锁和代理。`~/.ssh/config` 里给每个账号配一个 Host：

```sshconfig
Host wiseism126_github.com
    User git
    Hostname ssh.github.com     # ← 关键：443 端口的 SSH 入口
    IdentityFile C:/Users/wdidada/.ssh/id_ed25519_wiseism126_github
    Port 443
    IdentitiesOnly yes
```

验证方式（`Hi` 后面的账号名必须与你预期的账号一致）：

```bash
ssh -T git@wiseism126_github.com
# Hi wiseism! You've successfully authenticated, but GitHub does not provide shell access.
```

> ⚠️ 同一把 SSH 公钥不能重复添加到不同 GitHub 账号，会报 "Key is already in use"。
> 多账号必须各自生成独立的密钥。

### 坑 2：Windows 的 CRLF 会打死 Linux runner

`core.autocrlf=true` 时，checkout 出来的 `.sh` 文件是 CRLF，在 Linux runner 上会报 `bad interpreter`。仓库里加了 `.gitattributes` 强制 LF：

```gitattributes
*.sh text eol=lf
```

### 坑 3：`git add --chmod=+x` 在 Windows 上不生效

需要显式执行：

```bash
git update-index --chmod=+x scripts/*.sh
```

### 最终：一条命令推 4 个账号

账号与 SSH 别名的对应关系写在 `config/accounts.env` 里（第二列）：

```bash
bash scripts/push-all-remotes.sh
# ✓ edidada / edidadaoutlook / wiseism / wdidada126 全部完成
```

云端同步（`mirror.yml`）与本机无关，是主仓配了 `MIRROR_TOKEN` 后由 GitHub 自己执行的 HTTPS 推送，不受本机代理影响。

---

_本方案设计于 2026-09。Actions 配额以 [GitHub 官方计费文档](https://docs.github.com/billing/managing-billing-for-github-actions/about-billing-for-github-actions) 为准。_
