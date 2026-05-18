# Plan C — Deprecated API sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every deprecated `vim.loop.*` and `vim.api.nvim_buf_get_option`/`nvim_buf_set_option` call in `nvim-writing-metrics` with the modern `vim.uv.*` and `nvim_get_option_value`/`nvim_set_option_value` equivalents so the plugin continues to work when Neovim eventually removes the compatibility shims.

**Architecture:** Mechanical sweep, one commit per file. No behavior change. Run the test suite after each file converts so any regression is attributed to that file's changes, not the cumulative sweep. Per the spec, this plan skips per-task spec/code-quality reviews in favor of one holistic review at the end.

**Tech Stack:** Lua 5.1 (LuaJIT in Neovim), the `vim.uv` libuv binding, the `vim.api.nvim_*_option_value` API. All available in Neovim 0.10+; the plugin already requires Neovim ≥ 0.10 per `CHANGELOG.md`.

---

## Conventions

- **Plugin repo:** `~/projects/nvim-writing-metrics/` — git-tracked, commits land directly on `main`.
- **Run tests:** `cd ~/projects/nvim-writing-metrics && ./run-tests.sh` (all).
- **Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-17-tier3-tier4-cleanup-design.md`
- **Baseline test counts (HEAD `63549a7`, post-Plan B):** 87 pass / 32 fail across the full suite. New work must not increase the failure count. (The 32 failures cluster across `basic_spec.lua`, `full_spec.lua`, `config_spec.lua`, `compatibility_spec.lua`, `integration_spec.lua` — all pre-existing; see `project_nvim_writing_metrics_stale_tests.md` and `project_nvim_writing_metrics_full_spec_failures.md`.)

**Review discipline:** Per the spec, Plan C uses one holistic review at the end instead of per-task spec/code-quality reviews. Reasoning: changes are single-symbol mechanical replacements that any reviewer would judge with the same criteria, so one review of the combined diff is more efficient than seven small reviews.

**API replacement patterns (the only thing this plan does):**

```lua
-- Pattern 1: timer/clock APIs
vim.loop.now()        →  vim.uv.now()
vim.loop.new_timer()  →  vim.uv.new_timer()
vim.loop.hrtime()     →  vim.uv.hrtime()

-- Pattern 2: buffer-scoped get
vim.api.nvim_buf_get_option(bufnr, "X")
    →
vim.api.nvim_get_option_value("X", { buf = bufnr })

-- Pattern 3: buffer-scoped set
vim.api.nvim_buf_set_option(bufnr, "X", value)
    →
vim.api.nvim_set_option_value("X", value, { buf = bufnr })

-- Pattern 4: pcall wrapping pattern 2
pcall(vim.api.nvim_buf_get_option, bufnr, "X")
    →
pcall(vim.api.nvim_get_option_value, "X", { buf = bufnr })
```

Pre-existing facts the implementer should know going in:
- `vim.uv` is the canonical name for Neovim's libuv binding; `vim.loop` is the deprecated alias that still works but emits deprecation warnings in some Neovim versions.
- `nvim_get_option_value`/`nvim_set_option_value` accept an options table as the last argument; `{ buf = bufnr }` scopes the operation to a buffer (replacing `nvim_buf_*_option`'s positional bufnr argument).
- Line numbers in this plan were captured at HEAD `63549a7`. They may shift slightly as tasks land; use the symbolic patterns (e.g. `vim.loop.now()`) to find each site rather than relying solely on line numbers.

**Verification after each task** (boilerplate referenced from each task):

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile <file>" -c "qa!" 2>&1 | head -5
# Expected: no output (file parses cleanly).

./run-tests.sh 2>&1 | tail -10
# Expected: 87 pass / 32 fail total (unchanged from baseline).
```

---

## Task 1: Convert `cache.lua`

**File:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua`

**Sites to convert (4):**

| Line | Current call | Replacement |
|---|---|---|
| 21 | `vim.loop.now()` | `vim.uv.now()` |
| 142 | `vim.api.nvim_buf_get_option(args.buf, "filetype")` | `vim.api.nvim_get_option_value("filetype", { buf = args.buf })` |
| 161 | `vim.api.nvim_buf_get_option(args.buf, "filetype")` | `vim.api.nvim_get_option_value("filetype", { buf = args.buf })` |
| 180 | `vim.loop.new_timer()` | `vim.uv.new_timer()` |

- [ ] **Step 1: Apply the four replacements**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua`, find line 21 inside `local function now()`:

```lua
local function now()
  return vim.loop.now()
end
```

Replace with:

```lua
local function now()
  return vim.uv.now()
end
```

Then find line 142 inside the cache invalidation autocmd callback:

```lua
      local ft = vim.api.nvim_buf_get_option(args.buf, "filetype")
```

Replace with:

```lua
      local ft = vim.api.nvim_get_option_value("filetype", { buf = args.buf })
```

Then find line 161 inside the BufWritePost autocmd callback (same shape as the previous replacement):

```lua
      local ft = vim.api.nvim_buf_get_option(args.buf, "filetype")
```

Replace with:

```lua
      local ft = vim.api.nvim_get_option_value("filetype", { buf = args.buf })
```

Then find line 180 inside `M.setup_autocmds`:

```lua
  -- Optional: Periodic cleanup of stale entries (every 5 minutes)
  local timer = vim.loop.new_timer()
```

Replace with:

```lua
  -- Optional: Periodic cleanup of stale entries (every 5 minutes)
  local timer = vim.uv.new_timer()
```

- [ ] **Step 2: Verify the file parses and the deprecated symbols are gone**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/cache.lua" -c "qa!" 2>&1 | head -5
grep -n "vim\.loop\.\|nvim_buf_get_option\|nvim_buf_set_option" lua/writing-metrics/cache.lua
```

Expected: parse check has no output. Grep has no matches in cache.lua.

- [ ] **Step 3: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: 87 pass / 32 fail (unchanged from baseline). If pass/fail counts shift, STOP and investigate — the shift is attributable to this task's changes since nothing else moved.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/cache.lua
git commit -m "refactor(cache): migrate to vim.uv + nvim_get_option_value

Replaces vim.loop.now/new_timer with their vim.uv equivalents and
the two nvim_buf_get_option('filetype') calls with
nvim_get_option_value('filetype', { buf = ... }). No behavior
change — both APIs return the same values."
```

---

## Task 2: Convert `utils.lua`

**File:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua`

**Sites to convert (6):**

| Line | Current call | Replacement |
|---|---|---|
| 91 | `pcall(vim.api.nvim_buf_get_option, bufnr, "buftype")` | `pcall(vim.api.nvim_get_option_value, "buftype", { buf = bufnr })` |
| 271 | `vim.api.nvim_buf_set_option(bufnr, "modifiable", false)` | `vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })` |
| 272 | `vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")` | `vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })` |
| 319 | `vim.api.nvim_buf_set_option(bufnr, "filetype", opts.filetype or "markdown")` | `vim.api.nvim_set_option_value("filetype", opts.filetype or "markdown", { buf = bufnr })` |
| 320 | `vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")` | `vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })` |
| 321 | `vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")` | `vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })` |

- [ ] **Step 1: Apply the six replacements**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua`, find line 91 (inside `M.is_report_buffer`):

```lua
  local ok_buftype, buftype = pcall(vim.api.nvim_buf_get_option, bufnr, "buftype")
```

Replace with:

```lua
  local ok_buftype, buftype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = bufnr })
```

Then find lines 271-272 (likely inside a floating-window helper):

```lua
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
```

Replace with:

```lua
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
```

Then find lines 319-321 (the second floating-window setup block):

```lua
  vim.api.nvim_buf_set_option(bufnr, "filetype", opts.filetype or "markdown")
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
```

Replace with:

```lua
  vim.api.nvim_set_option_value("filetype", opts.filetype or "markdown", { buf = bufnr })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
```

- [ ] **Step 2: Verify the file parses and the deprecated symbols are gone**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/utils.lua" -c "qa!" 2>&1 | head -5
grep -n "vim\.loop\.\|nvim_buf_get_option\|nvim_buf_set_option" lua/writing-metrics/utils.lua
```

Expected: parse check has no output. Grep has no matches in utils.lua.

- [ ] **Step 3: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: 87 pass / 32 fail.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/utils.lua
git commit -m "refactor(utils): migrate to nvim_get/set_option_value

One pcall-wrapped get_option (is_report_buffer's buftype check)
and five set_options across two floating-window setup blocks.
The pcall(fn, ...) form is preserved by passing the new function
reference as the pcall target."
```

---

## Task 3: Convert `basic.lua`

**File:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua`

**Sites to convert (5 — all `nvim_buf_get_option(buf, "filetype")`):**

| Line | Current call | Replacement |
|---|---|---|
| 380 | `vim.api.nvim_buf_get_option(bufnr, "filetype")` | `vim.api.nvim_get_option_value("filetype", { buf = bufnr })` |
| 454 | `vim.api.nvim_buf_get_option(0, "filetype")` | `vim.api.nvim_get_option_value("filetype", { buf = 0 })` |
| 555 | `vim.api.nvim_buf_get_option(args.buf, "filetype")` | `vim.api.nvim_get_option_value("filetype", { buf = args.buf })` |
| 568 | `vim.api.nvim_buf_get_option(args.buf, "filetype")` | `vim.api.nvim_get_option_value("filetype", { buf = args.buf })` |
| 582 | `vim.api.nvim_buf_get_option(args.buf, "filetype")` | `vim.api.nvim_get_option_value("filetype", { buf = args.buf })` |

- [ ] **Step 1: Apply the five replacements**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua`, find each occurrence and apply the replacement. Because every site uses `"filetype"` and only the buffer argument varies, the easiest method is a targeted text replacement.

Find line 380 (likely inside a public API function):

```lua
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
```

Replace with:

```lua
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
```

Find line 454 (uses `0` for current buffer):

```lua
      local ft = vim.api.nvim_buf_get_option(0, "filetype")
```

Replace with:

```lua
      local ft = vim.api.nvim_get_option_value("filetype", { buf = 0 })
```

Find lines 555, 568, 582 (three autocmd callbacks, each with `args.buf`):

```lua
      local ft = vim.api.nvim_buf_get_option(args.buf, "filetype")
```

Replace each (3 sites, same shape):

```lua
      local ft = vim.api.nvim_get_option_value("filetype", { buf = args.buf })
```

- [ ] **Step 2: Verify the file parses and the deprecated symbols are gone**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/basic.lua" -c "qa!" 2>&1 | head -5
grep -n "vim\.loop\.\|nvim_buf_get_option\|nvim_buf_set_option" lua/writing-metrics/basic.lua
```

Expected: parse check has no output. Grep has no matches in basic.lua.

- [ ] **Step 3: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: 87 pass / 32 fail. (`basic_spec.lua` has 9 pre-existing failures — verify the count stays at 9, not 10+.)

- [ ] **Step 4: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/basic.lua
git commit -m "refactor(basic): migrate to nvim_get_option_value

Five buf_get_option('filetype') sites: one in a public API check,
one in a lualine component, three in autocmd callbacks. Behavior
unchanged."
```

---

## Task 4: Convert `full.lua`

**File:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/full.lua:89`

**Sites to convert (1):**

| Line | Current call | Replacement |
|---|---|---|
| 89 | `vim.api.nvim_buf_get_option(bufnr, "filetype")` | `vim.api.nvim_get_option_value("filetype", { buf = bufnr })` |

- [ ] **Step 1: Apply the replacement**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/full.lua`, find line 89 inside `M.show_report`'s filetype validation:

```lua
  -- Validation 2: Only generate reports for writing filetypes
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
```

Replace with:

```lua
  -- Validation 2: Only generate reports for writing filetypes
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
```

- [ ] **Step 2: Verify the file parses and the deprecated symbols are gone**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/full.lua" -c "qa!" 2>&1 | head -5
grep -n "vim\.loop\.\|nvim_buf_get_option\|nvim_buf_set_option" lua/writing-metrics/full.lua
```

Expected: parse check has no output. Grep has no matches in full.lua.

- [ ] **Step 3: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: 87 pass / 32 fail. (`full_spec.lua` has 4 pre-existing failures — verify it stays at 4.)

- [ ] **Step 4: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/full.lua
git commit -m "refactor(full): migrate to nvim_get_option_value

Single buf_get_option('filetype') in show_report's filetype
validation. Behavior unchanged."
```

---

## Task 5: Convert `init.lua`

**File:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua:105`

**Sites to convert (1):**

| Line | Current call | Replacement |
|---|---|---|
| 105 | `vim.api.nvim_buf_get_option(bufnr, "filetype")` | `vim.api.nvim_get_option_value("filetype", { buf = bufnr })` |

- [ ] **Step 1: Apply the replacement**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua`, find line 105 inside `M.is_writing_buffer`:

```lua
function M.is_writing_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
  local utils = get_utils()
  return utils.is_writing_filetype(ft)
end
```

Replace with:

```lua
function M.is_writing_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  local utils = get_utils()
  return utils.is_writing_filetype(ft)
end
```

- [ ] **Step 2: Verify the file parses and the deprecated symbols are gone**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/init.lua" -c "qa!" 2>&1 | head -5
grep -n "vim\.loop\.\|nvim_buf_get_option\|nvim_buf_set_option" lua/writing-metrics/init.lua
```

Expected: parse check has no output. Grep has no matches in init.lua.

- [ ] **Step 3: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: 87 pass / 32 fail.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/init.lua
git commit -m "refactor(init): migrate to nvim_get_option_value

Single buf_get_option('filetype') in is_writing_buffer. Behavior
unchanged."
```

---

## Task 6: Convert `display.lua`

**File:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua`

**Sites to convert (6 — all `nvim_buf_set_option`):**

| Line | Current call | Replacement |
|---|---|---|
| 106 | `vim.api.nvim_buf_set_option(report_bufnr, "modifiable", true)` | `vim.api.nvim_set_option_value("modifiable", true, { buf = report_bufnr })` |
| 112 | `vim.api.nvim_buf_set_option(report_bufnr, "modifiable", false)` | `vim.api.nvim_set_option_value("modifiable", false, { buf = report_bufnr })` |
| 805 | `vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")` | `vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })` |
| 806 | `vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")` | `vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })` |
| 807 | `vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")` | `vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })` |
| 808 | `vim.api.nvim_buf_set_option(bufnr, "modifiable", false)` | `vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })` |

- [ ] **Step 1: Apply the six replacements**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua`, find lines 106 and 112 (inside the report-buffer update helper):

```lua
  vim.api.nvim_buf_set_option(report_bufnr, "modifiable", true)
```

Replace with:

```lua
  vim.api.nvim_set_option_value("modifiable", true, { buf = report_bufnr })
```

And:

```lua
  vim.api.nvim_buf_set_option(report_bufnr, "modifiable", false)
```

Replace with:

```lua
  vim.api.nvim_set_option_value("modifiable", false, { buf = report_bufnr })
```

Then find lines 805-808 (the report-buffer creation block, just before `setup_report_keymaps`):

```lua
  vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")  -- Keep buffer when hidden (multiple reports)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
```

Replace with:

```lua
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })  -- Keep buffer when hidden (multiple reports)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
```

- [ ] **Step 2: Verify the file parses and the deprecated symbols are gone**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/display.lua" -c "qa!" 2>&1 | head -5
grep -n "vim\.loop\.\|nvim_buf_get_option\|nvim_buf_set_option" lua/writing-metrics/display.lua
```

Expected: parse check has no output. Grep has no matches in display.lua.

- [ ] **Step 3: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: 87 pass / 32 fail.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/display.lua
git commit -m "refactor(display): migrate to nvim_set_option_value

Six buf_set_option sites: two in the report-buffer update helper
(modifiable toggles around the writes) and four in the report-
buffer creation block (filetype, buftype, bufhidden, modifiable).
Behavior unchanged."
```

---

## Task 7: Sweep test files for consistency

**Files:**
- Modify: `~/projects/nvim-writing-metrics/tests/helpers.lua` (4 sites)
- Modify: `~/projects/nvim-writing-metrics/tests/basic_spec.lua` (2 sites)
- Modify: `~/projects/nvim-writing-metrics/tests/integration_spec.lua` (4 sites)

**Background:** The spec scopes Plan C to the production module files, but the test files use the same deprecated APIs. Including them in the sweep is a minor scope extension that keeps the codebase consistent and prevents the next audit from re-flagging them.

**Sites to convert (10 total):**

| File | Line | Current call | Replacement |
|---|---|---|---|
| `tests/helpers.lua` | 9 | `vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")` | `vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })` |
| `tests/helpers.lua` | 54 | `vim.loop.hrtime()` | `vim.uv.hrtime()` |
| `tests/helpers.lua` | 61 | `vim.loop.hrtime()` | `vim.uv.hrtime()` |
| `tests/helpers.lua` | 159 | `vim.api.nvim_buf_get_option(bufnr, "modified")` | `vim.api.nvim_get_option_value("modified", { buf = bufnr })` |
| `tests/basic_spec.lua` | 158 | `vim.loop.hrtime()` | `vim.uv.hrtime()` |
| `tests/basic_spec.lua` | 168 | `vim.loop.hrtime()` | `vim.uv.hrtime()` |
| `tests/integration_spec.lua` | 137 | `vim.loop.hrtime()` | `vim.uv.hrtime()` |
| `tests/integration_spec.lua` | 147 | `vim.loop.hrtime()` | `vim.uv.hrtime()` |
| `tests/integration_spec.lua` | 293 | `vim.loop.hrtime()` | `vim.uv.hrtime()` |
| `tests/integration_spec.lua` | 295 | `vim.loop.hrtime()` | `vim.uv.hrtime()` |

- [ ] **Step 1: Apply the four replacements in `tests/helpers.lua`**

In `~/projects/nvim-writing-metrics/tests/helpers.lua`, find line 9 inside `M.create_test_buffer`:

```lua
  vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
```

Replace with:

```lua
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
```

Then find lines 54 and 61 inside `M.wait_for_async`:

```lua
  local start = vim.loop.hrtime()
```

Replace with:

```lua
  local start = vim.uv.hrtime()
```

And:

```lua
    local elapsed = (vim.loop.hrtime() - start) / 1e6
```

Replace with:

```lua
    local elapsed = (vim.uv.hrtime() - start) / 1e6
```

Then find line 159 inside `M.cleanup_buffers`:

```lua
    if vim.api.nvim_buf_is_valid(bufnr) and not vim.api.nvim_buf_get_option(bufnr, "modified") then
```

Replace with:

```lua
    if vim.api.nvim_buf_is_valid(bufnr) and not vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
```

- [ ] **Step 2: Apply the two replacements in `tests/basic_spec.lua`**

In `~/projects/nvim-writing-metrics/tests/basic_spec.lua`, find lines 158 and 168 inside the "caches results" performance test:

```lua
      local start_time = vim.loop.hrtime()
```

Replace with:

```lua
      local start_time = vim.uv.hrtime()
```

And:

```lua
      local elapsed = (vim.loop.hrtime() - start_time) / 1e6
```

Replace with:

```lua
      local elapsed = (vim.uv.hrtime() - start_time) / 1e6
```

- [ ] **Step 3: Apply the four replacements in `tests/integration_spec.lua`**

In `~/projects/nvim-writing-metrics/tests/integration_spec.lua`, find lines 137, 147, 293, 295 (two timing blocks). For each `vim.loop.hrtime()` call:

```lua
      local start_time = vim.loop.hrtime()
```

Replace with:

```lua
      local start_time = vim.uv.hrtime()
```

And for each elapsed-calculation line:

```lua
      local elapsed = (vim.loop.hrtime() - start_time) / 1e6
```

Replace with:

```lua
      local elapsed = (vim.uv.hrtime() - start_time) / 1e6
```

(Same pattern as Step 2; apply identically at each of the 4 sites — 2 starts, 2 elapsed.)

- [ ] **Step 4: Verify the test files parse and the deprecated symbols are gone**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile tests/helpers.lua" -c "qa!" 2>&1 | head -5
grep -rn "vim\.loop\.\|nvim_buf_get_option\|nvim_buf_set_option" --include="*.lua" tests/
```

Expected: parse check has no output. Grep has no matches in `tests/`.

- [ ] **Step 5: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: 87 pass / 32 fail (unchanged).

- [ ] **Step 6: Confirm the entire repo is free of the deprecated APIs**

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "vim\.loop\.\|nvim_buf_get_option\|nvim_buf_set_option" --include="*.lua" lua/ tests/ scripts/ plugin/
```

Expected: zero matches. If anything appears, it's a site missed by Tasks 1-7; add it as a small follow-up edit in this same commit.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add tests/helpers.lua tests/basic_spec.lua tests/integration_spec.lua
git commit -m "refactor(tests): migrate to vim.uv + nvim_get/set_option_value

Sweep extension beyond the spec's production-file scope: tests
used the same deprecated APIs, and keeping them in lockstep with
the production modules avoids re-flagging by the next audit.
- helpers.lua: 1 set, 1 get, 2 hrtime
- basic_spec.lua: 2 hrtime
- integration_spec.lua: 4 hrtime"
```

---

## Final verification

After all seven tasks land, run a global confirmation:

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "vim\.loop\.\|nvim_buf_get_option\|nvim_buf_set_option" --include="*.lua" .
```

Expected: zero matches anywhere in the repo (or only matches in `docs/` markdown code examples, which are documentation and can be updated as a follow-up).

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: 87 pass / 32 fail (unchanged from baseline).

```bash
cd ~/projects/nvim-writing-metrics
git log --oneline 63549a7..HEAD
```

Expected: 7 commits, all `refactor(...)` prefixed:
- `refactor(cache): migrate to vim.uv + nvim_get_option_value`
- `refactor(utils): migrate to nvim_get/set_option_value`
- `refactor(basic): migrate to nvim_get_option_value`
- `refactor(full): migrate to nvim_get_option_value`
- `refactor(init): migrate to nvim_get_option_value`
- `refactor(display): migrate to nvim_set_option_value`
- `refactor(tests): migrate to vim.uv + nvim_get/set_option_value`

---

## Holistic review

Per the spec, Plan C uses one holistic review at the end. Dispatch one code-reviewer subagent against the cumulative diff:

```bash
cd ~/projects/nvim-writing-metrics
git diff 63549a7 HEAD --stat
git diff 63549a7 HEAD
```

Reviewer focus areas:
- **Correctness:** Each pattern-3 set conversion correctly moved the value argument into position 2 (between option name and options table), not position 3.
- **Pcall preservation:** The `tests/helpers.lua:159` and `utils.lua:91` sites that wrap calls in `pcall` correctly pass the function reference (not the result) as `pcall`'s first argument.
- **Comment hygiene:** Inline comments that referenced the old API names have been updated where present.
- **No behavior drift:** No site accidentally added or omitted an argument; the `{ buf = bufnr }` options table consistently uses `buf` (not `bufnr` or `buffer`).

---

## Summary

7 tasks, 7 commits on `main` of `~/projects/nvim-writing-metrics/`. 33 mechanical edits total (4 in cache, 6 in utils, 5 in basic, 1 in full, 1 in init, 6 in display, 10 in tests). No behavior change; no new tests; baseline test counts preserved at 87 pass / 32 fail. Estimated 45-60 minutes of focused work plus the holistic review.

After completion:
- The plugin is free of deprecated `vim.loop.*` and `nvim_buf_*_option` calls.
- The plugin continues to work transparently when Neovim eventually removes the compatibility shims.
- The codebase is consistent: no mixed old/new API usage to trip up future readers.
