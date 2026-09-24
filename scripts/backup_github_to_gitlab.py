#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 GitHub 上的仓库镜像备份到 GitLab。

纯 Python 标准库；git 走 SSH（~/.ssh/config 的 Host 别名）。
clone --mirror + push --mirror 完整保留所有分支、标签与 refs。
GitLab 支持 push-to-create：目标项目不存在时首次 push 会自动创建。
若本机 glab 已认证，则顺带把项目设为 private 并同步描述。

用法：
  python scripts/backup_github_to_gitlab.py --dry-run           # 只列计划
  python scripts/backup_github_to_gitlab.py --only ag-app       # 只备份一个（先验证）
  python scripts/backup_github_to_gitlab.py                     # 全部非 fork 仓库
  python scripts/backup_github_to_gitlab.py --max-size-mb 10    # 只备份 10MB 以下
  python scripts/backup_github_to_gitlab.py --update-existing   # 连已存在的一起更新
"""
from __future__ import annotations

import argparse
import json
import logging
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

LOG = logging.getLogger("backup")

GLAB_CANDIDATES = [
    "glab",
    r"C:\Program Files (x86)\glab\glab.exe",
    r"C:\Program Files\glab\glab.exe",
]


def find_glab() -> str | None:
    for c in GLAB_CANDIDATES:
        if shutil.which(c):
            return c
        if Path(c).is_file():
            return c
    return None


def run(cmd: list[str], timeout: int = 600, env: dict | None = None) -> tuple[int, str, str]:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           encoding="utf-8", errors="replace", env=env)
        return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s"
    except FileNotFoundError as e:
        return 127, "", str(e)


def list_repos(owner: str, include_fork: bool = False, include_archived: bool = True) -> list[dict]:
    """用 gh 列出 owner 的仓库（含私有，前提是 gh 已登录该账号）。"""
    rc, out, err = run(["gh", "api", "--paginate", "--slurp",
                        f"users/{owner}/repos?per_page=100&sort=full_name"], timeout=300)
    if rc != 0:
        raise SystemExit(f"gh 获取仓库列表失败: {err}")
    try:
        data = json.loads(out)
    except json.JSONDecodeError as e:
        raise SystemExit(f"解析 gh 输出失败: {e}\n前 200 字符: {out[:200]}")

    # --slurp 会把每一页作为一个数组放进外层数组，需要展平
    if data and isinstance(data[0], list):
        data = [item for page in data for item in page]

    repos = []
    for r in data:
        if r.get("owner", {}).get("login") != owner:
            continue
        if r.get("fork") and not include_fork:
            continue
        if r.get("archived") and not include_archived:
            continue
        repos.append({
            "name": r["name"],
            "size_mb": round(r.get("size", 0) / 1024, 2),
            "visibility": r.get("visibility"),
            "description": (r.get("description") or "")[:200],
            "default_branch": r.get("default_branch") or "main",
            "pushed_at": r.get("pushed_at"),
            "archived": bool(r.get("archived")),
        })
    return repos


def remote_exists(url: str, timeout: int = 60) -> bool:
    rc, _, _ = run(["git", "ls-remote", "--exit-code", url], timeout=timeout)
    return rc == 0


def gitlab_project_path(namespace: str, name: str) -> str:
    return quote(f"{namespace}/{name}", safe="")


def ensure_private(glab: str, namespace: str, name: str, desc: str) -> str:
    """用 glab API 把项目设为 private 并写描述。返回状态说明。"""
    enc = gitlab_project_path(namespace, name)
    rc, out, err = run([glab, "api", f"projects/{enc}"], timeout=60)
    if rc != 0:
        return f"skip(查询失败: {err[:60]})"
    try:
        proj = json.loads(out)
    except json.JSONDecodeError:
        return "skip(响应非 JSON)"
    if proj.get("visibility") == "private":
        return "private(已是)"
    args = [glab, "api", "-X", "PUT", f"projects/{enc}", "-f", "visibility=private"]
    if desc:
        args += ["-f", f"description={desc}"]
    rc, out, err = run(args, timeout=60)
    return "private(已设置)" if rc == 0 else f"设置失败: {err[:60]}"


def backup_one(repo: dict, args, workdir: Path, glab: str | None) -> dict:
    name = repo["name"]
    src_url = f"git@{args.gh_host}:{args.owner}/{name}.git"
    dst_url = f"git@{args.gl_host}:{args.namespace}/{name}.git"
    res = {"name": name, "size_mb": repo["size_mb"], "status": "pending",
           "detail": "", "seconds": 0}

    if args.dry_run:
        res["status"] = "planned"
        res["detail"] = f"{src_url} -> {dst_url}"
        return res

    if not args.update_existing and remote_exists(dst_url):
        res["status"] = "skipped"
        res["detail"] = "目标项目已存在（加 --update-existing 可强制更新）"
        LOG.info("跳过 %s：目标已存在", name)
        return res

    # 每次用唯一目录：Windows 上删除可能被占用而失败，复用同名目录会让 clone 因目录非空而报错
    tmpdir = Path(tempfile.mkdtemp(prefix=f"{name}-", dir=str(workdir)))
    mirror = tmpdir / f"{name}.git"

    t0 = time.time()
    rc, out, err = run(["git", "clone", "--mirror", src_url, str(mirror)],
                       timeout=args.timeout)
    if rc != 0:
        res["status"] = "failed"
        res["detail"] = f"clone 失败: {err[:200]}"
        res["seconds"] = round(time.time() - t0, 1)
        LOG.error("clone 失败 %s", name)
        return res

    rc, out, err = run(["git", "-C", str(mirror), "push", "--mirror", dst_url],
                       timeout=args.timeout)
    res["seconds"] = round(time.time() - t0, 1)
    if rc != 0:
        res["status"] = "failed"
        res["detail"] = f"push 失败: {err[:200]}"
        LOG.error("push 失败 %s", name)
        return res

    vis = "default"
    if glab:
        vis = ensure_private(glab, args.namespace, name, repo.get("description", ""))
    res["status"] = "ok"
    res["detail"] = f"已镜像 -> gitlab.com/{args.namespace}/{name} (visibility={vis})"
    LOG.info("完成 %s (%.1fs)", name, res["seconds"])

    if not args.keep:
        shutil.rmtree(tmpdir, ignore_errors=True)
    return res


def main() -> int:
    ap = argparse.ArgumentParser(description="GitHub -> GitLab 仓库镜像备份")
    ap.add_argument("--owner", default="edidada", help="GitHub 账号（默认 edidada）")
    ap.add_argument("--namespace", default="edidada", help="GitLab 目标 namespace")
    ap.add_argument("--gh-host", default="github.com", help="~/.ssh/config 中 GitHub 的 Host 别名")
    ap.add_argument("--gl-host", default="gitlab.com", help="~/.ssh/config 中 GitLab 的 Host 别名")
    ap.add_argument("--only", action="append", default=[], help="只备份指定仓库，可重复")
    ap.add_argument("--exclude", action="append", default=[], help="排除指定仓库，可重复")
    ap.add_argument("--max-size-mb", type=float, default=None, help="只备份小于该体积的仓库")
    ap.add_argument("--min-size-mb", type=float, default=None, help="只备份大于该体积的仓库")
    ap.add_argument("--include-fork", action="store_true", help="包含 fork 仓库")
    ap.add_argument("--update-existing", action="store_true", help="目标已存在时也强制更新")
    ap.add_argument("--dry-run", action="store_true", help="只输出计划，不执行")
    ap.add_argument("--workers", type=int, default=1, help="并发数，默认 1（串行更稳）")
    ap.add_argument("--timeout", type=int, default=3600, help="单个 git 操作超时秒数")
    ap.add_argument("--workdir", default=None, help="临时镜像存放目录")
    ap.add_argument("--keep", action="store_true", help="保留临时镜像目录")
    ap.add_argument("--report-dir", default="reports", help="报告输出目录")
    args = ap.parse_args()

    logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")

    glab = find_glab()
    if glab:
        rc, _, _ = run([glab, "auth", "status"], timeout=60)
        LOG.info("glab: %s（%s）", glab, "已认证" if rc == 0 else "未认证，可见性将取账号默认值")
        if rc != 0:
            glab = None
    else:
        LOG.warning("未找到 glab，将依赖 push-to-create 的默认可见性")

    repos = list_repos(args.owner, include_fork=args.include_fork)
    if args.only:
        repos = [r for r in repos if r["name"] in args.only]
    if args.exclude:
        repos = [r for r in repos if r["name"] not in args.exclude]
    if args.max_size_mb is not None:
        repos = [r for r in repos if r["size_mb"] <= args.max_size_mb]
    if args.min_size_mb is not None:
        repos = [r for r in repos if r["size_mb"] >= args.min_size_mb]

    total_mb = sum(r["size_mb"] for r in repos)
    LOG.info("待处理 %d 个仓库，合计约 %.0f MB", len(repos), total_mb)
    for r in repos[:10]:
        LOG.info("  - %-40s %8.1f MB", r["name"], r["size_mb"])
    if len(repos) > 10:
        LOG.info("  ... 还有 %d 个", len(repos) - 10)

    if args.dry_run:
        return 0

    workdir = Path(args.workdir) if args.workdir else Path.cwd() / ".backup-tmp"
    workdir.mkdir(parents=True, exist_ok=True)

    results: list[dict] = []
    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as ex:
        futs = {ex.submit(backup_one, r, args, workdir, glab): r["name"] for r in repos}
        for f in as_completed(futs):
            try:
                results.append(f.result())
            except Exception as e:  # noqa: BLE001
                results.append({"name": futs[f], "status": "error", "detail": str(e),
                                "seconds": 0, "size_mb": 0})

    results.sort(key=lambda x: x["name"])
    ok = sum(1 for r in results if r["status"] == "ok")
    bad = [r for r in results if r["status"] in ("failed", "error")]

    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    rdir = Path(args.report_dir)
    rdir.mkdir(parents=True, exist_ok=True)
    payload = {"generated_at": ts, "owner": args.owner, "namespace": args.namespace,
               "planned": len(repos), "ok": ok, "failed": len(bad), "results": results}
    (rdir / f"backup-{ts}.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [f"# GitHub -> GitLab 备份报告 {ts}", "",
             f"- 源：GitHub `{args.owner}`　目标：GitLab `{args.namespace}`",
             f"- 计划 {len(repos)} 个，成功 {ok} 个，失败 {len(bad)} 个", "",
             "| 仓库 | 体积(MB) | 状态 | 说明 |", "|---|---|---|---|"]
    for r in results:
        lines.append(f"| {r['name']} | {r['size_mb']} | {r['status']} | {r['detail']} |")
    (rdir / f"backup-{ts}.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    LOG.info("完成：成功 %d / 失败 %d；报告见 %s", ok, len(bad), rdir / f"backup-{ts}.md")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
