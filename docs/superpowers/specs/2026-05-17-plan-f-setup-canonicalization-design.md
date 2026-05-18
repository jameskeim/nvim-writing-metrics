# Plan F — `setup()` canonicalization design

**Date:** 2026-05-17
**Repo affected:** `~/projects/nvim-writing-metrics/`
**Baseline:** post Plan E — full suite 96 pass / 23 fail.
**Target:** 109 pass / 10 fail. Closes 13 failures (compat 7→0, integration 6→0) and resolves a latent production bug in the `_G.accurate_wordcount` shim.

## Goal

Make `require("writing-metrics").setup(opts)` the single canonical entry point for every side effect the plugin produces — command registration, autocmd registration, backward-compatibility globals, and the `basic` module's bootstrap. `plugin/writing-metrics.lua` shrinks to a minimal bootstrap that calls `setup({})` when the user isn't using lazy.nvim's opts table. Tests that call `metrics.setup()` get the full plugin behavior automatically, which is the source of all 13 closed failures.

## Why now

Three failure clusters in the test suite share one architectural root cause: side effects (commands, shims, autocmds) live at module-level in `plugin/writing-metrics.lua` and `init.lua`/`basic.lua` rather than inside `setup()`. The `plugin/` file runs at Neovim startup but not in busted/plenary test context, so test `before_each` blocks that call `metrics.setup()` get a half-initialized plugin. Beyond closing the tests, the consolidation fixes a real production bug (the `_G.accurate_wordcount` collision between `init.lua:500` function-form and `basic.lua:548` table-form — the table wins, so the function-form shim is dead code that lualine configs may silently be miscalling).

## Architecture

Three coupled changes plus three trivial folded-in test cleanups, in 4-5 commits on `main` of `~/projects/nvim-writing-metrics/`. Per the spec, Plan F uses **one holistic review at the end** in place of per-task reviews (same precedent as Plans C and E).

After Plan F:
- `plugin/writing-metrics.lua` is a ~15-line bootstrap. No command definitions, no autocmd definitions, no shim assignments.
- `lua/writing-metrics/commands.lua` is a new ~250-line module owning every `nvim_create_user_command` call, exporting `setup_commands(cfg)`.
- `lua/writing-metrics/init.lua` is the orchestrator. `setup()` calls config → commands → autocmds → shims → `basic.setup()` in that order.
- `_G.accurate_wordcount` is a callable table; `_G.text_metrics` stays a plain function.

## Change 1 — Extract commands to `lua/writing-metrics/commands.lua`

**Files affected:**
- Create: `lua/writing-metrics/commands.lua` (~250 lines)
- Modify: `lua/writing-metrics/init.lua` (`setup()` body)
- Modify: `lua/writing-metrics/config.lua` (add `commands.enable_legacy` to defaults)
- Modify: `plugin/writing-metrics.lua` (shrink to bootstrap)

**New module surface:**

```lua
-- lua/writing-metrics/commands.lua
local M = {}

--- Register all user commands. Idempotent — calling twice overwrites
--- (nvim_create_user_command's natural behavior).
--- @param cfg table Resolved config (from config.get())
function M.setup_commands(cfg)
  -- Primary commands (always registered)
  vim.api.nvim_create_user_command("WordCount", ...)
  vim.api.nvim_create_user_command("ReadabilityReport", ...)
  vim.api.nvim_create_user_command("ReadingTime", ...)
  vim.api.nvim_create_user_command("WritingMetrics", ...)
  vim.api.nvim_create_user_command("WritingMetricsToggle", ...)
  vim.api.nvim_create_user_command("WritingMetricsCache", ...)
  vim.api.nvim_create_user_command("WritingMetricsClear", ...)

  -- Legacy aliases (gated by config)
  if cfg.commands and cfg.commands.enable_legacy then
    vim.api.nvim_create_user_command("AccurateWordCount", ...)
    vim.api.nvim_create_user_command("ToggleWordCountMode", ...)
  end
end

return M
```

**Implementation details:**
- All command bodies are copied verbatim from `plugin/writing-metrics.lua` (lines 18–232). No behavior change.
- The legacy aliases (`:AccurateWordCount`, `:ToggleWordCountMode`) currently exist as TWO duplicate definitions in `plugin/writing-metrics.lua` (lines 131/143 — full implementations, dead code — and lines 220/227 — thin `vim.cmd("...")` wrappers, which win because they're defined later and overwrite). Plan F keeps the **wrapper form** (the live one) and deletes the dead full-implementation duplicates.

**Config change:**

Add to `M.defaults` in `lua/writing-metrics/config.lua`:

```lua
  -- Command registration
  commands = {
    enable_legacy = true, -- Register :AccurateWordCount, :ToggleWordCountMode aliases
  },
```

`enable_legacy = true` is the default to preserve backward compatibility — users who depend on the legacy aliases don't need to opt in.

**setup() integration:**

In `lua/writing-metrics/init.lua`'s `M.setup()`, after `config.setup(opts)` validates and merges the user config, add:

```lua
  -- Register user commands (replaces plugin/writing-metrics.lua's setup_commands)
  require("writing-metrics.commands").setup_commands(config.get())
```

(Note: `config.get()` is one of the missing accessors flagged in the config-spec audit. It's NOT required for Plan F — the call here can use `config.config` directly, the same way other modules in `init.lua` already do. Plan G will add `M.get()` as a clean accessor; Plan F shouldn't grow scope. Use `config.config` here and let Plan G migrate the call site.)

**Failures closed:** compat cluster 2 (2 tests: `registers all standard commands`, `registers legacy commands when enabled`) + integration cluster 3 (4 tests: `registers WordCount`, `registers ReadabilityReport`, `registers WritingMetricsToggle`, `registers legacy commands when enabled`). The `does not register legacy commands when disabled` test (which currently passes vacuously) starts asserting meaningfully against the new `enable_legacy` gate. Total: 6 tests closed.

## Change 2 — Move shims into `setup()`, make `_G.accurate_wordcount` a callable table

**Files affected:**
- Modify: `lua/writing-metrics/init.lua` (delete lines 498–533, add shim registration to `setup()` body)
- Modify: `lua/writing-metrics/basic.lua` (delete the `_G.accurate_wordcount = { ... }` block at lines 548–561)
- Modify: `tests/compatibility_spec.lua` (update one assertion to test callability, not `type == "function"`)

**The collision being resolved:**

| Location | Type | Contract |
|---|---|---|
| `init.lua:500` | function | `accurate_wordcount()` → number (current cached word count) |
| `basic.lua:548` | table | `accurate_wordcount.get_fast_count(bufnr)` → metrics |

Because `init.lua` requires `basic.lua` (indirectly via `get_basic()`), the table assignment fires after the function assignment and silently clobbers it. Anyone calling `accurate_wordcount()` in production today gets `attempt to call a table value`. The fix: a callable table that satisfies both contracts.

**New shim registration inside `setup()`** (replaces module-level sites):

```lua
  -- Backward-compat globals (must run after commands so basic is available)
  local basic = require("writing-metrics.basic")
  local cache = require("writing-metrics.cache")
  local utils = require("writing-metrics.utils")

  local acc_wc = {
    get_fast_count = basic.get_fast_count,
    get_accurate_count = basic.get_accurate_count,
    get_reading_time = basic.get_reading_time,
    show_reading_time = basic.show_reading_time,
    show_comparison = basic.show_comparison,
    toggle_statusline_mode = basic.toggle_statusline_mode,
    statusline_mode = basic.statusline_mode,
    update_lualine_accurate_count = basic.update_statusline_accurate_count,
  }
  setmetatable(acc_wc, {
    __call = function()
      local cached = cache.get_basic(vim.api.nvim_get_current_buf())
      return (cached and cached.words) or 0
    end,
  })
  _G.accurate_wordcount = acc_wc

  _G.text_metrics = function()
    local bufnr = vim.api.nvim_get_current_buf()
    if not M.is_writing_buffer(bufnr) then
      return ""
    end
    local cached = cache.get_basic(bufnr)
    if cached then
      return string.format(
        "󰗊 %s words  󰬶 %s chars",
        utils.format_number(cached.words),
        utils.format_number(cached.chars)
      )
    end
    return "󰗊 …"
  end
```

(Bodies are copied from the existing `init.lua:500-533` function-form site for `text_metrics` and from the merged contracts of both sites for `accurate_wordcount`.)

**Test assertion change** in `tests/compatibility_spec.lua`:

The current assertions at lines 24 and 31 check `_G.accurate_wordcount` exists and is a function:

```lua
assert.is_not_nil(_G.accurate_wordcount)
-- ...
assert.is_function(_G.accurate_wordcount)
```

Update the `is_function` assertion to test the actual contract (callable table):

```lua
assert.is_true(
  type(_G.accurate_wordcount) == "table",
  "accurate_wordcount should be a table"
)
local ok, _ = pcall(_G.accurate_wordcount)
assert.is_true(ok, "accurate_wordcount should be callable via __call")
```

`is_not_nil` and `provides _G.text_metrics` (line 37) need no change — `text_metrics` remains a plain function. The corresponding `text_metrics is callable` assertion at line 44 stays as `assert.is_function`.

**Failures closed:** compat cluster 1 (4 tests: `provides _G.accurate_wordcount`, `accurate_wordcount is callable`, `provides _G.text_metrics`, `text_metrics is callable`). Total: 4 tests closed.

## Change 3 — Move autocmds and `basic.setup()` into `setup()`

**Files affected:**
- Modify: `lua/writing-metrics/init.lua` (extend `setup()` to call autocmd registration and `basic.setup()`)
- Modify: `plugin/writing-metrics.lua` (delete `setup_autocommands()` and `initialize()`'s post-setup calls)

**Background:** `plugin/writing-metrics.lua`'s `initialize()` currently does (in order):
1. `wm.setup(opts)` — runs `init.lua`'s setup
2. `setup_commands()` — registers commands (moved to Change 1)
3. `setup_autocommands()` — registers 4 cache-invalidation autocmds (this change)
4. `basic.setup()` — bootstraps the basic module's statusline integration (this change)

After Plan F, all four steps happen inside `wm.setup()`, and `plugin/writing-metrics.lua` just calls `wm.setup({})`.

**Autocmd handling:** The 4 cache-invalidation autocmds in `plugin/writing-metrics.lua` (lines 244–280: TextChanged/TextChangedI, InsertLeave, BufWritePost, BufDelete) belong to augroup `WritingMetrics`. They register independently of `cache.setup_autocmds()` (which the existing `init.lua:setup()` already calls — that registers DIFFERENT autocmds inside augroup `WritingMetricsCache`). After Plan F, the plugin/ autocmds should be moved verbatim into a new private function in `init.lua` (or extended into `cache.setup_autocmds()`; either works). To keep the diff focused, **inline them into `init.lua:setup()` as a `vim.api.nvim_create_augroup` + 4 `nvim_create_autocmd` calls**. No behavior change; no consolidation with the cache module.

**`basic.setup()` call:** Add `require("writing-metrics.basic").setup()` to `init.lua:setup()` after the autocmd registration. Mirrors what `plugin/writing-metrics.lua:initialize()` does today.

**`plugin/writing-metrics.lua` final form:**

```lua
-- plugin/writing-metrics.lua
-- Bootstrap: load the plugin unless the user opted into lazy.nvim's opts flow.

if vim.g.loaded_writing_metrics then
  return
end

if not vim.g.writing_metrics_lazy then
  -- Traditional plugin loading — initialize with default opts.
  require("writing-metrics").setup({})
end
```

(The `vim.g.loaded_writing_metrics = 1` flag is set inside `init.lua:setup()` instead of in `plugin/`, so lazy.nvim users also get the flag and the `if vim.g.loaded_writing_metrics then return end` guard at the top of `plugin/` still works on subsequent reloads.)

**Failures closed:** None directly. This change is a structural follow-on from Change 1 — `plugin/`'s `initialize()` is no longer needed once `setup()` owns everything, so eliminating the duplicated orchestration is the natural cleanup. Without this, `plugin/` would be a confusing mix of "calls setup" + "registers autocmds + basic.setup separately."

## Change 4 — Fold in 3 stale-test fixes

**Files affected:**
- Modify: `tests/compatibility_spec.lua` (cluster 3, 1 line)
- Modify: `tests/integration_spec.lua` (cluster 1: callback arity + dead call; cluster 2: assertion shape)

All three live in test files Plan F already edits for the contract changes above, so the incremental cost is essentially zero (one extra commit covering all three, or rolled into Changes 1/2's commits). Same precedent as Plan C extending into test files and Plan E mixing test fixes with one implementation fix.

**compat cluster 3 (1 failure, line 158):** The `cache module exports expected functions` test asserts `cache.get_full` and `cache.set_full` exist. They never did. Remove `"get_full"` and `"set_full"` from the expected-functions list. One-line edit.

**integration cluster 1 (1 failure, line 102):** The `full workflow` test's callback is declared `function(data) result_data = data end` but `full.get_full_metrics` calls it as `callback(true, data)`, so `result_data` is the boolean `true`. The test then dereferences `result_data.words` and crashes. Fix: change the callback declaration to `function(ok, data) result_data = data end`. Also delete the dead `cache.get_full(bufnr)` call on line 105 (the function doesn't exist; the assertion that follows tests cache integration but the test would crash before reaching it). Two-line edit.

**integration cluster 2 (1 failure, line 175):** The `cache invalidates on buffer modification` test asserts `cache.get_basic(bufnr)` returns `nil` after `cache.invalidate(bufnr)`, but invalidate is a soft-stale mark by design — `get_basic` returns the cached entry with `stale = true`. Change the assertion from `assert.is_nil(...)` to `local entry, stale = cache.get_basic(bufnr); assert.is_true(stale, "entry should be marked stale after invalidate")`. One-line conceptual change (a few lines as written).

**Failures closed:** 3 (1 in compat_spec, 2 in integration_spec).

## Tasks & commits

4 commits on `main`:

1. **`feat(commands): extract command registration to dedicated module`** — Change 1. Creates `commands.lua`, adds `commands.enable_legacy` to config defaults, wires `setup()` to call it, shrinks `plugin/`'s `setup_commands()` to nothing (or deletes it outright). Closes 6 failures (compat cluster 2 + integration cluster 3). Expected: full suite 96/23 → 102/17.

2. **`refactor(shims): move globals into setup() as callable table`** — Change 2. Deletes module-level shim sites, builds callable-table `accurate_wordcount` and function `text_metrics` in `setup()`. Updates the one compat-spec assertion to test callability. Closes 4 failures (compat cluster 1). Expected: 102/17 → 106/13.

3. **`refactor(plugin): collapse initialize() into setup()`** — Change 3. Moves autocmds and `basic.setup()` from `plugin/`'s `initialize()` into `init.lua`'s `setup()`. `plugin/` becomes a ~15-line bootstrap. Closes 0 failures directly but completes the architectural consolidation. Expected: 106/13 (no count change; this is structural).

4. **`test(specs): fix 3 stale assertions in compat/integration`** — Change 4. compat cluster 3 (`get_full`/`set_full` removed from list), integration cluster 1 (callback arity + dead call), integration cluster 2 (invalidate assertion). Closes 3 failures. Expected: 106/13 → 109/10.

After each commit, re-run the full suite and confirm the count matches the table. Per Plan C/E pattern, **one holistic review at the end** against the cumulative diff `b819360..HEAD` (or whatever Plan E's tip SHA is).

## Verification

After all four commits land:

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected progression (totals across the whole suite):

| After commit | Full suite | What closed |
|---|---|---|
| Baseline (post Plan E) | 96 / 23 | — |
| 1: commands | 102 / 17 | 6 cmd-registration failures (compat-2 + integration-3) |
| 2: shims | 106 / 13 | 4 shim-timing failures (compat-1) |
| 3: plugin collapse | 106 / 13 | structural, no count change |
| 4: stale tests | 109 / 10 | 3 stale assertions (compat-3 + integration-1 + integration-2) |

The remaining 10 failures: 6 in `config_spec.lua` (Plan G territory) + 4 in `full_spec.lua` (separate isolation cluster).

## Holistic review

Single code-reviewer subagent against `git diff <plan-e-tip> HEAD`. Reviewer focus:

- **Change 1 — command parity:** Every command currently defined in `plugin/writing-metrics.lua` (11 calls, including the two duplicate `AccurateWordCount`/`ToggleWordCountMode` pairs) is represented exactly once in `commands.lua`. The legacy aliases use the wrapper form (the currently-live definition), not the dead full-implementation duplicates.
- **Change 1 — config defaults:** `commands.enable_legacy` defaults to `true`. The "disabled" test path actually exercises the disabled state.
- **Change 2 — callable-table correctness:** `setmetatable(acc_wc, { __call = ... })` is set BEFORE `_G.accurate_wordcount = acc_wc`. The `__call` body returns the same value the old `init.lua:500` function did (`cached.words or 0`). The table fields preserve the exact field names from `basic.lua:548`.
- **Change 2 — shim ordering:** Shims are registered AFTER `commands.setup_commands()` in `setup()` so the basic module is required before shim setup tries to reference it.
- **Change 3 — autocmd parity:** All 4 cache-invalidation autocmds (TextChanged, TextChangedI grouped, InsertLeave, BufWritePost, BufDelete) are preserved with the same patterns and same `WritingMetrics` augroup name.
- **Change 3 — `plugin/` minimalism:** The bootstrap file is ≤20 lines, contains no `nvim_create_user_command` or `nvim_create_autocmd` calls.
- **Change 4 — test fidelity:** Each updated assertion in clusters 1/2/3 actually checks what the test name claims.
- **No scope creep:** Diff doesn't touch `config_spec.lua`, `full_spec.lua`, or `basic_spec.lua` (Plan E already cleaned that one).

## Out of scope

- **`config_spec.lua` cleanup** (6 failures): Different module, different concerns (`M.get()` accessor, `filter.path` rename, `_filter_path` cache invalidation). Plan G.
- **`full_spec.lua` test-isolation failures** (4 failures): Different cluster, different root cause (`_G.writing_metrics_reports` not initialized in test scope, invalid buffer ids). Separate plan; the lower-friction one to start after Plan F.
- **`config.get()` accessor:** Plan F calls `config.config` directly to avoid scope creep. Plan G adds `M.get()` and migrates the call site.
- **Cache-autocmd deduplication:** Plan F preserves both `plugin/`'s autocmds (moved to `setup()`) and `cache.setup_autocmds()` (already called by setup); they belong to different augroups and don't conflict. If they DO overlap on inspection, that's a follow-up.
- **Removing the legacy aliases entirely:** `enable_legacy = true` default preserves them. Users can opt out via `setup({ commands = { enable_legacy = false } })`. Removing them is a breaking change for a future major version, not Plan F.

## Memory updates after completion

- Delete `project_nvim_writing_metrics_compatibility_spec_failures.md` (all 7 failures closed).
- Delete `project_nvim_writing_metrics_integration_spec_failures.md` (all 6 failures closed).
- Update `project_nvim_writing_metrics_full_spec_failures.md` baseline note from `96 / 23` to `109 / 10`.
- Update `project_nvim_writing_metrics_config_spec_failures.md` baseline note similarly.
- Update `MEMORY.md` index lines for the two deleted entries (just remove them).

## Summary

4 commits, ~3 file creations/moves + ~6 file edits, ~50-80 lines of net code change (mostly relocation, not new logic). Resolves 13 of the 19 remaining test failures and fixes a latent production bug. Estimated 60-90 minutes of focused work plus the holistic review. After completion the plugin's setup contract matches what any user reading the README would expect: "call `setup({ ... opts ... })` once, and everything works."
