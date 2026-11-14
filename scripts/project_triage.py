#!/usr/bin/env python3
"""Maintain GitHub project labels and DCO status; preview unless --apply is given."""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from fnmatch import fnmatchcase
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import quote

from lib.glyphs import markers

MARK = markers()
DCO_CONTEXT = "Project triage / DCO"
PR_STATES = {"status: blocked", "status: in-review", "status: ready"}
ISSUE_STATES = {"status: has-pr", "status: needs-triage"}
AREA_CHOICES = {
    "Lock screen or screen saver": "lock-screen",
    "Playback or sound": "playback",
    "Displays or Spaces": "displays",
    "Scene wallpaper": "scene",
    "Web wallpaper": "web",
    "Settings": "settings",
    "Steam Workshop or downloads": "workshop",
}
AREA_PATHS = {
    "lock-screen": ("App/Services/LockScreen/*", "Extension/*", "Shared/LockScreen*",
                    "Tests/Unit/LockScreen/*", "docs/features/lock-screen.md"),
    "playback": ("App/Services/Audio/*", "App/Services/NativeVideo/*",
                 "App/Services/Desktop/Playback*", "App/Services/Desktop/WallpaperPresentation*",
                 "App/Services/Desktop/WallpaperCoverage*", "App/Services/Desktop/OtherAudio*",
                 "Tests/Unit/Desktop/Playback*", "docs/features/performance.md",
                 "docs/features/audio-response.md"),
    "displays": ("App/Services/Desktop/Display*", "App/Services/Desktop/SystemDisplays*",
                 "App/Services/Desktop/SystemWake*", "App/Services/Desktop/*Space*",
                 "App/Services/Desktop/*Mirror*", "App/Services/Desktop/DesktopWallpaper*",
                 "Renderer/Core/src/display/*", "Renderer/Bridge/src/display/*",
                 "docs/features/display-layouts.md", "docs/features/spaces.md",
                 "docs/features/desktop-picture.md"),
    "scene": ("Renderer/Engine/*", "Renderer/Shader/*", "docs/features/scene-rendering.md"),
    "web": ("App/Services/WebWallpaper/*", "Tests/Unit/WebWallpaper/*",
            "docs/features/web-wallpapers.md"),
    "settings": ("App/Views/ControlPanel/Settings/*", "Tests/Unit/Panel/*Settings*"),
    "workshop": ("App/Services/Steam/*", "App/Services/Workshop/*", "Tests/Unit/Steam/*",
                 "Tests/Unit/Workshop/*", "App/Views/ControlPanel/Downloads/*",
                 "App/Views/ControlPanel/Discover/*", "docs/features/workshop-downloads.md"),
    "automation": (".github/*", "scripts/*", "docs/project-management.md"),
}
LABELS = {f"area: {area}": ("1d76db", f"Project area: {area}") for area in AREA_PATHS}
LABELS.update({
    "status: has-pr": ("c2e0c6", "An open PR has a closing link to this issue"),
    "status: needs-triage": ("fbca04", "Open issue needs an area; select one or add an area label"),
    "status: blocked": ("b60205", "PR has a conflict, review finding, failed CI, or missing DCO sign-off"),
    "status: in-review": ("d4c5f9", "PR is awaiting review, CI, or GitHub's mergeability calculation"),
    "status: ready": ("0e8a16", "Current-head approval, passing reported checks and DCO; human merge decision"),
})


class GitHub:
    """Use gh's authentication, pagination and HTTP errors; never execute event text."""

    def call(self, path, *, method="GET", payload=None, paginate=False):
        command = ["gh", "api", path, "--method", method]
        if paginate:
            command += ["--paginate", "--slurp"]
        if payload is not None:
            command += ["--input", "-"]
        result = subprocess.run(command, input=json.dumps(payload) if payload is not None else None,
                                capture_output=True, text=True, check=True, timeout=120)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def items(self, path, key=None):
        pages = self.call(path, paginate=True)
        return [item for page in pages for item in (page[key] if key else page)]

    def graphql(self, query, **variables):
        result = self.call("graphql", method="POST", payload={"query": query, "variables": variables})
        if result.get("errors"):
            raise RuntimeError(f"GraphQL failed: {result['errors']}")
        return result["data"]["repository"]

    def connection(self, repo, name, selection, number=None):
        owner, repository = repo.split("/")
        root = f"pullRequest(number: {number})" if number is not None else ""
        # Names and selections are fixed by this program; cursors and repository names are variables.
        query = ("query($owner:String!,$name:String!,$cursor:String){repository(owner:$owner,name:$name){"
                 + (root + "{" if root else "") + name
                 + "(first:100,after:$cursor" + (",states:OPEN" if name == "pullRequests" else "")
                 + "){nodes{" + selection + "}pageInfo{hasNextPage endCursor}}"
                 + ("}" if root else "") + "}}")
        cursor, items = None, []
        while True:
            result = self.graphql(query, owner=owner, name=repository, cursor=cursor)
            connection = (result["pullRequest"] if root else result)[name]
            items += connection["nodes"]
            if not connection["pageInfo"]["hasNextPage"]:
                return items
            cursor = connection["pageInfo"]["endCursor"]


@dataclass
class Change:
    number: int
    title: str
    current: set[str]
    desired: set[str]
    reasons: list[str] = field(default_factory=list)
    head: str | None = None
    draft: bool | None = None
    dco: dict | None = None
    closing: list[int] = field(default_factory=list)
    deferred: bool = False

    @property
    def add(self):
        return self.desired - self.current

    @property
    def remove(self):
        return self.current - self.desired


def signed_off(message):
    """A DCO trailer must be in the final footer, not quoted in the message body."""
    paragraphs = message.rstrip().rsplit("\n\n", 1)
    if len(paragraphs) != 2:
        return False
    footer = paragraphs[-1].splitlines()
    if not all(re.fullmatch(r"[\w-]+:\s+.+", line) or line.startswith((" ", "\t")) for line in footer):
        return False
    for line in footer:
        match = re.fullmatch(r"Signed-off-by:\s+([^<>]+?)\s*<[^<>\s]+@[^<>\s]+>\s*", line, re.IGNORECASE)
        if match and match.group(1).strip():
            return True
    return False


def issue_area(body):
    section = re.search(r"^### Area\s*\n(.*?)(?=^### |\Z)", body or "", re.MULTILINE | re.DOTALL)
    area = AREA_CHOICES.get(section.group(1).strip()) if section else None
    return {f"area: {area}"} if area else set()


def file_areas(paths):
    return {f"area: {area}" for area, patterns in AREA_PATHS.items()
            if any(fnmatchcase(path, pattern) for path in paths for pattern in patterns)}


def issue_change(issue, linked):
    current = {label["name"] for label in issue["labels"]}
    desired = current - ISSUE_STATES
    if issue["state"] == "open":
        # An explicit maintainer area survives future edits to the form.
        if not any(label.startswith("area: ") for label in desired):
            desired |= issue_area(issue.get("body"))
        if issue["number"] in linked:
            desired.add("status: has-pr")
        elif not any(label.startswith("area: ") for label in desired):
            desired.add("status: needs-triage")
    return Change(issue["number"], issue["title"], current, desired,
                  closing=sorted(linked.get(issue["number"], [])))


def pr_change(pr, paths, commits, threads, checks, runs, statuses):
    current = {label["name"] for label in pr["labels"]["nodes"]}
    desired = (current - PR_STATES) | file_areas(paths)
    unsigned = [commit["oid"][:8] for commit in commits if not signed_off(commit["message"])]
    reasons, waiting = [], []
    if unsigned:
        reasons.append(f"Missing DCO sign-off: {', '.join(unsigned)}")
    if pr["mergeable"] == "CONFLICTING":
        reasons.append("Merge conflict")
    elif pr["mergeable"] != "MERGEABLE":
        waiting.append("Mergeability pending")
    if pr["reviewDecision"] == "CHANGES_REQUESTED":
        reasons.append("Changes requested")
    unresolved = sum(not thread["isResolved"] and not thread["isOutdated"] for thread in threads)
    if unresolved:
        reasons.append(f"{unresolved} unresolved current review thread(s)")
    approved = any(review["state"] == "APPROVED"
                   and (review.get("commit") or {}).get("oid") == pr["headRefOid"]
                   and (review.get("author") or {}).get("login")
                   and review["author"]["login"] != (pr.get("author") or {}).get("login")
                   for review in pr["latestReviews"]["nodes"])
    if not approved:
        waiting.append("Current-head approval pending")
    for check in checks:
        if check["status"] != "completed":
            waiting.append(f"Check pending: {check['name']}")
        elif check["conclusion"] not in {"success", "neutral", "skipped"}:
            reasons.append(f"Check {check['conclusion']}: {check['name']}")
    if not any(check["name"] == "Python script tests" and check["conclusion"] == "success"
               and check["status"] == "completed" for check in checks):
        waiting.append("Passing Python script tests not reported on this head")
    latest_runs = {}
    for run in runs:
        if run["name"] == "Project triage":
            continue
        key = (run.get("workflow_id", run["name"]), run.get("event"), run.get("head_branch"))
        if key not in latest_runs or (run.get("id", 0), run.get("run_attempt", 0)) > (
                latest_runs[key].get("id", 0), latest_runs[key].get("run_attempt", 0)):
            latest_runs[key] = run
    for run in latest_runs.values():
        if run["status"] != "completed":
            waiting.append(f"Workflow pending: {run['name']}")
        elif run["conclusion"] not in {"success", "neutral", "skipped"}:
            reasons.append(f"Workflow {run['conclusion']}: {run['name']}")
    for status in statuses:
        if status["context"] == DCO_CONTEXT:
            continue
        if status["state"] in {"error", "failure"}:
            reasons.append(f"Status {status['state']}: {status['context']}")
        elif status["state"] == "pending":
            waiting.append(f"Status pending: {status['context']}")
    if pr["isDraft"]:
        waiting.insert(0, "Draft")
    else:
        desired.add("status: blocked" if reasons else "status: in-review" if waiting else "status: ready")
    dco = {"context": DCO_CONTEXT, "state": "failure" if unsigned else "success",
           "description": (f"{len(unsigned)} commit(s) missing Signed-off-by" if unsigned
                           else f"All {len(commits)} commits have a DCO trailer")}
    return Change(pr["number"], pr["title"], current, desired,
                  list(dict.fromkeys(reasons + waiting)), head=pr["headRefOid"], draft=pr["isDraft"], dco=dco)


def collect(api, repo):
    prs = api.connection(repo, "pullRequests", """
        number title headRefOid isDraft mergeable reviewDecision author{login}
        labels(first:100){nodes{name}}
        latestReviews(first:100){nodes{state author{login} commit{oid}}}
    """)
    changes, linked = [], {}
    for pr in prs:
        number, sha = pr["number"], pr["headRefOid"]
        refs = api.connection(repo, "closingIssuesReferences", "number state repository{nameWithOwner}", number)
        for issue in refs:
            if issue["state"] == "OPEN" and issue["repository"]["nameWithOwner"].lower() == repo.lower():
                linked.setdefault(issue["number"], []).append(number)
        paths = [item["path"] for item in api.connection(repo, "files", "path", number)]
        commits = [item["commit"] for item in api.connection(repo, "commits", "commit{oid message}", number)]
        threads = api.connection(repo, "reviewThreads", "isResolved isOutdated", number)
        prefix = f"repos/{repo}"
        checks = api.items(f"{prefix}/commits/{sha}/check-runs?per_page=100&filter=latest", "check_runs")
        runs = api.items(f"{prefix}/actions/runs?head_sha={sha}&per_page=100", "workflow_runs")
        # The combined status endpoint returns the latest value of each context.
        statuses = api.items(f"{prefix}/commits/{sha}/status?per_page=100", "statuses")
        change = pr_change(pr, paths, commits, threads, checks, runs, statuses)
        closed_refs = [str(issue["number"]) for issue in refs
                       if issue["state"] == "CLOSED" and issue["repository"]["nameWithOwner"].lower() == repo.lower()]
        if closed_refs:
            change.reasons.append("Historical closing link(s) to closed issues: #" + ", #".join(closed_refs))
        changes.append(change)
    issues = {issue["number"]: issue for issue in api.items(f"repos/{repo}/issues?state=open&per_page=100")
              if "pull_request" not in issue}
    # Reconcile labels left on closed items even if their close event was missed.
    for label in sorted(PR_STATES | ISSUE_STATES):
        for item in api.items(f"repos/{repo}/issues?state=closed&per_page=100&labels={quote(label, safe='')}"):
            if "pull_request" in item:
                current = {entry["name"] for entry in item["labels"]}
                if not any(change.number == item["number"] for change in changes):
                    changes.append(Change(item["number"], item["title"], current, current - PR_STATES))
            else:
                issues[item["number"]] = item
    changes += [issue_change(issue, linked) for issue in issues.values()]
    return changes


def apply(api, repo, changes):
    existing = {label["name"] for label in api.items(f"repos/{repo}/labels?per_page=100")}
    for name in sorted(LABELS.keys() - existing):
        color, description = LABELS[name]
        api.call(f"repos/{repo}/labels", method="POST",
                 payload={"name": name, "color": color, "description": description})
    for change in changes:
        if change.head:
            latest = api.call(f"repos/{repo}/pulls/{change.number}")
            if (latest["state"] != "open" or latest["head"]["sha"] != change.head
                    or latest["draft"] != change.draft):
                change.deferred = True
                change.reasons.insert(0, "Deferred: PR changed during this pass")
                print(f"{MARK.warn} #{change.number} changed during triage; deferred to the next run")
                continue
            old = api.items(f"repos/{repo}/commits/{change.head}/status?per_page=100", "statuses")
            if not any(all(status.get(key) == value for key, value in change.dco.items()) for status in old):
                api.call(f"repos/{repo}/statuses/{change.head}", method="POST", payload=change.dco)
        if change.add:
            api.call(f"repos/{repo}/issues/{change.number}/labels", method="POST",
                     payload={"labels": sorted(change.add)})
        for label in sorted(change.remove):
            api.call(f"repos/{repo}/issues/{change.number}/labels/{quote(label, safe='')}", method="DELETE")


def report(repo, changes):
    def cell(text):
        # Avoid table injection and accidental @mentions in Actions summaries.
        text = str(text).replace("&", "&amp;").replace("<", "&lt;").replace("|", "&#124;").replace("@", "&#64;").replace("\n", " ")
        return text.replace("[", "\\[").replace("]", "\\]").replace("`", "\\`")
    lines = ["# Project triage", "", "Labels describe recorded GitHub state, not a native/visual verification or permission to merge.",
             "", "| Item | Area | Status | Closing PRs / prerequisites |", "| --- | --- | --- | --- |"]
    for change in sorted(changes, key=lambda item: item.number, reverse=True):
        areas = ", ".join(sorted(label.removeprefix("area: ") for label in change.desired if label.startswith("area: "))) or "—"
        status = "deferred" if change.deferred else ", ".join(sorted(change.desired & (PR_STATES | ISSUE_STATES))) or "—"
        details = "; ".join(change.reasons) or ", ".join(f"#{number}" for number in change.closing) or "—"
        lines.append(f"| [#{change.number}](https://github.com/{repo}/issues/{change.number}) {cell(change.title)} | {cell(areas)} | {status} | {cell(details)} |")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"), help="GitHub owner/repository")
    parser.add_argument("--apply", action="store_true", help="Write labels and DCO statuses (default: read-only preview)")
    parser.add_argument("--summary", type=Path, help="Write the Markdown report to this path")
    args = parser.parse_args()
    if not args.repo or not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repo, re.ASCII):
        parser.error("--repo owner/repository or GITHUB_REPOSITORY is required")
    api = GitHub()
    try:
        changes = collect(api, args.repo)
        if args.apply:
            apply(api, args.repo, changes)
        summary = report(args.repo, changes)
        print(summary)
        if args.summary:
            args.summary.write_text(summary, encoding="utf-8")
        print(f"{MARK.ok} {'Applied' if args.apply else 'Previewed'} triage for {len(changes)} items")
        return 0
    except (subprocess.SubprocessError, RuntimeError, KeyError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        print(f"{MARK.missing} Project triage failed: {detail}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
