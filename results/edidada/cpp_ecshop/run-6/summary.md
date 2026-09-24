# edidada/cpp_ecshop CI 报告 · #6

## ❌ 失败

| 项 | 值 |
|---|---|
| 源仓库（私有） | [`edidada/cpp_ecshop`](https://github.com/edidada/cpp_ecshop) |
| 分支 / Ref | `main` |
| Commit | `2b7790aed374a60474b6f39d55346eeb969bf68b` |
| 构建类型 | `cmake` |
| 驱动器仓库（本仓库） | [`edidada/github_action_shell`](https://github.com/edidada/github_action_shell) |
| Run | [#6](https://github.com/edidada/github_action_shell/actions/runs/36022797537) |
| 触发方式 | `workflow_dispatch` |
| 触发者 | `edidada` |
| Runner | `Linux-X64` |
| 完成时间 | 2026-09-24 15:48:22 UTC |

## 执行步骤

| 步骤 | 状态 | 退出码 | 耗时 | 日志 |
|---|---|---|---|---|
| vcpkg bootstrap | ✅ ok | 0 | 0m00s | [01-vcpkg-bootstrap.log](logs/01-vcpkg-bootstrap.log) |
| cmake configure | ❌ fail | 1 | 0m00s | [02-cmake-configure.log](logs/02-cmake-configure.log) |
| cmake build | ❌ fail | 1 | 0m00s | [03-cmake-build.log](logs/03-cmake-build.log) |
| ctest | ✅ ok | 0 | 0m01s | [04-ctest.log](logs/04-ctest.log) |

## 失败日志摘要

<details><summary>❌ cmake configure (exit=1)</summary>

```
fatal: path 'versions/baseline.json' exists on disk, but not in 'ce613c41372b23b1f51333815feb3edd87ef8a8b'
while checking out baseline ce613c41372b23b1f51333815feb3edd87ef8a8b
while loading baseline version for nlohmann-json
error: while checking out baseline from commit 'ce613c41372b23b1f51333815feb3edd87ef8a8b', failed to `git show` versions/baseline.json. This may be fixed by fetching commits with `git fetch`.
error: /usr/bin/git --git-dir=/home/runner/work/github_action_shell/github_action_shell/source/.vcpkg/.git --work-tree=/home/runner/work/github_action_shell/github_action_shell/source/.vcpkg/.git -c core.autocrlf=false show ce613c41372b23b1f51333815feb3edd87ef8a8b:versions/baseline.json failed with exit code 128
fatal: path 'versions/baseline.json' exists on disk, but not in 'ce613c41372b23b1f51333815feb3edd87ef8a8b'
while checking out baseline ce613c41372b23b1f51333815feb3edd87ef8a8b
while loading baseline version for spdlog
error: while checking out baseline from commit 'ce613c41372b23b1f51333815feb3edd87ef8a8b', failed to `git show` versions/baseline.json. This may be fixed by fetching commits with `git fetch`.
error: /usr/bin/git --git-dir=/home/runner/work/github_action_shell/github_action_shell/source/.vcpkg/.git --work-tree=/home/runner/work/github_action_shell/github_action_shell/source/.vcpkg/.git -c core.autocrlf=false show ce613c41372b23b1f51333815feb3edd87ef8a8b:versions/baseline.json failed with exit code 128
fatal: path 'versions/baseline.json' exists on disk, but not in 'ce613c41372b23b1f51333815feb3edd87ef8a8b'
while checking out baseline ce613c41372b23b1f51333815feb3edd87ef8a8b
while loading baseline version for sqlite3
error: while checking out baseline from commit 'ce613c41372b23b1f51333815feb3edd87ef8a8b', failed to `git show` versions/baseline.json. This may be fixed by fetching commits with `git fetch`.
error: /usr/bin/git --git-dir=/home/runner/work/github_action_shell/github_action_shell/source/.vcpkg/.git --work-tree=/home/runner/work/github_action_shell/github_action_shell/source/.vcpkg/.git -c core.autocrlf=false show ce613c41372b23b1f51333815feb3edd87ef8a8b:versions/baseline.json failed with exit code 128
fatal: path 'versions/baseline.json' exists on disk, but not in 'ce613c41372b23b1f51333815feb3edd87ef8a8b'
while checking out baseline ce613c41372b23b1f51333815feb3edd87ef8a8b
while loading baseline version for sqlpp11
error: while checking out baseline from commit 'ce613c41372b23b1f51333815feb3edd87ef8a8b', failed to `git show` versions/baseline.json. This may be fixed by fetching commits with `git fetch`.
error: /usr/bin/git --git-dir=/home/runner/work/github_action_shell/github_action_shell/source/.vcpkg/.git --work-tree=/home/runner/work/github_action_shell/github_action_shell/source/.vcpkg/.git -c core.autocrlf=false show ce613c41372b23b1f51333815feb3edd87ef8a8b:versions/baseline.json failed with exit code 128
fatal: path 'versions/baseline.json' exists on disk, but not in 'ce613c41372b23b1f51333815feb3edd87ef8a8b'
while checking out baseline ce613c41372b23b1f51333815feb3edd87ef8a8b
while loading baseline version for sqlpp11-connector-mysql
error: while checking out baseline from commit 'ce613c41372b23b1f51333815feb3edd87ef8a8b', failed to `git show` versions/baseline.json. This may be fixed by fetching commits with `git fetch`.
error: /usr/bin/git --git-dir=/home/runner/work/github_action_shell/github_action_shell/source/.vcpkg/.git --work-tree=/home/runner/work/github_action_shell/github_action_shell/source/.vcpkg/.git -c core.autocrlf=false show ce613c41372b23b1f51333815feb3edd87ef8a8b:versions/baseline.json failed with exit code 128
fatal: path 'versions/baseline.json' exists on disk, but not in 'ce613c41372b23b1f51333815feb3edd87ef8a8b'
while checking out baseline ce613c41372b23b1f51333815feb3edd87ef8a8b
while loading baseline version for sqlpp11-connector-sqlite3
-- Running vcpkg install - failed
CMake Error at .vcpkg/scripts/buildsystems/vcpkg.cmake:984 (message):
  vcpkg install failed.  See logs for more information:
  /home/runner/work/github_action_shell/github_action_shell/source/build/vcpkg-manifest-install.log
Call Stack (most recent call first):
  /usr/local/share/cmake-3.31/Modules/CMakeDetermineSystem.cmake:146 (include)
  CMakeLists.txt:17 (project)


CMake Error: CMake was unable to find a build program corresponding to "Unix Makefiles".  CMAKE_MAKE_PROGRAM is not set.  You probably need to select a different build tool.
CMake Error: CMAKE_CXX_COMPILER not set, after EnableLanguage
-- Configuring incomplete, errors occurred!

```

</details>

<details><summary>❌ cmake build (exit=1)</summary>

```
no such file or directory
CMake Error: Generator: execution of make failed. Make command was:  -f Makefile -j

```

</details>

## 源仓库信息（gh 采集）

#### 仓库元信息

| 项 | 值 |
|---|---|
| 仓库 | [edidada/cpp_ecshop](https://github.com/edidada/cpp_ecshop) |
| 可见性 | 私有 🔒 |
| 默认分支 | `main` |
| 主语言 | C++ |
| 描述 | - |
| 大小 | 8042 KB |
| 最后推送 | 2026-09-24T13:55:25Z |
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

- [01-vcpkg-bootstrap.log](logs/01-vcpkg-bootstrap.log) · 4 行
- [02-cmake-configure.log](logs/02-cmake-configure.log) · 58 行
- [03-cmake-build.log](logs/03-cmake-build.log) · 2 行
- [04-ctest.log](logs/04-ctest.log) · 3 行

---

_由 [edidada/github_action_shell](https://github.com/edidada/github_action_shell) 自动生成，请勿手工编辑。_
