# Plan E — `basic_spec.lua` cleanup design

**Date:** 2026-05-17
**Repo affected:** `~/projects/nvim-writing-metrics/`
**Baseline:** `b819360` (post Plan C) — full suite 87 pass / 32 fail, `basic_spec.lua` 22 pass / 9 fail.
**Target:** `basic_spec.lua` 31 pass / 0 fail; full suite 96 pass / 23 fail. No other spec file's count moves.

## Goal

Eliminate the 9 known-failing tests in `basic_spec.lua` by fixing one real implementation bug (`get_fast_count` ignoring its buffer argument) and three stale test assertions that pre-date implementation modernizations. The cleanup is self-contained, well-understood, and has zero net effect on the production statusline word count.

## Why now

Memorized in `project_nvim_writing_metrics_stale_tests.md` since 2026-05-17. These 9 failures have been baseline noise for at least three feature cycles (reading-time, Plan A, Plan B, Plan C). Each new piece of work has to subtract them from the failure count to confirm no regression, which is friction. The root causes are documented; the fixes are mechanical.

## Architecture

Four atomic clusters, one commit per cluster, on `main` of `~/projects/nvim-writing-metrics/`. After each commit, re-run the full suite and confirm the failure count drops monotonically without disturbing the 23 pre-existing failures in other spec files (4 in `full_spec.lua` + 19 distributed across `config_spec.lua`, `compatibility_spec.lua`, `integration_spec.lua`).

Per the spec, Plan E uses **one holistic review at the end** in place of per-cluster spec/code-quality reviews — same reasoning as Plan C: mechanical changes, uniform reviewer criteria, one combined review is more efficient than four small ones.

## Clusters

### Cluster 1 — Fix `get_fast_count` (implementation bug)

**Files:**
- Modify: `lua/writing-metrics/basic.lua`

**Tests fixed:** 4 (`counts words in simple text`, `counts characters`, `handles single word`, `ignores markdown syntax in fast mode` in the `fast word count` describe block).

**Root cause:** `M.get_fast_count(bufnr)` accepts a `bufnr` argument and normalizes nil/0 to the current buffer, but its body calls `vim.fn.wordcount()`, which always counts the current buffer and ignores any input. The argument is dead. Production callers in the statusline pass `0` (current buffer), so the bug is invisible there, but `show_comparison` at `basic.lua:62,72` passes a real bufnr and silently gets the wrong count when the comparison buffer is not the current one.

**Fix:** Rewrite the function body to read the passed buffer directly:

```lua
function M.get_fast_count(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return { words = 0, chars = 0, sentences = 0, paragraphs = 0,
             avg_sentence_len = 0, avg_word_len = 0 }
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local words, chars = 0, 0
  for _, line in ipairs(lines) do
    for _ in line:gmatch("%S+") do words = words + 1 end
    chars = chars + vim.fn.strchars(line)
  end
  -- +1 char per newline between lines (matches vim.fn.wordcount() behaviour)
  if #lines > 1 then chars = chars + (#lines - 1) end

  return {
    words = words,
    chars = chars,
    sentences = 0,    -- preserved: this function never counted sentences
    paragraphs = 0,
    avg_sentence_len = 0,
    avg_word_len = 0,
  }
end
```

**Behavior change:** When called with a non-current `bufnr`, the function now returns counts for that buffer instead of for whatever buffer happens to be current. Production statusline (always `bufnr=0`) is unaffected. `show_comparison` correctness improves in the rare edge case where it runs against a non-current buffer.

**Verification:** After this commit, the 4 fast-count tests pass without modification, and the 2 invalid-buffer tests at `basic_spec.lua:455,464` continue to pass (covered by the `nvim_buf_is_valid` guard).

### Cluster 2 — Statusline assertions (test-only)

**Files:**
- Modify: `tests/basic_spec.lua`

**Tests fixed:** 3 (`returns statusline string`, `contains word count indicator`, `mode affects statusline output` in the `statusline integration` describe block).

**Root cause:** `M.get_statusline_string(bufnr)` returns:
- `""` (empty string) for non-writing filetypes
- `{ text, color }` table otherwise

Tests assert `assert.is_string(str)` which fails for the table return. The function name is misleading but consistent with how lualine consumes the value (lualine accepts either form).

**Fix:** Add a local helper at the top of the `statusline integration` describe block to normalize:

```lua
local function statusline_text(v)
  if type(v) == "table" then return v.text end
  return v
end
```

Then update the three failing tests to call `statusline_text(...)` before asserting on the text content. Keep the empty-filetype path tested separately so the empty-string return is still covered.

**Verification:** Tests pass. No implementation change.

### Cluster 3 — Async wait on "strips markdown" test (test-only)

**Files:**
- Modify: `tests/basic_spec.lua`

**Tests fixed:** 1 (`accurate word count - strips markdown syntax` at line ~121).

**Root cause:** The test calls `helpers.wait_for_async(predicate, timeout)` which returns silently on timeout. The next line dereferences `result_data.words` without asserting `result_data` is non-nil first. On slow CI or a slow Pandoc startup, the predicate hasn't been satisfied when the assertion runs, and the dereference fails with `attempt to index a nil value`.

**Fix:**
1. Bump the timeout from 3000ms (line 117) to 5000ms — matching the abbreviation tests at lines 264, 282, 302 in the same file which already use 5000.
2. Add an explicit `assert.is_not_nil(result_data, "Pandoc callback did not complete in time")` before any dereference, so timeout failures surface with a clear diagnostic instead of a confusing nil-index traceback.

**Verification:** Test passes locally. The descriptive failure message makes future timeouts (e.g., on slow CI) actionable.

### Cluster 4 — Lualine component assertion (test-only)

**Files:**
- Modify: `tests/basic_spec.lua`

**Tests fixed:** 1 (`component has required fields` at line ~247).

**Root cause:** `M.lualine_component()` returns a table in lualine's documented format: `{ render_fn, cond = ..., color = ... }`. The render function lives at `component[1]`, not `component.update`. The test was written against a different lualine convention.

**Fix:** Update the assertion from:

```lua
assert.is_true(type(component) == "function" or type(component.update) == "function")
```

to:

```lua
assert.is_function(component[1])
```

The companion assertions in the same `lualine_component` test (`is_table`, presence of `cond` and `color`) can stay as-is; they already match the real shape.

**Verification:** Test passes. No implementation change.

## Verification

After each cluster commits, run the full suite and confirm the monotonic drop:

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected progression (totals across the whole suite):

| After cluster | `basic_spec.lua` | Full suite |
|---|---|---|
| Baseline | 22 / 9 | 87 / 32 |
| Cluster 1 | 26 / 5 | 91 / 28 |
| Cluster 2 | 29 / 2 | 94 / 25 |
| Cluster 3 | 30 / 1 | 95 / 24 |
| Cluster 4 | 31 / 0 | 96 / 23 |

If any cluster's commit moves a count outside this table — particularly if any other spec file's failure count changes — STOP and investigate; the change is attributable to the just-landed commit.

## Holistic review

After all four commits land, dispatch one code-reviewer subagent against the cumulative diff (`git diff b819360 HEAD`). Reviewer focuses:

- **Cluster 1 correctness:** Does the rewritten word-counting loop match `vim.fn.wordcount()`'s semantics closely enough that the existing tests pass (the tests assert words > 0 and chars > words, not exact integers, so this is permissive — but verify the newline-count adjustment is right).
- **Test assertion accuracy:** Each updated assertion in clusters 2-4 actually checks what the test name claims.
- **Diagnostic quality:** The cluster 3 `is_not_nil` message is descriptive.
- **No scope creep:** Diff contains only the four targeted clusters' edits; no incidental refactoring, no other spec files touched, no production code outside `get_fast_count`.
- **Baseline preservation:** Other spec files' counts unchanged.

## Out of scope

- The 4 `full_spec.lua` isolation failures (`_G.writing_metrics_reports` not initialized in test scope). Different root cause; separate plan.
- The 19 unaccounted failures distributed across `config_spec.lua`, `compatibility_spec.lua`, `integration_spec.lua`. Not yet investigated; needs an audit pass before a fix plan.
- Renaming `get_statusline_string` (it returns a table sometimes, so the name lies) — out of scope for a cleanup plan; can be a future API-grooming task.
- Removing the bufnr parameter from `get_fast_count` — Cluster 1 fixes the contract instead. Removal would be a larger API change with more callers to touch.

## Summary

4 clusters, 4 commits on `main` of `~/projects/nvim-writing-metrics/`. ~30 lines of edits total (one production rewrite + ~15 lines of test updates). No production behavior change visible to users. Estimated 20-30 minutes of focused work plus the holistic review.

After completion:
- `basic_spec.lua` runs clean (31/0).
- Full suite at 96/23 — the remaining 23 failures are the `full_spec.lua` and config/compatibility/integration clusters, each tracked separately.
- `project_nvim_writing_metrics_stale_tests.md` memory should be deleted (no longer accurate) and the baseline note in any subsequent plan should be updated to 96/23.
