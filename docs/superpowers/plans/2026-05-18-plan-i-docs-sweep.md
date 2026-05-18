# Plan I — Architecture Docs Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync the three architecture docs (`CORE_MODULES.md`, `DESIGN_INNOVATIONS.md`, `MODULE_FLOW.md`) in `~/projects/nvim-writing-metrics/docs/` with the post-Plan-H state of the codebase. 17 atomic doc edits, no production code touched.

**Architecture:** Pure documentation work. No code, no tests, no runtime impact. Verification is by stale-term grep + cross-check against the source at HEAD + a fresh-reader pass at the end. Single commit at task close.

**Tech Stack:** Markdown. Read/Edit tools for in-place edits. Bash for verification greps.

**Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-18-plan-i-docs-sweep-design.md`

**Working directory for implementation:** `~/projects/nvim-writing-metrics/` (the only git repo we touch).

---

## File Structure

```
~/projects/nvim-writing-metrics/docs/
├── CORE_MODULES.md         # 10 edits (steps 1.1 - 1.10)
├── DESIGN_INNOVATIONS.md   #  2 edits (steps 2.1 - 2.2)
└── MODULE_FLOW.md          #  5 edits (steps 3.1 - 3.5)
```

Each step is one Edit-tool invocation against one file. Reads are used to anchor the edits — line numbers in this plan are accurate as of plan-writing time but will drift as edits land within a file. Always Read the current section before editing if a previous edit in the same file has changed line numbers.

---

## Task 1: Update `docs/CORE_MODULES.md` (10 edits)

**Files:**
- Modify: `~/projects/nvim-writing-metrics/docs/CORE_MODULES.md`

**Source files you may need to Read to verify claims:**
- `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` (especially the `setup()` function)
- `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua` (for `M.get()` and defaults)
- `~/projects/nvim-writing-metrics/lua/writing-metrics/commands.lua` (for the §5 section content)

### Step 1.1: Reframe the intro line and architecture box (Edit #1)

- [ ] **Step:** Open `docs/CORE_MODULES.md`, find the line `This document describes the four core modules that power nvim-writing-metrics.` at line 3, and the architecture box at lines 7-16.

Apply the edit:

**old_string:**
```
This document describes the four core modules that power nvim-writing-metrics.

## Architecture Overview

```
nvim-writing-metrics/
├── lua/writing-metrics/
│   ├── init.lua       # Main entry point & public API
│   ├── config.lua     # Configuration & auto-detection
│   ├── cache.lua      # Intelligent shared caching
│   └── utils.lua      # Shared utilities
└── scripts/
    └── textmetrics.lua  # Unified Pandoc filter
```
```

**new_string:**
```
This document describes the core modules that power nvim-writing-metrics.

## Architecture Overview

```
nvim-writing-metrics/
├── lua/writing-metrics/
│   ├── init.lua       # Main entry point & public API
│   ├── config.lua     # Configuration & auto-detection
│   ├── cache.lua      # Intelligent shared caching
│   ├── commands.lua   # User command registration
│   └── utils.lua      # Shared utilities
└── scripts/
    └── textmetrics.lua  # Unified Pandoc filter
```
```

(Net change: "four core modules" → "core modules"; added the `commands.lua` line between `cache.lua` and `utils.lua`.)

### Step 1.2: Add the setup-delegation note in §1 init.lua (Edit #2)

- [ ] **Step:** Open `docs/CORE_MODULES.md`, find the §1 init.lua section's "Auto-initialization" line at line 42.

Apply the edit:

**old_string:**
```
**Auto-initialization:** The module auto-initializes on first require if not explicitly setup.
```

**new_string:**
```
**Auto-initialization:** The module auto-initializes on first require if not explicitly setup.

**Command registration:** `setup()` delegates user-command registration to `commands.lua` via `commands.setup_commands(cfg)`. See §5 below for the registered commands and legacy-alias gating.
```

### Step 1.3: Update the `_G.accurate_wordcount` description in §1 (Edit #3)

- [ ] **Step:** In `docs/CORE_MODULES.md`, find the "Global Compatibility Shims" block at lines 37-40.

Apply the edit:

**old_string:**
```
**Global Compatibility Shims:**

- `_G.accurate_wordcount()` - Returns word count for current buffer (lualine compatible)
- `_G.text_metrics()` - Returns formatted metrics string (lualine compatible)
```

**new_string:**
```
**Global Compatibility Shims:**

- `_G.accurate_wordcount` - Callable table with two contracts:
  - Function form: `_G.accurate_wordcount()` returns the cached word count for the current buffer (original lualine contract from the prior accurate_wordcount.lua plugin)
  - Table form: `_G.accurate_wordcount.<method>(bufnr)` exposes the basic module's API — `get_fast_count`, `get_accurate_count`, `get_reading_time`, `show_reading_time`, `show_comparison`, `toggle_statusline_mode`, `statusline_mode`, `update_lualine_accurate_count`
- `_G.text_metrics()` - Returns formatted metrics string (lualine compatible)
```

### Step 1.4: Add the `M.get()` accessor to §2 config.lua Key Functions (Edit #4)

- [ ] **Step:** In `docs/CORE_MODULES.md`, find the §2 config.lua "Key Functions" list at lines 58-65.

Apply the edit:

**old_string:**
```
**Key Functions:**

- `M.find_filter()` - Find Pandoc filter using fallback chain
- `M.validate_pandoc()` - Check Pandoc >= 2.19 is installed
- `M.validate_dependencies()` - Validate both Pandoc and filter
- `M.get_filter_path()` - Get resolved filter path
- `M.setup(opts)` - Merge user config with defaults
- `M.is_enabled_filetype(ft)` - Check if filetype is enabled
- `M.get_targets(writing_type)` - Get target ranges for grant/creative/academic
```

**new_string:**
```
**Key Functions:**

- `M.find_filter()` - Find Pandoc filter using fallback chain
- `M.validate_pandoc()` - Check Pandoc >= 2.19 is installed
- `M.validate_dependencies()` - Validate both Pandoc and filter
- `M.get_filter_path()` - Get resolved filter path
- `M.setup(opts)` - Merge user config with defaults
- `M.get()` - Return the resolved (post-merge) config table by reference, for other modules to read merged opts without re-merging
- `M.is_enabled_filetype(ft)` - Check if filetype is enabled
- `M.get_targets(writing_type)` - Get target ranges for grant/creative/academic
```

### Step 1.5: Add `commands.enable_legacy` and `filter.auto_detect` semantics to defaults block (Edit #5)

- [ ] **Step:** In `docs/CORE_MODULES.md`, find the §2 config.lua defaults block at lines 67-103. Locate the `filter` entry:

```
  filter = {
    auto_detect = true,
    path = nil,  -- Explicit filter path. nil = use auto-detect.
  },
```

Apply the edit:

**old_string:**
```
  filter = {
    auto_detect = true,
    path = nil,  -- Explicit filter path. nil = use auto-detect.
  },
}
```

**new_string:**
```
  filter = {
    auto_detect = true,  -- false: trust filter.path unconditionally (don't fall through to the bundled/XDG/user-bin search even if path is nil or missing)
    path = nil,          -- Explicit filter path. nil + auto_detect=true → use auto-detect chain.
  },
  commands = {
    enable_legacy = true,  -- Register deprecated alias commands (:AccurateWordCount, :ToggleWordCountMode). false: aliases removed via nvim_del_user_command on setup().
  },
}
```

(Net change: added the `auto_detect` semantics comment; added the entire `commands = {...}` sibling block; the closing `}` of `M.defaults` stays.)

### Step 1.6: Insert new §5 `commands.lua` section (Edit #6)

- [ ] **Step:** In `docs/CORE_MODULES.md`, find the end of §4 utils.lua. The next heading after it is `## Design Decisions` (at line 197 as of plan-writing time). We're inserting a new §5 between them.

Find the line `### 4. `utils.lua` - Shared Utilities` and read forward to the `## Design Decisions` heading. The new §5 section goes immediately before `## Design Decisions`.

Apply the edit. **old_string** is the last line of §4 plus the `## Design Decisions` heading (use this as the anchor so Edit finds a unique match):

**old_string:**
```
- `M.validate_filter()` - Check filter exists

## Design Decisions
```

**new_string:**
```
- `M.validate_filter()` - Check filter exists

### 5. `commands.lua` - User Command Registration

Centralizes user-command registration so `init.lua`'s `setup()` stays focused on plugin-lifecycle concerns. Idempotent — `nvim_create_user_command` overwrites on redefine, so re-running `setup()` with different opts (e.g. toggling `enable_legacy`) is safe.

**Key Functions:**

- `M.setup_commands(cfg)` - Register all primary user commands and apply legacy-alias gating. Called once per `setup()` invocation. The `cfg` argument is the resolved config (typically `require("writing-metrics.config").get()`).

**Primary Commands Registered:**

| Command | Description |
|---------|-------------|
| `:WordCount` | Show word count (basic metrics). Honors visual range. |
| `:ReadabilityReport` | Generate comprehensive readability report. Honors visual range. |
| `:ReadingTime` | Show reading time toast (silent + spoken) |
| `:WritingMetrics` | Show plugin status and configuration (float) |
| `:WritingMetricsToggle` | Toggle between fast and accurate statusline mode |
| `:WritingMetricsCache` | Show cache statistics (float) |
| `:WritingMetricsClear[!]` | Clear all caches. `!` skips confirmation prompt. |

**Legacy Alias Gating:**

When `cfg.commands.enable_legacy == true` (the default), the following deprecated aliases are also registered:

| Old Command | Forwards To |
|-------------|-------------|
| `:AccurateWordCount` | `:WordCount` |
| `:ToggleWordCountMode` | `:WritingMetricsToggle` |

When `enable_legacy == false`, these aliases are explicitly removed via `nvim_del_user_command` (wrapped in `pcall` since deleting a non-existent command errors). This means flipping `enable_legacy` from `true` to `false` and re-running `setup()` cleanly de-registers the aliases.

**Dependencies:**

- `writing-metrics.config` (read at registration via `cfg`; command callbacks re-read live config via `require()` so config changes take effect without re-running `setup()`)
- `writing-metrics.basic` / `writing-metrics.full` / `writing-metrics.cache` / `writing-metrics.utils` — required lazily inside command callbacks

## Design Decisions
```

### Step 1.7: Update Backward Compatibility code example (Edit #7)

- [ ] **Step:** In `docs/CORE_MODULES.md`, find the §5 Backward Compatibility code example. After step 1.6 inserted a new §5, this section is now §6 by header order — but its anchor text is still "### 5. Backward Compatibility" because the Design Decisions section uses an independent numbering. Read the file forward from `## Design Decisions` to confirm the current header text before editing.

The target block:

```lua
_G.accurate_wordcount = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache = get_cache()
  local cached = cache.get_basic(bufnr)
  return cached and cached.words or 0
end
```

Apply the edit:

**old_string:**
```
_G.accurate_wordcount = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache = get_cache()
  local cached = cache.get_basic(bufnr)
  return cached and cached.words or 0
end
```

**new_string:**
```
_G.accurate_wordcount = setmetatable({
  get_fast_count         = basic.get_fast_count,
  get_accurate_count     = basic.get_accurate_count,
  get_reading_time       = basic.get_reading_time,
  show_reading_time      = basic.show_reading_time,
  show_comparison        = basic.show_comparison,
  toggle_statusline_mode = basic.toggle_statusline_mode,
  statusline_mode        = basic.statusline_mode,
  update_lualine_accurate_count = basic.update_statusline_accurate_count,
}, {
  __call = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cached = require("writing-metrics.cache").get_basic(bufnr)
    return (cached and cached.words) or 0
  end,
})

-- Two contracts, both preserved:
--   _G.accurate_wordcount()           → cached word count (original function shape)
--   _G.accurate_wordcount.<method>()  → basic-module methods (original table shape)
```

### Step 1.8: Drop the stale "pre-existing failure cluster" claim (Edit #8)

- [ ] **Step:** In `docs/CORE_MODULES.md`, find the Testing section's closing sentence (around line 295 as of plan-writing time):

```
A pre-existing failure cluster in `basic_spec.lua` and `full_spec.lua` is tracked separately; the goal for any new work is that the failure count does not increase.
```

Apply the edit:

**old_string:**
```

A pre-existing failure cluster in `basic_spec.lua` and `full_spec.lua` is tracked separately; the goal for any new work is that the failure count does not increase.

```

**new_string:**
```

```

(Net change: delete the whole sentence plus its surrounding blank lines, leaving a single blank line as separator. The spec suite is 118/0 after Plan H — the cluster no longer exists.)

### Step 1.9: Update §Module Statistics to include commands.lua (Edit #9)

- [ ] **Step:** In `docs/CORE_MODULES.md`, find the §Module Statistics block (around line 378). The current text:

```
- **Total lines (core modules):** ~1,455 across `init.lua`, `config.lua`, `cache.lua`, `utils.lua`
```

Verify current line counts before writing the new figure. Run from `~/projects/nvim-writing-metrics/`:

```bash
wc -l lua/writing-metrics/init.lua lua/writing-metrics/config.lua lua/writing-metrics/cache.lua lua/writing-metrics/commands.lua lua/writing-metrics/utils.lua
```

Expected output (as of plan-writing time): a total around `1593`.

Apply the edit using the verified figure:

**old_string:**
```
- **Total lines (core modules):** ~1,455 across `init.lua`, `config.lua`, `cache.lua`, `utils.lua`
```

**new_string** (round to nearest 10, e.g. `~1,590` if `wc -l` reported 1593):
```
- **Total lines (core modules):** ~<ROUNDED_TOTAL> across `init.lua`, `config.lua`, `cache.lua`, `commands.lua`, `utils.lua`
```

Replace `<ROUNDED_TOTAL>` with the actual rounded number from your `wc -l` output (e.g. `1,590`).

### Step 1.10: Replace §Next Steps with §Future Work (Edit #10)

- [ ] **Step:** In `docs/CORE_MODULES.md`, find the §Next Steps block (lines 367-376 as of plan-writing time):

```
## Next Steps

With core modules complete, the next phases are:

1. **Track 3: Display Module** - Format and render metrics reports
2. **Track 4: Commands Module** - User commands and keybindings
3. **Track 5: Integration** - Lualine, writing modes, existing plugins
4. **Track 6: Testing** - Comprehensive test suite with plenary.nvim
5. **Track 7: Documentation** - README, help docs, examples
```

Apply the edit:

**old_string:**
```
## Next Steps

With core modules complete, the next phases are:

1. **Track 3: Display Module** - Format and render metrics reports
2. **Track 4: Commands Module** - User commands and keybindings
3. **Track 5: Integration** - Lualine, writing modes, existing plugins
4. **Track 6: Testing** - Comprehensive test suite with plenary.nvim
5. **Track 7: Documentation** - README, help docs, examples
```

**new_string:**
```
## Future Work

The plugin is in steady-state maintenance. Known follow-ups, in no particular order:

1. **Plan J — `tests/` luacheck cleanup.** Close the 3 remaining warnings in `tests/` that were scoped out of Plan H. Brings the whole repo to 0 luacheck warnings.
2. **Plan K — stylua reconciliation.** Decide whether to keep the deliberate column-aligned comments and live with 7 unrunnable stylua diffs, or run `stylua lua/` and accept the formatting loss. Currently in a deliberate-but-uncommitted state.
3. **`filter.auto_detect` simplification.** Evaluate whether the `auto_detect=true|false` toggle adds enough value to justify the configuration surface. If auto-detect never fails in practice, the toggle could be retired in favor of "use `filter.path` if set, otherwise auto-detect."
4. **`:checkhealth writing-metrics` completeness audit.** Verify the health check exercises the full dependency chain — Pandoc version, filter path, autocmd registration, command registration — after Plan F's `setup()` refactor.
```

---

## Task 2: Update `docs/DESIGN_INNOVATIONS.md` (2 edits)

**Files:**
- Modify: `~/projects/nvim-writing-metrics/docs/DESIGN_INNOVATIONS.md`

### Step 2.1: Delete the "Measurement" subsection from §4 Lazy Module Loading (Edit #11)

- [ ] **Step:** In `docs/DESIGN_INNOVATIONS.md`, find the §4 "Lazy Module Loading" section's "**Measurement:**" block at lines 155-174 as of plan-writing time. The target block:

```
**Measurement:**

```lua
-- Eager loading
local start = vim.loop.hrtime()
local config = require("writing-metrics.config")
local cache = require("writing-metrics.cache")
local utils = require("writing-metrics.utils")
local init = require("writing-metrics")
local elapsed = (vim.loop.hrtime() - start) / 1e6
print(string.format("Eager: %.2fms", elapsed))  -- ~15ms

-- Lazy loading
local start = vim.loop.hrtime()
local init = require("writing-metrics")
local elapsed = (vim.loop.hrtime() - start) / 1e6
print(string.format("Lazy: %.2fms", elapsed))   -- ~0.5ms
```

**30x faster startup!**
```

Apply the edit:

**old_string:**
```
**Measurement:**

```lua
-- Eager loading
local start = vim.loop.hrtime()
local config = require("writing-metrics.config")
local cache = require("writing-metrics.cache")
local utils = require("writing-metrics.utils")
local init = require("writing-metrics")
local elapsed = (vim.loop.hrtime() - start) / 1e6
print(string.format("Eager: %.2fms", elapsed))  -- ~15ms

-- Lazy loading
local start = vim.loop.hrtime()
local init = require("writing-metrics")
local elapsed = (vim.loop.hrtime() - start) / 1e6
print(string.format("Lazy: %.2fms", elapsed))   -- ~0.5ms
```

**30x faster startup!**

## 5. Backward Compatibility Shims
```

**new_string:**
```
## 5. Backward Compatibility Shims
```

(Net change: the entire Measurement subsection is removed. The next heading "## 5. Backward Compatibility Shims" now follows directly after the Benefits bullets.)

### Step 2.2: Update the `_G.accurate_wordcount` snippet in §5 (Edit #12)

- [ ] **Step:** In `docs/DESIGN_INNOVATIONS.md`, find the §5 Backward Compatibility Shims implementation block. The target block:

```lua
-- Implementation
_G.accurate_wordcount = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache = get_cache()
  local cached = cache.get_basic(bufnr)
  return cached and cached.words or 0
end
```

Apply the edit:

**old_string:**
```
-- Implementation
_G.accurate_wordcount = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache = get_cache()
  local cached = cache.get_basic(bufnr)
  return cached and cached.words or 0
end
```

**new_string:**
```
-- Implementation
_G.accurate_wordcount = setmetatable({
  get_fast_count         = basic.get_fast_count,
  get_accurate_count     = basic.get_accurate_count,
  get_reading_time       = basic.get_reading_time,
  show_reading_time      = basic.show_reading_time,
  show_comparison        = basic.show_comparison,
  toggle_statusline_mode = basic.toggle_statusline_mode,
  statusline_mode        = basic.statusline_mode,
  update_lualine_accurate_count = basic.update_statusline_accurate_count,
}, {
  __call = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cached = require("writing-metrics.cache").get_basic(bufnr)
    return (cached and cached.words) or 0
  end,
})

-- Two contracts, both preserved:
--   _G.accurate_wordcount()           → cached word count (original function shape)
--   _G.accurate_wordcount.<method>()  → basic-module methods (original table shape)
```

---

## Task 3: Update `docs/MODULE_FLOW.md` (5 edits)

**Files:**
- Modify: `~/projects/nvim-writing-metrics/docs/MODULE_FLOW.md`

### Step 3.1: Add `commands` box to the High-Level Architecture diagram (Edit #13)

- [ ] **Step:** In `docs/MODULE_FLOW.md`, find the architecture diagram at lines 5-37. The current bottom row of boxes (after `init.lua`):

```
      │               │              │
      ▼               ▼              ▼
┌──────────┐   ┌──────────┐   ┌──────────┐
│ config   │   │  cache   │   │  utils   │
│          │   │          │   │          │
│ - Setup  │   │ - Store  │   │ - Pandoc │
│ - Detect │   │ - Fetch  │   │ - Format │
│ - Valid  │   │ - Invalid│   │ - Files  │
└────┬─────┘   └────┬─────┘   └────┬─────┘
     │              │              │
     └──────────────┴──────────────┘
```

Apply the edit to extend the row with a `commands` box:

**old_string:**
```
      │               │              │
      ▼               ▼              ▼
┌──────────┐   ┌──────────┐   ┌──────────┐
│ config   │   │  cache   │   │  utils   │
│          │   │          │   │          │
│ - Setup  │   │ - Store  │   │ - Pandoc │
│ - Detect │   │ - Fetch  │   │ - Format │
│ - Valid  │   │ - Invalid│   │ - Files  │
└────┬─────┘   └────┬─────┘   └────┬─────┘
     │              │              │
     └──────────────┴──────────────┘
```

**new_string:**
```
      │               │              │              │
      ▼               ▼              ▼              ▼
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ config   │   │  cache   │   │ commands │   │  utils   │
│          │   │          │   │          │   │          │
│ - Setup  │   │ - Store  │   │ - Register│  │ - Pandoc │
│ - Detect │   │ - Fetch  │   │ - Legacy │   │ - Format │
│ - Valid  │   │ - Invalid│   │   gating │   │ - Files  │
└────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘
     │              │              │              │
     └──────────────┴──────────────┴──────────────┘
```

Also update the init.lua box just above to add a fourth downward arrow. Find this block earlier in the file:

```
└─────┬───────────────┬──────────────┬────────────────────────┘
      │               │              │
      ▼               ▼              ▼
```

Apply this second edit to add a fourth column:

**old_string:**
```
└─────┬───────────────┬──────────────┬────────────────────────┘
      │               │              │
      ▼               ▼              ▼
```

**new_string:**
```
└─────┬───────────────┬──────────────┬───────────────┬────────┘
      │               │              │               │
      ▼               ▼              ▼               ▼
```

(Note: this step has two Edit operations. Both must succeed before moving on.)

### Step 3.2: Strip the stale "Check full cache" branch from Flow 1 (Edit #14)

- [ ] **Step:** In `docs/MODULE_FLOW.md`, find the "Flow 1: Statusline Update (Fast Path)" block at lines 41-76. The stale branch is at lines 53-58:

```
  │     ├─> Check basic cache (cache.get_basic)
  │     │     │
  │     │     ├─> Basic cache valid? → Return cached data ✓ (< 0.1ms)
  │     │     │
  │     │     └─> Basic cache expired?
  │     │           └─> Check full cache (smart optimization!)
  │     │                 │
  │     │                 ├─> Full cache valid? → Extract basic metrics ✓
  │     │                 │
  │     │                 └─> Both invalid? → Return "..." (trigger background update)
```

Apply the edit:

**old_string:**
```
  │     ├─> Check basic cache (cache.get_basic)
  │     │     │
  │     │     ├─> Basic cache valid? → Return cached data ✓ (< 0.1ms)
  │     │     │
  │     │     └─> Basic cache expired?
  │     │           └─> Check full cache (smart optimization!)
  │     │                 │
  │     │                 ├─> Full cache valid? → Extract basic metrics ✓
  │     │                 │
  │     │                 └─> Both invalid? → Return "..." (trigger background update)
```

**new_string:**
```
  │     ├─> Check basic cache (cache.get_basic via changedtick)
  │     │     │
  │     │     ├─> changedtick matches stored tick? → Return cached data ✓ (< 0.1ms)
  │     │     │
  │     │     └─> Tick differs (content changed)?
  │     │           └─> Return last-known data marked stale; trigger background update
```

### Step 3.3: Replace Flow 2 with lean diagram + "Why" note (Edit #15)

- [ ] **Step:** In `docs/MODULE_FLOW.md`, find the "Flow 2: Full Report (Comprehensive Path)" block at lines 78-114. The current stale block:

```
### Flow 2: Full Report (Comprehensive Path)

```
User presses <leader>mr
  │
  ├─> show_full_report()
  │     │
  │     ├─> get_metrics(bufnr, "full", callback)
  │     │     │
  │     │     ├─> Check full cache (cache.get_full)
  │     │     │     │
  │     │     │     ├─> Cache valid? → Return immediately ✓
  │     │     │     │
  │     │     │     └─> Cache invalid? → Compute fresh
  │     │     │           │
  │     │     │           ├─> Get buffer content
  │     │     │           ├─> Write temp file
  │     │     │           ├─> Run Pandoc with mode="full"
  │     │     │           ├─> Parse JSON output
  │     │     │           └─> Store in cache (cache.set_full)
  │     │     │                 └─> Also extracts and caches basic metrics!
  │     │     │
  │     │     └─> Callback with full metrics data
  │     │
  │     ├─> Format full report (format_full_report)
  │     │     ├─> Basic statistics section
  │     │     ├─> Readability scores section
  │     │     ├─> Sentence variety section
  │     │     ├─> Passive voice section
  │     │     ├─> Nominalizations section
  │     │     ├─> Vocabulary section
  │     │     └─> AI words section
  │     │
  │     └─> Display in tab/split (utils.open_report_tab)
  │
  └─> User reviews report
```
```

Apply the edit:

**old_string:**
```
### Flow 2: Full Report (Comprehensive Path)

```
User presses <leader>mr
  │
  ├─> show_full_report()
  │     │
  │     ├─> get_metrics(bufnr, "full", callback)
  │     │     │
  │     │     ├─> Check full cache (cache.get_full)
  │     │     │     │
  │     │     │     ├─> Cache valid? → Return immediately ✓
  │     │     │     │
  │     │     │     └─> Cache invalid? → Compute fresh
  │     │     │           │
  │     │     │           ├─> Get buffer content
  │     │     │           ├─> Write temp file
  │     │     │           ├─> Run Pandoc with mode="full"
  │     │     │           ├─> Parse JSON output
  │     │     │           └─> Store in cache (cache.set_full)
  │     │     │                 └─> Also extracts and caches basic metrics!
  │     │     │
  │     │     └─> Callback with full metrics data
  │     │
  │     ├─> Format full report (format_full_report)
  │     │     ├─> Basic statistics section
  │     │     ├─> Readability scores section
  │     │     ├─> Sentence variety section
  │     │     ├─> Passive voice section
  │     │     ├─> Nominalizations section
  │     │     ├─> Vocabulary section
  │     │     └─> AI words section
  │     │
  │     └─> Display in tab/split (utils.open_report_tab)
  │
  └─> User reviews report
```
```

**new_string:**
```
### Flow 2: Full Report (Comprehensive Path)

```
User presses <leader>mr
  │
  ├─> show_full_report()
  │     │
  │     ├─> get_metrics(bufnr, "full", callback)
  │     │     │  (always computes fresh — no full-mode cache)
  │     │     ├─> Get buffer content (utils.get_buffer_content)
  │     │     ├─> Write temp file (utils.write_temp_file)
  │     │     ├─> Run Pandoc with mode="full" (utils.run_pandoc)
  │     │     ├─> Parse JSON output (utils.parse_full_output)
  │     │     └─> Callback with full metrics data
  │     │
  │     ├─> Render full report (display.format_full_report)
  │     │     ├─> Basic statistics section
  │     │     ├─> Readability scores section
  │     │     ├─> Sentence variety section
  │     │     ├─> Passive voice section
  │     │     ├─> Nominalizations section
  │     │     ├─> Vocabulary section
  │     │     └─> AI words section
  │     │
  │     └─> Display in tab/split (utils.open_report_tab)
  │
  └─> User reviews report
```

**Why no full-mode cache?** Reports are user-triggered (typically once per editing session, not per redraw) and benefit more from fresh output than from cache reuse. Caching them would risk showing stale readability scores after edits — a worse failure mode than the 200-500ms recomputation cost. See `cache.lua` for the canonical "What's NOT cached" docstring.
```

### Step 3.4: Add `commands.lua` to Module Dependencies (Edit #16)

- [ ] **Step:** In `docs/MODULE_FLOW.md`, find the "Module Dependencies" block at lines 174-192. The current block:

```
## Module Dependencies

```
init.lua
  ├─> Depends on: config, cache, utils
  └─> Provides: Public API, global shims

config.lua
  ├─> Depends on: (none, standalone)
  └─> Provides: Configuration, validation, auto-detection

cache.lua
  ├─> Depends on: (none, reads changedtick via vim.b[bufnr])
  └─> Provides: Changedtick-based caching for basic metrics

utils.lua
  ├─> Depends on: config (for filter path)
  └─> Provides: File ops, Pandoc execution, formatting, UI
```
```

Apply the edit:

**old_string:**
```
init.lua
  ├─> Depends on: config, cache, utils
  └─> Provides: Public API, global shims

config.lua
  ├─> Depends on: (none, standalone)
  └─> Provides: Configuration, validation, auto-detection

cache.lua
  ├─> Depends on: (none, reads changedtick via vim.b[bufnr])
  └─> Provides: Changedtick-based caching for basic metrics

utils.lua
  ├─> Depends on: config (for filter path)
  └─> Provides: File ops, Pandoc execution, formatting, UI
```

**new_string:**
```
init.lua
  ├─> Depends on: config, cache, commands, utils, basic
  └─> Provides: Public API, global shims (callable accurate_wordcount, text_metrics)

config.lua
  ├─> Depends on: (none, standalone)
  └─> Provides: Configuration, validation, auto-detection, M.get() accessor

cache.lua
  ├─> Depends on: (none, reads changedtick via vim.b[bufnr])
  └─> Provides: Changedtick-based caching for basic metrics

commands.lua
  ├─> Depends on: config (for legacy gating at registration); callbacks lazy-require basic/full/cache/utils
  └─> Provides: User-command registration (setup_commands)

utils.lua
  ├─> Depends on: config (for filter path)
  └─> Provides: File ops, Pandoc execution, formatting, UI
```

### Step 3.5: Add `commands.setup_commands` to Initialization Sequence (Edit #17)

- [ ] **Step:** In `docs/MODULE_FLOW.md`, find the "Initialization Sequence" block at lines 249-272. The current block:

```
## Initialization Sequence

```
First require("writing-metrics")
  │
  ├─> Load init.lua
  │     └─> Schedule auto-initialization
  │
  └─> vim.schedule() deferred execution
        │
        ├─> Check if already initialized
        │
        └─> Call setup() with defaults
              │
              ├─> Load config module
              │     ├─> Merge user opts with defaults
              │     ├─> Validate Pandoc installation
              │     └─> Auto-detect filter path
              │
              ├─> Load cache module
              │     └─> Setup autocmds for invalidation
              │
              └─> Mark as initialized
```

This ensures the plugin "just works" without explicit setup() call, while still allowing customization.
```

Apply the edit:

**old_string:**
```
First require("writing-metrics")
  │
  ├─> Load init.lua
  │     └─> Schedule auto-initialization
  │
  └─> vim.schedule() deferred execution
        │
        ├─> Check if already initialized
        │
        └─> Call setup() with defaults
              │
              ├─> Load config module
              │     ├─> Merge user opts with defaults
              │     ├─> Validate Pandoc installation
              │     └─> Auto-detect filter path
              │
              ├─> Load cache module
              │     └─> Setup autocmds for invalidation
              │
              └─> Mark as initialized
```

**new_string:**
```
First require("writing-metrics")
  │
  ├─> Load init.lua
  │     └─> Schedule auto-initialization
  │
  └─> vim.schedule() deferred execution
        │
        ├─> Check if already initialized
        │
        └─> Call setup() with defaults (idempotent — re-runs reset shims + commands)
              │
              ├─> Load config module
              │     ├─> Merge user opts with defaults
              │     ├─> Validate Pandoc installation
              │     └─> Resolve filter path (auto-detect if filter.auto_detect=true)
              │
              ├─> Register global shims
              │     ├─> _G.accurate_wordcount (callable table, both contracts)
              │     └─> _G.text_metrics (function)
              │
              ├─> Load commands module
              │     └─> commands.setup_commands(config.get())
              │            ├─> Register :WordCount, :ReadabilityReport, etc.
              │            └─> Register or remove legacy aliases per cfg.commands.enable_legacy
              │
              ├─> Load cache module
              │     └─> Setup autocmds for invalidation
              │
              └─> Mark as initialized
```

---

## Task 4: Verification and Commit

**Files:**
- Read-only checks across `~/projects/nvim-writing-metrics/docs/`
- Single commit in `~/projects/nvim-writing-metrics/`

### Step 4.1: Stale-term grep across the three modified docs

- [ ] **Step:** Run from `~/projects/nvim-writing-metrics/`:

```bash
for term in "four core modules" "30x faster" "pre-existing failure cluster" "vim.loop" "set_full" "cache.get_full" "Track 3" "Track 4" "Track 5" "Track 6" "Track 7"; do
  echo "=== Searching for: $term ==="
  grep -nH "$term" docs/CORE_MODULES.md docs/DESIGN_INNOVATIONS.md docs/MODULE_FLOW.md || echo "(no matches — good)"
done
```

Expected: every term should report `(no matches — good)`.

If any term still has matches, that's a missed edit. Open the file at the reported line, decide whether the match is a genuine stale reference (fix it) or a legitimate occurrence (e.g., a quote like "`vim.loop` was migrated to `vim.uv` in Plan C" — but no such reference exists in current docs after this plan's edits, so any hit should be fixed). If you fix something, re-run the grep.

### Step 4.2: Cross-check the new `_G.accurate_wordcount` snippets against source

- [ ] **Step:** Confirm the 8-method list in the new snippet matches what `init.lua` actually forwards. Run:

```bash
grep -A1 "local acc_wc = {" ~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua | head -15
```

Compare against the 8 methods listed in the new snippets you wrote in steps 1.7 and 2.2:
- `get_fast_count`
- `get_accurate_count`
- `get_reading_time`
- `show_reading_time`
- `show_comparison`
- `toggle_statusline_mode`
- `statusline_mode`
- `update_lualine_accurate_count` (note: this aliases `basic.update_statusline_accurate_count` — the doc shows the alias name as exposed on the table)

If a method is missing or renamed in source, update the snippets in both files.

### Step 4.3: Cross-check the new §5 commands list against `commands.lua`

- [ ] **Step:** Confirm the 7 primary commands and 2 legacy aliases listed in step 1.6 match what `commands.lua` registers. Run:

```bash
grep "nvim_create_user_command\|nvim_del_user_command" ~/projects/nvim-writing-metrics/lua/writing-metrics/commands.lua
```

Expected commands (primary): `WordCount`, `ReadabilityReport`, `ReadingTime`, `WritingMetrics`, `WritingMetricsToggle`, `WritingMetricsCache`, `WritingMetricsClear`. Expected legacy aliases: `AccurateWordCount`, `ToggleWordCountMode`. If anything differs, update the §5 tables in `CORE_MODULES.md` to match.

### Step 4.4: Fresh-reader pass

- [ ] **Step:** Read each modified file end to end with no codebase context.

```bash
# Open each in turn — read straight through
cat ~/projects/nvim-writing-metrics/docs/CORE_MODULES.md
cat ~/projects/nvim-writing-metrics/docs/DESIGN_INNOVATIONS.md
cat ~/projects/nvim-writing-metrics/docs/MODULE_FLOW.md
```

For each doc ask:
- Does the architecture diagram match the module list in the prose?
- Does any sentence reference a function or behavior that no longer exists?
- Does the prose flow naturally where sections were deleted (e.g., DESIGN_INNOVATIONS.md after the Measurement deletion)?
- Is the new `commands.lua` content coherent (no dangling "see section X" pointers)?

Fix any issue found, then re-run step 4.1 if you touched anything.

### Step 4.5: Commit

- [ ] **Step:** Stage and commit. Run from `~/projects/nvim-writing-metrics/`:

```bash
git add docs/CORE_MODULES.md docs/DESIGN_INNOVATIONS.md docs/MODULE_FLOW.md
git status
```

Expected: three modified files, no untracked additions.

Then commit with the message from the spec:

```bash
git commit -m "$(cat <<'EOF'
docs: sync architecture docs with post-Plan-H state (Plan I)

Closes 11 audit items + 3 adjacent stale claims across CORE_MODULES.md,
DESIGN_INNOVATIONS.md, MODULE_FLOW.md:
- Adds commands.lua module section and integrates it into the
  architecture diagram, dependency graph, and init sequence
- Updates _G.accurate_wordcount snippets to reflect the callable-table
  contract introduced in Plan F (both call form and 8-method table form)
- Removes stale full-mode cache flows from MODULE_FLOW.md Flow 1 + 2;
  adds 'why no full cache' note to Flow 2
- Drops the stale '30x faster startup' measurement subsection (numbers
  were unverified after Plan F's setup() refactor)
- Documents M.get() accessor, commands.enable_legacy default, and
  filter.auto_detect semantics
- Replaces stale 'Next Steps' (Track 3/4/5/6/7 — all shipped) with a
  Future Work list (Plan J, Plan K, auto_detect simplification,
  checkhealth audit)
- Updates Module Statistics line count to include commands.lua
- Drops stale 'pre-existing failure cluster' claim (suite is 118/0
  after Plan H)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Run `git log -1 --stat` to verify the commit looks right.

---

## Done When

- All 17 edits applied across the three docs.
- Step 4.1 grep returns zero matches for every stale term.
- Steps 4.2 and 4.3 cross-checks pass.
- Step 4.4 fresh-reader pass turns up no remaining issues.
- A single commit is on `main` in `~/projects/nvim-writing-metrics/` with the message above.
