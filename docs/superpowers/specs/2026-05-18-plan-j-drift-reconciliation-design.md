# Plan J — Drift Reconciliation (Working-Directory Switch Preparation)

**Date:** 2026-05-18
**Status:** Design (awaiting implementation plan)
**Target repo:** `~/projects/nvim-writing-metrics/` (primary); plus `~/.config/nvim/` and `~/.claude/` (operational cleanup)
**Affects:** Project CLAUDE.md, spec/plan storage location, user-level CLAUDE.md, auto-memory

**Note on this spec's own location:** This spec lives at `~/.config/nvim/docs/superpowers/specs/` at the time of writing. As part of Action A below, it (and 16 sibling files) will be copied into `~/projects/nvim-writing-metrics/docs/superpowers/specs/` and the originals deleted. The Plan J implementation includes its own relocation.

---

## Problem

After Plans A-I shipped, three independent drift problems make it risky to switch working directories from `~/.config/nvim` to `~/projects/nvim-writing-metrics/`:

1. **Project CLAUDE.md is stale.** Three concrete claims contradict the post-Plan-H state:
   - "106 test cases across 6 test files" (actual: 118/0 after Plan H)
   - "Global `_G.accurate_wordcount` table with old API" (actual: callable-table contract per Plan F, with both function and table shapes)
   - Missing `commands.lua` from the Module Structure list (Plan F extracted this module)

2. **The spec/plan files live in an unversioned directory.** `~/.config/nvim/docs/superpowers/{specs,plans}/` is not a git repo, not in a dotfiles repo, and not backed up. Plans A-I shipped from here (currently ~18-19 markdown files; the implementer will re-count at implementation time, including this spec and the Plan J plan itself). If the directory is lost, the spec history becomes unrecoverable except via commit messages.

3. **Project CLAUDE.md has no Plan History pointer.** A fresh Claude session opened in `~/projects/nvim-writing-metrics/` has no awareness that 9 plans have shipped or where to find their design rationale.

4. **The `feedback_brainstorming_pace` memory is keyed to the wrong directory.** It lives at `~/.claude/projects/-home-jkeim--config-nvim/memory/` — only loaded when the working dir is `~/.config/nvim`. The memory captures a *universal* collaboration preference that should apply regardless of project.

## Scope

**In scope (touches three locations):**

1. `~/projects/nvim-writing-metrics/` (git repo) — two commits:
   - Move + commit all spec/plan markdown files from `~/.config/nvim/docs/superpowers/` into `docs/superpowers/` (count current at implementation time, including this spec and Plan J's plan)
   - Update `CLAUDE.md`: fix 3 stale claims + add Plan History pointer
2. `~/.config/nvim/docs/superpowers/` (unversioned source) — deleted and replaced with a symlink to the project repo's `docs/superpowers/` for dual-access
3. `~/.claude/CLAUDE.md` (user-level, currently empty) — populated with the brainstorming-pace feedback
4. `~/.claude/projects/-home-jkeim--config-nvim/memory/` — `feedback_brainstorming_pace.md` deleted and its index entry removed

**Out of scope:**
- The existing empty `~/projects/nvim-writing-metrics/docs/plans/` directory (left alone; doesn't conflict with the new `docs/superpowers/plans/`)
- The `project_nvim_text_sharing_known_issues` memory (different plugin; closed-work memo; can be cleaned up separately if/when nvim-text-sharing is revisited)
- Introducing git versioning at `~/.config/nvim` (only the specs/plans subdir leaves; the rest of the config remains unversioned per status quo)
- Production code, tests, or other docs
- Other Future Work items (Plan K stylua, auto_detect simplification, :checkhealth audit)

## Design Decisions (Locked)

### D1. Specs and plans move into the project repo

Source: `~/.config/nvim/docs/superpowers/{specs,plans}/`. Target: `~/projects/nvim-writing-metrics/docs/superpowers/{specs,plans}/`. The implementer re-counts files at implementation time and uses that count for verification. Rationale: specs are about this plugin; they belong with the code they describe; in-repo means versioned, discoverable, and survives any nvim-config blow-up. Acceptable cost: if a second plugin project appears later, that one will have its own spec dir — the current files are all about this plugin, so the cost is theoretical.

### D2. Plan History in project CLAUDE.md = minimal pointer

One short paragraph in `~/projects/nvim-writing-metrics/CLAUDE.md` stating that specs/plans live at `docs/superpowers/{specs,plans}/`, that each spec maps to a Plan letter and one commit on `main`, and that `git log --oneline` is the way to find which commit shipped a given plan. No maintained table or list. Rationale: the directory IS the history; a maintained summary drifts. The locked content:

```
## Plan History

The plugin has a per-feature design-spec history under `docs/superpowers/specs/` and implementation plans under `docs/superpowers/plans/`. Each spec corresponds to a single Plan (letter-named: A, B, C, ...) and to one commit on `main`.

Use `git log --oneline` to find which commit shipped a given plan, or read the spec files directly for the design rationale.
```

### D3. Universal feedback memory promotes to `~/.claude/CLAUDE.md`

The `feedback_brainstorming_pace` memory describes how to collaborate with the user regardless of project. The right home is the user-level `~/.claude/CLAUDE.md` (currently empty), which is loaded into every project's context automatically. The per-project copy at `~/.claude/projects/-home-jkeim--config-nvim/memory/feedback_brainstorming_pace.md` is deleted, and its index entry is removed from that memory dir's `MEMORY.md`. Single source of truth, universal coverage, no drift risk.

### D4. Ordered, multi-stage execution with rollback gates

Because the operations span four locations (project repo, nvim config dir, user-level CLAUDE.md, project memory dir), and only the project repo is versioned, the implementation must preserve rollback paths. Order:

1. **Action A** — copy specs/plans into project repo, commit. Originals at `~/.config/nvim/docs/superpowers/` still exist.
2. **Action B** — update project CLAUDE.md (4 edits), commit. References the location Action A established.
3. **Action C** — only after A and B land, delete originals at `~/.config/nvim/docs/superpowers/` and replace with a symlink to the project repo's `docs/superpowers/`. Gated on a final `diff -r` byte-equal check before deletion.
4. **Action D** — write user-level `~/.claude/CLAUDE.md`. No git, no rollback gate needed.
5. **Action E** — delete promoted memory from project memory dir. No git; Claude Code's file-history backup makes this recoverable.

## Per-Action Change List

### Action A — Move specs/plans into project repo (commit 1)

**Source:** `~/.config/nvim/docs/superpowers/{specs,plans}/`
**Target:** `~/projects/nvim-writing-metrics/docs/superpowers/{specs,plans}/`

| Step | Operation |
|------|-----------|
| A.1 | `mkdir -p ~/projects/nvim-writing-metrics/docs/superpowers/{specs,plans}` |
| A.2 | Copy all `.md` files from source to target using `cp -p` to preserve mtimes |
| A.3 | Verify file count: `ls source | wc -l` == `ls target | wc -l` for both subdirs |
| A.4 | Verify byte-equal: `diff -r source target` outputs nothing |
| A.5 | `git add docs/superpowers/ && git commit` with message below |
| A.6 | Do NOT delete originals yet (Action C handles that, gated on a final check) |

Commit message:
```
docs: import design specs and implementation plans

Imports the 17 spec/plan markdown files that documented Plans A
through I from their previous unversioned home at
~/.config/nvim/docs/superpowers/. Specs and plans now live next
to the code they describe, with proper version control.

Each file corresponds to one Plan letter; each Plan letter
corresponds to one commit on main.
```

### Action B — Update project CLAUDE.md (commit 2)

**File:** `~/projects/nvim-writing-metrics/CLAUDE.md` — 4 atomic edits.

| Edit | Location | Change |
|------|----------|--------|
| B1 | "Core modules" list, lines 20-27 | Add a `commands.lua` line between `utils.lua` and `display.lua`: `- `commands.lua` - User command registration; called from init.lua's setup() (idempotent)` |
| B2 | Backward Compatibility section, line 75 | Replace `Global `_G.accurate_wordcount` table with old API` with a description naming both contracts (function shape returns cached count, table shape exposes basic-module methods) |
| B3 | Development Commands → Running Tests, line 83 | Update the test-count sentence to the verified post-Plan-H figures. The implementer must first run `./run-tests.sh` and `ls tests/*_spec.lua \| wc -l` to obtain the actual counts, then substitute them. The sentence currently asserts "106 test cases across 6 test files"; this is stale. |
| B4 | New section between Backward Compatibility and Development Commands | Insert `## Plan History` with the locked content from D2 |

Commit message:
```
docs(CLAUDE): fix stale claims + add Plan History pointer

Closes drift identified during Plan I review:
- Adds commands.lua to the Module Structure list (Plan F extracted
  this module; CLAUDE.md missed the update)
- Updates _G.accurate_wordcount description to reflect the
  callable-table contract (Plan F)
- Updates test count to current state (Plan H: 118/0, was 106/6)
- Adds Plan History section pointing readers at docs/superpowers/
  for design context
```

### Action C — Replace originals with a symlink back to the project repo (no commit)

The source dir at `~/.config/nvim/docs/superpowers/` is deleted, then immediately replaced with a symlink to the new canonical location in the project repo. This preserves dual-access (browsing the specs from the nvim config working directory still works) without sacrificing the single-source-of-truth goal — the project repo remains authoritative and versioned; the nvim config dir gets a transparent view.

| Step | Operation |
|------|-----------|
| C.1 | Confirm Actions A and B commits exist locally: `git log --oneline -2` shows both |
| C.2 | Paranoia byte-equal check: `diff -r ~/.config/nvim/docs/superpowers/ ~/projects/nvim-writing-metrics/docs/superpowers/` outputs nothing. STOP if anything differs. |
| C.3 | Delete and symlink in one shell invocation (no gap window): `rm -rf ~/.config/nvim/docs/superpowers/ && ln -s ~/projects/nvim-writing-metrics/docs/superpowers ~/.config/nvim/docs/superpowers`. Chaining with `&&` ensures the symlink is created atomically with the deletion — there is no moment when the path exists in neither form. |
| C.4 | Verify the symlink resolves: `readlink ~/.config/nvim/docs/superpowers` prints the target path; `ls ~/.config/nvim/docs/superpowers/specs/` lists the same files as `ls ~/projects/nvim-writing-metrics/docs/superpowers/specs/` |
| C.5 | Spot-check: `diff <(cat ~/.config/nvim/docs/superpowers/specs/2026-05-18-plan-j-drift-reconciliation-design.md) <(cat ~/projects/nvim-writing-metrics/docs/superpowers/specs/2026-05-18-plan-j-drift-reconciliation-design.md)` outputs nothing (same file via two paths — reading through the symlink resolves to the canonical project-repo copy) |

### Action D — Promote brainstorming-pace memory to `~/.claude/CLAUDE.md` (no commit)

| Step | Operation |
|------|-----------|
| D.1 | Read `~/.claude/CLAUDE.md` to confirm it's still empty (0 bytes at brainstorm time); if anything's there now, append rather than overwrite |
| D.2 | Write the brainstorming-pace content (verbatim from the implementation plan) to `~/.claude/CLAUDE.md` |
| D.3 | Verify by reading the file back |

The content to write:

```markdown
# Collaboration preferences

## Brainstorming pace

When brainstorming a plan, ask substantive design-tradeoff questions (rename direction, contract shape, API choice, scope boundary with clear tradeoffs) and skip meta-process questions (audit-first vs design-first, single plan vs multi-plan, fold X into Y). On scope/process decisions, make the recommendation and execute.

- **Substantive (ask):** rename direction, contract shape, API choice, behavior change, scope boundary that has clear tradeoffs the user is best-placed to weigh
- **Process (recommend, don't ask):** whether to audit before designing, whether to split into multiple plans, whether to fold X into Y, cadence of review

For process decisions, state the recommendation in one sentence and execute. If the user prefers a different path, they'll redirect — but the default is "you make the call, I proceed."
```

### Action E — Delete promoted memory from project memory dir (no commit)

| Step | Operation |
|------|-----------|
| E.1 | `rm ~/.claude/projects/-home-jkeim--config-nvim/memory/feedback_brainstorming_pace.md` |
| E.2 | Edit `~/.claude/projects/-home-jkeim--config-nvim/memory/MEMORY.md`: remove the line beginning `- [Brainstorming pace:` |
| E.3 | Verify: `MEMORY.md` retains only the `project_nvim_text_sharing_known_issues` line; the memory file is gone from the directory |

## Verification

Per-action checks are documented in each Action above. The plan-level integration check (performed by the user, not the implementer, after the implementation lands): restart Claude Code with the working directory set to `~/projects/nvim-writing-metrics/` and confirm:

1. `~/.claude/CLAUDE.md` content loads into the session's `claudeMd` block (visible at session start)
2. `docs/superpowers/specs/` and `docs/superpowers/plans/` are present from the new working dir
3. The Plan History section in the project's `CLAUDE.md` is visible
4. `git log --oneline -3` shows the two Plan J commits at the top of `main`

## Risk Profile

- **Action A:** low. File copy with byte-equal verification before commit.
- **Action B:** low. Four small CLAUDE.md edits with concrete old/new strings.
- **Action C:** low *because* of the verification gate at C.2. If `diff -r` shows any difference, the deletion is blocked. The symlink itself is trivial to revert (`rm ~/.config/nvim/docs/superpowers`). Minor caveat: some tools (Telescope, ripgrep with default settings) follow symlinks and may surface the project's specs as if they're part of the nvim config — if this becomes annoying, the symlink can be removed without losing anything since the canonical files are in the project repo.
- **Action D:** low. New content into an empty file. The user-level CLAUDE.md is loaded into every project, so changes here have global effect — but the content is a faithful translation of an existing memory.
- **Action E:** low. Single file delete + single line removal. Claude Code's file-history backup makes the deleted file recoverable.

No production code touched. No tests affected. No published API changes.

## Rollback Story

- **Between A and C:** the originals at `~/.config/nvim/docs/superpowers/` are untouched. Reverting commit 1 in the project repo cleanly restores the pre-Plan-J state.
- **After C but before D/E:** the spec/plan migration is irreversible without re-importing from git history. By this point, the verification gate at C.2 has confirmed the new home is byte-equal to the source. The symlink at `~/.config/nvim/docs/superpowers` can be removed without affecting the canonical files (`rm ~/.config/nvim/docs/superpowers` only deletes the symlink, not the target).
- **For D/E:** these touch only Claude's memory state. If the new `~/.claude/CLAUDE.md` content feels wrong, edit it directly. The deleted project-memory file can be restored from `~/.claude/projects/-home-jkeim--config-nvim/file-history/`.
