# 仓库台账：4 账号 × 同名仓库

> 「同名不同用途」的管理清单。每次新增同名仓库、或某份副本开始独立演化时，在这里登记。
> 分支规则见 [BRANCHING.md](BRANCHING.md)。

**实测日期**：2026-09-25 · **工具**：`gh api`（逐账号切换凭证）

---

## 1. Driver 仓库 `github_action_shell`

四个账号下各一份，**互相不是 fork 关系**（`fork=false`），纯粹靠本机 `git push` 同步。

| 账号 | visibility | default branch | 分支策略 | 关联的私有源 |
|---|---|---|---|---|
| `edidada` | public | `main` | 主账号，唯一跑 schedule + 写 `results/` | `cpp_ecshop` ✅ |
| `edidadaoutlook` | public | `main` | 只读镜像 | 无 ❌ |
| `wiseism` | public | `main` | 只读镜像 | 无 ❌ |
| `wdidada126` | public | `main` | 只读镜像 | 无 ❌ |

> **待办**：按 [BRANCHING.md §6](BRANCHING.md) 迁移后，上表的 default branch 会变成 `acct/<owner>`。

### ⚠️ 已发现的配置陷阱

`config/sources.env` 目前给 **4 个账号都映射了 `cpp_ecshop`**，但实测只有 `edidada` 名下有这个仓库：

```
edidada          vis=private  size=8042KB        ✅
edidadaoutlook   404 Not Found                   ❌
wiseism          404 Not Found                   ❌
wdidada126       404 Not Found                   ❌
```

**后果**：另外 3 个账号一旦触发 `run-source`，会在 checkout 私有源那一步直接失败。

**处理**：把无效行注释掉即可，runner 会优雅跳过。

```bash
# config/sources.env
edidada=cpp_ecshop
# edidadaoutlook=cpp_ecshop   ← 该账号下不存在此仓库
# wiseism=cpp_ecshop
# wdidada126=cpp_ecshop
```

---

## 2. 同名仓库盘点

### `compiler_script` — 4 份，**当前同源未分叉**

| 账号 | visibility | size | default branch | HEAD SHA |
|---|---|---|---|---|
| `edidada` | public | — | `main` | `e3360b7c1b` |
| `edidadaoutlook` | public | 785 KB | `main` | `e3360b7c1b` |
| `wiseism` | public | 818 KB | `main` | `e3360b7c1b` |
| `wdidada126` | public | 808 KB | `main` | `e3360b7c1b` |

**HEAD SHA 四份完全一致** → 目前是**同一份代码的四个副本**，用途相同，尚未分叉。

体积差异（785 / 818 / 808 KB）来自各仓库的 git object 计数不同（推流历史不一致），不代表内容有差异。

> 📌 **这是「同名不同用途」最容易出事的一类** —— 看起来是四份同步的副本，
> 但只要任一账号在本地改了自己的那份并推上去，四份就永久分叉，且没有任何机制会告诉你。
> 要独立演化请显式登记到 §4，并按 BRANCHING.md 建 `acct/` 分支。

### `cpp_ecshop` — 仅 1 份

| 账号 | visibility | size | 用途 |
|---|---|---|---|
| `edidada` | **private** | 8042 KB | C++ / CMake / vcpkg 商城项目，本方案的驱动对象 |

### `simpledb_cpp` — 仅 1 份

| 账号 | visibility | size | 用途 |
|---|---|---|---|
| `wdidada126` | public | 28 KB | 该账号独有，不参与本方案 |

---

## 3. 各账号非 fork 仓库总量

| 账号 | 非 fork 仓库数 | 备注 |
|---|---|---|
| `edidada` | 50 | 含 cpp_ecshop；另有 4 个 >60MB 大仓（Kubernetes15 553MB / boost 129MB / FFmpeg4Android 64MB / Projects 60MB）|
| `edidadaoutlook` | 2 | compiler_script, github_action_shell |
| `wiseism` | 2 | compiler_script, github_action_shell |
| `wdidada126` | 3 | compiler_script, github_action_shell, simpledb_cpp |

---

## 4. 独立演化登记表

**新增同名副本、或某份副本要开始做不同的事时，先在这里补一行再动手。**

| 仓库名 | 账号 | 用途（一句话） | 是否共享 `main` | 分支 | 登记日期 |
|---|---|---|---|---|---|
| _(暂无)_ | | | | | |

填写示例：

| 仓库名 | 账号 | 用途 | 是否共享 `main` | 分支 | 登记日期 |
|---|---|---|---|---|---|
| compiler_script | wiseism | 只跑 Java 工具链验证，不用 Apache 那套 | 否 | `acct/wiseism` | 2026-09-25 |

### 判断要不要放手的三个问题

在给某份同名副本做定制前，先自问：

1. **这个改动另外 3 个账号也想要吗？** → 是：进 `main`；否：进 `acct/*`
2. **它会不会导致 HEAD SHA 永久分叉？** → 会：必须在 §4 登记，并写明用途
3. **改用 `config/sources.<owner>.env` overlay 能不能解决？** → 能：就别开分支（开销最小）

---

## 5. 巡检

建议每月跑一次，看有没有静默分叉：

```bash
prev=$(gh api user --jq '.login')
for u in edidada edidadaoutlook wiseism wdidada126; do
  gh auth switch --user "$u" >/dev/null 2>&1
  printf "%-16s " "$u"
  gh api "repos/$u/compiler_script/commits/main" --jq '.sha[0:10]' 2>/dev/null || echo "(无此仓库)"
done
gh auth switch --user "$prev" >/dev/null 2>&1
```

四个 SHA **一致** = 仍然同源；**不一致** = 已分叉，立刻补 §4 的登记。
