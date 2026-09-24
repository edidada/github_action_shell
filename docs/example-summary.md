# 归档报告样例

> 下面是脚本针对真实私有仓库 `edidada/cpp_ecshop` 跑出来的实际输出形态。
> 每轮运行会落到 `results/<账号>/<源仓库>/<变体>/run-<编号>/summary.md`。


| 项 | 值 |
|---|---|
| 源仓库（私有） | [`edidada/cpp_ecshop`](https://github.com/edidada/cpp_ecshop) |
| 分支 / Ref | `main` |
| Commit | `2b7790a` |
| 构建类型 | `cmake` |
| 驱动器仓库（本仓库） | [`local/github_action_shell`](https://github.com/local/github_action_shell) |
| Run | [#0](https://github.com/local/github_action_shell/actions/runs/local) |
| 触发方式 | `manual` |
| 触发者 | `local` |
| Runner | `unknown-unknown` |
| 完成时间 | 2026-09-24 13:04:03 UTC |

## 执行步骤

| 步骤 | 状态 | 退出码 | 耗时 | 日志 |
|---|---|---|---|---|
| run scripts/smoke.sh | ✅ ok | 0 | 0m02s | [01-run-scripts-smoke-sh.log](logs/01-run-scripts-smoke-sh.log) |

## 源仓库信息（gh 采集）

#### 仓库元信息

| 项 | 值 |
|---|---|
| 仓库 | [edidada/cpp_ecshop](https://github.com/edidada/cpp_ecshop) |
| 可见性 | 私有 🔒 |
| 默认分支 | `main` |
| 主语言 | C++ |
| 描述 | - |
| 大小 | 8019 KB |
| 最后推送 | 2026-09-24T12:53:57Z |
| 分支数 | 3 |

> Actions 配额：Actions 配额信息不可用（需要 PAT 具备对该账号的 Actions 计费读权限）

#### 分支

```
crow
main
work
```

#### 最近的提交

| SHA | 作者 | 时间 | 说明 |
|---|---|---|---|
| `2b7790a` | root | 2026-09-19T15:12:35Z | Merge #9 into main from work |
| `8e43001` | somessyy | 2026-09-19T15:05:18Z | fix: apply configured log level consistently |
| `d440afa` | somessyy | 2026-09-19T14:58:29Z | refactor: unify route error handling |
| `0453d6d` | somessyy | 2026-09-19T14:45:50Z | add /api/v1/home crow |
| `9a1622c` | somessyy | 2026-09-19T14:41:32Z | add /api/v1/home crow |

#### 源仓库自带 Workflow

```
total=2
  - ci [active]
  - ci-http-servers [active]
```

#### 源仓库最近的 Actions 运行

```
  - ci #6 → failure @ 2026-09-19T15:56:08Z
  - ci-http-servers #1 → failure @ 2026-09-19T14:42:34Z
  - ci #5 → failure @ 2026-09-19T11:57:43Z
  - ci #4 → failure @ 2026-09-19T10:01:31Z
  - ci #3 → failure @ 2026-09-19T09:27:40Z
```

#### 贡献者

```

```

## 日志

- [01-run-scripts-smoke-sh.log](logs/01-run-scripts-smoke-sh.log) · 2 行

---

_由 [local/github_action_shell](https://github.com/local/github_action_shell) 自动生成，请勿手工编辑。_
