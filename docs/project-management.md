# Project management

The [Project triage workflow](../.github/workflows/project-triage.yml) maintains
issue and PR metadata with GitHub Actions. It needs no installed app, paid
service, personal access token, or language model. Existing review bots and
ClickUp synchronization keep their own responsibilities.

The [Dependabot configuration](../.github/dependabot.yml) checks GitHub Actions
dependencies weekly on Monday at 02:00 Singapore time. It groups action updates
into a single PR, caps concurrent dependency PRs at two, and labels them
`dependencies` and `area: automation`. Updates still need review and merge;
there is no automatic merge. The Rust and app dependency sets are outside this
configuration. Dependabot starts after its configuration reaches the default
branch; repository dependency-update settings must allow it.

Useful queue views: [needs triage](https://github.com/MMFoundation/WallpaperMachine/issues?q=is%3Aopen+is%3Aissue+label%3A%22status%3A+needs-triage%22),
[issues with a PR](https://github.com/MMFoundation/WallpaperMachine/issues?q=is%3Aopen+is%3Aissue+label%3A%22status%3A+has-pr%22),
[blocked PRs](https://github.com/MMFoundation/WallpaperMachine/pulls?q=is%3Aopen+is%3Apr+label%3A%22status%3A+blocked%22),
and [ready PRs](https://github.com/MMFoundation/WallpaperMachine/pulls?q=is%3Aopen+is%3Apr+label%3A%22status%3A+ready%22).

## Areas and issue tracking

The optional **Area** field on both issue forms supplies an `area:` label. An
issue without an area gets `status: needs-triage`; a maintainer can add an area
label to finish that step. An existing area is preserved when the form changes.
PRs gain areas from their changed paths; manually added areas are preserved.

`status: has-pr` means an **open PR has a GitHub closing link to that open issue**.
Use `Fixes #123` or `Closes #123` when the whole issue will be resolved; GitHub's
manual development links also count when they are closing links. A plain
`Related: #123` reference does not count. The label disappears when the last
implementing PR closes or removes its closing link, and on closed issues.
Multiple PRs can implement one issue; cross-repository links are ignored.

Historical links to already closed issues appear in the run summary. The bot
does not turn partial fixes into closing links or decide which reports are
duplicates. It does not close issues, merge PRs, or assign priorities.

## PR readiness and DCO

Non-draft PRs get exactly one managed readiness label:

| Label | Meaning |
| --- | --- |
| `status: blocked` | Merge conflict, requested changes, unresolved current review thread, failed check/workflow/status, or missing DCO sign-off |
| `status: in-review` | No recorded blocker, but CI, mergeability, or approval on the current head is pending |
| `status: ready` | GitHub reports mergeable, a reviewer approved the current head, all reported checks are settled without failure, Python script tests passed on that head, and every commit has a DCO trailer |

Drafts have no readiness label. Outdated review threads alone do not block a
PR, but GitHub's outstanding `CHANGES_REQUESTED` decision still does. A skipped
check is not treated as a failure; the Python test check specifically must pass.
An `action_required` workflow is a blocker, even if a review bot's check is green.
Current-head approval deliberately becomes pending again after a new commit.

The **Project triage / DCO** commit status checks every PR commit for a final
`Signed-off-by: Name <email>` trailer. `Co-Authored-By:` or a trailer quoted in
the message body does not satisfy it. It checks the trailer format, not the
signer's identity or agreement, and never signs for a contributor or ticks the
PR's DCO checkbox. See [the contribution agreement](../CONTRIBUTING.md#license-and-sign-off).

Readiness is a navigation aid, not a replacement for review, the native gate,
manual verification, or a maintainer's merge decision. In particular, the bot
cannot establish that a native test result in a PR description covers its head.
The workflow is not added as a required branch-protection rule.

## Updates, preview and operation

Issue and PR changes, external check completions, and the completion of Checks,
Claude Code Review or Test reconcile the whole open queue. An hourly pass repairs
missed events, picks up review changes, and removes managed status labels from
closed items. GitHub may delay scheduled runs. Each run's Actions summary lists
the queue, closing links, and recorded prerequisites. There are no bot comments
or automatic reminders. Model-routing labels, author scores, and all labels
outside the managed status sets are preserved.

The workflow runs only code checked out from the default branch, including for
fork PRs. It reads GitHub API metadata; it never checks out PR code, downloads
workflow artifacts, or uses repository secrets beyond its scoped `GITHUB_TOKEN`.
Only labels and the bot's DCO commit status are written, with unchanged values
left alone. A PR whose head changes during a pass is deferred to the next run.

Preview locally with existing GitHub CLI authentication:

```sh
python3 scripts/project_triage.py --repo MMFoundation/WallpaperMachine
python3 scripts/tests/test_project_triage.py
```

Add `--apply` to write the planned metadata. The workflow's **Run workflow**
form also defaults to a preview; select **apply** to reconcile immediately.
The workflow must first be on the default branch to become active. Disable
**Project triage** in Actions to stop it; labels already present remain, and
its last DCO status remains attached to each checked commit.
