# Plan H — Final cleanup design

**Date:** 2026-05-17
**Repo affected:** `~/projects/nvim-writing-metrics/`
**Baseline:** post Plan G (HEAD `ab4e76c`) — full suite 115 pass / 4 fail; `full_spec.lua` is 19/4 (the only remaining failures).
**Target:** 118 pass / 0 fail (the deleted "caches full metrics" test drops the total by 1; the 3 callback fixes convert 3 failures to passes; the 1 deleted test removes its failure entirely). Zero luacheck warnings. All memorized follow-up debt closed.

## Goal

Close the final 4 test failures, drain every memorized Plan E/F follow-up debt, eliminate 5 trivial unused-variable warnings, and add the two missing lint config pieces (`.stylua.toml` and a Pandoc-globals stanza in `.luacheckrc`) so the project's lint output is signal-only. After Plan H, `nvim-writing-metrics` reaches a steady state: clean suite, clean lint, no known debt in code. A separate Plan I will sweep stale documentation.

## Why now

This is the natural completion of the test-cleanup arc started in Plan E (`basic_spec`), continued through Plans F (`compat_spec` + `integration_spec`) and G (`config_spec`). The remaining 4 failures all live in `full_spec.lua` and turn out — per a fresh audit — to be three stale callback-arity tests (same root cause Plan F fixed in integration_spec) plus one stale assertion against a never-shipped cache tier. Once these close, the suite is green. Bundling in the four memorized follow-up items and the lint-infrastructure work is opportunistic: each is small, each is independent, and there's no future plan whose scope they'd naturally fit into otherwise.

The audit also surfaced: `display.lua` (1031 lines) is cohesive and shouldn't be split; `M.get_fast_count`-style anti-patterns exist in exactly one other place (`show_comparison`); 195 luacheck warnings on `scripts/textmetrics.lua` are all false positives caused by Pandoc-injected globals the config doesn't know about; 11 doc references are stale (deferred to Plan I).

## Architecture

Seven commits on `main` of `~/projects/nvim-writing-metrics/`, grouped by concern so each is independently revertable. Per the spec convention established by Plans C, E, F, G, **one holistic review at the end** against the cumulative diff.

## Commit 1 — `test(full): fix callback arity in 3 tests, delete stale cache assertion`

**Files:**
- Modify: `tests/full_spec.lua`

**Failures closed:** 4 of 4 in `full_spec.lua`. Full suite: 115/4 → 118/0 (3 callback fixes convert failures to passes; 1 stale test deleted drops the total test count from 119 to 118 while removing its failure).

The 4 failures break down into two distinct fixes:

### Three callback-arity fixes (lines 91, 131, 284)

Each test passes a single-arg callback `function(data)` to `full.get_full_metrics`, but the production code calls `callback(ok, data)` — a two-arg call. So `data` captures the boolean `true` (success flag), and subsequent `result_data.<field>` accesses crash with "attempt to index a boolean". Same drift Plan F fixed in `integration_spec.lua` cluster 1. Three identical-shape edits:

- Line 91: `function(data)` → `function(_, data)`
- Line 131: `function(data)` → `function(_, data)`
- Line 284: `function(data)` → `function(_, data)`

### One stale cache assertion (line 105)

Test "caches full metrics" calls `cache.get_full(bufnr)` and asserts the result is non-nil. Two things are wrong:
1. `cache.get_full` doesn't exist — `cache.lua` only exposes `get_basic`, `set_basic`, `invalidate`, `clear_all`, `get_statistics`.
2. `full.get_full_metrics` deliberately doesn't cache — the comment on `full.lua:40` reads `-- Return fresh data (no caching)`.

Per `docs/DESIGN_INNOVATIONS.md` lines 39-41 and `docs/CORE_MODULES.md:156`, this is an explicit design decision: full reports are user-triggered, infrequent, and benefit more from up-to-date output than from cached staleness. The full-cache test was written when the two-tier design was still aspirational; it never got removed when the design was simplified.

**Fix:** Delete the entire `it("caches full metrics", function() ... end)` block (the test body around line 105, plus its surrounding `it` wrapper). Plan I will update `docs/MODULE_FLOW.md`'s elaborate but contradictory full-cache flow diagrams to match the simplified design.

## Commit 2 — `fix(basic): show_comparison reads passed buffer + document statusline fallback`

**Files:**
- Modify: `lua/writing-metrics/basic.lua`

**Failures closed:** 0 (no test catches the latent bug); fixes one production correctness issue.

### Main fix: `show_comparison` (line 291)

`M.show_comparison(bufnr)` accepts a buffer number and uses it for accurate-count calls and line-count queries, but at line 291 it calls `vim.fn.wordcount()` directly — which always counts the current buffer regardless of `bufnr`. Same bug Plan E fixed in `get_fast_count`. In production `show_comparison` is usually called with `bufnr = 0` (current buffer) so the bug is invisible day-to-day, but the contract is wrong.

Find the line:

```lua
  local fast_wc = vim.fn.wordcount()
```

Replace with:

```lua
  local fast_result = M.get_fast_count(bufnr)
  local fast_wc = { words = fast_result.words or 0, chars = fast_result.chars or 0 }
```

(The shape preserves the existing `fast_wc.words` / `fast_wc.chars` accesses further down in the function so no other lines need to change.)

### Documentation comment: `get_statusline_string` (line 460 area)

The audit flagged `vim.fn.wordcount()` at `basic.lua:460` as UNCLEAR — the function accepts `bufnr` but the accurate-mode fallback branch silently ignores it. No real caller passes a non-current `bufnr` (the only invocation point is `lualine_component`, which always passes `0`), so the mismatch is latent. Rather than a code change, add a one-line comment documenting the constraint so future readers don't get confused.

Find the line:

```lua
  local wc = vim.fn.wordcount()
```

(at approximately line 460 — confirm the exact line with `grep -n "vim.fn.wordcount" basic.lua | head -5` since other sites in the file also match). Replace with:

```lua
  -- Note: vim.fn.wordcount() always reads the current buffer. This branch
  -- ignores the bufnr parameter; lualine only ever calls us with bufnr=0,
  -- so the mismatch is latent. If this function is ever called from outside
  -- lualine, this branch needs the get_fast_count treatment too.
  local wc = vim.fn.wordcount()
```

## Commit 3 — `test(basic): bump async timeout from 3000ms to 5000ms`

**Files:**
- Modify: `tests/basic_spec.lua` (line 98)

**Failures closed:** 0; pre-empts a potential CI flake.

The "calls callback with metrics" test at line ~96-102 uses a 3000ms `wait_for_async` timeout. Plan E bumped the sister "strips markdown syntax" test (line 117) to 5000ms to match the abbreviation tests further down. This test was missed in that pass.

Find:

```lua
      local success = helpers.wait_for_async(function()
        return callback_called
      end, 3000)
```

Replace with:

```lua
      local success = helpers.wait_for_async(function()
        return callback_called
      end, 5000)
```

## Commit 4 — `refactor(init): drop dead BufDelete autocmd`

**Files:**
- Modify: `lua/writing-metrics/init.lua`

**Failures closed:** 0; removes dead semantic noise.

`init.lua:179` registers a `BufDelete` autocmd (augroup `WritingMetrics`) that calls `cache.invalidate(ev.buf)` — marks the entry stale. Separately, `cache.lua:172` registers a `{BufDelete, BufWipeout}` autocmd (augroup `WritingMetricsCache`) that calls `cache.remove(args.buf)` — actually deletes the entry. Both fire on the same writing-filetype buffer deletion event. `cache.remove` is the correct semantic (deleted buffer's entries should be removed, not marked stale), and it runs alongside the dead invalidate.

Plan F copied this autocmd verbatim from the old `plugin/writing-metrics.lua`'s `setup_autocommands()` block, where it was already dead. Plan F's reviewer flagged it; Plan H finally drops it.

Find the block (around lines 179-186, inside `M.setup()`'s autocmd registration block):

```lua
  vim.api.nvim_create_autocmd("BufDelete", {
    group = cache_invalidation_group,
    pattern = writing_patterns,
    callback = function(ev)
      cache.invalidate(ev.buf)
    end,
    desc = "Clean up cache on buffer deletion",
  })
```

Delete the entire `nvim_create_autocmd("BufDelete", ...)` block (including the trailing closing `})`). The three remaining autocmds in that block (`TextChanged`+`TextChangedI`, `InsertLeave`, `BufWritePost`) stay untouched — they correctly invalidate the cache (mark stale) on content changes.

## Commit 5 — `test(helpers): drop legacy ari/chars from mock_pandoc_full`

**Files:**
- Modify: `tests/full_spec.lua` (line 57)
- Modify: `tests/helpers.lua` (lines 111, 121)

**Failures closed:** 0; removes dual-naming debt.

The Plan F follow-up identified that `tests/helpers.lua`'s `mock_pandoc_full` populates both the legacy field names (`basic.chars`, `readability.ari`) and the new names (`basic.characters`, `readability.automated_readability`) to keep `full_spec.lua:57`'s old assertion passing. Now that all OTHER call sites use the new names, the legacy duplicates can drop.

Pre-cleanup verification: a grep confirms no test asserts on `metrics.basic.chars` (only the to-be-deleted `init.lua:349` site inside the dead `format_full_report` function — Commit 6 deletes that). And only one test still asserts on the legacy `readability.ari`: `full_spec.lua:57`.

### Step A: migrate the one stale `full_spec.lua` assertion

In `tests/full_spec.lua`, find line 57:

```lua
      assert.is_number(result.readability.ari)
```

Replace with:

```lua
      assert.is_number(result.readability.automated_readability)
```

### Step B: drop the duplicate keys from `mock_pandoc_full`

In `tests/helpers.lua`, find the `mock_pandoc_full` table. The relevant section (around lines 108-124) currently contains both forms:

```lua
  "basic": {
    "words": 100,
    "chars": 500,
    "characters": 500,
    "sentences": 5,
```

Delete the `"chars": 500,` line so the basic block keeps only `"characters": 500,`. Then in the same table:

```lua
  "readability": {
    "coleman_liau": 12.3,
    "ari": 11.8,
    "automated_readability": 11.8,
```

Delete the `"ari": 11.8,` line so the readability block keeps only `"automated_readability": 11.8,`.

### Step C: leave `assert_metrics_structure`'s basic-mode assertions alone

`tests/helpers.lua` lines 82-88 in `assert_metrics_structure(metrics, "basic")` assert `metrics.chars` and `metrics.words`. These are NOT dual-naming — basic mode's Pandoc filter output is a flat 6-value tuple `{words, chars, sentences, paragraphs, avg_sentence_len, avg_word_len}` where `chars` is the canonical field name. The dual-naming was only in the nested full-mode mock, which Step B cleans up.

## Commit 6 — `refactor: drop 4 dead variables and 1 dead function (luacheck cleanup)`

**Files:**
- Modify: `lua/writing-metrics/basic.lua` (line 554)
- Modify: `lua/writing-metrics/cache.lua` (line 102)
- Modify: `lua/writing-metrics/display.lua` (line 334)
- Modify: `lua/writing-metrics/init.lua` (function `format_full_report`, around line 337)

**Failures closed:** 0; closes 5 luacheck warnings.

Five trivial cleanups, each one or two lines. The dead function in `init.lua` is the largest piece (~30 lines).

### `basic.lua:554` — unused `local cache`

Find the line (likely near the bottom of the file or inside a function that no longer needs the cache module):

```lua
        local cache = ...
```

(The exact form will be visible from `grep -n "local cache" lua/writing-metrics/basic.lua` — there may be multiple matches; pick the one luacheck flagged at line 554.) Delete the entire line. If the line is part of a `local A, B = require_x(), require_y()` style multi-declaration, drop only the `cache` part and adjust.

### `cache.lua:102` — unused loop variable `entry`

Find the line:

```lua
  for bufnr, entry in pairs(...) do
```

Rename `entry` to `_entry` (luacheck idiom for "intentionally ignored"):

```lua
  for bufnr, _entry in pairs(...) do
```

### `display.lua:334` — unused `local utils`

Find the line:

```lua
  local utils = require("writing-metrics.utils")
```

Delete the entire line. If the function body later actually references `utils`, that's a real bug and the function needs a different fix — but luacheck flagged this site specifically as unused, so the line is dead.

### `init.lua:337` — dead function `format_full_report`

Find the function (around lines 335-405 — the function `local function format_full_report(data)` and its closing `end`):

```lua
--- @param data table Full metrics data
--- @return table Lines for display
local function format_full_report(data)
  ...
end
```

Delete the entire function including its docstring. Verified by grep across `lua/`, `tests/`, `plugin/`, `scripts/`, and `~/.config/nvim/` that there are zero callers — its responsibility moved to `display.format_report` during the unification work.

## Commit 7 — `chore(lint): add stylua config + scope luacheck Pandoc globals`

**Files:**
- Create: `.stylua.toml` (new file at repo root)
- Modify: `.luacheckrc` (add a `files["scripts/textmetrics.lua"]` stanza)

**Failures closed:** 0; eliminates 195 luacheck false-positive warnings; unblocks future stylua use.

### Create `.stylua.toml`

The codebase uses 2-space indentation throughout `lua/`. Without a `.stylua.toml`, running `stylua --check lua/` produces 8 diffs because stylua's default is tabs. Adding a config file matching the existing convention means future contributors can run stylua without churn:

```toml
# stylua configuration matching the existing 2-space indentation convention.
column_width = 120
indent_type = "Spaces"
indent_width = 2
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
```

(`column_width = 120` is permissive; the existing code mixes 80- and 120-char lines. `quote_style = "AutoPreferDouble"` matches the convention of using double quotes for most strings. `call_parentheses = "Always"` keeps `require("X")` style consistent.)

### Update `.luacheckrc` to handle Pandoc-injected globals

`scripts/textmetrics.lua` is a Pandoc Lua filter that runs inside Pandoc's runtime environment, which injects a number of globals (`pandoc`, plus per-element variables in `Pandoc(el)` walker contexts and accumulator variables). Currently luacheck reports 195 warnings on this file, all variants of "accessing undefined variable" for legitimate Pandoc-environment names.

Find the existing `.luacheckrc` (already has a `files["tests/"]` section). Append:

```lua
-- Pandoc filter has its own runtime environment with injected globals.
files["scripts/textmetrics.lua"] = {
  globals = {
    "pandoc",                  -- Pandoc filter API entry point
    "words",                   -- accumulator: word count
    "chars",                   -- accumulator: char count
    "sentences",               -- accumulator: sentence count
    "paragraphs",              -- accumulator: paragraph count
    "lines",                   -- accumulator: line count
    "questions",               -- accumulator: question count
    "passive_sentences",       -- accumulator: passive voice detections
    "passive_examples",        -- accumulator: passive voice example strings
    "total_nominalizations",   -- accumulator: nominalization count
    "nominalization_examples", -- accumulator: nominalization example strings
    "ai_word_counts",          -- accumulator: AI-style word frequency table
    "sentence_beginnings",     -- accumulator: sentence-opening category counts
  },
}
```

This declares the Pandoc-injected and accumulator globals so luacheck stops flagging them. The exact list comes from the 195 warnings emitted today — every flagged name is captured.

Verification after this commit: `cd ~/projects/nvim-writing-metrics && luacheck lua/ tests/ scripts/ plugin/ 2>&1 | tail -3` should report `Total: 0 warnings / 0 errors in 22 files` (down from 195/0).

## Verification

After all seven commits land:

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **118 pass / 0 fail**. Breakdown by spec file:
- `basic_spec`: 31 / 0 (unchanged, post-Plan-E)
- `cache_spec`: unchanged
- `compatibility_spec`: 17 / 0 (unchanged, post-Plan-F)
- `config_spec`: 12 / 0 (unchanged, post-Plan-G)
- `display_spec`: unchanged
- `full_spec`: **22 / 0** (was 19 / 4 — 3 callback fixes convert failures to passes; 1 stale test deleted, dropping the file's total from 23 to 22)
- `init_spec`: unchanged
- `integration_spec`: 19 / 0 (unchanged, post-Plan-F)
- `utils_spec`: unchanged

```bash
cd ~/projects/nvim-writing-metrics
luacheck lua/ tests/ scripts/ plugin/ 2>&1 | tail -3
```

Expected: **Total: 0 warnings / 0 errors in 22 files**.

```bash
cd ~/projects/nvim-writing-metrics
stylua --check lua/ 2>&1 | grep "Diff in" | wc -l
```

Expected: **0** (after Commit 7 adds `.stylua.toml` matching the codebase's 2-space style; no reformatting needed).

```bash
cd ~/projects/nvim-writing-metrics
git log --oneline ab4e76c..HEAD
```

Expected: 7 commits, prefixed `test(full)`, `fix(basic)`, `test(basic)`, `refactor(init)`, `test(helpers)`, `refactor:`, `chore(lint)`.

## Holistic review

Per the spec convention, Plan H uses one holistic review at the end. Dispatch one code-reviewer subagent against `git diff ab4e76c HEAD`. Reviewer focus areas:

- **Commit 1 — callback arity:** All three sites (`tests/full_spec.lua:91, 131, 284`) updated to `function(_, data)`. The "caches full metrics" test is fully deleted (no residual lines, no orphan describe block).
- **Commit 2 — show_comparison fix:** The `fast_wc = { words = ..., chars = ... }` shape preserves downstream accesses without rewriting them. The `get_statusline_string` comment is descriptive and correctly placed.
- **Commit 2 — show_comparison test coverage:** No existing test catches this fix (audit confirmed). The change is verified by `vim.fn.wordcount()` no longer appearing in `show_comparison`'s body — manual code inspection only.
- **Commit 3 — timeout consistency:** 5000ms now matches the abbreviation tests and the Plan-E-fixed strips-markdown test. No other 3000ms `wait_for_async` calls remain in `basic_spec.lua`.
- **Commit 4 — autocmd parity:** Only the `BufDelete` autocmd in `init.lua`'s setup() block was removed. The three remaining content-change autocmds (`TextChanged`+`TextChangedI`, `InsertLeave`, `BufWritePost`) are intact and still register correctly. The `cache.lua:172` `{BufDelete, BufWipeout}` autocmd that does the real work is unchanged.
- **Commit 5 — dual-naming:** Both legacy keys removed from `mock_pandoc_full` (only `characters` and `automated_readability` remain in the nested tables). Test `full_spec.lua:57` migrated to the new field name. Sanity: `assert_metrics_structure(metrics, "basic")` STILL asserts `metrics.chars` because that's the canonical basic-mode field name — this is correct, not stale.
- **Commit 6 — dead code:** `format_full_report` is fully removed (function + docstring). The 3 unused `local` declarations are gone. The loop variable rename uses `_entry` (luacheck-recognized "intentionally ignored" idiom). Test suite passes — confirming nothing inadvertently depended on the dead function or unused locals.
- **Commit 7 — lint config completeness:** `.stylua.toml` matches the codebase's 2-space convention (running `stylua --check lua/` returns zero diffs). `.luacheckrc`'s new `files["scripts/textmetrics.lua"]` stanza declares every Pandoc-injected global the filter uses (the count of warnings drops from 195 to 0 with no `--no-` filter flags added).
- **No scope creep:** Diff doesn't touch `docs/` (deferred to Plan I), `display.lua`'s structure (audit verdict: cohesive, leave alone), or any spec file outside the four touched in Commits 1, 3, 5.
- **No behavior drift in unrelated tests:** The other 7 spec file counts are unchanged from Plan G baseline.

## Out of scope

- **Documentation sweep (Plan I).** Audit found 11 stale references across `docs/CORE_MODULES.md` (7), `docs/DESIGN_INNOVATIONS.md` (1), `docs/MODULE_FLOW.md` (3). Several are load-bearing (architecture diagrams omit `commands.lua`, `_G.accurate_wordcount` described as function-only, full-cache flow shown that the design explicitly rejected). Distinct concern from code review; bundling would dilute reviewer focus. Brainstorm Plan I immediately after Plan H lands.
- **Resurrecting full-mode caching.** Explicitly decided against in the user-confirmed Q1 answer. Aligns with the existing design notes that already document this choice. The contradictory `docs/MODULE_FLOW.md` flow diagrams get cleaned up in Plan I.
- **Reformatting `lua/` to stylua defaults.** Would be a tabs-vs-spaces churn across all 8 files for zero behavioral benefit. The `.stylua.toml` config in Commit 7 makes a reformat unnecessary.
- **CI / pre-commit hooks for stylua and luacheck.** Worth its own conversation once the lint output is signal-only. Plan H makes that possible; the infrastructure decision belongs elsewhere.
- **`display.lua` split.** Audit verdict: cohesive (8 section renderers + tight `SECTIONS`/keymaps coupling). No clean split exists. Leave alone.
- **The other 4 `vim.fn.wordcount()` sites in `basic.lua`.** Audit verdict: 3 CORRECT (statusline current-buffer reads, visual-mode selection counts); 1 UNCLEAR (statusline accurate-mode fallback at line 460) — addressed by the comment in Commit 2, not a code change.

## Memory updates after completion

- Delete `~/.claude/projects/-home-jkeim--config-nvim/memory/project_nvim_writing_metrics_full_spec_failures.md` (all 4 failures closed).
- Delete `~/.claude/projects/-home-jkeim--config-nvim/memory/project_nvim_writing_metrics_plan_e_followups.md` (both items addressed: show_comparison fix in Commit 2, basic_spec timeout in Commit 3).
- Delete `~/.claude/projects/-home-jkeim--config-nvim/memory/project_nvim_writing_metrics_plan_f_followups.md` (both items addressed: BufDelete duplicate in Commit 4, helpers dual-naming in Commit 5).
- Update `~/.claude/projects/-home-jkeim--config-nvim/memory/MEMORY.md`: remove the three deleted entries' lines. Add a new entry pointing to a fresh `project_nvim_writing_metrics_plan_i_doc_sweep.md` memory (the 11 stale doc references, awaiting Plan I) — or skip the memory and let Plan I's brainstorm re-derive from the audit findings here.

## Summary

7 commits, ~60 lines of net code change across `lua/writing-metrics/{basic,init,cache,display}.lua` and `tests/{full_spec,basic_spec,helpers}.lua`, plus one new `.stylua.toml` file and a small `.luacheckrc` addition. Closes the final 4 test failures, drains all 4 memorized follow-up debt items, eliminates 5 trivial luacheck warnings and 195 false-positive ones, and unblocks future stylua use. Estimated 45-60 minutes of focused work plus the holistic review.

After Plan H lands, `nvim-writing-metrics` is at a steady state: clean test suite, clean lint output, no known code debt. The only outstanding work is `docs/` staleness (Plan I, ~11 line edits across three markdown files) and any user-driven feature work.
