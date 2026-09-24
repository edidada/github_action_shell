# 项目长期记忆：github_action_shell

## 定位

Public CI driver：用公开仓库的免费 Actions runner，拉取并执行**私有仓库**的脚本/构建，
结果归档回本仓库 `results/`。源仓 `edidada/cpp_ecshop`（私有，C++/CMake/vcpkg）的 Actions
分钟已耗尽，计算被搬到本仓库。

## 账号与 SSH 别名映射（本机 ~/.ssh/config）

| 账号 | SSH 别名 | 角色 |
|---|---|---|
| edidada | `github.com`（默认 Host） | **主账号**：唯一跑 schedule、唯一写 `results/`、负责 mirror |
| edidadaoutlook | `edidadaoutlook.com` | 镜像 |
| wiseism | `wiseism126_github.com` | 镜像 |
| wdidada126 | `wdidada126_github.com` | 镜像 |

验证命令：`ssh -T git@<别名>` → 应返回 `Hi <账号>!`
本机推送：`bash scripts/push-all-remotes.sh`（默认 SSH，`--https` 会走 gh 凭证）

## 约定

- **owner 自动推导**：workflow 里源仓库用 `${{ github.repository_owner }}/cpp_ecshop`，
  同一份 workflow 在 4 个账号各自拉取自己账号的同名私有仓，绝不硬编码 owner。
- **单向同步**：主仓 → 镜像仓单向。镜像仓不自动跑 schedule，避免多处写 `results/` 冲突。
- **改映射**：`config/accounts.env`（账号+SSH别名）、`config/sources.env`（账号→私有源仓库）。
- **归档路径**：`results/<账号>/<源仓库>/<变体>/run-<编号>/summary.md`
- **换行符**：`.gitattributes` 强制 LF，不要动它。
- **脚本可执行位**：Windows 下必须 `git update-index --chmod=+x`。

## 本机网络约束

`HTTPS_PROXY` 存在且不放行 github.com:443，git 的 HTTPS 推流会 502。
**一律走 SSH 443 别名**；云端 mirror 走 HTTPS 但由 GitHub 执行，不受影响。

## 合规提醒（已写入 DESIGN.md）

用 public 仓库构建私有代码属灰色地带。更合规的替代：把 cpp_ecshop 转 public、
自建 self-hosted runner、或把矩阵砍到只剩 Linux（倍率从 308 降到 20）。
