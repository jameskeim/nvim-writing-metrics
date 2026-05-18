# Plan H — Final cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the final 4 `full_spec.lua` failures, drain all 4 memorized Plan E/F follow-up items, eliminate 5 trivial luacheck warnings, and add `.stylua.toml` + a Pandoc-globals stanza to `.luacheckrc` so lint output becomes signal-only.

**Architecture:** Seven commits on `main` of `~/projects/nvim-writing-metrics/`, grouped by concern so each is independently revertable. Per the spec convention established by Plans C, E, F, G, **one holistic review at the end** against the cumulative diff. No new tests written; existing tests either get fixed (callback arity), deleted (stale cache assertion), or have one assertion line migrated to the canonical field name.

**Tech Stack:** Lua 5.1 (LuaJIT in Neovim), `vim.api.nvim_create_autocmd`, `vim.api.nvim_buf_get_lines` (for the `show_comparison` fix following the Plan E pattern), `stylua 2.5.2` for formatting config, `luacheck 1.2.0` for lint config, `busted`/`plenary.test_harness` for tests.

---

## Conventions

- **Plugin repo:** `~/projects/nvim-writing-metrics/` — git-tracked, commits land directly on `main`.
- **Run tests:** `cd ~/projects/nvim-writing-metrics && ./run-tests.sh` (all specs).
- **Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-17-plan-h-final-cleanup-design.md`
- **Baseline (HEAD `ab4e76c`, post-Plan G):** 115 pass / 4 fail across the full suite; `full_spec.lua` is 19 / 4.
- **Target:** 118 pass / 0 fail. Zero luacheck warnings. The total drops from 119 to 118 because Commit 1 deletes one stale test (3 callback fixes convert failures to passes; the deleted test removes its failure entirely).

**Verification after each task:**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected progression:

| After commit | full_spec | Full suite | Notes |
|---|---|---|---|
| Baseline (post Plan G) | 19 / 4 | 115 / 4 | — |
| 1: full_spec test fixes | 22 / 0 | 118 / 0 | suite green |
| 2: show_comparison | 22 / 0 | 118 / 0 | latent bug fixed |
| 3: timeout bump | 22 / 0 | 118 / 0 | flake pre-empted |
| 4: dead autocmd | 22 / 0 | 118 / 0 | — |
| 5: helpers dual-naming | 22 / 0 | 118 / 0 | — |
| 6: unused-var sweep | 22 / 0 | 118 / 0 | luacheck (lua/): 5 → 0 |
| 7: lint config | 22 / 0 | 118 / 0 | luacheck (whole repo): 195 → 0 |

If any task's count diverges from the table, STOP and investigate before committing.

**Note on "write the failing test first" steps:** Plan H is cleanup, not feature work. The 4 failing tests already exist; Commit 1's "red" step is "confirm the targeted tests currently fail" — not writing new tests. Commits 2-7 close zero test failures (they fix latent bugs, drop dead code, or add infrastructure); their "red" step is "baseline test count must not change after this commit."

---

## Task 1: Fix callback arity + delete stale full-cache test

**Files:**
- Modify: `~/projects/nvim-writing-metrics/tests/full_spec.lua`

**Failures closed:** 4 (the entire `full_spec.lua` cluster — 3 callback-arity fixes at lines 91, 131, 284 convert failures to passes; the "caches full metrics" test at line 105 is deleted, removing its failure and dropping the file's total test count by 1).

- [ ] **Step 1: Confirm the 4 targeted tests currently fail**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/full_spec.lua 2>&1 | grep -aE "Success: |Failed : "
```

Expected: `Success: 19` / `Failed: 4`. The 4 failures are `generates metrics with callback` (line 84/91), `handles empty buffer` (line 125/131), `caches full metrics` (line 105), and `handles buffer with only whitespace` (line 278/284).

- [ ] **Step 2: Fix callback arity at line 91**

In `~/projects/nvim-writing-metrics/tests/full_spec.lua`, find the callback in the `generates metrics with callback` test (around line 91):

```lua
      full.get_full_metrics(bufnr, function(data)
        result_data = data
      end)
```

Replace with:

```lua
      full.get_full_metrics(bufnr, function(_, data)
        result_data = data
      end)
```

The production code calls `callback(ok, data)` — a two-arg invocation. The previous single-arg form captured the boolean success flag as `result_data`, which then crashed later `result_data.<field>` accesses with "attempt to index a boolean".

- [ ] **Step 3: Fix callback arity at line 131**

In the same file, find the callback in the `handles empty buffer` test (around line 131). The before/after shape is identical to Step 2:

```lua
      full.get_full_metrics(bufnr, function(data)
        result_data = data
      end)
```

Replace with:

```lua
      full.get_full_metrics(bufnr, function(_, data)
        result_data = data
      end)
```

(If the two callbacks have identical surrounding text, use a single Edit with more surrounding context to disambiguate each site, OR use `replace_all: true` since all three callbacks in this file share the same broken form.)

- [ ] **Step 4: Fix callback arity at line 284**

In the same file, find the callback in the `handles buffer with only whitespace` test (around line 284). Identical shape to Steps 2 and 3:

```lua
      full.get_full_metrics(bufnr, function(data)
        result_data = data
      end)
```

Replace with:

```lua
      full.get_full_metrics(bufnr, function(_, data)
        result_data = data
      end)
```

- [ ] **Step 5: Delete the stale "caches full metrics" test (line 105)**

In `~/projects/nvim-writing-metrics/tests/full_spec.lua`, find the entire `it("caches full metrics", function() ... end)` block. The test asserts `cache.get_full(bufnr)` returns non-nil, but `cache.lua` exposes no `get_full` function and `full.lua:40` explicitly comments `-- Return fresh data (no caching)`. The full-cache test was written against a never-shipped two-tier cache design; the design philosophy is that full reports always recompute (documented in `docs/DESIGN_INNOVATIONS.md:39-41` and `docs/CORE_MODULES.md:156`).

The test block looks approximately like (the exact surrounding lines will be visible from the test runner output):

```lua
    it("caches full metrics", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local result_data = nil

      full.get_full_metrics(bufnr, function(_, data)
        result_data = data
      end)

      helpers.wait_for_async(function() return result_data ~= nil end, 5000)

      local cached = cache.get_full(bufnr)
      assert.is_not_nil(cached, "Full metrics should be cached after computation")
    end)
```

(The actual body might differ slightly — find it by searching for the literal string `"caches full metrics"` in the file.)

Delete the entire `it(...) ... end)` block, including the trailing `end)` and any blank line that separates it from the next test. The surrounding `describe(...)` block stays intact.

- [ ] **Step 6: Verify the file parses**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile tests/full_spec.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 7: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **118 pass / 0 fail** (was 115/4). Specifically: `full_spec` drops from 19/4 to 22/0 (3 callback fixes pass + 1 deleted test reduces the total from 23 to 22).

If counts diverge, STOP and investigate before committing.

- [ ] **Step 8: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add tests/full_spec.lua
git commit -m "test(full): fix callback arity in 3 tests, delete stale cache assertion

3 tests (lines 91, 131, 284) declared single-arg callbacks
'function(data)' but full.get_full_metrics calls callback(ok,
data) — same drift Plan F fixed in integration_spec. Each callback
updated to function(_, data) so the metrics table lands in
result_data instead of the boolean success flag.

1 test 'caches full metrics' (line 105) deleted entirely. The
assertion against cache.get_full(bufnr) tested a never-shipped
two-tier cache design that the plugin explicitly rejected in
favor of always-fresh full reports (see docs/DESIGN_INNOVATIONS.md
lines 39-41 and full.lua:40 'Return fresh data (no caching)').
docs/MODULE_FLOW.md still has stale flow diagrams describing the
abandoned full-cache; Plan I will clean those up.

Closes 4 of 4 full_spec.lua failures. Full suite: 115/4 → 118/0
(total drops from 119 to 118 due to the deleted test)."
```

---

## Task 2: Fix `show_comparison` buffer-scope bug + document statusline fallback

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua`

**Failures closed:** 0 (no test catches the latent bug). Fixes one production correctness issue (`show_comparison` silently counts the wrong buffer when called with a non-current `bufnr`) and adds a comment documenting a related latent issue at the `get_statusline_string` fallback site.

- [ ] **Step 1: Baseline test counts (must NOT change after this task)**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: 118 / 0 (post-Task-1 baseline). After Task 2, this must remain exactly 118 / 0 — Task 2 changes no test behavior.

- [ ] **Step 2: Fix `show_comparison` at line 291**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua`, find the line (around line 291 inside `M.show_comparison(bufnr)`):

```lua
  local fast_wc = vim.fn.wordcount()
```

Replace with:

```lua
  local fast_result = M.get_fast_count(bufnr)
  local fast_wc = { words = fast_result.words or 0, chars = fast_result.chars or 0 }
```

`vim.fn.wordcount()` always reads the current buffer regardless of `bufnr`. `M.get_fast_count` (fixed in Plan E) honors the passed buffer via `nvim_buf_get_lines` + Lua counting. The two-line replacement preserves the downstream `fast_wc.words` / `fast_wc.chars` accesses unchanged — the table just gets built from the right source.

- [ ] **Step 3: Add comment documenting the statusline accurate-mode fallback**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua`, find the `vim.fn.wordcount()` call at line 460 (inside `M.get_statusline_string`'s accurate-mode "no cache at all" fallback branch). Verify the exact line with:

```bash
cd ~/projects/nvim-writing-metrics
grep -n "vim.fn.wordcount" lua/writing-metrics/basic.lua
```

The site to target is the LAST entry in that grep (line ~460 — not the earlier ones at 205, 291, 413, 429, which the audit classified as CORRECT or were just fixed in Step 2). Find:

```lua
  local wc = vim.fn.wordcount()
```

Replace with:

```lua
  -- Note: vim.fn.wordcount() always reads the current buffer. This branch
  -- ignores the bufnr parameter; lualine only ever calls us with bufnr=0,
  -- so the mismatch is latent. If this function is ever called from outside
  -- lualine, this branch needs the get_fast_count treatment too.
  local wc = vim.fn.wordcount()
```

(Add the four-line comment immediately before the existing line; do not modify the assignment itself.)

- [ ] **Step 4: Verify the file parses and `show_comparison` no longer calls wordcount() directly**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/basic.lua" -c "qa!" 2>&1 | head -5
grep -n "vim.fn.wordcount" lua/writing-metrics/basic.lua
```

Expected: parse check has no output. Grep returns 4 sites (not 5): the call at line 291 inside `show_comparison` is gone, replaced with `M.get_fast_count(bufnr)`. The remaining 4 sites (205, 413, 427-area, 460-area) are the audit-CORRECT statusline reads and the now-documented fallback.

- [ ] **Step 5: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: **118 / 0** (UNCHANGED from Task 1). This task is pure latent-bug-fix; if counts move either way, something behavior-changed inadvertently.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/basic.lua
git commit -m "fix(basic): show_comparison reads passed buffer + document statusline fallback

show_comparison(bufnr) at line 291 called vim.fn.wordcount()
directly, which always counts the current buffer regardless of
bufnr. Same buffer-scope bug Plan E fixed in get_fast_count. In
production show_comparison is usually called with bufnr=0
(current buffer) so the bug is invisible day-to-day, but the
contract is wrong: callers passing a non-current buffer silently
get counts for whichever buffer happens to be current at call
time.

Fix uses the M.get_fast_count(bufnr) accessor Plan E established;
preserves the downstream fast_wc.words / fast_wc.chars accesses
by building the table from the get_fast_count result.

Separately: get_statusline_string's accurate-mode fallback at
line ~460 has the same latent mismatch (accepts bufnr, calls
wordcount which ignores it), but its only real caller is
lualine_component which always passes 0. Added a 4-line comment
documenting the constraint so future readers don't get confused
or callers don't expand the function's reach without fixing the
fallback.

Closes 0 test failures (no test catches the latent bug). Tests
remain at 118/0."
```

---

## Task 3: Bump async timeout from 3000ms to 5000ms

**Files:**
- Modify: `~/projects/nvim-writing-metrics/tests/basic_spec.lua`

**Failures closed:** 0; pre-empts a CI flake on slow Pandoc startup.

- [ ] **Step 1: Baseline test counts (must NOT change after this task)**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: 118 / 0.

- [ ] **Step 2: Bump the timeout**

In `~/projects/nvim-writing-metrics/tests/basic_spec.lua`, find the `calls callback with metrics` test (around lines 94-102). The current `wait_for_async` block:

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

5000ms matches the abbreviation tests further down in the same file (lines 264, 282, 302 — already at 5000) and the strips-markdown-syntax test that Plan E bumped (line 117). This is the one remaining 3000ms async wait in `basic_spec.lua`.

- [ ] **Step 3: Verify the file parses**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile tests/basic_spec.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 4: Confirm no other 3000ms async waits remain in `basic_spec.lua`**

```bash
cd ~/projects/nvim-writing-metrics
grep -nE "wait_for_async.*3000\)" tests/basic_spec.lua
```

Expected: zero matches. If any 3000ms wait still exists, find and bump it OR leave it (it's outside Plan H's scope — flag in the commit message).

- [ ] **Step 5: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: **118 / 0** (UNCHANGED).

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add tests/basic_spec.lua
git commit -m "test(basic): bump async timeout from 3000ms to 5000ms

The 'calls callback with metrics' test waited 3000ms for the
Pandoc callback. Plan E bumped the sister 'strips markdown
syntax' test (line 117) to 5000ms to match the abbreviation
tests at lines 264/282/302; this one was missed in that pass.
Bringing it in line pre-empts CI flakes on slow Pandoc startup.

Closes 0 test failures. Tests remain at 118/0."
```

---

## Task 4: Drop dead BufDelete autocmd from `init.lua`

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua`

**Failures closed:** 0; removes dead semantic noise.

The `init.lua` `setup()` body registers a `BufDelete` autocmd (around line 179) that calls `cache.invalidate(ev.buf)` — marks the entry stale. Separately, `cache.lua:172`'s `setup_autocmds()` registers a `{BufDelete, BufWipeout}` autocmd that calls `cache.remove(args.buf)` — actually deletes the entry. Both fire on writing-filetype buffer deletion; `cache.remove` is the correct semantic (deleted buffer's entries should be removed, not just marked stale) and runs alongside the dead invalidate. Plan F copied this autocmd verbatim from the old `plugin/writing-metrics.lua` where it was already dead; the Plan F reviewer flagged it.

- [ ] **Step 1: Baseline test counts (must NOT change after this task)**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: 118 / 0.

- [ ] **Step 2: Delete the dead BufDelete autocmd block**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua`, find the BufDelete block (around lines 179-186 inside `M.setup()`'s cache-invalidation autocmd registration):

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

Delete the entire `nvim_create_autocmd("BufDelete", ...)` block, including the trailing `})` line and any blank line that separates it from the next autocmd or the next statement. Do NOT touch:
- The three OTHER autocmds in the same block (`{TextChanged, TextChangedI}`, `InsertLeave`, `BufWritePost`) — they correctly invalidate the cache on content changes.
- The `cache.lua:172` `{BufDelete, BufWipeout}` autocmd — that one calls `cache.remove` and is the correct production behavior.

- [ ] **Step 3: Verify the file parses**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/init.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 4: Confirm only one `BufDelete` autocmd remains in the codebase**

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "nvim_create_autocmd.*BufDelete\|nvim_create_autocmd({.*BufDelete" lua/ --include="*.lua"
```

Expected: 2 matches —
- `lua/writing-metrics/cache.lua:172`: the canonical `{ BufDelete, BufWipeout }` autocmd that calls `cache.remove` (kept).
- `lua/writing-metrics/init.lua:113` (the `{BufDelete, BufWipeout}` for report cleanup) — UNRELATED, registers report-cleanup logic, not cache invalidation. Stays.

If a THIRD match still exists in `init.lua` near the cache-invalidation block, the deletion in Step 2 was incomplete — find and remove.

- [ ] **Step 5: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: **118 / 0** (UNCHANGED).

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/init.lua
git commit -m "refactor(init): drop dead BufDelete autocmd

init.lua:179 registered a BufDelete autocmd that called
cache.invalidate(ev.buf) — marks the entry stale. cache.lua:172
already registers a {BufDelete, BufWipeout} autocmd that calls
cache.remove(args.buf) — actually deletes the entry. Both fired
on writing-filetype buffer deletion; cache.remove is the correct
semantic (deleted buffer's entries should be removed, not marked
stale) and runs alongside the dead invalidate.

Plan F copied this autocmd verbatim from the old
plugin/writing-metrics.lua where it was already dead. Plan F's
reviewer flagged it; Plan H drops it.

The three other autocmds in the same setup() block ({TextChanged,
TextChangedI}, InsertLeave, BufWritePost) are intact and still
correctly invalidate the cache on content changes. init.lua:113
({BufDelete, BufWipeout} for report cleanup) is unrelated and
also stays.

Closes 0 test failures. Tests remain at 118/0."
```

---

## Task 5: Drop legacy `ari` / `chars` from `mock_pandoc_full`

**Files:**
- Modify: `~/projects/nvim-writing-metrics/tests/full_spec.lua` (line 57)
- Modify: `~/projects/nvim-writing-metrics/tests/helpers.lua` (lines 111, 121)

**Failures closed:** 0; removes dual-naming debt from the Plan F follow-up memory.

`tests/helpers.lua`'s `mock_pandoc_full` populates both the legacy field names (`basic.chars`, `readability.ari`) and the new names (`basic.characters`, `readability.automated_readability`) so the legacy assertion at `full_spec.lua:57` would keep passing during the Plan F unification. A pre-cleanup grep confirms no test asserts on `metrics.basic.chars` anywhere (only the to-be-deleted `init.lua:349` site inside the dead `format_full_report` function — that whole function gets deleted in Task 6). Only one test still asserts on `readability.ari`: `full_spec.lua:57`. Migrate that one assertion, then drop the legacy duplicates.

- [ ] **Step 1: Baseline test counts (must NOT change after this task)**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: 118 / 0.

- [ ] **Step 2: Migrate the one stale `full_spec.lua` assertion**

In `~/projects/nvim-writing-metrics/tests/full_spec.lua`, find line 57:

```lua
      assert.is_number(result.readability.ari)
```

Replace with:

```lua
      assert.is_number(result.readability.automated_readability)
```

- [ ] **Step 3: Drop the legacy `chars` key from `mock_pandoc_full.basic`**

In `~/projects/nvim-writing-metrics/tests/helpers.lua`, find the `mock_pandoc_full` table's `basic` block (around lines 108-119). The current shape:

```lua
  "basic": {
    "words": 100,
    "chars": 500,
    "characters": 500,
    "sentences": 5,
    "paragraphs": 2,
    "words_per_sentence": 20.0,
    "words_per_paragraph": 50.0,
    "avg_words_per_sentence": 20.0,
    "avg_words_per_paragraph": 50.0
  },
```

Delete the `"chars": 500,` line (third entry inside `"basic":`). The result:

```lua
  "basic": {
    "words": 100,
    "characters": 500,
    "sentences": 5,
    "paragraphs": 2,
    "words_per_sentence": 20.0,
    "words_per_paragraph": 50.0,
    "avg_words_per_sentence": 20.0,
    "avg_words_per_paragraph": 50.0
  },
```

- [ ] **Step 4: Drop the legacy `ari` key from `mock_pandoc_full.readability`**

In the same `tests/helpers.lua` file, find the `readability` block (around lines 120-125). The current shape:

```lua
  "readability": {
    "coleman_liau": 12.3,
    "ari": 11.8,
    "automated_readability": 11.8,
    "flesch_reading_ease": 58.4,
    "flesch_kincaid": 10.2,
```

(The block likely continues with more readability fields below this.)

Delete the `"ari": 11.8,` line. The result:

```lua
  "readability": {
    "coleman_liau": 12.3,
    "automated_readability": 11.8,
    "flesch_reading_ease": 58.4,
    "flesch_kincaid": 10.2,
```

- [ ] **Step 5: Do NOT touch the basic-mode assertions in `assert_metrics_structure`**

`tests/helpers.lua` lines 82, 88 inside `assert_metrics_structure(metrics, "basic")` assert `metrics.chars` and `metrics.words`. These are NOT dual-naming — basic mode's Pandoc filter output is a flat 6-value tuple `{words, chars, sentences, paragraphs, avg_sentence_len, avg_word_len}` where `chars` is the canonical field name. Leave these assertions alone.

- [ ] **Step 6: Verify files parse**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile tests/full_spec.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile tests/helpers.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output for either parse check.

- [ ] **Step 7: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: **118 / 0** (UNCHANGED).

- [ ] **Step 8: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add tests/full_spec.lua tests/helpers.lua
git commit -m "test(helpers): drop legacy ari/chars from mock_pandoc_full

The Plan F follow-up memory identified that mock_pandoc_full
populates both the legacy nested field names (basic.chars,
readability.ari) and the new names (basic.characters,
readability.automated_readability) to keep the legacy assertion
at full_spec.lua:57 passing.

Pre-cleanup grep confirmed no other test asserts on
metrics.basic.chars (only init.lua:349 in the dead
format_full_report function, which Task 6 deletes). Only one
test still asserted readability.ari: full_spec.lua:57 — migrated
to automated_readability here.

Both legacy keys removed from mock_pandoc_full. The basic-mode
assertions in assert_metrics_structure (lines 82, 88) are NOT
dual-naming — basic mode's Pandoc filter output is a flat 6-value
tuple where chars is the canonical field name — those stay.

Closes 0 test failures. Tests remain at 118/0."
```

---

## Task 6: Drop 4 dead variables and 1 dead function (luacheck cleanup)

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua` (line 554)
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua` (line 102)
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua` (line 334)
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` (function `format_full_report`, lines ~335-405)

**Failures closed:** 0; closes 5 luacheck warnings in `lua/`.

Five trivial cleanups verified by code inspection during the audit. The dead function in `init.lua` is the largest piece (~30-70 lines).

- [ ] **Step 1: Baseline test counts AND luacheck warning count**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
luacheck lua/ 2>&1 | tail -3
```

Expected:
- Tests: 118 / 0.
- Luacheck: `Total: 5 warnings / 0 errors in 8 files`.

- [ ] **Step 2: Delete unused `local cache` in `basic.lua:554`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua`, find the line at 554. Context (lines 552-557):

```lua
--- Setup autocommands for cache invalidation and updates
function M.setup_autocmds()
  local cache = require("writing-metrics.cache")

  local group = vim.api.nvim_create_augroup("WritingMetricsBasic", { clear = true })
```

The `local cache = require("writing-metrics.cache")` declaration at line 554 is genuinely unused — `setup_autocmds`'s body only references `M.update_statusline_accurate_count`, `vim.api.nvim_create_*`, and a separately-required `utils` inside each autocmd callback. The `M.setup()` function further down DOES re-require `cache`, but that's a different function and a different lexical scope.

Find:

```lua
function M.setup_autocmds()
  local cache = require("writing-metrics.cache")

  local group = vim.api.nvim_create_augroup("WritingMetricsBasic", { clear = true })
```

Replace with:

```lua
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup("WritingMetricsBasic", { clear = true })
```

(Delete the `local cache` line AND the blank line that immediately followed it, so the function body starts directly with the augroup declaration.)

- [ ] **Step 3: Rename unused loop variable in `cache.lua:102`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua`, find line 102. Context (lines 100-105):

```lua
  -- Count entries and estimate memory
  for _, entry in pairs(cache.basic) do
    basic_count = basic_count + 1
    -- Rough memory estimate: changedtick (8 bytes) + timestamp (8 bytes) + data (estimate 200 bytes)
    basic_memory = basic_memory + 240
  end
```

The loop variable `entry` is unused (the body uses only the accumulators). Luacheck's idiom for "intentionally ignored" is the leading underscore. Find:

```lua
  for _, entry in pairs(cache.basic) do
```

Replace with:

```lua
  for _, _entry in pairs(cache.basic) do
```

(Just rename `entry` → `_entry` to signal intent; the variable is referenced nowhere in the body, so renaming is safe.)

- [ ] **Step 4: Delete unused `local utils` in `display.lua:334`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua`, find line 334. Context (lines 332-335):

```lua
function M.format_sentence_variety_section(variability)
  local lines = {}
  local utils = require("writing-metrics.utils")

  table.insert(lines, "")
```

The `local utils` declaration is unused — the function body uses only `M.section_heading`, `M.interpret_sentence_variety`, `string.format`, `table.insert`, `math.floor`, `math.max`. No `utils.X` references.

Find:

```lua
function M.format_sentence_variety_section(variability)
  local lines = {}
  local utils = require("writing-metrics.utils")

  table.insert(lines, "")
```

Replace with:

```lua
function M.format_sentence_variety_section(variability)
  local lines = {}

  table.insert(lines, "")
```

(Delete the `local utils` line AND the blank line that immediately followed it.)

- [ ] **Step 5: Delete dead `format_full_report` function in `init.lua`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua`, find and delete the dead function. The block to delete starts with this docstring + function header (at approximately line 335-337):

```lua
--- @param data table Full metrics data
--- @return table Lines for display
local function format_full_report(data)
  local utils = get_utils()
  local lines = {
    "# Writing Metrics - Comprehensive Report",
    "",
  }

  -- Basic statistics
  if data.basic then
    table.insert(lines, "## Basic Statistics")
    ...
```

…and ends with the function's closing `end` (approximately line 405-410). The function body populates a multi-section `lines` table with formatted readability/basic-stats output and returns it. The full body is ~70 lines.

To find the exact bounds reliably:

```bash
cd ~/projects/nvim-writing-metrics
grep -n "local function format_full_report\|^end" lua/writing-metrics/init.lua | head -20
```

The first match is the function start. The next bare `end` at column 1 (matching `^end`) after that line is the function's closing `end`. Delete inclusive of the two `--- @param` / `--- @return` docstring lines immediately above the `local function` declaration AND through that closing `end`. Then also delete any blank line immediately after the closing `end` if it leaves two consecutive blank lines (so the file collapses cleanly to the next block).

Audit confirmed zero callers: a recursive grep across `lua/`, `tests/`, `plugin/`, `scripts/`, and `~/.config/nvim/` returns only the definition itself (and a separate `_format_full_report` mention in `~/.config/nvim/docs/WRITING_METRICS_IMPLEMENTATION.md`, which is a different name in a planning doc — not live code). The function's responsibility moved to `display.format_report` during Plan F's unification; this dead copy survived.

After deletion, verify nothing else broke:

```bash
cd ~/projects/nvim-writing-metrics
grep -n "format_full_report" lua/writing-metrics/init.lua
```

Expected: zero matches (the function is gone; nothing else in init.lua references it).

- [ ] **Step 6: Verify files parse and luacheck count is now 0**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/basic.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile lua/writing-metrics/cache.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile lua/writing-metrics/display.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile lua/writing-metrics/init.lua" -c "qa!" 2>&1 | head -5
luacheck lua/ 2>&1 | tail -3
```

Expected:
- Parse checks: no output for any of the four files.
- Luacheck: `Total: 0 warnings / 0 errors in 8 files`.

If luacheck still reports warnings, address the remaining sites OR leave them with a brief commit-message note (do NOT add inline `-- luacheck: ignore` directives in this task — those belong in Task 7's lint-config commit if needed).

- [ ] **Step 7: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: **118 / 0** (UNCHANGED). If counts move, something behavior-changed inadvertently — most likely the dead function deletion in Step 5 removed something with a non-obvious dependency.

- [ ] **Step 8: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/basic.lua lua/writing-metrics/cache.lua lua/writing-metrics/display.lua lua/writing-metrics/init.lua
git commit -m "refactor: drop 4 dead variables and 1 dead function (luacheck cleanup)

Five trivial cleanups, each one or two lines except the dead
function which is ~70 lines:

- basic.lua:554: deleted unused 'local cache' in setup_autocmds().
  cache module is re-required separately in M.setup() further down.
- cache.lua:102: renamed unused loop variable 'entry' to '_entry'
  (luacheck idiom for 'intentionally ignored'). The body only
  references accumulators.
- display.lua:334: deleted unused 'local utils' in
  format_sentence_variety_section. The body never references utils.
- init.lua:~337: deleted entire 'format_full_report' function +
  docstring. Audit confirmed zero callers across lua/, tests/,
  plugin/, scripts/, and ~/.config/nvim/. Responsibility moved
  to display.format_report during Plan F unification; this dead
  copy survived.

Closes 5 luacheck warnings in lua/ (5 → 0). Test suite unchanged
at 118/0."
```

---

## Task 7: Add `.stylua.toml` + scope luacheck Pandoc globals

**Files:**
- Create: `~/projects/nvim-writing-metrics/.stylua.toml` (new file at repo root)
- Modify: `~/projects/nvim-writing-metrics/.luacheckrc`

**Failures closed:** 0; eliminates 195 luacheck false-positive warnings in `scripts/textmetrics.lua`; unblocks future stylua use without forcing a reformat-the-codebase churn.

- [ ] **Step 1: Baseline test counts AND luacheck counts (whole repo)**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
stylua --check lua/ 2>&1 | grep -c "Diff in"
luacheck lua/ tests/ scripts/ plugin/ 2>&1 | tail -3
```

Expected:
- Tests: 118 / 0.
- Stylua: 8 (one diff per file in `lua/writing-metrics/`).
- Luacheck (whole repo): roughly `Total: 195 warnings / 0 errors in 22 files`.

- [ ] **Step 2: Create `.stylua.toml`**

Create a new file at `~/projects/nvim-writing-metrics/.stylua.toml` with this content:

```toml
# stylua configuration matching the existing 2-space indentation convention.
column_width = 120
indent_type = "Spaces"
indent_width = 2
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
```

- `column_width = 120`: permissive; the existing code mixes 80- and 120-char lines and longer table-construction blocks.
- `indent_type = "Spaces"` + `indent_width = 2`: matches the codebase's existing indentation.
- `quote_style = "AutoPreferDouble"`: matches the convention of double quotes for most strings.
- `call_parentheses = "Always"`: keeps `require("X")` style consistent (rather than letting stylua drop parens in some single-arg calls).

- [ ] **Step 3: Verify stylua diffs disappear after the config lands**

```bash
cd ~/projects/nvim-writing-metrics
stylua --check lua/ 2>&1 | head -10
```

Expected: zero output (no "Diff in" lines). If diffs remain, the `.stylua.toml` config doesn't match the codebase's actual style — adjust `quote_style` or `call_parentheses` until the diff count is zero. Common adjustment needed: `quote_style = "AutoPreferSingle"` if stylua complains about single-quote usage somewhere.

- [ ] **Step 4: Update `.luacheckrc` to handle Pandoc-injected globals**

In `~/projects/nvim-writing-metrics/.luacheckrc`, find the existing `files["tests/"]` block. The current end of file:

```lua
-- Read globals for testing (plenary.nvim)
files["tests/"] = {
  globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "assert",
    "pending",
  },
}

-- Exclude external dependencies and generated files
exclude_files = {
  ".luarocks/",
  ".git/",
  "vendor/",
}

-- Warnings to ignore
ignore = {
  "212", -- Unused argument (common in callbacks)
  "631", -- Line too long (handled by formatter)
}
```

Insert a new `files["scripts/textmetrics.lua"]` block after the existing `files["tests/"]` block (before the `exclude_files` block) so the file ends:

```lua
-- Read globals for testing (plenary.nvim)
files["tests/"] = {
  globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "assert",
    "pending",
  },
}

-- Pandoc filter has its own runtime environment with injected globals.
-- pandoc is the Pandoc filter API entry point; the others are accumulator
-- variables populated by walker functions in the filter.
files["scripts/textmetrics.lua"] = {
  globals = {
    "pandoc",
    "words",
    "chars",
    "sentences",
    "paragraphs",
    "lines",
    "questions",
    "passive_sentences",
    "passive_examples",
    "total_nominalizations",
    "nominalization_examples",
    "ai_word_counts",
    "sentence_beginnings",
  },
}

-- Exclude external dependencies and generated files
exclude_files = {
  ".luarocks/",
  ".git/",
  "vendor/",
}

-- Warnings to ignore
ignore = {
  "212", -- Unused argument (common in callbacks)
  "631", -- Line too long (handled by formatter)
}
```

The 13 names listed are exactly the ones luacheck flagged across the 195 warnings in `scripts/textmetrics.lua` — verified via the audit pass.

- [ ] **Step 5: Confirm luacheck warnings drop to zero across the whole repo**

```bash
cd ~/projects/nvim-writing-metrics
luacheck lua/ tests/ scripts/ plugin/ 2>&1 | tail -3
```

Expected: `Total: 0 warnings / 0 errors in 22 files`. If any warnings remain in `scripts/textmetrics.lua`, the globals list missed a name — add it to the block in Step 4. If warnings appear elsewhere (in `tests/` or `plugin/`), they're unrelated to Plan H's scope; flag in the commit message.

- [ ] **Step 6: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: **118 / 0** (UNCHANGED). Lint config changes don't affect tests.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add .stylua.toml .luacheckrc
git commit -m "chore(lint): add stylua config + scope luacheck Pandoc globals

Two lint-infrastructure additions:

1. Create .stylua.toml matching the codebase's 2-space indentation
   convention. Without it, 'stylua --check lua/' reported 8 diffs
   because stylua's default is tabs. The config lets future
   contributors run stylua without churn and unblocks pre-commit
   integration if anyone wants it later.

2. Add files['scripts/textmetrics.lua'] stanza to .luacheckrc
   declaring the 13 Pandoc-injected globals (pandoc, plus 12
   accumulator variables: words, chars, sentences, paragraphs,
   lines, questions, passive_sentences, passive_examples,
   total_nominalizations, nominalization_examples, ai_word_counts,
   sentence_beginnings). Eliminates 195 false-positive warnings
   from 'luacheck lua/ tests/ scripts/ plugin/'.

Closes 0 test failures. Tests remain at 118/0. Luacheck: 195 → 0
across the whole repo. Stylua: 8 diffs → 0."
```

---

## Final verification

After all seven tasks land, run:

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **118 pass / 0 fail**.

```bash
cd ~/projects/nvim-writing-metrics
luacheck lua/ tests/ scripts/ plugin/ 2>&1 | tail -3
```

Expected: `Total: 0 warnings / 0 errors in 22 files`.

```bash
cd ~/projects/nvim-writing-metrics
stylua --check lua/ 2>&1 | grep -c "Diff in"
```

Expected: `0`.

```bash
cd ~/projects/nvim-writing-metrics
git log --oneline ab4e76c..HEAD
```

Expected: 7 commits, prefixed `test(full)`, `fix(basic)`, `test(basic)`, `refactor(init)`, `test(helpers)`, `refactor:`, `chore(lint)`.

---

## Holistic review

Per the spec convention, Plan H uses one holistic review at the end. Dispatch one code-reviewer subagent against the cumulative diff:

```bash
cd ~/projects/nvim-writing-metrics
git diff ab4e76c HEAD --stat
git diff ab4e76c HEAD
```

Reviewer focus areas:

- **Task 1 — callback arity:** All three sites (`tests/full_spec.lua:91, 131, 284`) updated to `function(_, data)`. The "caches full metrics" test is fully deleted (no residual lines, no orphan `describe` wrapper). The deleted test reduces `full_spec.lua`'s total test count by 1 (23 → 22).
- **Task 2 — show_comparison fix:** The `fast_wc = { words = ..., chars = ... }` shape preserves downstream `fast_wc.words` / `fast_wc.chars` accesses without rewriting them. The comment at the line-460 site is descriptive, placed before the line it documents, and doesn't change the assignment behavior.
- **Task 2 — wordcount inventory check:** `grep -n "vim.fn.wordcount" lua/writing-metrics/basic.lua` returns exactly 4 sites after Task 2 (was 5). The remaining 4 are statusline current-buffer reads and the now-documented fallback.
- **Task 3 — timeout consistency:** 5000ms now matches the abbreviation tests and the Plan-E-fixed strips-markdown test. `grep -nE "wait_for_async.*3000\)" tests/basic_spec.lua` returns zero matches.
- **Task 4 — autocmd parity:** Only the dead `BufDelete` autocmd in `init.lua`'s `setup()` block was removed. The three remaining content-change autocmds (`{TextChanged, TextChangedI}`, `InsertLeave`, `BufWritePost`) are intact and still correctly invalidate the cache on content changes. The `cache.lua:172` `{BufDelete, BufWipeout}` autocmd that does the real work (calling `cache.remove`) is unchanged. The unrelated `init.lua:113` `{BufDelete, BufWipeout}` for report cleanup is unchanged.
- **Task 5 — dual-naming:** Both legacy keys removed from `mock_pandoc_full` (only `characters` and `automated_readability` remain in the nested tables). Test `full_spec.lua:57` migrated to the new field name. `assert_metrics_structure(metrics, "basic")` STILL asserts `metrics.chars` because that's the canonical basic-mode field name — this is correct, not stale.
- **Task 6 — dead code:** `format_full_report` is fully removed (function + docstring). The 3 unused `local` declarations are gone. The loop variable rename uses `_entry`. Test suite passes — confirming nothing inadvertently depended on the dead function or unused locals.
- **Task 7 — lint config completeness:** `.stylua.toml` matches the codebase's 2-space convention (`stylua --check lua/` returns zero diffs). `.luacheckrc`'s new `files["scripts/textmetrics.lua"]` stanza declares every Pandoc-injected global the filter uses. The count of warnings drops from 195 to 0 with no `--no-` filter flags added.
- **No scope creep:** Diff doesn't touch `docs/` (deferred to Plan I), `display.lua`'s structure (audit verdict: cohesive, leave alone), or any spec file outside the three touched in Tasks 1, 3, 5.
- **Baseline preservation:** Other spec files' pass/fail counts are unchanged from Plan G baseline.

---

## After completion

Memory updates:

- Delete `~/.claude/projects/-home-jkeim--config-nvim/memory/project_nvim_writing_metrics_full_spec_failures.md` (all 4 failures closed).
- Delete `~/.claude/projects/-home-jkeim--config-nvim/memory/project_nvim_writing_metrics_plan_e_followups.md` (both items addressed: show_comparison in Task 2, basic_spec timeout in Task 3).
- Delete `~/.claude/projects/-home-jkeim--config-nvim/memory/project_nvim_writing_metrics_plan_f_followups.md` (both items addressed: BufDelete duplicate in Task 4, helpers dual-naming in Task 5).
- Update `~/.claude/projects/-home-jkeim--config-nvim/memory/MEMORY.md`: remove the three deleted entries' lines. Optionally add an entry pointing to a fresh `project_nvim_writing_metrics_plan_i_doc_sweep.md` memory documenting the 11 stale doc references — or skip the memory and let Plan I's brainstorm re-derive from this plan's spec.

After Plan H lands, `nvim-writing-metrics` is at a steady state: clean test suite (118 / 0), clean lint output (0 warnings across 22 files), no known code debt. The only outstanding work is `docs/` staleness (Plan I, ~11 line edits across three markdown files).

## Summary

7 commits, ~60 lines of net code change across `lua/writing-metrics/{basic,init,cache,display}.lua` and `tests/{full_spec,basic_spec,helpers}.lua`, plus one new `.stylua.toml` file and a small `.luacheckrc` addition. Closes the final 4 test failures, drains all 4 memorized follow-up debt items, eliminates 5 trivial luacheck warnings and 195 false-positive ones, and unblocks future stylua use. Estimated 45-60 minutes of focused work plus the holistic review.
