#!/usr/bin/env python3
"""Behavior tests for project triage; no network or GitHub writes."""
from __future__ import annotations

import copy
from pathlib import Path
import sys
import unittest
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import project_triage as triage

REPO = "example/wallpaper"
HEAD = "a" * 40
SIGNED = "fix: preserve wallpapers\n\nSigned-off-by: A Developer <dev@example.org>\n"


def issue(number=1, labels=(), state="open", body=""):
    return {"number": number, "title": "Wallpaper problem", "state": state, "body": body,
            "labels": [{"name": label} for label in labels]}


def pr(number=2, **overrides):
    result = {"number": number, "title": "fix: preserve wallpapers", "headRefOid": HEAD,
              "isDraft": False, "mergeable": "MERGEABLE", "reviewDecision": "APPROVED",
              "author": {"login": "contributor"}, "labels": {"nodes": []},
              "latestReviews": {"nodes": [{"state": "APPROVED", "author": {"login": "maintainer"},
                                           "commit": {"oid": HEAD}}]}}
    result.update(overrides)
    return result


def ready_change(pull=None, **overrides):
    args = {"paths": [], "commits": [{"oid": HEAD, "message": SIGNED}], "threads": [],
            "checks": [{"name": "Python script tests", "status": "completed", "conclusion": "success"}],
            "runs": [], "statuses": []}
    args.update(overrides)
    return triage.pr_change(pull or pr(), **args)


class MemoryGitHub:
    """A mutable metadata store, including changes made concurrently by maintainers."""

    def __init__(self, pulls=(), issues=()):
        self.pulls = {pull["number"]: copy.deepcopy(pull) for pull in pulls}
        self.issues = {entry["number"]: copy.deepcopy(entry) for entry in issues}
        self.labels = set(triage.LABELS)
        self.commit_statuses = []
        self.refs = {}
        self.pr_state = "open"
        for pull in pulls:
            self.issues[pull["number"]] = issue(pull["number"], [label["name"] for label in pull["labels"]["nodes"]])
            self.issues[pull["number"]]["pull_request"] = {}

    def connection(self, repo, name, selection, number=None):
        if name == "pullRequests":
            return list(self.pulls.values())
        return {"closingIssuesReferences": self.refs.get(number, []), "files": [],
                "commits": [{"commit": {"oid": HEAD, "message": SIGNED}}],
                "reviewThreads": []}[name]

    def items(self, path, key=None):
        if "/check-runs?" in path:
            return [{"name": "Python script tests", "status": "completed", "conclusion": "success"}]
        if "/actions/runs?" in path:
            return []
        if "/commits/" in path:
            return copy.deepcopy(self.commit_statuses)
        if path.endswith("/labels?per_page=100"):
            return [{"name": name} for name in self.labels]
        if "state=closed" in path:
            label = unquote(path.split("labels=")[1])
            return [entry for entry in self.issues.values() if entry["state"] == "closed"
                    and label in {item["name"] for item in entry["labels"]}]
        return [entry for entry in self.issues.values() if entry["state"] == "open"]

    def call(self, path, *, method="GET", payload=None):
        if "/pulls/" in path:
            pull = self.pulls[int(path.rsplit("/", 1)[1])]
            return {"state": self.pr_state, "draft": pull["isDraft"], "head": {"sha": pull["headRefOid"]}}
        if path.endswith("/labels") and "/issues/" not in path:
            self.labels.add(payload["name"])
        elif "/statuses/" in path:
            self.commit_statuses = [copy.deepcopy(payload)]
        else:
            number = int(path.split("/issues/")[1].split("/")[0])
            labels = {entry["name"] for entry in self.issues[number]["labels"]}
            if method == "POST":
                labels |= set(payload["labels"])
            elif method == "DELETE":
                labels.remove(unquote(path.rsplit("/", 1)[1]))
            self.issues[number]["labels"] = [{"name": name} for name in labels]


class SignoffTests(unittest.TestCase):
    def test_valid_footer_with_coauthor_and_case_variation(self):
        self.assertTrue(triage.signed_off(SIGNED))
        self.assertTrue(triage.signed_off(SIGNED.rstrip() + "\nCo-Authored-By: Other <other@example.org>\n"))
        self.assertTrue(triage.signed_off(SIGNED.replace("Signed-off-by", "signed-off-by")))

    def test_coauthor_quoted_body_and_invalid_identity_do_not_certify(self):
        for message in [SIGNED.replace("Signed-off-by", "Co-Authored-By"),
                        SIGNED + "\nThis quotes an earlier footer.\n",
                        "fix: example\n\nFor example:\nSigned-off-by: Other <other@example.org>",
                        SIGNED.replace("A Developer", " "), SIGNED.replace("dev@example.org", "invalid")]:
            with self.subTest(message=message):
                self.assertFalse(triage.signed_off(message))


class ClassificationTests(unittest.TestCase):
    def test_form_area_resolves_triage_but_unknown_area_needs_a_person(self):
        change = triage.issue_change(issue(labels=["status: needs-triage"], body="### Area\n\nSettings\n\n### What happened\n\nslow"), {})
        self.assertEqual(change.desired, {"area: settings"})
        self.assertIn("status: needs-triage", triage.issue_change(issue(body="### Area\n\nNot sure / other"), {}).desired)

    def test_existing_area_and_unmanaged_labels_survive_form_edits(self):
        change = triage.issue_change(issue(labels=["area: scene", "Opus", "review: low"], body="### Area\n\nSettings"), {})
        self.assertEqual(change.desired, {"area: scene", "Opus", "review: low"})

    def test_removing_last_pr_clears_has_pr_without_clearing_manual_area(self):
        change = triage.issue_change(issue(labels=["area: playback", "status: has-pr"]), {})
        self.assertEqual(change.desired, {"area: playback"})
        self.assertIn("status: has-pr", triage.issue_change(issue(), {1: [2, 3]}).desired)

    def test_closed_issue_loses_managed_tracking_labels(self):
        change = triage.issue_change(issue(labels=["bug", "status: has-pr"], state="closed"), {1: [2]})
        self.assertEqual(change.desired, {"bug"})

    def test_paths_can_add_multiple_areas(self):
        areas = triage.file_areas(["Extension/WallpaperController.swift", "App/Services/Desktop/PlaybackPreferences.swift", ".github/workflows/checks.yml"])
        self.assertEqual(areas, {"area: lock-screen", "area: playback", "area: automation"})

    def test_only_local_open_closing_links_mark_issues_as_implemented(self):
        api = MemoryGitHub([pr()], [issue(1), issue(3), issue(4)])
        api.refs[2] = [{"number": 1, "state": "OPEN", "repository": {"nameWithOwner": REPO}},
                       {"number": 3, "state": "CLOSED", "repository": {"nameWithOwner": REPO}},
                       {"number": 4, "state": "OPEN", "repository": {"nameWithOwner": "elsewhere/repo"}}]
        changes = {change.number: change for change in triage.collect(api, REPO)}
        self.assertIn("status: has-pr", changes[1].desired)
        self.assertNotIn("status: has-pr", changes[3].desired)
        self.assertNotIn("status: has-pr", changes[4].desired)
        self.assertTrue(any("closed issues: #3" in reason for reason in changes[2].reasons))

    def test_closed_pr_cleanup_recovers_a_missed_close_event(self):
        closed = issue(7, ["area: scene", "status: blocked"], "closed")
        closed["pull_request"] = {}
        changes = triage.collect(MemoryGitHub(issues=[closed]), REPO)
        self.assertEqual(len(changes), 1)
        self.assertEqual(changes[0].desired, {"area: scene"})


class ReadinessTests(unittest.TestCase):
    def test_complete_current_head_can_be_ready(self):
        change = ready_change()
        self.assertEqual(change.desired & triage.PR_STATES, {"status: ready"})
        self.assertEqual(change.dco["state"], "success")

    def test_action_required_is_a_blocker_even_with_green_checks(self):
        change = ready_change(runs=[{"name": "Checks", "status": "completed", "conclusion": "action_required"}])
        self.assertIn("status: blocked", change.desired)
        self.assertTrue(any("action_required" in reason for reason in change.reasons))

    def test_old_approval_does_not_approve_a_new_head(self):
        pull = pr()
        pull["latestReviews"]["nodes"][0]["commit"]["oid"] = "old-head"
        self.assertIn("status: in-review", ready_change(pull).desired)

    def test_self_approval_does_not_count(self):
        pull = pr()
        pull["latestReviews"]["nodes"][0]["author"]["login"] = "contributor"
        self.assertIn("status: in-review", ready_change(pull).desired)

    def test_conflict_requested_changes_and_current_threads_block(self):
        for changes in [{"pull": pr(mergeable="CONFLICTING")}, {"pull": pr(reviewDecision="CHANGES_REQUESTED")},
                        {"threads": [{"isResolved": False, "isOutdated": False}]}]:
            with self.subTest(changes=changes):
                self.assertIn("status: blocked", ready_change(**changes).desired)
        self.assertIn("status: ready", ready_change(threads=[{"isResolved": False, "isOutdated": True}]).desired)

    def test_waits_for_python_pass_and_all_pending_checks(self):
        for checks in [[], [{"name": "Python script tests", "status": "completed", "conclusion": "skipped"}],
                       [{"name": "Python script tests", "status": "in_progress", "conclusion": None}]]:
            self.assertIn("status: in-review", ready_change(checks=checks).desired)

    def test_failed_check_and_unsigned_commit_block(self):
        change = ready_change(commits=[{"oid": HEAD, "message": "fix: missing footer"}])
        self.assertIn("status: blocked", change.desired)
        self.assertEqual(change.dco["state"], "failure")
        self.assertIn("status: blocked", ready_change(checks=[{"name": "Python script tests", "status": "completed", "conclusion": "failure"}]).desired)

    def test_new_success_replaces_old_cancelled_workflow_and_ignores_itself(self):
        runs = [{"id": 2, "workflow_id": 10, "name": "Checks", "status": "completed", "conclusion": "success"},
                {"id": 1, "workflow_id": 10, "name": "Checks", "status": "completed", "conclusion": "cancelled"},
                {"name": "Project triage", "status": "in_progress", "conclusion": None}]
        self.assertIn("status: ready", ready_change(runs=runs).desired)

    def test_own_old_dco_failure_does_not_block_after_signoff_fix(self):
        self.assertIn("status: ready", ready_change(statuses=[{"context": triage.DCO_CONTEXT, "state": "failure"}]).desired)
        self.assertIn("status: blocked", ready_change(statuses=[{"context": "Other test", "state": "failure"}]).desired)

    def test_draft_clears_readiness_without_certifying_missing_dco(self):
        pull = pr(isDraft=True, labels={"nodes": [{"name": "status: ready"}, {"name": "Opus"}]})
        change = ready_change(pull, commits=[{"oid": HEAD, "message": "unsigned"}])
        self.assertEqual(change.desired, {"Opus"})
        self.assertEqual(change.dco["state"], "failure")


class ApplyTests(unittest.TestCase):
    def test_first_run_creates_the_taxonomy_even_with_an_empty_queue(self):
        api = MemoryGitHub()
        api.labels.clear()
        triage.apply(api, REPO, [])
        self.assertEqual(api.labels, set(triage.LABELS))

    def test_additive_edits_preserve_concurrent_unmanaged_labels(self):
        api = MemoryGitHub([pr()], [issue(1, ["status: needs-triage"])])
        change = triage.issue_change(api.issues[1], {1: [2]})
        api.issues[1]["labels"].append({"name": "Sonnet"})
        triage.apply(api, REPO, [change])
        self.assertEqual({entry["name"] for entry in api.issues[1]["labels"]}, {"status: has-pr", "Sonnet"})

    def test_second_pass_is_idle_and_keeps_unmanaged_labels(self):
        api = MemoryGitHub([pr(labels={"nodes": [{"name": "Sonnet"}]})])
        change = ready_change(api.pulls[2])
        triage.apply(api, REPO, [change])
        first = copy.deepcopy((api.issues, api.commit_statuses))
        api.pulls[2]["labels"]["nodes"] = copy.deepcopy(api.issues[2]["labels"])
        triage.apply(api, REPO, [ready_change(api.pulls[2])])
        self.assertEqual((api.issues, api.commit_statuses), first)

    def test_changed_head_draft_or_closed_state_defers_stale_result(self):
        for mutation in ["head", "draft", "closed"]:
            with self.subTest(mutation=mutation):
                api = MemoryGitHub([pr()])
                change = ready_change(api.pulls[2])
                if mutation == "head":
                    api.pulls[2]["headRefOid"] = "new-head"
                elif mutation == "draft":
                    api.pulls[2]["isDraft"] = True
                else:
                    api.pr_state = "closed"
                triage.apply(api, REPO, [change])
                self.assertEqual(api.commit_statuses, [])
                self.assertEqual(api.issues[2]["labels"], [])
                self.assertIn("| deferred |", triage.report(REPO, [change]))

    def test_report_cannot_turn_title_into_an_image_mention_or_table_row(self):
        change = triage.issue_change(issue(body="", labels=[]), {})
        change.title = "![image](https://example.org/x) | @person\n<script>"
        report = triage.report(REPO, [change])
        self.assertNotIn("![image]", report)
        self.assertNotIn("@person", report)
        self.assertNotIn("<script>", report)
        self.assertEqual(len([line for line in report.splitlines() if line.startswith("| ")]), 3)


if __name__ == "__main__":
    unittest.main()
