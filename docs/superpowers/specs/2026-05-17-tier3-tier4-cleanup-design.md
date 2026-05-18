# Tier 3 + Tier 4 Cleanup — Design Spec

**Date:** 2026-05-17
**Status:** Brainstorm output, pending detailed implementation plans
**Scope:** `nvim-writing-metrics` (13 items) + `nvim-text-sharing` (2 items + 2 UX changes)

## Goals

1. **Fix user-visible bugs** in the writing-metrics Pandoc filter (paragraph double-counting, UTF-8 byte counting, cosmetic Pandoc writer abort).
2. **Fix narrow-trigger bugs** in plumbing (greedy JSON parsing, temp-file cleanup on early return, HTTP server toast accuracy, `os.tmpname()` race).
3. **Eliminate dead code and doc drift** so the codebase matches its documentation.
4. **Modernize deprecated APIs** in a single mechanical sweep that runs last.
5. **Improve `nvim-text-sharing` UX** with proper lazy-loading and discoverable `:Share*` commands.

## Non-goals

- No new features beyond the `:Share*` commands.
- No refactoring beyond what the listed fixes require.
- No changes to the reading-time feature or anything outside the audit list.

## Out of scope (deferred separately)

- 9 stale tests in `nvim-writing-metrics/tests/basic_spec.lua` (memorialized in `project_nvim_writing_metrics_stale_tests.md`).
- 4 isolation failures in `nvim-writing-metrics/tests/full_spec.lua` (memorialized in `project_nvim_writing_metrics_full_spec_failures.md`).

## Plan structure

Four focused implementation plans, executed in order **A → B → D → C**.

### Plan A — Filter & utils bug fixes (high-impact)

- **Repo:** `nvim-writing-metrics`
- **Files:** `scripts/textmetrics.lua`, `lua/writing-metrics/utils.lua`, `lua/writing-metrics/full.lua`
- **Estimated commits:** 5–6

| Item | Location | Fix |
|---|---|---|
| #1 — `os.exit(0)` aborts Pandoc writer | `scripts/textmetrics.lua:1101` | Replace with `return pandoc.Pandoc({}, el.meta)`. Eliminates the cosmetic `table.concat` error documented in CLAUDE.md. |
| #7 — Bullet/numbered list items double-counted | `scripts/textmetrics.lua:904-920` | Either skip the per-item paragraph increment OR stop recursing into inner `Para` blocks. Detailed plan picks one. |
| #8 — `chars` uses byte length not codepoints | `scripts/textmetrics.lua:813` (+ propagation) | Replace `#el.text` with `utf8.len(el.text)`, with byte-length fallback for malformed UTF-8. Affects ARI and Coleman-Liau outputs. |
| #16 — ARI uses total chars not letter chars | `scripts/textmetrics.lua:459-462, 970` | Pass `total_word_chars` (already tracked at line 64) to `calculate_ari` instead of the global `chars` accumulator. |
| #3 — Greedy `{→end` JSON parse | `utils.lua:201-221` + duplicate at `full.lua:49-74` | Replace with a balanced-brace or last-`{`-on-its-own-line strategy. Extract a single helper used by both sites. |
| #4 — Temp file leak on `run_pandoc` early return | `utils.lua:117-151` | Add `cleanup_temp_file` to the early-return path when filter is missing. |

### Plan B — State, UX, dead code, doc rewrite (medium-value cleanup)

- **Repo:** `nvim-writing-metrics`
- **Files:** `init.lua`, `display.lua`, `utils.lua`, `cache.lua`, `config.lua`, `docs/DESIGN_INNOVATIONS.md`
- **Estimated commits:** 5–7

| Item | Location | Fix |
|---|---|---|
| #13 — `_G.writing_metrics_reports` leaks across `:Lazy reload` | `init.lua:10, 31-88` | Reset the global in `setup()` unconditionally instead of preserving it via `or {}`. Optionally migrate to module-local. |
| #15-display — Vocabulary "nan%" on edge inputs | `display.lua:629, 640` | Add `total > 0` guards before `(word_count / total) * 100`. |
| #14 — Section navigation 1-8 coupled to emoji glyphs | `display.lua:798-806` | Decouple keymaps from glyph patterns. Likely approach: store sections as a `{key, pattern, heading}` table and generate keymaps and headings from the same source. |
| #2 — `get_content_hash` is dead code | `utils.lua:358-369` | Delete the unused function. Test suite must still pass. |
| #11 — `cache.is_valid()` and `basic_ttl` are dead | `cache.lua:28-35, 126`, `config.lua:9`, `plugin/writing-metrics.lua:95` | Delete `is_valid`, remove `basic_ttl` from defaults and references. Document removal in CHANGELOG. |
| #9 — Doc drift in DESIGN_INNOVATIONS.md | `docs/DESIGN_INNOVATIONS.md` | Rewrite to reflect current architecture: changedtick-based staleness, basic-only caching, full reports always fresh. Preserve any accurate sections. |

### Plan D — `nvim-text-sharing` fixes & UX

- **Repos:** `nvim-text-sharing` (commits) + `~/.config/nvim` (no commits — not git-tracked)
- **Files:** `~/projects/nvim-text-sharing/lua/text-sharing/init.lua`, `~/projects/nvim-text-sharing/README.md`, `~/.config/nvim/lua/plugins/text-sharing.lua`
- **Estimated commits:** 3–4 in `nvim-text-sharing`, 0 in `~/.config/nvim`

| Item | Location | Fix |
|---|---|---|
| #5 — HTTP server stale state + misleading "started" toast | `init.lua:208-233` | Pre-detect port-in-use via brief `vim.uv.new_tcp` bind/close probe before `jobstart`. Surface real failure instead of false "started." Clear `M.config.http_server_pid` defensively in `setup()`. |
| #6 — `os.tmpname()` race / symlink TOCTOU | `init.lua:166` | Replace with `vim.fn.tempname()` (same secure helper `nvim-writing-metrics` uses). |
| UX-1 — No commands registered | `init.lua` | Add `:ShareDropbox`, `:ShareDropboxSave`, `:ShareDropboxOpen`, `:ShareDropboxFolder`, `:ShareQR`, `:ServeHTTP`, `:StopHTTP` (final names pinned in detailed plan). |
| UX-2 — `lazy = false` at startup | `~/.config/nvim/lua/plugins/text-sharing.lua:6` | Switch to `lazy = true` with `keys = { "<leader>y" }` AND `cmd = { "ShareDropbox", ... }` triggers. |
| README — keep current sections, add commands | `~/projects/nvim-text-sharing/README.md` | Add a Commands section or extend Keybindings table. Existing 65-line README is solid; this is additive only. |

### Plan C — Deprecated API sweep (mechanical, last)

- **Repo:** `nvim-writing-metrics`
- **Files:** `cache.lua`, `utils.lua`, `basic.lua`, `full.lua`, `init.lua`, `display.lua`
- **Estimated commits:** 1 single mechanical sweep, or up to ~6 split by file

| Item | Replacements |
|---|---|
| #10 — Deprecated APIs | `vim.loop.now()` → `vim.uv.now()` (`cache.lua:21`); `vim.loop.new_timer()` → `vim.uv.new_timer()` (`cache.lua:195`); `vim.api.nvim_buf_get_option(buf, 'X')` → `vim.api.nvim_get_option_value('X', { buf = buf })` (multiple sites); `vim.api.nvim_buf_set_option(buf, 'X', v)` → `vim.api.nvim_set_option_value('X', v, { buf = buf })` (multiple sites). |

Goes last so it picks up any new sites added during Plans A and B.

## Cross-cutting decisions

**Branch / commit strategy.** Commit directly to `main` in each repo. Both `nvim-writing-metrics` and `nvim-text-sharing` are personal plugins; no PR review process. Each audit item gets its own focused commit where practical.

**Test discipline.** TDD where it pays:

- Filter changes (#1, #7, #8, #16): fixture-based verification via `pandoc --lua-filter` against known inputs. For #1, capture stderr to confirm the cosmetic error is gone.
- utils/full plumbing (#3, #4): unit tests where possible. #3 is testable by feeding `parse_full_output` a string with `{` in a warning preamble.
- State/UX (#13, #15-display, #14): regression tests where the failure mode is observable. For #14, add a structural test asserting "each section heading in `format_*_section` has a matching jump keymap" so renderers and the data table stay in sync.
- Dead code (#2, #11): no new tests; existing suite must pass after deletion (proves the code really was dead).
- Text-sharing (#5, #6): #5 port-bind detection is testable; #6 is structural. Commands smoke-test via `:` invocation.
- API sweep (#10): no new tests; existing suite must still pass.

**Review discipline.** Per-task subagent-driven-development (implementer → spec-compliance → code-quality) for Plans A, B, D. Plan C skips per-task reviews in favor of one holistic review at the end, since it is single-symbol mechanical change.

**Spec authoring cadence.** This one master design spec covers all 4 plans at high level. Plan A's detailed implementation plan gets written immediately after this spec is approved. Plans B/C/D get their detailed plans written just-in-time when their turn comes, incorporating anything learned from earlier plans.

**Failure-mode handling.**
- If an audit item turns out more complex than expected (e.g., #7's "loose list" fix breaks compact-list counting), escalate and re-scope rather than forcing it.
- If the test suite shows new failures after a fix, treat as a regression and revert the commit.
- The 9 pre-existing `basic_spec.lua` failures and 4 pre-existing `full_spec.lua` failures remain the regression baseline; do not count them against new work.

## Sequencing rationale

- **A first** — highest-impact bugs, concentrated in two files. Subsequent reports become accurate during the rest of the work.
- **B second** — builds on a stable filter/utils foundation. `#13` fix also makes B's own iteration smoother (no stale-state surprises during `:Lazy reload`).
- **D third** — different repo, natural pause point. Verify nothing in `nvim-writing-metrics` is left dangling before switching repos.
- **C last** — deprecated-API sweep picks up anything new added during A and B. Sweeping first would force every subsequent fix to be re-touched.

## Cross-plan dependency risks

| Risk | Mitigation |
|---|---|
| Plan A's #8 (UTF-8 chars) changes values fed to ARI and Coleman-Liau. | Before changing, grep `tests/` for any committed score expectations and update them in the same commit. |
| Plan B's #11 (delete `basic_ttl`) could break user configs that pass it. | Acceptable break for a personal plugin; document in CHANGELOG. (Alternative: accept-and-ignore with a one-time `vim.notify` deprecation warning.) |
| Plan C's API sweep — each `nvim_buf_get_option` → `nvim_get_option_value` migration has a slightly different argument shape. | Run the test suite after each file is converted, not at the end. |
| Plan D's #5 (port detection) has a subtle race: probe binds-and-closes, python3 binds a millisecond later. | Acceptable for personal-use plugin; not worth engineering around. |

## Watch-outs

- The cosmetic Pandoc error from #1 was previously listed as "deferred" in CLAUDE.md. Verify the fix actually eliminates the error by running a report and grepping stderr.
- Section nav decoupling (#14) requires a structural choice (data table vs anchor IDs). Decided in Plan B's detailed plan.
- `:Share*` command names listed are a starting point; final names pinned in Plan D's detailed plan based on which feel right alongside existing `:WordCount` / `:WritingMetrics` conventions.

## After all four plans land

Update project memory entries:

- `project_nvim_writing_metrics_stale_tests.md` — adjust baseline if any fixes happen to address pre-existing test failures.
- `project_nvim_text_sharing_known_issues.md` — reclassify #5 and #6 as FIXED.
