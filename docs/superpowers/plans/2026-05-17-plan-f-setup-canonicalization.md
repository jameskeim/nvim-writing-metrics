# Plan F — `setup()` canonicalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `require("writing-metrics").setup(opts)` the single canonical entry point for command registration, autocmd registration, backward-compatibility globals, and the `basic` module's bootstrap — closing 13 of the remaining 23 test failures and resolving the latent `_G.accurate_wordcount` collision bug.

**Architecture:** Four sequential commits on `main` of `~/projects/nvim-writing-metrics/`. Commit 1 extracts command registration into a new `commands.lua` module called from `setup()`. Commit 2 moves the `_G.accurate_wordcount` / `_G.text_metrics` shims into `setup()` and resolves the function-vs-table collision via a callable table. Commit 3 collapses `plugin/writing-metrics.lua`'s remaining responsibilities (autocmds, `basic.setup()`, loaded flag) into `setup()` so `plugin/` becomes a ~15-line bootstrap. Commit 4 cleans up 3 stale assertions in the test files Plan F already touches. Per the spec, Plan F uses one holistic review at the end (mirrors Plan C/E).

**Tech Stack:** Lua 5.1 (LuaJIT in Neovim), `vim.api.nvim_create_user_command`, `vim.api.nvim_create_autocmd`, Lua `__call` metamethod for callable-table compat shim, `busted`/`plenary.test_harness` for tests.

---

## Conventions

- **Plugin repo:** `~/projects/nvim-writing-metrics/` — git-tracked, commits land directly on `main`.
- **Run tests:** `cd ~/projects/nvim-writing-metrics && ./run-tests.sh` (all specs).
- **Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-17-plan-f-setup-canonicalization-design.md`
- **Baseline (HEAD `a08eab8`, post-Plan E):** 96 pass / 23 fail across the full suite.
- **Target:** 109 pass / 10 fail. The remaining 10 are 6 in `config_spec.lua` (Plan G) + 4 in `full_spec.lua` (separate isolation plan).

**Verification after each task:**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected progression (totals across the whole suite):

| After commit | Full suite | What closed |
|---|---|---|
| Baseline (post Plan E) | 96 / 23 | — |
| Task 1 (commands) | 102 / 17 | compat-2 (2) + integration-3 (4) = 6 |
| Task 2 (shims) | 106 / 13 | compat-1 (4) |
| Task 3 (plugin collapse) | 106 / 13 | structural, no count change |
| Task 4 (stale tests) | 109 / 10 | compat-3 (1) + integration-1 (1) + integration-2 (1) = 3 |

If a task's count diverges from the table, STOP and investigate — the shift is attributable to the just-landed change.

**Setup() ordering convention** (used in Tasks 1-3): `setup()` runs config + shims on every call, but the structural side effects (autocmds, commands, `basic.setup`) are guarded by `M._initialized` so they only fire once per process. Shims MUST be outside the guard because the test `before_each` pattern nils the globals between calls and relies on `setup()` to restore them.

---

## Task 1: Extract commands to `commands.lua`

**Files:**
- Create: `~/projects/nvim-writing-metrics/lua/writing-metrics/commands.lua`
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua` (add `commands.enable_legacy` to defaults)
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` (call `commands.setup_commands` from `setup()`)
- Modify: `~/projects/nvim-writing-metrics/plugin/writing-metrics.lua` (delete `setup_commands()` and its call from `initialize()`)

**Failures closed:** 6 (compat cluster 2: `registers all standard commands`, `registers legacy commands when enabled` + integration cluster 3: `registers WordCount`, `registers ReadabilityReport`, `registers WritingMetricsToggle`, `registers legacy commands when enabled`).

- [ ] **Step 1: Confirm the 6 targeted tests currently fail**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/compatibility_spec.lua 2>&1 | grep -aE "registers|Success: |Failed : "
./run-tests.sh -t tests/integration_spec.lua 2>&1 | grep -aE "registers|Success: |Failed : "
```

Expected: `compatibility_spec` reports 10/7; `integration_spec` reports 13/6. The `registers ...` tests show as failures in both files.

- [ ] **Step 2: Add `commands` defaults to `config.lua`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua`, find the `M.defaults = {` block. After the `filter = { ... }` block (the last key in `M.defaults`), add a new `commands` key. The relevant existing context:

```lua
  -- Pandoc filter settings
  filter = {
    auto_detect = true, -- Automatically find bundled filter
    custom_path = nil, -- Override with custom path
  },
}
```

Replace with:

```lua
  -- Pandoc filter settings
  filter = {
    auto_detect = true, -- Automatically find bundled filter
    custom_path = nil, -- Override with custom path
  },

  -- Command registration
  commands = {
    enable_legacy = true, -- Register :AccurateWordCount and :ToggleWordCountMode aliases
  },
}
```

`enable_legacy = true` is the default so existing users who rely on the legacy command names don't break.

- [ ] **Step 3: Create `lua/writing-metrics/commands.lua`**

Write the following file at `~/projects/nvim-writing-metrics/lua/writing-metrics/commands.lua`. All command bodies are copied verbatim from `plugin/writing-metrics.lua`'s `setup_commands()` (lines 17–232). Only the duplicate `AccurateWordCount`/`ToggleWordCountMode` definitions (the dead full-implementation pair at plugin/.lua:131-148) are deleted; the live wrapper pair (plugin/.lua:220-232) is kept.

```lua
--- User command registration for nvim-writing-metrics
--- @module writing-metrics.commands
local M = {}

--- Register all user commands. Idempotent — nvim_create_user_command
--- overwrites on redefine, so calling twice is safe.
--- @param cfg table Resolved config (e.g. require("writing-metrics.config").config)
function M.setup_commands(cfg)
  -- Primary commands

  vim.api.nvim_create_user_command("WordCount", function(opts)
    local basic = require("writing-metrics.basic")
    if opts.range == 2 then
      basic.show_comparison(vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2])
    else
      basic.show_comparison()
    end
  end, {
    desc = "Show word count (basic metrics)",
    range = true,
  })

  vim.api.nvim_create_user_command("ReadabilityReport", function(opts)
    local full = require("writing-metrics.full")
    if opts.range == 2 then
      full.show_report(vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2])
    else
      full.show_report()
    end
  end, {
    desc = "Generate comprehensive readability report",
    range = true,
  })

  vim.api.nvim_create_user_command("ReadingTime", function()
    require("writing-metrics.basic").show_reading_time()
  end, { desc = "Show reading time toast (silent + spoken)" })

  vim.api.nvim_create_user_command("WritingMetrics", function()
    local config = require("writing-metrics.config")
    local utils = require("writing-metrics.utils")

    local pandoc_status = vim.fn.executable("pandoc") == 1
      and "✓ Available"
      or "✗ Not found (install for full functionality)"

    local lines = {
      "# Writing Metrics Plugin",
      "",
      "**Version:** 1.0.0",
      "**Pandoc:** " .. pandoc_status,
      "",
      "## Commands",
      "",
      "| Command | Description |",
      "|---------|-------------|",
      "| `:WordCount` | Show basic word count (works in visual mode) |",
      "| `:ReadabilityReport` | Generate comprehensive report |",
      "| `:ReadingTime` | Show reading time toast (silent + spoken) |",
      "| `:WritingMetricsToggle` | Toggle fast/accurate mode |",
      "| `:WritingMetricsCache` | Show cache status and statistics |",
      "| `:WritingMetricsClear` | Clear all caches |",
      "",
      "## Backward Compatibility",
      "",
      "| Old Command | New Command |",
      "|-------------|-------------|",
      "| `:AccurateWordCount` | `:WordCount` |",
      "| `:ToggleWordCountMode` | `:WritingMetricsToggle` |",
      "",
      "## Keybindings (suggested)",
      "",
      "```lua",
      "vim.keymap.set('n', '<leader>mc', '<cmd>WordCount<cr>')",
      "vim.keymap.set('v', '<leader>mc', '<cmd>WordCount<cr>')",
      "vim.keymap.set('n', '<leader>mr', '<cmd>ReadabilityReport<cr>')",
      "vim.keymap.set('n', '<leader>mt', '<cmd>WritingMetricsToggle<cr>')",
      "vim.keymap.set('n', '<leader>mT', '<cmd>ReadingTime<cr>')",
      "```",
      "",
      "## Configuration",
      "",
      "**Cache strategy:**",
      "- Statusline: Basic metrics cached until buffer content changes (changedtick)",
      "- Reports: Always compute fresh (no cache)",
      "",
      "**Enabled features:**",
      "- Basic metrics: " .. (config.config.features.basic and "✓" or "✗"),
      "- Readability formulas: " .. (config.config.features.readability and "✓" or "✗"),
      "- Passive voice detection: " .. (config.config.features.passive_voice and "✓" or "✗"),
      "- Nominalization detection: " .. (config.config.features.nominalizations and "✓" or "✗"),
      "- Vocabulary analysis: " .. (config.config.features.vocabulary and "✓" or "✗"),
      "- Sentence variety: " .. (config.config.features.sentence_variety and "✓" or "✗"),
      "",
      "---",
      "",
      "Press `q` to close | See `:help writing-metrics` for full documentation",
    }

    local bufnr = utils.create_float_window({
      title = "Writing Metrics",
      lines = lines,
      border = config.config.display.float_border,
    })

    vim.bo[bufnr].filetype = "markdown"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, silent = true, nowait = true })
  end, {
    desc = "Show Writing Metrics help and status",
  })

  vim.api.nvim_create_user_command("WritingMetricsToggle", function()
    local basic = require("writing-metrics.basic")
    basic.toggle_statusline_mode()
  end, {
    desc = "Toggle between fast and accurate word count mode",
  })

  vim.api.nvim_create_user_command("WritingMetricsCache", function()
    local cache = require("writing-metrics.cache")
    local config = require("writing-metrics.config")
    local utils = require("writing-metrics.utils")
    local stats = cache.get_statistics()

    local lines = {
      "# Cache Statistics",
      "",
      "## Basic Cache (Statusline Only)",
      "",
      "| Metric | Value |",
      "|--------|-------|",
      "| Entries | " .. stats.basic.count .. " |",
      "| Memory | " .. string.format("%.2f KB", stats.basic.memory / 1024) .. " |",
      "| TTL | " .. stats.basic.ttl .. "ms |",
      "",
      "## Cache Strategy",
      "",
      "- **Statusline:** Content-based cache (like Vim's wordcount) - valid until text changes",
      "- **Reports:** Always compute fresh (no cache)",
      "",
      "Cache is invalidated on text changes, not time-based expiration.",
      "",
      "---",
      "",
      "Press `q` to close | Use `:WritingMetricsClear` to clear cache",
    }

    local bufnr = utils.create_float_window({
      title = "Cache Status",
      lines = lines,
      border = config.config.display.float_border,
    })

    vim.bo[bufnr].filetype = "markdown"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, silent = true, nowait = true })
  end, {
    desc = "Show cache statistics and performance metrics",
  })

  vim.api.nvim_create_user_command("WritingMetricsClear", function(opts)
    local cache = require("writing-metrics.cache")
    local utils = require("writing-metrics.utils")

    if opts.bang then
      cache.clear_all()
      utils.notify("All caches cleared", "info")
    else
      local choice = vim.fn.confirm(
        "Clear all Writing Metrics caches?",
        "&Yes\n&No",
        2
      )

      if choice == 1 then
        cache.clear_all()
        utils.notify("All caches cleared", "info")
      else
        utils.notify("Cache clear cancelled", "info")
      end
    end
  end, {
    desc = "Clear all caches (use ! to skip confirmation)",
    bang = true,
  })

  -- Legacy aliases (gated by config)
  if cfg.commands and cfg.commands.enable_legacy then
    vim.api.nvim_create_user_command("AccurateWordCount", function(opts)
      vim.cmd("WordCount" .. (opts.range == 2 and " '<,'>" or ""))
    end, {
      desc = "DEPRECATED: Use :WordCount instead",
      range = true,
    })

    vim.api.nvim_create_user_command("ToggleWordCountMode", function()
      vim.cmd("WritingMetricsToggle")
    end, {
      desc = "DEPRECATED: Use :WritingMetricsToggle instead",
    })
  end
end

return M
```

- [ ] **Step 4: Wire `commands.setup_commands` from `init.lua:setup()`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua`, find `M.setup`'s `if M._initialized then return true end` early-return (around line 53). The lines immediately AFTER that guard currently are:

```lua
  -- Setup cache invalidation autocmds
  local cache = get_cache()
  cache.setup_autocmds()
```

Insert command registration BEFORE that block (still inside the guard, so it runs once):

```lua
  -- Register user commands (replaces plugin/writing-metrics.lua's setup_commands)
  require("writing-metrics.commands").setup_commands(get_config().config)

  -- Setup cache invalidation autocmds
  local cache = get_cache()
  cache.setup_autocmds()
```

Note: `get_config()` is a local function near the top of `init.lua` that returns the config module. `get_config().config` is the live merged config (the `M.config` table inside `config.lua`). This matches the pattern other call sites in `init.lua` use; Plan G will add a `M.get()` accessor and migrate this site.

- [ ] **Step 5: Delete command registration from `plugin/writing-metrics.lua`**

In `~/projects/nvim-writing-metrics/plugin/writing-metrics.lua`, delete the entire `local function setup_commands() ... end` block (lines ~17–232, ending with the `ToggleWordCountMode` deprecated alias and the closing `end` of `setup_commands`). Also delete the `setup_commands()` call inside `initialize()` (line ~311). The other parts of `plugin/` (autocmds, `basic.setup` call, `initialize`, the bottom `if not vim.g.writing_metrics_lazy then initialize() end` and `return { setup = initialize }`) stay untouched in this task — Task 3 collapses them.

After this edit, `plugin/writing-metrics.lua`'s `initialize()` should look like:

```lua
local function initialize(opts)
  -- Load main module
  local ok, wm = pcall(require, "writing-metrics")
  if not ok then
    vim.notify(
      "Writing Metrics: Failed to load main module: " .. tostring(wm),
      vim.log.levels.ERROR
    )
    return
  end

  -- Setup with provided opts (from lazy.nvim) or defaults
  local setup_ok = wm.setup(opts or {})
  if not setup_ok then
    vim.notify(
      "Writing Metrics: Setup failed - check dependencies",
      vim.log.levels.WARN
    )
    return
  end

  -- Register autocommands
  setup_autocommands()

  -- Setup basic module (statusline integration)
  local basic_ok, basic = pcall(require, "writing-metrics.basic")
  if basic_ok then
    basic.setup()
  end

  -- Mark as loaded
  vim.g.loaded_writing_metrics = 1
end
```

(The `setup_commands()` call between `setup_ok` check and `setup_autocommands()` is gone; everything else is unchanged.)

- [ ] **Step 6: Verify files parse**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/commands.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile lua/writing-metrics/config.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile lua/writing-metrics/init.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile plugin/writing-metrics.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output for any of the four parse checks.

- [ ] **Step 7: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **102 pass / 17 fail** (was 96/23 — six command-registration tests now pass). Specifically: `compatibility_spec` drops from 10/7 to 12/5; `integration_spec` drops from 13/6 to 17/2. Other spec files unchanged.

If counts diverge, STOP and investigate before committing.

- [ ] **Step 8: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/commands.lua lua/writing-metrics/config.lua lua/writing-metrics/init.lua plugin/writing-metrics.lua
git commit -m "feat(commands): extract command registration to dedicated module

Moves all 9 user commands from plugin/writing-metrics.lua's local
setup_commands() into a new lua/writing-metrics/commands.lua module
exporting M.setup_commands(cfg). init.lua's setup() now calls it
during the one-time initialization branch, so tests that call
metrics.setup() get commands registered (matching how production
already gets them via the plugin/ file).

Drops the duplicate :AccurateWordCount and :ToggleWordCountMode
definitions — the live wrapper form at plugin/.lua:220-232
overwrote the full-implementation form at plugin/.lua:131-148, so
only the live form is preserved. Both legacy aliases are now gated
behind the new commands.enable_legacy config option (default true,
preserving backward compatibility).

Closes 6 of the 19 remaining test failures: compat cluster 2
(registers all standard commands, registers legacy commands when
enabled) + integration cluster 3 (registers WordCount,
ReadabilityReport, WritingMetricsToggle, legacy commands)."
```

---

## Task 2: Move shims into `setup()` as callable table

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` (delete module-level shim block lines 498–533, add shim registration to `setup()` body OUTSIDE the `_initialized` guard)
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua` (delete the `_G.accurate_wordcount = { ... }` block lines 548–561)
- Modify: `~/projects/nvim-writing-metrics/tests/compatibility_spec.lua` (update one assertion to test callability instead of `type == "function"`)

**Failures closed:** 4 (compat cluster 1: `provides _G.accurate_wordcount`, `accurate_wordcount is callable`, `provides _G.text_metrics`, `text_metrics is callable`).

- [ ] **Step 1: Confirm the 4 targeted tests currently fail**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/compatibility_spec.lua 2>&1 | grep -aE "provides|callable|Success: |Failed : " | head -15
```

Expected: `compatibility_spec` reports 12/5 (post-Task-1 baseline). The four `provides` / `is callable` tests show as failures.

- [ ] **Step 2: Add shim installation to `init.lua:setup()`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua`, find the line `_G.writing_metrics_reports = {}` inside `M.setup()` (around line 48). Insert the shim-installation block AFTER it but BEFORE the `if M._initialized then return true end` guard, so the shims re-register on every `setup()` call (this is what makes the test `before_each` pattern work):

```lua
  _G.writing_metrics_reports = {}

  -- Backward-compatibility globals. Re-establish on every setup() call so
  -- tests that nil them in before_each can rely on setup() to restore them.
  -- accurate_wordcount is a callable table: accurate_wordcount() returns the
  -- current cached word count (the original init.lua function-form contract),
  -- and accurate_wordcount.<method>(...) gives access to the basic module's
  -- API (the original basic.lua table-form contract). Both old contracts work.
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

  -- One-time side effects (autocmds, validators, command registration).
  if M._initialized then
    return true
  end
```

(The block ends with the existing `if M._initialized then return true end` — that line is not new, just shown for orientation.)

- [ ] **Step 3: Delete the module-level shim block in `init.lua`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua`, find and delete the entire block from `--- Compatibility shim for accurate_wordcount global function` (around line 498) through the closing `end` of the `_G.text_metrics` function (around line 533). The relevant block to delete:

```lua
--- Compatibility shim for accurate_wordcount global function
--- Used by existing lualine configuration
_G.accurate_wordcount = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache = get_cache()
  local cached = cache.get_basic(bufnr)

  if cached then
    return cached.words or 0
  end

  return 0
end

--- Compatibility shim for text_metrics global function
_G.text_metrics = function()
  local bufnr = vim.api.nvim_get_current_buf()

  if not M.is_writing_buffer(bufnr) then
    return ""
  end

  local cache = get_cache()
  local cached = cache.get_basic(bufnr)

  if cached then
    local utils = get_utils()
    return string.format(
      "󰗊 %s words  󰬶 %s chars",
      utils.format_number(cached.words),
      utils.format_number(cached.chars)
    )
  end

  return "󰗊 …"
end
```

Delete it entirely (including the leading blank line if present). The next block in the file should be the `-- Manual testing:` comment block at line ~535.

- [ ] **Step 4: Delete the module-level shim block in `basic.lua`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua`, find and delete the block from the `-- ═══...` header line through the closing `}` of the `_G.accurate_wordcount` table (around lines 548–561):

```lua
-- ═══════════════════════════════════════════════════════════════
-- BACKWARD COMPATIBILITY
-- ═══════════════════════════════════════════════════════════════

--- Global API for backward compatibility with accurate-wordcount.lua
--- This allows existing configs to work without changes
_G.accurate_wordcount = {
  get_accurate_count = M.get_accurate_count,
  get_fast_count = M.get_fast_count,
  get_reading_time = M.get_reading_time,
  show_reading_time = M.show_reading_time,
  show_comparison = M.show_comparison,
  toggle_statusline_mode = M.toggle_statusline_mode,
  statusline_mode = M.statusline_mode,
  update_lualine_accurate_count = M.update_statusline_accurate_count,
}
```

Delete the entire block including the box-drawing header. The next block in the file (the `AUTOCOMMANDS & SETUP` section) stays intact.

- [ ] **Step 5: Update the compatibility_spec assertion for the callable-table contract**

In `~/projects/nvim-writing-metrics/tests/compatibility_spec.lua`, find the test body for `accurate_wordcount is callable` (around line 27-35). The current body (approximate):

```lua
    it("accurate_wordcount is callable", function()
      assert.is_function(_G.accurate_wordcount)
    end)
```

Replace with:

```lua
    it("accurate_wordcount is callable", function()
      -- accurate_wordcount is a callable table (has __call metamethod) so it
      -- satisfies both the function-form contract (used by lualine configs)
      -- and the table-form contract (used as a module API for methods).
      assert.is_true(
        type(_G.accurate_wordcount) == "table",
        "accurate_wordcount should be a table"
      )
      local ok = pcall(_G.accurate_wordcount)
      assert.is_true(ok, "accurate_wordcount should be callable via __call")
    end)
```

The `provides _G.accurate_wordcount` test at line ~24 (`assert.is_not_nil(_G.accurate_wordcount)`) needs no change — `is_not_nil` works for tables too. The `provides _G.text_metrics` test at line ~37 also needs no change. The `text_metrics is callable` test at line ~44 (which uses `assert.is_function`) needs no change either — `text_metrics` remains a plain function, only `accurate_wordcount` becomes a callable table.

- [ ] **Step 6: Verify files parse**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/init.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile lua/writing-metrics/basic.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile tests/compatibility_spec.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output for any of the three parse checks.

- [ ] **Step 7: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **106 pass / 13 fail** (was 102/17 — four shim-timing tests now pass). Specifically: `compatibility_spec` drops from 12/5 to 16/1 (only cluster 3's `cache.get_full`/`set_full` test remains). Other spec files unchanged.

If counts diverge, STOP and investigate before committing.

- [ ] **Step 8: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/init.lua lua/writing-metrics/basic.lua tests/compatibility_spec.lua
git commit -m "refactor(shims): move globals into setup() as callable table

The module-level _G.accurate_wordcount shims in init.lua:498 and
basic.lua:548 collided — basic.lua's table form clobbered
init.lua's function form because basic loaded second, leaving the
function-form shim as dead code (lualine configs calling
accurate_wordcount() were silently broken).

Resolves the collision by deleting both module-level sites and
installing a single callable table inside setup() — has the
basic-module method API AND the __call metamethod that returns the
current cached word count. Both old contracts work. Shim
installation runs on every setup() call (outside the _initialized
guard) so tests that nil the globals in before_each can rely on
setup() to restore them.

text_metrics stays as a plain function (no collision, no method
API). compatibility_spec's accurate_wordcount-is-callable
assertion updated to match the callable-table contract.

Closes 4 of the 13 remaining failures: compat cluster 1 (provides
_G.accurate_wordcount, accurate_wordcount is callable, provides
_G.text_metrics, text_metrics is callable)."
```

---

## Task 3: Collapse `plugin/`'s `initialize()` into `setup()`

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` (extend `setup()` to register the 4 cache-invalidation autocmds and call `basic.setup()`)
- Modify: `~/projects/nvim-writing-metrics/plugin/writing-metrics.lua` (delete `setup_autocommands()`, the `initialize()` function, the `basic.setup()` call, and shrink the file to a bootstrap)

**Failures closed:** 0. Structural change; completes the architectural consolidation so `setup()` is the canonical entry point for all side effects.

- [ ] **Step 1: Confirm tests pass at the post-Task-2 baseline**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: 106 / 13 (no change from Task 2). This is the baseline Task 3 should preserve — count MUST NOT change.

- [ ] **Step 2: Add autocmd registration + `basic.setup()` + loaded flag to `init.lua:setup()`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua`, find the `setup_report_cleanup()` call followed by the `M._initialized = true` line near the end of `M.setup()`. Insert the new logic BEFORE `M._initialized = true`:

```lua
  -- Call setup function
  setup_report_cleanup()

  -- Cache-invalidation autocmds (moved from plugin/writing-metrics.lua).
  -- These complement cache.setup_autocmds() above — that registers autocmds
  -- under augroup WritingMetricsCache; these go under augroup WritingMetrics
  -- and cover the writing-filetype patterns explicitly.
  local cache_invalidation_group = vim.api.nvim_create_augroup("WritingMetrics", { clear = true })
  local writing_patterns = { "*.md", "*.txt", "*.tex", "*.fountain", "*.org", "*.asciidoc", "*.rst" }

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = cache_invalidation_group,
    pattern = writing_patterns,
    callback = function(ev)
      cache.invalidate(ev.buf)
    end,
    desc = "Invalidate cache on text changes",
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = cache_invalidation_group,
    pattern = writing_patterns,
    callback = function(ev)
      cache.invalidate(ev.buf)
    end,
    desc = "Invalidate cache after leaving insert mode",
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = cache_invalidation_group,
    pattern = writing_patterns,
    callback = function(ev)
      cache.invalidate(ev.buf)
    end,
    desc = "Invalidate cache after saving",
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = cache_invalidation_group,
    pattern = writing_patterns,
    callback = function(ev)
      cache.invalidate(ev.buf)
    end,
    desc = "Clean up cache on buffer deletion",
  })

  -- Setup basic module (statusline integration, moved from plugin/writing-metrics.lua)
  local basic_ok, basic_mod = pcall(require, "writing-metrics.basic")
  if basic_ok then
    basic_mod.setup()
  end

  -- Mark loaded so plugin/writing-metrics.lua's top-level guard short-circuits
  -- on subsequent sources (e.g., :Lazy reload). lazy.nvim opts users get this
  -- flag too, since setup() is their entry point.
  vim.g.loaded_writing_metrics = 1

  M._initialized = true
  return true
end
```

The pre-existing `local cache = get_cache()` line (immediately before `cache.setup_autocmds()`, earlier in `setup()` and unchanged by Plan F) is in scope at this point in the function — re-use that `cache` local in the autocmd callbacks. The new block above declares `local cache_invalidation_group` (not `local cache`) so there's no shadowing collision.

- [ ] **Step 3: Shrink `plugin/writing-metrics.lua` to a bootstrap**

Replace the entire contents of `~/projects/nvim-writing-metrics/plugin/writing-metrics.lua` with:

```lua
-- plugin/writing-metrics.lua
-- Bootstrap: load the plugin unless the user opted into lazy.nvim's opts flow.
--
-- All side effects (commands, autocmds, shims, basic.setup) live inside
-- require("writing-metrics").setup(). This file just calls setup() once
-- for traditional plugin-manager users.

if vim.g.loaded_writing_metrics then
  return
end

if not vim.g.writing_metrics_lazy then
  -- Traditional plugin loading — initialize with default opts.
  require("writing-metrics").setup({})
end
```

This deletes ~315 lines (every `setup_commands` / `setup_autocommands` / `initialize` body, and the `return { setup = initialize }` at the bottom). The `if vim.g.loaded_writing_metrics then return end` guard at the top stays — it's set by `setup()` so re-sourcing this file (e.g. `:source plugin/writing-metrics.lua`) short-circuits.

- [ ] **Step 4: Verify files parse**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/init.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile plugin/writing-metrics.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output for either parse check.

- [ ] **Step 5: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **106 pass / 13 fail** (UNCHANGED from Task 2). This task is purely structural — if the count moves either way, something behavior-changed inadvertently.

If counts diverge, STOP and investigate before committing.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/init.lua plugin/writing-metrics.lua
git commit -m "refactor(plugin): collapse initialize() into setup()

Moves the 4 cache-invalidation autocmds and the basic.setup() call
from plugin/writing-metrics.lua into init.lua's setup() body. Sets
vim.g.loaded_writing_metrics = 1 inside setup() so both traditional
plugin-manager users (who run plugin/) and lazy.nvim opts users
(who don't) get the flag.

plugin/writing-metrics.lua shrinks from 334 lines to 13 — just the
loaded guard and a single call to setup({}) for traditional
plugin-manager users. No behavior change.

setup() is now the single canonical entry point for every side
effect the plugin produces."
```

---

## Task 4: Fix 3 stale-test assertions

**Files:**
- Modify: `~/projects/nvim-writing-metrics/tests/compatibility_spec.lua` (cluster 3, 1 site)
- Modify: `~/projects/nvim-writing-metrics/tests/integration_spec.lua` (cluster 1: callback arity + dead call; cluster 2: assertion shape)

**Failures closed:** 3 (compat cluster 3: `cache module exports expected functions` + integration cluster 1: `full workflow` + integration cluster 2: `cache invalidates on buffer modification`).

- [ ] **Step 1: Confirm the 3 targeted tests currently fail**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/compatibility_spec.lua 2>&1 | grep -aE "expected functions|Success: |Failed : "
./run-tests.sh -t tests/integration_spec.lua 2>&1 | grep -aE "full workflow|invalidates|Success: |Failed : "
```

Expected: `compatibility_spec` reports 16/1 (post-Task-2 baseline); `integration_spec` reports 17/2 (post-Task-1 baseline). The three targeted tests show as failures.

- [ ] **Step 2: Fix `compat_spec` cluster 3 — remove stale `get_full`/`set_full` from expected list**

In `~/projects/nvim-writing-metrics/tests/compatibility_spec.lua`, find the `cache module exports expected functions` test (around line 155–165). The test body has a list of expected function names; locate the line(s) containing `"get_full"` and `"set_full"`. The block likely looks like:

```lua
    it("cache module exports expected functions", function()
      local cache = require("writing-metrics.cache")
      local expected = {
        "get_basic",
        "set_basic",
        "get_full",
        "set_full",
        "invalidate",
        "clear_all",
        "get_statistics",
      }
      for _, name in ipairs(expected) do
        assert.is_function(cache[name], "Missing function: " .. name)
      end
    end)
```

(The exact ordering and indentation may differ; the key is the list contains `"get_full"` and `"set_full"`.) Delete just those two lines so the expected list reads:

```lua
      local expected = {
        "get_basic",
        "set_basic",
        "invalidate",
        "clear_all",
        "get_statistics",
      }
```

The cache module's actual exports are `get_basic`, `set_basic`, `invalidate`, `clear_all`, `get_statistics` — `get_full` and `set_full` were never implemented (planned two-tier cache API that never shipped).

- [ ] **Step 3: Fix `integration_spec` cluster 1 — callback arity + dead `cache.get_full` call**

In `~/projects/nvim-writing-metrics/tests/integration_spec.lua`, find the `full workflow` test (around lines 85–110). The test invokes `full.get_full_metrics(bufnr, function(data) result_data = data end)` and then references `cache.get_full(bufnr)`. Two edits:

**3a.** Update the callback signature from single-arg `data` to two-arg `ok, data` (matching what `full.get_full_metrics` actually calls):

Find the line:

```lua
      full.get_full_metrics(bufnr, function(data)
        result_data = data
      end)
```

Replace with:

```lua
      full.get_full_metrics(bufnr, function(ok, data)
        if ok then
          result_data = data
        end
      end)
```

**3b.** Delete the dead `cache.get_full(bufnr)` reference (around line 105). The cache module has no `get_full` function; the call returns nil and any assertion against it crashes. Find a line like:

```lua
      local cached = cache.get_full(bufnr)
      assert.is_not_nil(cached, "result should have been cached")
```

Delete both lines (the call and the assertion that follows). The test's earlier `assert_metrics_structure(result_data)` assertion is sufficient to verify the full-workflow path; the cache assertion was testing a code path that doesn't exist.

If the surrounding context makes it ambiguous which lines to delete, the rule is: delete every line that references `cache.get_full` or asserts against its return value, but keep the `assert_metrics_structure(result_data)` line and the surrounding `wait_for_async` / `is_not_nil(result_data)` scaffolding.

- [ ] **Step 4: Fix `integration_spec` cluster 2 — soft-stale invalidate assertion**

In `~/projects/nvim-writing-metrics/tests/integration_spec.lua`, find the `cache invalidates on buffer modification` test (around line 160–180). Locate the assertion (around line 175) that follows `cache.invalidate(bufnr)`:

```lua
      cache.invalidate(bufnr)

      -- Cache should now be invalidated
      assert.is_nil(cache.get_basic(bufnr))
```

The implementation marks invalidated entries with `stale = true` and keeps the data in place (so the statusline can show a last-known-good value while a fresh count computes). The assertion should test the staleness flag instead of nullity. Replace with:

```lua
      cache.invalidate(bufnr)

      -- Cache should now be marked stale (soft-stale design: data preserved
      -- so statusline can show last-known-good while a fresh count computes).
      local entry, stale = cache.get_basic(bufnr)
      assert.is_not_nil(entry, "cached entry should still be present after invalidate")
      assert.is_true(stale, "cached entry should be marked stale after invalidate")
```

If `cache.get_basic` returns only one value (entry) and exposes staleness via a different mechanism, adjust accordingly — but per the audit memory the function returns `(entry, stale_flag)`. Verify by reading `lua/writing-metrics/cache.lua`'s `M.get_basic` definition (around line 50–80) before writing the final assertion. If the contract is different (e.g., `entry.stale` boolean field), use that:

```lua
      cache.invalidate(bufnr)

      local entry = cache.get_basic(bufnr)
      assert.is_not_nil(entry, "cached entry should still be present after invalidate")
      assert.is_true(entry.stale, "cached entry should be marked stale after invalidate")
```

Choose whichever matches the actual `get_basic` return shape.

- [ ] **Step 5: Verify files parse**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile tests/compatibility_spec.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile tests/integration_spec.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output for either parse check.

- [ ] **Step 6: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **109 pass / 10 fail** (was 106/13 — three stale assertions now pass). Specifically: `compatibility_spec` drops from 16/1 to 17/0; `integration_spec` drops from 17/2 to 19/0. The remaining 10 failures are 6 in `config_spec.lua` (Plan G) + 4 in `full_spec.lua` (separate plan).

If counts diverge, STOP and investigate before committing.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add tests/compatibility_spec.lua tests/integration_spec.lua
git commit -m "test(specs): fix 3 stale assertions in compat/integration

Three pre-existing test failures with the same character as the
basic_spec.lua failures Plan E cleaned up — test assertions
written against API contracts that drifted before the
implementation finalised.

- compat: remove cache.get_full/set_full from expected-functions
  list (the two-tier cache API was planned but never shipped;
  the cache module only exposes get_basic/set_basic/invalidate/
  clear_all/get_statistics).
- integration: fix full_workflow callback arity (full.get_full_metrics
  calls cb(ok, data) but the test declared cb(data), making
  result_data the boolean true) and delete the dead cache.get_full
  call/assertion (function doesn't exist).
- integration: replace cache.get_basic == nil assertion after
  cache.invalidate with a staleness check — invalidate is a soft-
  stale mark by design (preserves last-known-good for statusline)
  and the test was written against a deprecated hard-delete contract.

Closes the final 3 failures from the audit batch (compat cluster 3
+ integration clusters 1 and 2). Suite reaches 109 / 10."
```

---

## Final verification

After all four tasks land, run:

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **109 pass / 10 fail**. Breakdown by spec file:
- `cache_spec`: unchanged
- `config_spec`: 6 / 6 (unchanged — Plan G territory)
- `compatibility_spec`: 17 / 0 (was 10 / 7 — all 7 closed)
- `display_spec`: unchanged
- `full_spec`: 19 / 4 (unchanged — separate isolation plan)
- `init_spec`: unchanged
- `integration_spec`: 19 / 0 (was 13 / 6 — all 6 closed)
- `utils_spec`: unchanged
- `basic_spec`: 31 / 0 (post-Plan-E, unchanged)

```bash
cd ~/projects/nvim-writing-metrics
git log --oneline a08eab8..HEAD
```

Expected: 4 commits, prefixed `feat(commands)`, `refactor(shims)`, `refactor(plugin)`, `test(specs)`.

---

## Holistic review

Per the spec, Plan F uses one holistic review at the end. Dispatch one code-reviewer subagent against the cumulative diff:

```bash
cd ~/projects/nvim-writing-metrics
git diff a08eab8 HEAD --stat
git diff a08eab8 HEAD
```

Reviewer focus areas:

- **Task 1 command parity:** The new `commands.lua` registers exactly 9 unique commands (`WordCount`, `ReadabilityReport`, `ReadingTime`, `WritingMetrics`, `WritingMetricsToggle`, `WritingMetricsCache`, `WritingMetricsClear`, plus 2 legacy aliases gated by `enable_legacy`). The dead duplicate definitions of `:AccurateWordCount`/`:ToggleWordCountMode` from `plugin/.lua:131-148` are GONE (only the wrapper-form definitions remain). Each command's body matches the original verbatim.
- **Task 1 config wiring:** `commands.enable_legacy` defaults to `true` (preserves backward compat). The `if cfg.commands and cfg.commands.enable_legacy` guard tolerates missing config (in case `setup_commands` is called with a raw config table that omits the `commands` key).
- **Task 2 callable-table correctness:** `setmetatable(acc_wc, { __call = ... })` is set BEFORE `_G.accurate_wordcount = acc_wc`. The `__call` body returns the same value the deleted `init.lua:500` function did (`cached.words or 0`). The table fields preserve every field name from the deleted `basic.lua:548` table.
- **Task 2 shim ordering inside setup():** Shim installation is OUTSIDE the `if M._initialized then return true end` guard so it runs every call. The `local basic = require(...)` / `local cache = require(...)` lines don't conflict with the `local cache = get_cache()` call later in the function (different scope).
- **Task 2 test fidelity:** The updated `accurate_wordcount is callable` assertion actually tests both the type AND callability — not just one. The other compat-spec assertions for `_G.text_metrics` are unchanged.
- **Task 3 autocmd parity:** All 4 cache-invalidation autocmd events (TextChanged+TextChangedI grouped, InsertLeave, BufWritePost, BufDelete) and patterns (the 7 writing-filetype globs) are preserved. The augroup name `WritingMetrics` matches the original.
- **Task 3 plugin/ minimalism:** The new `plugin/writing-metrics.lua` is ≤20 lines and contains no `nvim_create_user_command` or `nvim_create_autocmd` calls — every side effect has migrated to `setup()`.
- **Task 3 loaded-flag placement:** `vim.g.loaded_writing_metrics = 1` is set inside `setup()` (so lazy.nvim opts users get it too) AND the `if vim.g.loaded_writing_metrics then return end` guard at the top of `plugin/` still works for re-source protection.
- **Task 4 assertion correctness:** Each updated assertion checks what the test name claims. The integration-cluster-2 staleness assertion uses whichever `cache.get_basic` return shape actually exists (multi-return vs `entry.stale` field) — verify against the real implementation.
- **No scope creep:** Diff doesn't touch `config_spec.lua`, `full_spec.lua`, `basic_spec.lua`. No incidental refactoring outside the four targeted changes.
- **Baseline preservation:** `cache_spec`, `display_spec`, `full_spec`, `init_spec`, `utils_spec`, `basic_spec` counts unchanged from baseline.

---

## After completion

Memory cleanup:

- Delete `~/.claude/projects/-home-jkeim--config-nvim/memory/project_nvim_writing_metrics_compatibility_spec_failures.md` (all 7 failures closed; entry would mislead future sessions).
- Delete `~/.claude/projects/-home-jkeim--config-nvim/memory/project_nvim_writing_metrics_integration_spec_failures.md` (all 6 failures closed).
- Update `project_nvim_writing_metrics_full_spec_failures.md` baseline note from `96 / 23` to `109 / 10`.
- Update `project_nvim_writing_metrics_config_spec_failures.md` baseline note similarly.
- Update `MEMORY.md`: remove the two deleted entries' lines; update the full_spec line if its description references the old baseline.

## Summary

4 tasks, 4 commits on `main` of `~/projects/nvim-writing-metrics/`. ~50-80 lines of net code change (mostly relocation, not new logic): one new module file, three modified module files, one shrunk plugin file, two test files updated. Resolves 13 of the 19 remaining test failures (compat 7→0, integration 6→0) and fixes a latent production bug in `_G.accurate_wordcount`. Estimated 60-90 minutes of focused work plus the holistic review.

After completion, `setup()` is the canonical, single entry point for every side effect the plugin produces — matching what any user reading the README would expect: "call `setup({ ...opts... })` once, and everything works."
