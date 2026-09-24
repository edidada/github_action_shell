# 执行结果归档目录

每轮运行会在 `results/<账号>/<源仓库>/<变体>/run-<编号>/` 下生成：

| 文件 | 说明 |
|---|---|
| `summary.md` | 本次运行的完整报告（推荐从这里看） |
| `steps.tsv` | 每一步的名称 / 状态 / 退出码 / 耗时 |
| `status` | 最终状态：`success` / `failure` / `skipped` |
| `repo-info.md` | 用 `gh` 采集到的源仓库元信息 |
| `repo-info.json` | 同上，原始 JSON |
| `logs/*.log` | 每一步的完整日志 |

注意：本仓库是 public，归入此处的内容对所有人可见，请勿在脚本输出中打印敏感信息。
