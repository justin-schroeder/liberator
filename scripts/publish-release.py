#!/usr/bin/env python3
"""Prepare and atomically push a stable SemVer release; standard library only."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
VERSION_PATTERN = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
SECRETS = {"DEVELOPER_ID_P12_BASE64", "DEVELOPER_ID_P12_PASSWORD", "DEVELOPER_ID_APPLICATION",
           "DEVELOPER_TEAM_ID", "NOTARY_APPLE_ID", "NOTARY_APP_PASSWORD"}


def run(*args, capture=True, env=None):
    return subprocess.run(args, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None, env=env).stdout


def git(*args):
    return run("git", *args).strip()


def version(value):
    if not re.fullmatch(VERSION_PATTERN, value):
        raise ValueError("Use a stable MAJOR.MINOR.PATCH version (no leading zeros or prereleases).")
    return tuple(map(int, value.split(".")))


def next_version(current, choice):
    parts = list(version(current))
    if choice in ("major", "minor", "patch"):
        index = ("major", "minor", "patch").index(choice)
        parts[index] += 1
        parts[index + 1:] = [0] * (2 - index)
        result = tuple(parts)
    else:
        result = version(choice)
    if result <= version(current):
        raise ValueError("The release version must increase.")
    return ".".join(map(str, result))


def clean():
    if git("status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Commit or remove all tracked/untracked changes before releasing (ignored build files are fine).")
    for marker in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "BISECT_LOG"):
        if (ROOT / git("rev-parse", "--git-path", marker)).exists():
            raise ValueError("Finish the active Git operation before releasing.")
    if git("branch", "--show-current") != "main":
        raise ValueError("Release from main, not a detached HEAD or feature branch.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bump", nargs="?", help="major, minor, patch, or exact version (e.g. 1.2.3)")
    parser.add_argument("--yes", action="store_true", help="Run without prompts; requires an explicit bump")
    parser.add_argument("--dry-run", action="store_true", help="Fetch and check the release plan without building, committing, tagging or pushing")
    args = parser.parse_args()
    if (args.yes or not sys.stdin.isatty()) and not args.bump:
        parser.error("Provide major, minor, patch, or an exact version.")
    if not sys.stdin.isatty() and not (args.yes or args.dry_run):
        parser.error("Agents must pass --yes (or --dry-run); input is never read from a pipe.")
    clean()
    remote = git("remote", "get-url", "origin")
    if remote not in ("git@github.com:justin-schroeder/liberator.git", "https://github.com/justin-schroeder/liberator.git", "https://github.com/justin-schroeder/liberator"):
        raise ValueError("origin must point to justin-schroeder/liberator.")
    git("fetch", "origin", "refs/heads/main:refs/remotes/origin/main", "--tags")
    head = git("rev-parse", "HEAD")
    if head != git("rev-parse", "refs/remotes/origin/main"):
        raise ValueError("Local main must exactly match origin/main. Push or reconcile commits first.")
    current = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
    choice = args.bump or input(f"Current version {current}. Bump [major/minor/patch/exact version]: ").strip()
    target = next_version(current, choice)
    tag = "v" + target
    for existing in git("tag", "--list", "v*").splitlines():
        if re.fullmatch("v" + VERSION_PATTERN, existing) and version(existing[1:]) >= version(target):
            raise ValueError(f"{tag} must be newer than existing tag {existing}.")
    available = {item["name"] for item in json.loads(run("gh", "secret", "list", "--repo", "justin-schroeder/liberator", "--json", "name"))}
    missing = sorted(SECRETS - available)
    print(f"Release {current} → {target}\nCommit version bump on main; atomically push main and {tag} to {remote}.", flush=True)
    if missing:
        print("Missing Actions secrets: " + ", ".join(missing), flush=True)
    if args.dry_run:
        print("Dry run complete. No working files, commits, tags, or remote refs changed. Tests/build not run.")
        return
    if missing:
        raise ValueError("Configure the release secrets documented in DEVELOPMENT.md before publishing.")
    if not args.yes and input("Build, validate, and publish this release? [y/N] ").strip().lower() not in ("y", "yes"):
        print("Cancelled.")
        return
    run("./test.sh", capture=False)
    run("./build.sh", "universal", capture=False, env={**os.environ, "RELEASE_VERSION": target})
    clean()
    if git("rev-parse", "HEAD") != head:
        raise ValueError("HEAD changed during validation; start again.")
    if git("ls-remote", "origin", "refs/heads/main").split()[0] != head:
        raise ValueError("origin/main changed during validation; synchronize and start again.")
    if git("ls-remote", "origin", "refs/tags/" + tag):
        raise ValueError("The release tag was created remotely during validation; start again.")
    path = ROOT / "Resources/Info.plist"
    original = path.read_text()
    updated, count = re.subn(r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)",
                            lambda m: m[1] + target + m[2], original)
    if count != 1:
        raise ValueError("Cannot locate exactly one bundle version.")
    path.write_text(updated)
    print("Creating release commit and annotated tag…", flush=True)
    git("add", "--", "Resources/Info.plist")
    git("commit", "-m", f"Release {tag}")
    git("tag", "-a", tag, "-m", f"Liberator {target}")
    try:
        run("git", "push", "--atomic", "origin", "HEAD:refs/heads/main", f"refs/tags/{tag}:refs/tags/{tag}", capture=False)
    except subprocess.CalledProcessError:
        print(f"Push failed; local release commit and {tag} were retained. Inspect remote state before retrying the atomic push. No force push was attempted.", file=sys.stderr)
        raise
    print(f"Release queued: https://github.com/justin-schroeder/liberator/actions\nDMG appears after signing and notarization succeed: https://github.com/justin-schroeder/liberator/releases/tag/{tag}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, OSError, EOFError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        sys.exit(1)
