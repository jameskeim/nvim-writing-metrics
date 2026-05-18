# Plan J — Drift Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile workspace drift between `~/.config/nvim/` and `~/projects/nvim-writing-metrics/` so that switching working directories doesn't lose context. Moves the spec/plan history into the project repo, fixes stale CLAUDE.md claims, promotes universal feedback memory to the user-level CLAUDE.md, and replaces the old spec location with a symlink for dual-access.

**Architecture:** Five sequential actions across three locations (project git repo, nvim config dir, user-level Claude config). Two commits in the project repo. The remaining actions operate on unversioned files with careful gating and a symlink for backward compatibility.

**Tech Stack:** Bash for file operations and verification. Read/Edit/Write tools for content changes. Git for the two project-repo commits.

**Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-18-plan-j-drift-reconciliation-design.md` (this file moves to `~/projects/nvim-writing-metrics/docs/superpowers/specs/` during Task 1)

---

## File Map

```
Files modified or created:

~/projects/nvim-writing-metrics/
├── docs/
│   └── superpowers/         ← CREATED (Task 1)
│       ├── specs/           ← CREATED + populated from ~/.config/nvim/...
│       └── plans/           ← CREATED + populated from ~/.config/nvim/...
└── CLAUDE.md                ← MODIFIED (Task 2): 4 edits

~/.config/nvim/
└── docs/
    └── superpowers/         ← DELETED then REPLACED with symlink (Task 3)

~/.claude/
└── CLAUDE.md                ← MODIFIED (Task 4): empty → populated with feedback content

~/.claude/projects/-home-jkeim--config-nvim/memory/
├── feedback_brainstorming_pace.md   ← DELETED (Task 5)
└── MEMORY.md                         ← MODIFIED (Task 5): one line removed
```

No code, no tests, no build artifacts.

---

## Task 1: Move specs and plans into the project repo

**Files:**
- Create: `~/projects/nvim-writing-metrics/docs/superpowers/specs/` (directory)
- Create: `~/projects/nvim-writing-metrics/docs/superpowers/plans/` (directory)
- Copy from: `~/.config/nvim/docs/superpowers/specs/*.md`
- Copy from: `~/.config/nvim/docs/superpowers/plans/*.md`
- Commit: `~/projects/nvim-writing-metrics/` (one commit)

- [ ] **Step 1.1: Capture the current file counts at the source**

Run:
```bash
ls ~/.config/nvim/docs/superpowers/specs/ | wc -l
ls ~/.config/nvim/docs/superpowers/plans/ | wc -l
```

Record both numbers. You'll use them in Step 1.4 to verify the copy was complete. As of plan-writing time, expect roughly 8 specs and 11 plans (the count includes this plan and the Plan J design spec).

- [ ] **Step 1.2: Create the target directories**

Run:
```bash
mkdir -p ~/projects/nvim-writing-metrics/docs/superpowers/{specs,plans}
```

Verify:
```bash
ls -d ~/projects/nvim-writing-metrics/docs/superpowers/specs ~/projects/nvim-writing-metrics/docs/superpowers/plans
```

Expected: both directories listed.

- [ ] **Step 1.3: Copy all markdown files with mtimes preserved**

Run:
```bash
cp -p ~/.config/nvim/docs/superpowers/specs/*.md ~/projects/nvim-writing-metrics/docs/superpowers/specs/
cp -p ~/.config/nvim/docs/superpowers/plans/*.md ~/projects/nvim-writing-metrics/docs/superpowers/plans/
```

The `-p` flag preserves the modification times — these are used by some tooling for "what's recent" ordering.

- [ ] **Step 1.4: Verify file counts match**

Run:
```bash
echo "Source specs: $(ls ~/.config/nvim/docs/superpowers/specs/ | wc -l)"
echo "Target specs: $(ls ~/projects/nvim-writing-metrics/docs/superpowers/specs/ | wc -l)"
echo "Source plans: $(ls ~/.config/nvim/docs/superpowers/plans/ | wc -l)"
echo "Target plans: $(ls ~/projects/nvim-writing-metrics/docs/superpowers/plans/ | wc -l)"
```

Expected: source and target counts match for both specs and plans.

If they don't match, STOP. Investigate before proceeding. Possible cause: a hidden dotfile or non-`.md` file in the source dir that the glob skipped — review with `ls -la <source>` and decide whether it should be copied.

- [ ] **Step 1.5: Verify byte-for-byte equality**

Run:
```bash
diff -r ~/.config/nvim/docs/superpowers/ ~/projects/nvim-writing-metrics/docs/superpowers/
```

Expected: no output at all.

If `diff -r` reports any difference, STOP. Possible causes: a file failed to copy, a hidden file exists only on one side, permissions issue. Investigate and re-run Step 1.3 if needed.

- [ ] **Step 1.6: Stage the new files**

Run:
```bash
cd ~/projects/nvim-writing-metrics
git status
git add docs/superpowers/
git status
```

Expected on first `git status`: untracked files under `docs/superpowers/`. Expected on second: those files now staged.

- [ ] **Step 1.7: Commit**

Run from `~/projects/nvim-writing-metrics/`:
```bash
git commit -m "$(cat <<'EOF'
docs: import design specs and implementation plans

Imports the spec/plan markdown files that documented Plans A
through J from their previous unversioned home at
~/.config/nvim/docs/superpowers/. Specs and plans now live next
to the code they describe, with proper version control.

Each spec corresponds to one Plan letter; each Plan letter
corresponds to one commit on main.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Verify:
```bash
git log -1 --stat
```

Expected: one new commit on top of HEAD, showing all the .md files under `docs/superpowers/` as additions.

- [ ] **Step 1.8: Do NOT delete originals yet**

The originals at `~/.config/nvim/docs/superpowers/` remain untouched until Task 3. This preserves the rollback path: if anything in Task 2 goes wrong, reverting the Task 1 commit cleanly restores the pre-Plan-J state with the originals still in place.

---

## Task 2: Update project CLAUDE.md

**Files:**
- Modify: `~/projects/nvim-writing-metrics/CLAUDE.md` (4 edits)
- Commit: `~/projects/nvim-writing-metrics/` (one commit)

- [ ] **Step 2.1: Verify the current test count before editing B3**

The B3 edit needs the live test-suite figures. Run from `~/projects/nvim-writing-metrics/`:
```bash
./run-tests.sh 2>&1 | tail -10
ls tests/*_spec.lua | wc -l
```

Record:
- The number of passing tests (expect 118)
- The number of failing tests (expect 0)
- The number of `_spec.lua` files (expect 9)

These figures replace the stale `106 test cases across 6 test files` in Step 2.4. If your numbers differ from the expected, use your actual numbers — the docs should reflect reality.

- [ ] **Step 2.2: Edit B1 — Add `commands.lua` to the Module Structure list**

Read `~/projects/nvim-writing-metrics/CLAUDE.md` around lines 20-27 to confirm the current list.

Apply this Edit:

**old_string:**
```
- `utils.lua` - Shared utilities (Pandoc execution, file I/O, formatting, notifications)
- `display.lua` - Report formatting and buffer management
```

**new_string:**
```
- `utils.lua` - Shared utilities (Pandoc execution, file I/O, formatting, notifications)
- `commands.lua` - User command registration; called from init.lua's setup() (idempotent)
- `display.lua` - Report formatting and buffer management
```

- [ ] **Step 2.3: Edit B2 — Update `_G.accurate_wordcount` description**

Read around line 75 to confirm the current text.

Apply this Edit:

**old_string:**
```
- Global `_G.accurate_wordcount` table with old API
```

**new_string:**
```
- Global `_G.accurate_wordcount` callable table — `_G.accurate_wordcount()` returns the cached word count (function shape), `_G.accurate_wordcount.<method>(bufnr)` exposes basic-module methods (table shape). Both contracts preserved from the prior `accurate_wordcount.lua` plugin.
```

- [ ] **Step 2.4: Edit B3 — Update the test count claim**

Read around line 83 to confirm the current text.

Apply this Edit, substituting the figures you recorded in Step 2.1:

**old_string:**
```
The test suite uses plenary.nvim with 106 test cases across 6 test files.
```

**new_string** (substitute actual numbers — example uses the expected 118/0/9):
```
The test suite uses plenary.nvim with 118 test cases across 9 test files (118 passing, 0 failing after Plan H).
```

If your recorded figures from Step 2.1 differ, use them. The structure of the new sentence is: `with <total> test cases across <file-count> test files (<passing> passing, <failing> failing after Plan H)`.

- [ ] **Step 2.5: Edit B4 — Insert the Plan History section**

This is a new section, inserted between the existing `## Backward Compatibility` section (ends around line 78) and `## Development Commands` (starts around line 79). Read those two sections to find the exact transition.

The end of Backward Compatibility currently looks like (around lines 76-78):
```
- Command aliases: `:AccurateWordCount` → `:WordCount`, `:ToggleWordCountMode` → `:WritingMetricsToggle`
- Legacy lualine integration functions

## Development Commands
```

Apply this Edit:

**old_string:**
```
- Legacy lualine integration functions

## Development Commands
```

**new_string:**
```
- Legacy lualine integration functions

## Plan History

The plugin has a per-feature design-spec history under `docs/superpowers/specs/` and implementation plans under `docs/superpowers/plans/`. Each spec corresponds to a single Plan (letter-named: A, B, C, ...) and to one commit on `main`.

Use `git log --oneline` to find which commit shipped a given plan, or read the spec files directly for the design rationale.

## Development Commands
```

- [ ] **Step 2.6: Verify all four edits applied**

Run from `~/projects/nvim-writing-metrics/`:
```bash
grep -n "commands.lua" CLAUDE.md
grep -n "callable table" CLAUDE.md
grep -n "Plan H" CLAUDE.md
grep -n "Plan History" CLAUDE.md
```

Expected: at least one match for each grep.

Also verify the stale strings are gone:
```bash
grep -n "106 test cases" CLAUDE.md && echo "FAIL: stale" || echo "OK: gone"
grep -n "table with old API" CLAUDE.md && echo "FAIL: stale" || echo "OK: gone"
```

Both should print "OK: gone".

- [ ] **Step 2.7: Review the diff**

Run:
```bash
git diff CLAUDE.md
```

Expected: only the four edits visible. No unrelated changes. Sanity-check that the surrounding context didn't get mangled by any Edit operation.

- [ ] **Step 2.8: Stage and commit**

Run from `~/projects/nvim-writing-metrics/`:
```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(CLAUDE): fix stale claims + add Plan History pointer

Closes drift identified during Plan I review:
- Adds commands.lua to the Module Structure list (Plan F extracted
  this module; CLAUDE.md missed the update)
- Updates _G.accurate_wordcount description to reflect the
  callable-table contract (Plan F)
- Updates test count to current state (Plan H: 118/0, was 106/6)
- Adds Plan History section pointing readers at docs/superpowers/
  for design context

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Verify:
```bash
git log -2 --oneline
```

Expected: two new commits on top of where you started, one for the import (Task 1) and one for this CLAUDE.md update.

---

## Task 3: Delete originals and replace with symlink

**Files:**
- Delete: `~/.config/nvim/docs/superpowers/` (entire directory)
- Create (symlink): `~/.config/nvim/docs/superpowers` → `~/projects/nvim-writing-metrics/docs/superpowers`

- [ ] **Step 3.1: Confirm Tasks 1 and 2 commits exist locally**

Run from `~/projects/nvim-writing-metrics/`:
```bash
git log --oneline -2
```

Expected output should include:
- A `docs(CLAUDE):` commit at HEAD (from Task 2.8)
- A `docs:` import commit at HEAD~1 (from Task 1.7)

If either is missing, STOP. Re-run the missing task before proceeding to Task 3.2.

- [ ] **Step 3.2: Paranoia byte-equal check (the deletion gate)**

Run:
```bash
diff -r ~/.config/nvim/docs/superpowers/ ~/projects/nvim-writing-metrics/docs/superpowers/
```

Expected: no output.

If `diff -r` reports ANY difference, STOP. Do not proceed to Step 3.3. Investigate:
- Did something modify a file in the source dir between Task 1 and now?
- Is there an extra file in source or target that wasn't there during the original copy?

Only after `diff -r` is clean do you have the safe-to-delete signal.

- [ ] **Step 3.3: Delete and symlink in one atomic shell invocation**

Run this as a single chained command — the `&&` ensures the symlink is created immediately after the deletion, leaving no window where the path exists in neither form:

```bash
rm -rf ~/.config/nvim/docs/superpowers/ && ln -s ~/projects/nvim-writing-metrics/docs/superpowers ~/.config/nvim/docs/superpowers
```

If `rm` succeeds but `ln -s` fails (e.g., target dir doesn't exist for some reason), recreate the symlink manually:
```bash
ln -s ~/projects/nvim-writing-metrics/docs/superpowers ~/.config/nvim/docs/superpowers
```

- [ ] **Step 3.4: Verify the symlink**

Run:
```bash
readlink ~/.config/nvim/docs/superpowers
```

Expected: prints `/home/jkeim/projects/nvim-writing-metrics/docs/superpowers` (or a similar absolute path that resolves correctly).

Then verify directory listings are identical via both paths:
```bash
ls ~/.config/nvim/docs/superpowers/specs/ | sort > /tmp/via_symlink.txt
ls ~/projects/nvim-writing-metrics/docs/superpowers/specs/ | sort > /tmp/via_direct.txt
diff /tmp/via_symlink.txt /tmp/via_direct.txt
rm /tmp/via_symlink.txt /tmp/via_direct.txt
```

Expected: `diff` produces no output.

- [ ] **Step 3.5: Content spot-check through the symlink**

Confirm the content read through the symlink matches the content at the canonical location:
```bash
diff <(cat ~/.config/nvim/docs/superpowers/specs/2026-05-18-plan-j-drift-reconciliation-design.md) \
     <(cat ~/projects/nvim-writing-metrics/docs/superpowers/specs/2026-05-18-plan-j-drift-reconciliation-design.md)
```

Expected: no output (identical content via two paths).

---

## Task 4: Promote brainstorming-pace memory to user-level CLAUDE.md

**Files:**
- Modify: `~/.claude/CLAUDE.md` (currently 0 bytes per the brainstorm probe)

- [ ] **Step 4.1: Confirm `~/.claude/CLAUDE.md` is still empty**

Run:
```bash
wc -c ~/.claude/CLAUDE.md
```

Expected: `0 /home/jkeim/.claude/CLAUDE.md`.

If the file has content (someone or something has written to it since the brainstorm probe), DO NOT overwrite. Instead, append the new content to the existing file using Edit with the existing tail as the anchor. The remaining steps assume an empty file — if it's not empty, mentally adjust accordingly.

- [ ] **Step 4.2: Write the brainstorming-pace content**

Use the Write tool against `~/.claude/CLAUDE.md` with this exact content:

```markdown
# Collaboration preferences

## Brainstorming pace

When brainstorming a plan, ask substantive design-tradeoff questions (rename direction, contract shape, API choice, scope boundary with clear tradeoffs) and skip meta-process questions (audit-first vs design-first, single plan vs multi-plan, fold X into Y). On scope/process decisions, make the recommendation and execute.

- **Substantive (ask):** rename direction, contract shape, API choice, behavior change, scope boundary that has clear tradeoffs the user is best-placed to weigh
- **Process (recommend, don't ask):** whether to audit before designing, whether to split into multiple plans, whether to fold X into Y, cadence of review

For process decisions, state the recommendation in one sentence and execute. If the user prefers a different path, they'll redirect — but the default is "you make the call, I proceed."
```

- [ ] **Step 4.3: Verify content written**

Run:
```bash
wc -l ~/.claude/CLAUDE.md
cat ~/.claude/CLAUDE.md
```

Expected: file is no longer empty; content matches what was written in Step 4.2.

---

## Task 5: Remove promoted memory from project memory dir

**Files:**
- Delete: `~/.claude/projects/-home-jkeim--config-nvim/memory/feedback_brainstorming_pace.md`
- Modify: `~/.claude/projects/-home-jkeim--config-nvim/memory/MEMORY.md` (remove one line)

- [ ] **Step 5.1: Confirm the file to delete exists**

Run:
```bash
ls -la ~/.claude/projects/-home-jkeim--config-nvim/memory/feedback_brainstorming_pace.md
```

Expected: file listed with non-zero size.

If the file doesn't exist (already deleted), skip Step 5.2 but still complete Step 5.3 to remove any stale MEMORY.md entry.

- [ ] **Step 5.2: Delete the memory file**

Run:
```bash
rm ~/.claude/projects/-home-jkeim--config-nvim/memory/feedback_brainstorming_pace.md
```

Verify deletion:
```bash
ls ~/.claude/projects/-home-jkeim--config-nvim/memory/feedback_brainstorming_pace.md 2>&1
```

Expected: error like "No such file or directory" (or equivalent for your `ls`).

- [ ] **Step 5.3: Remove the index entry from MEMORY.md**

Read `~/.claude/projects/-home-jkeim--config-nvim/memory/MEMORY.md` to confirm current content.

Expected current content:
```
- [Brainstorming pace: substantive vs process questions](feedback_brainstorming_pace.md) — ask design tradeoffs; for sequencing/scope decisions, recommend and proceed
- [nvim-text-sharing: extracted plugin location, prior audit items closed](project_nvim_text_sharing_known_issues.md) — lives at ~/projects/nvim-text-sharing/ loaded via lazy dir spec; HTTP-server stale state and os.tmpname race FIXED by Plan D
```

Apply this Edit on `~/.claude/projects/-home-jkeim--config-nvim/memory/MEMORY.md`:

**old_string:**
```
- [Brainstorming pace: substantive vs process questions](feedback_brainstorming_pace.md) — ask design tradeoffs; for sequencing/scope decisions, recommend and proceed
- [nvim-text-sharing: extracted plugin location, prior audit items closed](project_nvim_text_sharing_known_issues.md) — lives at ~/projects/nvim-text-sharing/ loaded via lazy dir spec; HTTP-server stale state and os.tmpname race FIXED by Plan D
```

**new_string:**
```
- [nvim-text-sharing: extracted plugin location, prior audit items closed](project_nvim_text_sharing_known_issues.md) — lives at ~/projects/nvim-text-sharing/ loaded via lazy dir spec; HTTP-server stale state and os.tmpname race FIXED by Plan D
```

- [ ] **Step 5.4: Verify MEMORY.md**

Run:
```bash
cat ~/.claude/projects/-home-jkeim--config-nvim/memory/MEMORY.md
```

Expected: only the nvim-text-sharing line remains. The brainstorming-pace line is gone.

Also verify the memory directory:
```bash
ls ~/.claude/projects/-home-jkeim--config-nvim/memory/
```

Expected: `MEMORY.md` and `project_nvim_text_sharing_known_issues.md` listed; `feedback_brainstorming_pace.md` NOT listed.

---

## Task 6: Final integration verification

**Files:**
- No modifications. Read-only validation that the cumulative effect matches the design goal.

- [ ] **Step 6.1: Confirm both project-repo commits are on `main`**

Run from `~/projects/nvim-writing-metrics/`:
```bash
git log --oneline -3
git status
```

Expected: two new commits at the top (`docs(CLAUDE):` and `docs:`), then the prior HEAD. `git status` clean.

- [ ] **Step 6.2: Confirm the symlink is in place and resolves**

Run:
```bash
ls -la ~/.config/nvim/docs/superpowers
readlink ~/.config/nvim/docs/superpowers
ls ~/.config/nvim/docs/superpowers/specs/ | head -3
```

Expected: `ls -la` shows the path as a symlink (starts with `l` in the permissions column, has `->` in the listing); `readlink` prints the target; `ls` through the symlink lists actual files.

- [ ] **Step 6.3: Confirm `~/.claude/CLAUDE.md` populated**

Run:
```bash
wc -l ~/.claude/CLAUDE.md
head -5 ~/.claude/CLAUDE.md
```

Expected: non-zero line count; content begins with `# Collaboration preferences`.

- [ ] **Step 6.4: Confirm project memory dir cleaned up**

Run:
```bash
ls ~/.claude/projects/-home-jkeim--config-nvim/memory/
cat ~/.claude/projects/-home-jkeim--config-nvim/memory/MEMORY.md
```

Expected: `feedback_brainstorming_pace.md` not listed; `MEMORY.md` shows only the nvim-text-sharing line.

- [ ] **Step 6.5: Report completion**

Summary the implementer should report back:
- Two commits on `main` in `~/projects/nvim-writing-metrics/`: SHA of Task 1's import commit, SHA of Task 2's CLAUDE.md update commit
- File counts moved (X specs, Y plans)
- Symlink in place at `~/.config/nvim/docs/superpowers` pointing to the project repo
- User-level `~/.claude/CLAUDE.md` populated (line count)
- Project memory `MEMORY.md` reduced to one entry

User performs the post-implementation integration test separately by restarting Claude Code in `~/projects/nvim-writing-metrics/` and confirming the new content loads as expected.

---

## Done When

- Task 1 commit is on `main` with all spec/plan files copied (verified by `diff -r` returning empty)
- Task 2 commit is on `main` with the 4 CLAUDE.md edits applied (verified by grep checks)
- Task 3 leaves `~/.config/nvim/docs/superpowers` as a symlink to the project repo (verified by `readlink`)
- Task 4 leaves `~/.claude/CLAUDE.md` populated with the brainstorming-pace content
- Task 5 leaves the project memory dir with only the nvim-text-sharing entry
- Task 6 integration checks all pass
