# Plan B — State, UX, dead code, doc rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix six items from the Tier 3/4 audit in `nvim-writing-metrics` — a state-reset bug (#13), a div-by-zero display bug (#15-display), an emoji-coupled navigation refactor (#14), two dead-code removals (#2, #11), and a documentation rewrite (#9).

**Architecture:** Five small fixes plus one focused refactor. The refactor (#14) introduces a single `M.SECTIONS` table in `display.lua` that drives both the rendered headings and the section-jump keymaps so they can't drift apart. All other tasks are localized edits.

**Tech Stack:** Lua 5.1 (LuaJIT in Neovim), plenary.busted for tests, markdown for the doc rewrite.

---

## Conventions

- **Plugin repo:** `~/projects/nvim-writing-metrics/` — git-tracked, commits land directly on `main`.
- **Run tests:** `cd ~/projects/nvim-writing-metrics && ./run-tests.sh` (all) or `-t tests/<spec>.lua` for one file.
- **Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-17-tier3-tier4-cleanup-design.md`
- **Baseline test counts (post-Plan A HEAD b6c87c4):** 22 pass / 9 fail in `basic_spec.lua`; 19 pass / 4 fail in `full_spec.lua`; 3 pass / 0 fail in `utils_spec.lua`. Pre-existing failures memorialized in `project_nvim_writing_metrics_stale_tests.md` and `project_nvim_writing_metrics_full_spec_failures.md`. New work must not increase the failure count.

Pre-existing facts the implementer should know going in:
- `_G.writing_metrics_reports` is a global table mapping normalized source-buffer keys to report-buffer numbers. Used by `display.lua` to find existing reports and update them in place.
- `display.format_*_section` functions emit markdown headings like `## 📊 Basic Statistics` for 8 distinct sections.
- `display.setup_report_keymaps` binds keys `1`-`8` in report buffers to search-jump commands like `/^## 📊<CR>:nohlsearch<CR>` — currently the emoji glyphs are hardcoded in TWO places (heading + keymap pattern) with no shared source of truth.
- The cache is changedtick-based (see `cache.content_changed` at `cache.lua:137-147`); the `basic_ttl` config knob and `cache.is_valid` function are unused leftovers from the previous TTL-based design.
- `tests/config_spec.lua` and `tests/compatibility_spec.lua` already reference `cache.full_ttl` (which no longer exists in defaults), so some of those tests likely fail at baseline — they're part of the pre-existing failure cluster.

---

## Task 1: Fix #13 — Reset `_G.writing_metrics_reports` in `setup()`

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua:10, 31-43`
- Test: `~/projects/nvim-writing-metrics/tests/init_spec.lua` (NEW FILE)

**Background:** `_G.writing_metrics_reports` is initialized at module-load with `_G.writing_metrics_reports = _G.writing_metrics_reports or {}`. The `or {}` clause preserves any prior global, so after `:Lazy reload` (which re-`require`s the module without restarting Neovim) stale buffer numbers from the previous load survive — they may now point to wiped buffers or collide with newly-allocated bufnrs. Fix: reset the table unconditionally inside `setup()` so each plugin setup gets a clean slate.

- [ ] **Step 1: Create a new test file with the failing test**

Create `~/projects/nvim-writing-metrics/tests/init_spec.lua` with:

```lua
-- Tests for writing-metrics init module
local helpers = require("tests.helpers")

describe("writing-metrics init", function()
  after_each(function()
    helpers.cleanup_buffers()
  end)

  describe("setup", function()
    it("resets _G.writing_metrics_reports so :Lazy reload doesn't preserve stale state", function()
      -- Simulate stale state from a previous module load.
      _G.writing_metrics_reports = { ["/some/stale/path.md"] = 9999 }

      -- Re-require and call setup() — what :Lazy reload effectively does.
      package.loaded["writing-metrics"] = nil
      local wm = require("writing-metrics")
      wm.setup({})

      assert.same({}, _G.writing_metrics_reports,
        "setup() should reset the reports table; got: "
        .. vim.inspect(_G.writing_metrics_reports))
    end)
  end)
end)
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/init_spec.lua 2>&1 | tail -10
```

Expected: the test fails because `_G.writing_metrics_reports` still contains `{ ["/some/stale/path.md"] = 9999 }` after setup. (The current `or {}` preserves the table since it's non-nil.)

- [ ] **Step 3: Apply the fix**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua`, find the existing initialization at line 10:

```lua
--- Global tracking table for report buffers
--- Keys are normalized: absolute resolved path for named buffers,
--- "unnamed:<bufnr>" for unnamed buffers (see display.tracking_key).
--- @type table<string, number>
_G.writing_metrics_reports = _G.writing_metrics_reports or {}
```

Replace with:

```lua
--- Global tracking table for report buffers.
--- Keys are normalized: absolute resolved path for named buffers,
--- "unnamed:<bufnr>" for unnamed buffers (see display.tracking_key).
--- The table is reset to {} inside setup() so :Lazy reload doesn't
--- preserve stale buffer numbers from a previous load. This line
--- ensures the table exists for code paths that touch it before
--- setup() runs.
--- @type table<string, number>
_G.writing_metrics_reports = _G.writing_metrics_reports or {}
```

(Comment-only update at line 10 — the `or {}` initialization stays as a safety net.)

Then in the same file, find the `setup()` function around line 31-43:

```lua
function M.setup(opts)
  -- Always merge opts so subsequent calls with explicit opts are honored.
  local config = get_config()
  local ok = config.setup(opts or {})

  if not ok then
    return false
  end

  -- One-time side effects (autocmds, validators, command registration).
  if M._initialized then
    return true
  end
```

Replace with:

```lua
function M.setup(opts)
  -- Always merge opts so subsequent calls with explicit opts are honored.
  local config = get_config()
  local ok = config.setup(opts or {})

  if not ok then
    return false
  end

  -- Reset report tracking unconditionally so :Lazy reload (which re-requires
  -- this module but preserves _G across the reload) starts each setup with
  -- a fresh table. Without this, stale buffer numbers from the prior load
  -- can collide with newly-allocated bufnrs or point to wiped buffers.
  _G.writing_metrics_reports = {}

  -- One-time side effects (autocmds, validators, command registration).
  if M._initialized then
    return true
  end
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/init_spec.lua 2>&1 | tail -10
```

Expected: the new test passes (1 success / 0 failed in `init_spec.lua`).

- [ ] **Step 5: Run the full suite to confirm no regressions**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: total pass count is up by 1; failure count unchanged from baseline.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/init.lua tests/init_spec.lua
git commit -m "fix(init): reset _G.writing_metrics_reports in setup() for :Lazy reload safety

The module-load init (= ... or {}) preserved stale state across
:Lazy reload, because _G survives the module re-require. Stale
bufnrs could collide with newly-allocated buffers or point to
wiped buffers. setup() now resets the table unconditionally so
each plugin setup starts clean."
```

---

## Task 2: Fix #15-display — Guard vocabulary div-by-zero

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua:629, 640`
- Test: `~/projects/nvim-writing-metrics/tests/display_spec.lua` (NEW FILE)

**Background:** In `format_vocabulary_section`, the variable `total = vocabulary.total_words or 0`. Two lines later, `local word_pct = (word_count / total) * 100`. If `total == 0` (empty buffer edge case, or upstream miscount), the result is `nan` (0/0) or `inf` (positive/0), and the formatted output shows `nan%` or `inf%`. The fix is a `total > 0` guard at both sites.

- [ ] **Step 1: Create a new test file with the failing test**

Create `~/projects/nvim-writing-metrics/tests/display_spec.lua` with:

```lua
-- Tests for writing-metrics.display module
local helpers = require("tests.helpers")

describe("writing-metrics.display", function()
  local display

  before_each(function()
    package.loaded["writing-metrics.display"] = nil
    display = require("writing-metrics.display")
  end)

  after_each(function()
    helpers.cleanup_buffers()
  end)

  describe("format_vocabulary_section", function()
    it("does not produce nan% or inf% when total_words is 0", function()
      -- Edge case: vocabulary present but total_words is 0.
      -- Could happen if upstream miscounts or with an empty buffer.
      local vocabulary = {
        total_words = 0,
        unique_words = 0,
        ttr = 0,
        most_frequent = {
          { word = "ghost", count = 1 },
          { word = "phantom", count = 2 },
        },
      }

      local lines = display.format_vocabulary_section(vocabulary)
      local rendered = table.concat(lines, "\n")

      assert.is_nil(rendered:lower():find("nan"),
        "rendered output should not contain 'nan'; got: " .. rendered)
      assert.is_nil(rendered:lower():find("inf"),
        "rendered output should not contain 'inf'; got: " .. rendered)
    end)
  end)
end)
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/display_spec.lua 2>&1 | tail -10
```

Expected: the test fails — the rendered output contains `nan%` from the `(1 / 0) * 100` calculation.

- [ ] **Step 3: Apply the fix**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua`, find the first occurrence around line 629 inside `format_vocabulary_section`:

```lua
    for i = 1, max_words do
      local item = vocabulary.most_frequent[i]
      local word = item.word or item[1]
      local word_count = item.count or item[2]
      local word_pct = (word_count / total) * 100
      table.insert(lines, string.format("%2d. **%s** - %d times (%.2f%%)", i, word, word_count, word_pct))
    end
```

Replace with:

```lua
    for i = 1, max_words do
      local item = vocabulary.most_frequent[i]
      local word = item.word or item[1]
      local word_count = item.count or item[2]
      -- Guard against 0/0 = nan or n/0 = inf when total_words is 0
      -- (empty buffer edge case or upstream miscount).
      local word_pct = total > 0 and (word_count / total * 100) or 0
      table.insert(lines, string.format("%2d. **%s** - %d times (%.2f%%)", i, word, word_count, word_pct))
    end
```

Then find the second occurrence around line 640 in the same function (inside the overused-words loop):

```lua
    -- Check for overused words (> 1%)
    local overused = {}
    for _, item in ipairs(vocabulary.most_frequent) do
      local word = item.word or item[1]
      local word_count = item.count or item[2]
      local word_pct = (word_count / total) * 100
      if word_pct > 1.0 then
        table.insert(overused, { word = word, count = word_count, pct = word_pct })
      end
    end
```

Replace with:

```lua
    -- Check for overused words (> 1%)
    local overused = {}
    for _, item in ipairs(vocabulary.most_frequent) do
      local word = item.word or item[1]
      local word_count = item.count or item[2]
      -- Same div-by-zero guard as above.
      local word_pct = total > 0 and (word_count / total * 100) or 0
      if word_pct > 1.0 then
        table.insert(overused, { word = word, count = word_count, pct = word_pct })
      end
    end
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/display_spec.lua 2>&1 | tail -10
```

Expected: the new test passes.

- [ ] **Step 5: Run the full suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: total pass count up by 1; failure count unchanged.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/display.lua tests/display_spec.lua
git commit -m "fix(display): guard vocabulary div-by-zero (no more nan%)

format_vocabulary_section computed word_count / total without
guarding total > 0, producing nan% or inf% in the rendered report
when the upstream basic.total_words is zero (empty buffer edge
case). Both call sites now short-circuit to 0% when total is 0."
```

---

## Task 3: Fix #14 — Decouple section navigation from emoji glyphs

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua` — add `M.SECTIONS` table and `M.section_heading()` helper near the top; update 8 `format_*_section` functions to call the helper; rewrite `setup_report_keymaps`.
- Test: extend `~/projects/nvim-writing-metrics/tests/display_spec.lua` (created in Task 2) with new `describe` block.

**Background:** Section-jump keymaps in `setup_report_keymaps` are bound to search commands like `/^## 📊<CR>` — the emoji glyphs are hardcoded. If a heading's icon is ever swapped, renamed, or removed, the keymap silently breaks. The fix introduces a single `M.SECTIONS` table with `{ name, key, icon, title }` entries and derives both the rendered headings and the keymaps from it.

The 8 sections, with their current (key, icon, title) bindings, are:

| Key | Icon | Title | Formatter |
|---|---|---|---|
| 1 | 📊 | Basic Statistics | `format_basic_section` |
| 2 | 📖 | Readability Scores | `format_readability_section` |
| 3 | 📝 | Sentence Length Variety | `format_sentence_variety_section` |
| 4 | 🎯 | Sentence Beginning Variety | (inside `format_sentence_variety_section` at line 425) |
| 5 | 🔍 | Passive Voice Analysis | `format_passive_voice_section` |
| 6 | 📐 | Nominalization Analysis | (inside another formatter at line 544) |
| 7 | 📚 | Vocabulary Richness | `format_vocabulary_section` |
| 8 | 🤖 | AI-Style Detection | `format_ai_style_section` |

(Note: "Sentence Beginning Variety" and "Nominalization Analysis" are emitted inside larger formatters at the line numbers shown above, not in dedicated `format_*` functions. The fix still routes their headings through `section_heading()` to keep them coupled to the keymap table.)

- [ ] **Step 1: Write the failing tests**

Append this `describe` block to `~/projects/nvim-writing-metrics/tests/display_spec.lua` (created in Task 2), inside the outer `describe("writing-metrics.display", function() ... end)`:

```lua
  describe("section navigation data", function()
    it("M.SECTIONS has 8 entries with unique keys, icons, and names", function()
      assert.is_table(display.SECTIONS)
      assert.equals(8, #display.SECTIONS)

      local keys, icons, names = {}, {}, {}
      for _, s in ipairs(display.SECTIONS) do
        assert.is_string(s.key, "section needs string key")
        assert.is_string(s.icon, "section needs string icon")
        assert.is_string(s.name, "section needs string name")
        assert.is_string(s.title, "section needs string title")
        assert.is_nil(keys[s.key], "duplicate key: " .. s.key)
        assert.is_nil(icons[s.icon], "duplicate icon: " .. s.icon)
        assert.is_nil(names[s.name], "duplicate name: " .. s.name)
        keys[s.key], icons[s.icon], names[s.name] = true, true, true
      end
    end)

    it("section_heading returns '## <icon> <title>' that matches the keymap pattern", function()
      for _, s in ipairs(display.SECTIONS) do
        local heading = display.section_heading(s.name)
        assert.equals("## " .. s.icon .. " " .. s.title, heading,
          "section_heading(" .. s.name .. ") should produce expected line")
        -- The keymap is /^## <icon><CR>. Verify the heading line matches.
        assert.is_truthy(heading:find("^## " .. s.icon, 1, false),
          "heading should match navigation pattern for key " .. s.key)
      end
    end)

    it("section_heading errors on unknown name", function()
      assert.has.errors(function()
        display.section_heading("nonexistent_section")
      end)
    end)
  end)
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/display_spec.lua 2>&1 | tail -15
```

Expected: all three new tests fail with `attempt to index field 'SECTIONS' (a nil value)` (or similar — `M.SECTIONS` and `M.section_heading` don't exist yet).

- [ ] **Step 3: Add the `M.SECTIONS` table and `M.section_heading` helper**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua`, find the top of the file (after `local M = {}` and any other module-level locals, before the first `function M.foo`). Add:

```lua
--- Section metadata: single source of truth for both the rendered
--- report headings and the section-jump keymaps. Keep these in
--- 1:1 correspondence so the keymap regex (/^## <icon><CR>) always
--- matches the heading emitted by the formatter for that section.
--- @type table<integer, { name: string, key: string, icon: string, title: string }>
M.SECTIONS = {
  { name = "basic",            key = "1", icon = "📊", title = "Basic Statistics" },
  { name = "readability",      key = "2", icon = "📖", title = "Readability Scores" },
  { name = "length",           key = "3", icon = "📝", title = "Sentence Length Variety" },
  { name = "beginnings",       key = "4", icon = "🎯", title = "Sentence Beginning Variety" },
  { name = "passive",          key = "5", icon = "🔍", title = "Passive Voice Analysis" },
  { name = "nominalizations",  key = "6", icon = "📐", title = "Nominalization Analysis" },
  { name = "vocabulary",       key = "7", icon = "📚", title = "Vocabulary Richness" },
  { name = "ai_style",         key = "8", icon = "🤖", title = "AI-Style Detection" },
}

-- Build name -> section lookup for fast access by section_heading().
local _sections_by_name = {}
for _, s in ipairs(M.SECTIONS) do
  _sections_by_name[s.name] = s
end

--- Build the markdown heading line for a named section.
--- The returned string is what the formatters emit AND what the
--- navigation keymaps search for, so both stay coupled to M.SECTIONS.
--- @param name string Section name (see M.SECTIONS entries)
--- @return string "## <icon> <title>"
function M.section_heading(name)
  local section = _sections_by_name[name]
  if not section then
    error("Unknown section name: " .. tostring(name))
  end
  return string.format("## %s %s", section.icon, section.title)
end
```

- [ ] **Step 4: Run the data-table tests and verify they pass**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/display_spec.lua 2>&1 | tail -10
```

Expected: the three section-navigation tests now pass (plus the Task 2 vocabulary test).

- [ ] **Step 5: Replace hardcoded headings in formatters with `M.section_heading()` calls**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua`, make 8 single-line changes. For each, the change is identical in shape: `table.insert(lines, "## <icon> <title>")` → `table.insert(lines, M.section_heading("<name>"))`.

**5a.** Around line 173 (inside `format_basic_section`):

```lua
  table.insert(lines, "## 📊 Basic Statistics")
```

→

```lua
  table.insert(lines, M.section_heading("basic"))
```

**5b.** Around line 224 (inside `format_readability_section`):

```lua
  table.insert(lines, "## 📖 Readability Scores")
```

→

```lua
  table.insert(lines, M.section_heading("readability"))
```

**5c.** Around line 302 (inside `format_sentence_variety_section`):

```lua
  table.insert(lines, "## 📝 Sentence Length Variety")
```

→

```lua
  table.insert(lines, M.section_heading("length"))
```

**5d.** Around line 425 (also inside `format_sentence_variety_section`, second heading):

```lua
  table.insert(lines, "## 🎯 Sentence Beginning Variety")
```

→

```lua
  table.insert(lines, M.section_heading("beginnings"))
```

**5e.** Around line 507 (inside `format_passive_voice_section`):

```lua
  table.insert(lines, "## 🔍 Passive Voice Analysis")
```

→

```lua
  table.insert(lines, M.section_heading("passive"))
```

**5f.** Around line 544 (inside the nominalizations formatter):

```lua
  table.insert(lines, "## 📐 Nominalization Analysis")
```

→

```lua
  table.insert(lines, M.section_heading("nominalizations"))
```

**5g.** Around line 601 (inside `format_vocabulary_section`):

```lua
  table.insert(lines, "## 📚 Vocabulary Richness")
```

→

```lua
  table.insert(lines, M.section_heading("vocabulary"))
```

**5h.** Around line 670 (inside `format_ai_style_section`):

```lua
  table.insert(lines, "## 🤖 AI-Style Detection")
```

→

```lua
  table.insert(lines, M.section_heading("ai_style"))
```

- [ ] **Step 6: Rewrite `setup_report_keymaps` to derive from `M.SECTIONS`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua` around lines 790-807, find:

```lua
--- Setup keymaps for navigating the report
--- @param bufnr number Buffer number
function M.setup_report_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true, nowait = true }

  -- Close report
  vim.keymap.set("n", "q", "<cmd>close<cr>", opts)
  -- <Esc> intentionally NOT mapped: users press it reflexively for unrelated
  -- reasons (clearing search highlight, breaking out of pending ops). Use q.

  -- Jump to sections
  vim.keymap.set("n", "1", "/^## 📊<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "2", "/^## 📖<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "3", "/^## 📝<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "4", "/^## 🎯<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "5", "/^## 🔍<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "6", "/^## 📐<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "7", "/^## 📚<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "8", "/^## 🤖<CR>:nohlsearch<CR>", opts)
end
```

Replace with:

```lua
--- Setup keymaps for navigating the report
--- Section-jump keymaps are derived from M.SECTIONS so icon/key
--- changes in one place automatically propagate to the other.
--- @param bufnr number Buffer number
function M.setup_report_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true, nowait = true }

  -- Close report
  vim.keymap.set("n", "q", "<cmd>close<cr>", opts)
  -- <Esc> intentionally NOT mapped: users press it reflexively for unrelated
  -- reasons (clearing search highlight, breaking out of pending ops). Use q.

  -- Jump to sections (derived from M.SECTIONS)
  for _, section in ipairs(M.SECTIONS) do
    local cmd = string.format("/^## %s<CR>:nohlsearch<CR>", section.icon)
    vim.keymap.set("n", section.key, cmd, opts)
  end
end
```

- [ ] **Step 7: Run the full suite and verify everything still passes**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: total pass count up by all tests added in Task 1, 2, and 3 so far. Failure count unchanged from baseline.

Also do a manual smoke check that the headings still render correctly:

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "lua local d = require('writing-metrics.display'); print(d.section_heading('basic'))" -c "qa!" 2>&1 | tail -3
```

Expected output line: `## 📊 Basic Statistics`

- [ ] **Step 8: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/display.lua tests/display_spec.lua
git commit -m "refactor(display): drive section nav keymaps from M.SECTIONS table

Headings emitted by format_*_section functions and the section-jump
keymaps in setup_report_keymaps now both derive from a single
M.SECTIONS table. Previously an icon change in one place could
silently break navigation, since the keymap regex hardcoded the
glyph. Adds section_heading() helper and tests for SECTIONS
self-consistency (unique keys/icons/names) and helper output."
```

---

## Task 4: Fix #2 — Delete unused `get_content_hash` function

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua:377-442` (delete function + manual-test comment)
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua:133` (drop historical reference)

**Background:** `M.get_content_hash` was the cache's original change-detection mechanism. It was replaced by `vim.b[bufnr].changedtick` in commit `6b468dc`. No live caller invokes it (only the function definition and historical mentions in comments remain). No test exercises it. Removing it is a pure delete.

- [ ] **Step 1: Verify no live callers exist**

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "get_content_hash" --include="*.lua" --include="*.md"
```

Expected: matches only at the function definition (`utils.lua:380`), the manual-testing comment (`utils.lua:442`), and a historical reference in `cache.lua:133` (a comment explaining changedtick replaces it). No code that calls the function as a function. If anything else shows up, STOP and investigate — there may be a consumer the audit missed.

- [ ] **Step 2: Delete the function and its manual-test comment**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua`, find the function around lines 377-392:

```lua
--- Generate a simple hash of buffer content for cache invalidation
--- @param bufnr number|nil Buffer number
--- @return string Content hash
function M.get_content_hash(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local content = M.get_buffer_content(bufnr)

  -- Simple hash using string length and first/last chars
  -- Good enough for cache invalidation without crypto overhead
  local len = #content
  local first = content:sub(1, 100)
  local last = content:sub(-100)

  return string.format("%d:%s:%s", len, first, last)
end
```

Delete the whole block (~16 lines including the docstring).

Then find the manual-test comment around line 442 (likely near the bottom of utils.lua):

```lua
-- :lua local hash = require("writing-metrics.utils").get_content_hash(0); print(hash)
```

Delete that single line.

- [ ] **Step 3: Update the historical reference in cache.lua**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua` around lines 131-136 (the docstring on `M.content_changed`):

```lua
--- Check if content has changed since last cache
--- Uses vim.b[bufnr].changedtick — a free, monotonically-increasing per-buffer
--- integer maintained by Neovim. Avoids expensive get_content_hash calls on
--- every TextChangedI (which fires on every keystroke in insert mode).
--- @param bufnr number Buffer number
--- @return boolean True if content changed
```

Replace with:

```lua
--- Check if content has changed since last cache
--- Uses vim.b[bufnr].changedtick — a free, monotonically-increasing per-buffer
--- integer maintained by Neovim. Cheap enough to call on every TextChangedI
--- (fires on every keystroke in insert mode).
--- @param bufnr number Buffer number
--- @return boolean True if content changed
```

(Removes the historical reference to `get_content_hash` now that the function is gone.)

- [ ] **Step 4: Run the full suite to confirm no tests depended on the function**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: pass/fail counts unchanged from after Task 3.

- [ ] **Step 5: Verify nothing else references the deleted function**

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "get_content_hash" --include="*.lua" --include="*.md"
```

Expected: no matches at all. (The DESIGN_INNOVATIONS.md still has historical references — those get rewritten in Task 6 and are acceptable until then.)

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/utils.lua lua/writing-metrics/cache.lua
git commit -m "chore(utils): remove dead get_content_hash function

Replaced by vim.b[bufnr].changedtick in commit 6b468dc. No live
callers anywhere in the codebase. Also drops the historical
reference in cache.content_changed's docstring."
```

---

## Task 5: Fix #11 — Delete `cache.is_valid` and `basic_ttl` dead code

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua:24-35, 110-129`
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua:6-11`
- Modify: `~/projects/nvim-writing-metrics/plugin/writing-metrics.lua:92-95`
- Modify: `~/projects/nvim-writing-metrics/tests/config_spec.lua:35-97`
- Modify: `~/projects/nvim-writing-metrics/tests/compatibility_spec.lua:188-213`
- Modify: `~/projects/nvim-writing-metrics/README.md:185-190` (config example)
- Modify: `~/projects/nvim-writing-metrics/CHANGELOG.md` (document removal)

**Background:** The cache stopped using TTL-based validation (replaced by changedtick). `cache.is_valid()` has no callers and `basic_ttl` in the defaults has no consumers. Removing them tidies the config surface and unblocks Task 6's doc rewrite. Some test files reference both `basic_ttl` AND a `full_ttl` that no longer exists — those tests are part of the pre-existing failure cluster and need to be removed (not updated) since the keys they assert about are going away.

- [ ] **Step 1: Verify no live callers of `cache.is_valid`**

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "is_valid" --include="*.lua" | grep -v "nvim_buf_is_valid\|nvim_win_is_valid\|--\s\|^\s*--" | head -20
```

Expected: only the function definition itself in `cache.lua` matches (after filtering out the `nvim_buf_is_valid` API calls and comment lines). If any call site shows up, STOP and investigate.

- [ ] **Step 2: Delete `cache.is_valid` and remove `ttl` from `get_statistics`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua`, find around lines 24-35:

```lua
--- Check if a cache entry is still valid
--- @param entry CacheEntry|nil Cache entry
--- @param ttl number Time-to-live in milliseconds
--- @return boolean
function M.is_valid(entry, ttl)
  if not entry then
    return false
  end

  local age = now() - entry.timestamp
  return age < ttl
end
```

Delete this entire 12-line block.

Then in the same file, find `M.get_statistics` around lines 108-129:

```lua
--- Get comprehensive cache statistics
--- @return table Statistics including cache size and memory usage
function M.get_statistics()
  local config = require("writing-metrics.config")
  local basic_count = 0
  local basic_memory = 0

  -- Count entries and estimate memory
  for _, entry in pairs(cache.basic) do
    basic_count = basic_count + 1
    -- Rough memory estimate: changedtick (8 bytes) + timestamp (8 bytes) + data (estimate 200 bytes)
    basic_memory = basic_memory + 240
  end

  return {
    basic = {
      count = basic_count,
      memory = basic_memory,
      ttl = config.config.cache.basic_ttl,
    },
  }
end
```

Replace with:

```lua
--- Get comprehensive cache statistics
--- @return table Statistics including cache size and memory usage
function M.get_statistics()
  local basic_count = 0
  local basic_memory = 0

  -- Count entries and estimate memory
  for _, entry in pairs(cache.basic) do
    basic_count = basic_count + 1
    -- Rough memory estimate: changedtick (8 bytes) + timestamp (8 bytes) + data (estimate 200 bytes)
    basic_memory = basic_memory + 240
  end

  return {
    basic = {
      count = basic_count,
      memory = basic_memory,
    },
  }
end
```

(Removes the `require("writing-metrics.config")` line and the `ttl = ...` field.)

- [ ] **Step 3: Remove the `cache` block from defaults**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua` around lines 6-11:

```lua
M.defaults = {
  -- Cache settings (single-tier for statusline only)
  cache = {
    basic_ttl = 500, -- 500ms for responsive statusline
    -- Reports always compute fresh (no cache)
  },

  -- Feature toggles
```

Replace with:

```lua
M.defaults = {
  -- Feature toggles
```

(Deletes the entire `cache = { ... }` block — 6 lines including the comment.)

- [ ] **Step 4: Update the `:WritingMetrics` status display**

In `~/projects/nvim-writing-metrics/plugin/writing-metrics.lua` around lines 90-96:

```lua
      "## Configuration",
      "",
      "**Cache strategy:**",
      "- Statusline: Basic metrics cached for " .. config.config.cache.basic_ttl .. "ms",
      "- Reports: Always compute fresh (no cache)",
      "",
      "**Enabled features:**",
```

Replace with:

```lua
      "## Configuration",
      "",
      "**Cache strategy:**",
      "- Statusline: Basic metrics cached until buffer content changes (changedtick)",
      "- Reports: Always compute fresh (no cache)",
      "",
      "**Enabled features:**",
```

- [ ] **Step 5: Update tests that referenced `basic_ttl` / `full_ttl`**

In `~/projects/nvim-writing-metrics/tests/config_spec.lua` around lines 40-52, find:

```lua
    it("has reasonable cache TTL values", function()
      local defaults = config.get()

      assert.is_number(defaults.cache.basic_ttl)
      assert.is_number(defaults.cache.full_ttl)

      -- Basic should be shorter than full
      assert.is_true(defaults.cache.basic_ttl <= defaults.cache.full_ttl)

      -- Should be in milliseconds (reasonable range)
      assert.is_true(defaults.cache.basic_ttl >= 100)
      assert.is_true(defaults.cache.basic_ttl <= 10000)
    end)
```

Delete this entire `it(...)` block.

Then around line 33-36 (the test that asserts `defaults.cache` is a table):

```lua
      assert.is_table(defaults.cache)
      assert.is_table(defaults.filter)
      assert.is_table(defaults.commands)
```

Remove just the `defaults.cache` assertion:

```lua
      assert.is_table(defaults.filter)
      assert.is_table(defaults.commands)
```

Then around lines 68-97 (the two `it("merges user options..."` and `it("preserves nested options..."` tests that use `cache = { basic_ttl = ... }`):

```lua
    it("merges user options with defaults", function()
      config.setup({
        cache = {
          basic_ttl = 1000,
        },
      })

      local settings = config.get()

      assert.equals(1000, settings.cache.basic_ttl)
      -- Other defaults should still be present
      assert.is_number(settings.cache.full_ttl)
      assert.is_table(settings.filter)
    end)

    it("preserves nested options not overridden", function()
      config.setup({
        cache = {
          basic_ttl = 999,
        },
      })

      local settings = config.get()

      -- Modified value
      assert.equals(999, settings.cache.basic_ttl)
      -- Unmodified nested value
      assert.is_number(settings.cache.full_ttl)
    end)
```

Delete both of these `it(...)` blocks entirely. (They test merging behavior that's covered by the remaining "allows disabling legacy commands" test, which uses the still-extant `commands` block.)

In `~/projects/nvim-writing-metrics/tests/compatibility_spec.lua` around lines 188-213:

```lua
  describe("configuration compatibility", function()
    it("accepts old-style configuration", function()
      local success = pcall(metrics.setup, {
        cache = {
          basic_ttl = 500,
          full_ttl = 30000,
        },
      })

      assert.is_true(success)
    end)

    it("merges user config with defaults", function()
      metrics.setup({
        cache = {
          basic_ttl = 999,
        },
      })

      local config = require("writing-metrics.config")
      local settings = config.get()

      assert.equals(999, settings.cache.basic_ttl)
      assert.is_number(settings.cache.full_ttl)
    end)
  end)
```

Delete this entire `describe(...)` block (it only contains the two stale tests).

- [ ] **Step 6: Update the README config example**

In `~/projects/nvim-writing-metrics/README.md` around lines 184-190, find:

```lua
require("writing-metrics").setup({
  filetypes = { "markdown", "text", "tex", "fountain" },
  cache = {
    basic_ttl = 500,  -- Cache duration for statusline (ms)
  },
  display = {
    report_window = "tab",  -- "tab", "split", or "vsplit"
  },
```

Replace with:

```lua
require("writing-metrics").setup({
  filetypes = { "markdown", "text", "tex", "fountain" },
  display = {
    report_window = "tab",  -- "tab", "split", or "vsplit"
  },
```

(Removes the entire `cache = { basic_ttl = 500 }` block.)

- [ ] **Step 7: Add a CHANGELOG entry**

In `~/projects/nvim-writing-metrics/CHANGELOG.md`, find the `## [Unreleased]` section and the existing `### Added` subsection. After the `### Added` content, add a new `### Removed` subsection:

```markdown
### Removed
- `cache.basic_ttl` config option and `cache.is_valid()` function — both
  obsoleted by the changedtick-based cache validation introduced earlier.
  The `cache = {}` block can be removed from user setup() calls. Passing
  it is harmless (deep-merge ignores unknown keys), but the value has no
  effect since validation no longer uses TTL.
```

- [ ] **Step 8: Run the full suite and confirm no regressions beyond the deleted-tests cleanup**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -15
```

Expected: total test counts drop by the number of deleted tests (1 in config_spec.lua's "has reasonable cache TTL values"; 2 in config_spec.lua's user-config tests; 2 in compatibility_spec.lua's configuration-compatibility block = **5 deleted**). Failure count should ALSO drop because some of these deleted tests were among the pre-existing failures (the `full_ttl` assertions errored on `nil <= number`).

If the failure count goes up unexpectedly (e.g., another test relies on `defaults.cache` being a table), investigate the new failure and either restore the minimal `cache = {}` block in defaults or update the dependent test.

- [ ] **Step 9: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/cache.lua lua/writing-metrics/config.lua plugin/writing-metrics.lua tests/config_spec.lua tests/compatibility_spec.lua README.md CHANGELOG.md
git commit -m "chore(cache): remove dead is_valid + basic_ttl config knob

The cache switched to changedtick-based validation; is_valid()
has no callers and basic_ttl has no consumers. Removes:
- cache.is_valid() function
- cache.basic_ttl default
- TTL field from cache.get_statistics() return value
- Five test assertions/blocks that reference basic_ttl or the
  long-defunct full_ttl key
- Reference to basic_ttl in :WritingMetrics help text and README
  config example

CHANGELOG documents the removal so users can drop cache = {}
from their setup() calls (harmless to keep — deep merge ignores
unknown keys — but no longer meaningful)."
```

---

## Task 6: Fix #9 — Rewrite `docs/DESIGN_INNOVATIONS.md`

**Files:**
- Modify: `~/projects/nvim-writing-metrics/docs/DESIGN_INNOVATIONS.md`

**Background:** The current doc claims a "Smart Cache Extraction" two-tier cache architecture (basic and full caches with extraction between them) that does not exist in the code. The actual cache is single-tier (basic only), changedtick-based, and reports always compute fresh. Section 2 also describes the old `get_content_hash` content-fingerprint approach that was replaced by changedtick. Sections 3-5 (auto-detection, lazy module loading, backward-compat shims) are still accurate.

Rewrite Sections 1 and 2 to match reality. Leave Sections 3-5 as-is unless they reference removed code.

- [ ] **Step 1: Verify Sections 3-5 are still accurate**

```bash
cd ~/projects/nvim-writing-metrics
sed -n '102,260p' docs/DESIGN_INNOVATIONS.md
```

Expected: Section 3 ("Auto-Detection via Introspection") references `find_filter()` and `get_plugin_dir()`. Section 4 ("Lazy Module Loading") describes the `get_config()` / `get_cache()` / `get_utils()` pattern. Section 5 ("Backward Compatibility Shims") references `_G.text_metrics` and `_G.accurate_wordcount`. Confirm each by spot-checking:

```bash
cd ~/projects/nvim-writing-metrics
grep -n "find_filter\|get_plugin_dir\|get_config\|get_cache\|_G.text_metrics\|_G.accurate_wordcount" lua/writing-metrics/init.lua lua/writing-metrics/config.lua | head -10
```

Expected: all referenced symbols exist. If anything is missing, note it for additional rewrites.

- [ ] **Step 2: Replace Sections 1 and 2**

In `~/projects/nvim-writing-metrics/docs/DESIGN_INNOVATIONS.md`, find the start of "## 1. Smart Cache Extraction" (line ~5) and the end of "## 2. Content-Based Cache Invalidation" (just before "## 3. Auto-Detection via Introspection" around line ~102). Replace everything between (inclusive of both section 1 and section 2, exclusive of section 3) with:

```markdown
## 1. Single-Tier Changedtick Cache

**Problem:** The statusline word count is asked for on every redraw, but the buffer rarely changes between most redraws (cursor moves, mode changes, window resizes). Recomputing word/char counts via Pandoc for each call would be wasteful — Pandoc startup alone costs ~150 ms.

**Solution:** A single per-buffer cache keyed by buffer number, validated against Neovim's built-in `vim.b[bufnr].changedtick`.

```lua
function M.set_basic(bufnr, data)
  local tick = vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].changedtick or -1
  cache.basic[bufnr] = {
    changedtick = tick,
    timestamp = now(),
    data = data,
    stale = false,
  }
end

function M.content_changed(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return true
  end
  local tick = vim.b[bufnr].changedtick
  local entry = cache.basic[bufnr]
  return not entry or entry.changedtick ~= tick
end
```

**Why changedtick is the right primitive:**

- Neovim maintains `b:changedtick` automatically — it increments on every buffer modification (edit, undo, redo, paste).
- Reading it is O(1) and allocation-free.
- It does not change on cursor movement, mode changes, or window operations — exactly the events that would force unnecessary recomputation under a naive autocmd-based scheme.
- Comparing two integers is faster than hashing buffer content; for a 50,000-word document this is the difference between sub-microsecond cache validation and milliseconds of hashing per statusline redraw.

**What's NOT cached:**

Full readability reports always compute fresh (see `full.get_full_metrics`). Reports are infrequent (user-triggered via `<leader>mr`) and benefit more from up-to-date output than from cached staleness. The cache only stores basic metrics for the statusline.

## 2. Async Pandoc Execution

**Problem:** Pandoc invocations take 100-500 ms depending on document size. Blocking the editor for that long on every word-count refresh would be unacceptable.

**Solution:** All Pandoc calls go through `utils.run_pandoc()`, which uses `vim.system()` with an async callback and wraps the callback in `vim.schedule()` so it's safe to call Vimscript functions from the result.

```lua
function M.run_pandoc(input_file, mode, callback)
  local config = require("writing-metrics.config")
  local filter_path = config.get_filter_path()
  if not filter_path then
    M.cleanup_temp_file(input_file)
    callback(false, "Pandoc filter not found")
    return
  end

  local cmd = { "pandoc", input_file, "--lua-filter", filter_path,
                "-t", "plain", "--metadata", "metrics_mode=" .. mode }

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(false, "Pandoc failed: " .. (result.stderr or "unknown error"))
        return
      end
      callback(true, result.stdout)
    end)
  end)
end
```

**Why this matters:**

- The statusline can request an accurate count and continue rendering without waiting. The result arrives asynchronously and the statusline updates on the next redraw via the cache.
- `vim.schedule()` is essential: callbacks from `vim.system` may run in a "fast event context" where most Vimscript functions error out. Scheduling defers the callback to the next event-loop tick where it's safe.
- Temp file cleanup happens inside the callback so the file lives long enough for Pandoc to read it. An early-return path (filter missing) also cleans up to avoid leaks.
```

(After the replacement, "## 3. Auto-Detection via Introspection" should immediately follow at the next line.)

- [ ] **Step 3: Verify the doc reads correctly end to end**

```bash
cd ~/projects/nvim-writing-metrics
head -120 docs/DESIGN_INNOVATIONS.md
```

Expected: the new Sections 1 and 2 flow cleanly into Section 3, with no leftover content from the old smart-extraction discussion. The "## 1." and "## 2." headings should appear once each.

```bash
cd ~/projects/nvim-writing-metrics
grep -c "^## " docs/DESIGN_INNOVATIONS.md
```

Expected: 5 (sections 1-5; the file should still have all five top-level sections).

- [ ] **Step 4: Confirm no remaining mentions of the obsolete cache architecture**

```bash
cd ~/projects/nvim-writing-metrics
grep -in "smart cache\|smart extraction\|two-tier\|cache.full\|extract_basic_from_full\|97% reduction\|80% reduction" docs/DESIGN_INNOVATIONS.md
```

Expected: no matches. Any remaining hit means the rewrite left stale claims.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add docs/DESIGN_INNOVATIONS.md
git commit -m "docs: rewrite DESIGN_INNOVATIONS cache sections to match reality

Sections 1 (Smart Cache Extraction) and 2 (Content-Based Cache
Invalidation) described a two-tier cache and content-hash
mechanism that no longer exist. Cache.lua is single-tier and
changedtick-driven; reports always compute fresh. Rewrites both
sections to describe what's actually in the code:
- Single-tier changedtick cache (replaces 'Smart Cache Extraction')
- Async Pandoc execution (replaces 'Content-Based Cache
  Invalidation', which was really about hashing)

Sections 3-5 (Auto-Detection, Lazy Module Loading, Backward
Compatibility Shims) are still accurate and left as-is."
```

---

## Final verification

After all six tasks land, run the full suite one last time:

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

**Expected pass count change from baseline (post-Plan A):** +4 net (1 init_spec + 1 vocabulary + 3 section-nav = 5 new; −5 deleted = net 0 in COUNT, but conceptually +5 new tests minus 5 stale tests that referenced removed config keys, with possible failure-count drop where the deleted tests were among the failures).

More usefully, the expected outcome is:
- `init_spec.lua` new: 1 pass / 0 fail
- `display_spec.lua` new: 4 pass / 0 fail (1 vocabulary + 3 section-nav)
- `config_spec.lua`: pass count down by 3, failure count down by 1+ (the `full_ttl` assertion test was erroring)
- `compatibility_spec.lua`: pass count down by 2, failure count down by some
- All other spec files: unchanged

The net failure-count change should be ≤ 0 (no new failures; possibly some pre-existing failures resolved by deleting the stale tests).

Commit log review:

```bash
cd ~/projects/nvim-writing-metrics
git log --oneline b6c87c4..HEAD
```

Expected: 6 commits, mix of `fix(...)`, `refactor(...)`, `chore(...)`, and `docs:` prefixes.

---

## Summary

6 tasks. 6 commits land on `main` of `~/projects/nvim-writing-metrics/`. 5 new tests added (1 in a new `tests/init_spec.lua`, 1 + 3 in a new `tests/display_spec.lua`); 5 stale tests deleted from `tests/config_spec.lua` and `tests/compatibility_spec.lua`. Estimated 1.5-2 hours of focused work.

After completion:
- `:Lazy reload` no longer leaks stale report-buffer tracking state (#13).
- The readability report won't produce "nan%" / "inf%" on empty-buffer edge cases (#15-display).
- Section navigation in the report buffer is decoupled from emoji glyphs — changing an icon updates both the heading and the keymap atomically (#14).
- `utils.get_content_hash` is gone (#2).
- `cache.is_valid` and `basic_ttl` are gone, with tests and docs updated (#11).
- `docs/DESIGN_INNOVATIONS.md` Sections 1-2 now describe the actual single-tier changedtick cache and async Pandoc plumbing (#9).
