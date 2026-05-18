# Reading Time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reading-time estimation to `nvim-writing-metrics` (with silent + spoken WPM profiles), surface it in three places (statusline, full report, dedicated keymap toast), then remove the orphaned `nvim-prose` plugin.

**Architecture:** Reading time is a pure derivation of word count (`math.ceil(words / wpm)`). Two functions in `basic.lua`: `get_reading_time(bufnr)` reads cached words and returns formatted strings; `show_reading_time()` pops a toast. The full report's `format_basic_section` appends two table rows. The statusline string composer `get_statusline_string` appends a small suffix. Reading time is never cached separately — recomputed from cached words.

**Tech Stack:** Lua 5.1 (LuaJIT in Neovim), plenary.busted for tests, lazy.nvim plugin spec.

---

## Conventions

- **Plugin repo:** `~/projects/nvim-writing-metrics/` — git-tracked. All writing-metrics commits land on `main` directly (the previous Tier 1/2 branch was already merged).
- **Config repo:** `~/.config/nvim/` — **NOT git-tracked**; edits go in directly without commits.
- **Run tests:** `cd ~/projects/nvim-writing-metrics && ./run-tests.sh -t tests/basic_spec.lua` for one spec; no args for all.
- **Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-16-reading-time-design.md`

Spec-relevant facts the implementer should know going in:
- `cache.get_basic(bufnr)` returns `(data, is_stale)` where `data` is a table with fields `.words`, `.chars`, `.sentences`, `.paragraphs`.
- `basic.get_accurate_count(bufnr, callback)` calls `callback(result, method)` where `result` is the metrics table (or nil on error) and `method` is `"pandoc" | "cached" | "fallback" | "error"`.
- `basic.get_statusline_string(bufnr)` returns either `""` (filetype not enabled) or `{ text = "...", color = "green"|"orange" }`. **Has 4 return paths** (visual selection, fast mode, accurate-cached, no-cache-fallback) — all need the reading-time suffix appended.
- Config defaults live in `M.defaults` (file: `config.lua`); merged user config is exposed at `require("writing-metrics.config").config`.

---

## Task 1: Add reading_time config defaults

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua` — add block inside `M.defaults`

- [ ] **Step 1: Read the existing defaults structure**

Read `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua` lines 1-80 to find the `M.defaults` table and identify a good insertion point (likely after the `targets` block or alongside `display`).

- [ ] **Step 2: Insert the reading_time block**

Add this block as a new top-level key inside `M.defaults`:

```lua
  -- Reading time estimation
  reading_time = {
    enabled = true,                 -- compute reading time at all
    wpm_silent = 200,               -- average silent reading speed
    wpm_spoken = 150,               -- presentation / spoken delivery rate
    statusline = true,              -- show in statusline
    statusline_profile = "silent",  -- "silent" | "spoken" | "both"
  },
```

Place it after the `targets` block (or wherever makes the structure feel cohesive — alongside `display` and `features` is also fine).

- [ ] **Step 3: Verify the file still parses**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/config.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output (Lua loaded successfully).

- [ ] **Step 4: Verify config merges correctly**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "lua local c = require('writing-metrics.config'); c.setup({}); print(vim.inspect(c.config.reading_time))" -c "qa!" 2>&1 | head -10
```

Expected output includes:
```
{
  enabled = true,
  statusline = true,
  statusline_profile = "silent",
  wpm_silent = 200,
  wpm_spoken = 150
}
```

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/config.lua
git commit -m "feat(config): add reading_time defaults block

Silent (200 wpm) + spoken (150 wpm) profiles; statusline toggle and
profile selector. Used by upcoming get_reading_time API."
```

---

## Task 2: Add get_reading_time API with TDD tests

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua` — add `M.get_reading_time` function
- Test: `~/projects/nvim-writing-metrics/tests/basic_spec.lua` — add new describe block

- [ ] **Step 1: Write failing tests in basic_spec.lua**

Inside the existing `describe("writing-metrics.basic", function() ... end)` block, add:

```lua
  describe("get_reading_time", function()
    it("computes minutes from cached word count using configured WPM", function()
      -- Buffer with arbitrary content; cache is populated directly with known count.
      local bufnr = helpers.create_test_buffer("placeholder")
      cache.set_basic(bufnr, { words = 400, chars = 1500, sentences = 20, paragraphs = 4 })

      -- 400 / 200 = 2.0 → ceil = 2 silent minutes
      -- 400 / 150 = 2.667 → ceil = 3 spoken minutes
      local result = basic.get_reading_time(bufnr)

      assert.is_not_nil(result)
      assert.equals(2, result.silent_minutes)
      assert.equals(3, result.spoken_minutes)
      assert.equals("~2 min", result.silent)
      assert.equals("~3 min", result.spoken)
    end)

    it("returns nil when reading_time.enabled is false", function()
      local config = require("writing-metrics.config")
      local saved = vim.deepcopy(config.config.reading_time or {})
      config.config.reading_time = vim.tbl_extend("force", saved, { enabled = false })

      local bufnr = helpers.create_test_buffer("placeholder")
      cache.set_basic(bufnr, { words = 400, chars = 1500, sentences = 20, paragraphs = 4 })

      local result = basic.get_reading_time(bufnr)
      assert.is_nil(result)

      -- Restore config so subsequent tests aren't affected
      config.config.reading_time = saved
    end)

    it("returns nil when buffer has no cached word count", function()
      local bufnr = helpers.create_test_buffer("placeholder")
      cache.clear_all()

      local result = basic.get_reading_time(bufnr)
      assert.is_nil(result)
    end)
  end)
```

- [ ] **Step 2: Run tests, expect failure**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/basic_spec.lua
```

Expected: the three new tests fail with `attempt to call field 'get_reading_time' (a nil value)` (function does not exist yet).

- [ ] **Step 3: Add get_reading_time function**

Edit `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua`. Find a sensible insertion point near the other public API functions (after `M.get_accurate_count` is a good spot). Add:

```lua
--- Compute reading time for a buffer.
--- Reads cached word count; returns nil if reading_time is disabled or no
--- cached count exists. Returned strings are pre-formatted ("~5 min").
--- @param bufnr integer Buffer to compute for (0 or nil = current buffer)
--- @return table|nil { silent_minutes, spoken_minutes, silent, spoken }
function M.get_reading_time(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr

  local config = require("writing-metrics.config").config.reading_time
  if not config or not config.enabled then
    return nil
  end

  local wpm_silent = config.wpm_silent or 200
  local wpm_spoken = config.wpm_spoken or 150
  if wpm_silent <= 0 or wpm_spoken <= 0 then
    return nil
  end

  local cache = require("writing-metrics.cache")
  local cached, _is_stale = cache.get_basic(bufnr)
  if not cached or not cached.words or cached.words <= 0 then
    return nil
  end

  local silent_min = math.ceil(cached.words / wpm_silent)
  local spoken_min = math.ceil(cached.words / wpm_spoken)

  return {
    silent_minutes = silent_min,
    spoken_minutes = spoken_min,
    silent = string.format("~%d min", silent_min),
    spoken = string.format("~%d min", spoken_min),
  }
end
```

Also export the function in the module's export block (search for `get_accurate_count = M.get_accurate_count` to find it):

```lua
-- Add to the export table:
get_reading_time = M.get_reading_time,
```

- [ ] **Step 4: Run tests, expect pass**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/basic_spec.lua
```

Expected: the three new tests pass. Pre-existing test counts in basic_spec.lua should remain unchanged (i.e., new tests add to the success count without breaking any).

If a test fails because `cache.get_basic` returns wrapped data (e.g., `cached.data.words` instead of `cached.words`), inspect `cache.lua`'s `get_basic` function and adjust the access pattern in `get_reading_time` to match. The test fixture writes `cache.set_basic(bufnr, { words = 400, ... })` so whatever shape `set_basic` stores, `get_basic` must round-trip.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/basic.lua tests/basic_spec.lua
git commit -m "feat(basic): add get_reading_time API

Pure derivation from cached word count: silent (200 wpm) and spoken
(150 wpm) minutes formatted as '~N min'. Returns nil when disabled,
no cached words, or invalid WPM."
```

---

## Task 3: Add show_reading_time function and :ReadingTime command

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua` — add `M.show_reading_time`
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` — register `:ReadingTime` user command

- [ ] **Step 1: Add show_reading_time to basic.lua**

In `basic.lua`, add this function near `M.get_reading_time` (just below it):

```lua
--- Show a vim.notify toast with both reading-time profiles.
--- Triggers an accurate word count via the standard pipeline; falls
--- back to vim.fn.wordcount() if the accurate path fails.
function M.show_reading_time()
  local config = require("writing-metrics.config").config.reading_time
  if not config or not config.enabled then
    vim.notify("Reading time is disabled in config (reading_time.enabled = false)", vim.log.levels.WARN)
    return
  end

  local utils = require("writing-metrics.utils")
  local bufnr = vim.api.nvim_get_current_buf()

  local function format_toast(words, prefix)
    local silent_min = math.ceil(words / config.wpm_silent)
    local spoken_min = math.ceil(words / config.wpm_spoken)
    return string.format(
      "%s~%d min silent · ~%d min spoken  (%s words at %d/%d wpm)",
      prefix or "",
      silent_min,
      spoken_min,
      utils.format_number(words),
      config.wpm_silent,
      config.wpm_spoken
    )
  end

  M.get_accurate_count(bufnr, function(result, _method)
    if result and result.words and result.words > 0 then
      vim.notify(format_toast(result.words), vim.log.levels.INFO)
      return
    end

    -- Fallback: raw fast count, marked clearly
    local wc = vim.fn.wordcount()
    local words = wc.words or 0
    if words > 0 then
      vim.notify(format_toast(words, "(fast) "), vim.log.levels.WARN)
    else
      vim.notify("No words to count in current buffer", vim.log.levels.WARN)
    end
  end)
end
```

Export it in the module export table alongside `get_reading_time`:

```lua
show_reading_time = M.show_reading_time,
```

- [ ] **Step 2: Register :ReadingTime command in init.lua**

Read `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` to find the existing command registrations (search for `nvim_create_user_command`). They probably live in `M.setup()` after the autocmds. Add a new command alongside `WordCount` and `ReadabilityReport`:

```lua
  vim.api.nvim_create_user_command("ReadingTime", function()
    require("writing-metrics.basic").show_reading_time()
  end, { desc = "Show reading time toast (silent + spoken)" })
```

- [ ] **Step 3: Smoke-test the command**

Test in a real Neovim session (manual — `vim.notify` is interactive):

```bash
cd ~/projects/nvim-writing-metrics
nvim test_document.md
```

In Neovim, run `:ReadingTime`. Expected: a notification appears with format `~N min silent · ~M min spoken  (X words at 200/150 wpm)`. Press a key to dismiss if needed.

If `vim.notify` is captured by noice or another popup system, the format should still be visible.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/basic.lua lua/writing-metrics/init.lua
git commit -m "feat(basic): add show_reading_time + :ReadingTime command

Triggers accurate count then displays a vim.notify toast with both
profiles. Falls back to fast count (marked '(fast)') if accurate fails.
Wired to user command :ReadingTime for keymap use."
```

---

## Task 4: Extend get_statusline_string with reading-time suffix

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua` — extend `get_statusline_string`

- [ ] **Step 1: Locate get_statusline_string**

Read `basic.lua` around line 261-340 to see all 4 return paths of `get_statusline_string`:
1. Visual selection (mode matches `[vV]`)
2. Fast mode (`statusline_mode == "fast"`)
3. Accurate mode with cache hit (fresh or stale)
4. No-cache fallback

Each path returns `{ text = "...", color = "green"|"orange" }`.

- [ ] **Step 2: Add a private suffix helper near the top of basic.lua**

Add this local function near the top of the module (after `local M = {}` and any other locals), before `M.get_statusline_string`:

```lua
--- Build the statusline reading-time suffix (e.g., "  ⏱ ~5 min").
--- Returns "" if disabled, no cached words, or invalid config.
--- @param bufnr integer
--- @return string
local function statusline_reading_time_suffix(bufnr)
  local config = require("writing-metrics.config").config.reading_time
  if not config or not config.enabled or not config.statusline then
    return ""
  end

  local rt = M.get_reading_time(bufnr)
  if not rt then return "" end

  local profile = config.statusline_profile or "silent"
  if profile == "spoken" then
    return string.format("  🎤 %s", rt.spoken)
  elseif profile == "both" then
    -- Compact form: ⏱ ~5/~7 min
    return string.format("  ⏱ ~%d/~%d min", rt.silent_minutes, rt.spoken_minutes)
  else
    -- Default: silent
    return string.format("  ⏱ %s", rt.silent)
  end
end
```

Note: since `M.get_reading_time` is defined later in the file, calling it here requires that the local function is invoked at runtime (after the module is fully loaded), not at module-load time. This is the case for `statusline_reading_time_suffix` since it's only called from within `get_statusline_string` which is only invoked by lualine at render time.

- [ ] **Step 3: Append the suffix to each return path in get_statusline_string**

Modify each of the 4 return paths in `get_statusline_string` to compute and append the suffix. For each return statement that produces `{ text = string.format(...), color = ... }`, add `.. statusline_reading_time_suffix(bufnr)` to the text:

**Path 1 — visual selection (around line 281-289):**

Old:
```lua
    return {
      text = string.format(
        "󰒉 %s words  󰬷 %s chars (sel)",
        utils.format_number(visual_words),
        utils.format_number(visual_chars)
      ),
      color = "green",
    }
```

New (visual selection mode — DO NOT append reading time; selection metrics are scoped, reading-time isn't):
```lua
    return {
      text = string.format(
        "󰒉 %s words  󰬷 %s chars (sel)",
        utils.format_number(visual_words),
        utils.format_number(visual_chars)
      ),
      color = "green",
    }
```

(Leave visual path UNCHANGED — reading time of a selection isn't meaningful at the same scope.)

**Path 2 — fast mode (around line 293-303):**

Old:
```lua
    return {
      text = string.format(
        "⚡ %s words  󰬶 %s chars",
        utils.format_number(wc.words or 0),
        utils.format_number(wc.chars or 0)
      ),
      color = "green",
    }
```

New:
```lua
    return {
      text = string.format(
        "⚡ %s words  󰬶 %s chars",
        utils.format_number(wc.words or 0),
        utils.format_number(wc.chars or 0)
      ) .. statusline_reading_time_suffix(bufnr),
      color = "green",
    }
```

**Path 3 — accurate mode with cache hit (around line 310-324):**

Old:
```lua
    return {
      text = string.format(
        "%s %s words  󰬶 %s chars",
        icon,
        utils.format_number(cached.words),
        utils.format_number(cached.chars)
      ),
      color = color,
    }
```

New:
```lua
    return {
      text = string.format(
        "%s %s words  󰬶 %s chars",
        icon,
        utils.format_number(cached.words),
        utils.format_number(cached.chars)
      ) .. statusline_reading_time_suffix(bufnr),
      color = color,
    }
```

**Path 4 — no-cache fallback (around line 327-336):**

Old:
```lua
  return {
    text = string.format(
      "⚠️ %s words  󰬶 %s chars",
      utils.format_number(wc.words or 0),
      utils.format_number(wc.chars or 0)
    ),
    color = "orange",
  }
```

New:
```lua
  return {
    text = string.format(
      "⚠️ %s words  󰬶 %s chars",
      utils.format_number(wc.words or 0),
      utils.format_number(wc.chars or 0)
    ) .. statusline_reading_time_suffix(bufnr),
    color = "orange",
  }
```

Note: in fast mode and the no-cache fallback, `M.get_reading_time(bufnr)` will return nil because the cache may be empty. The suffix helper handles this by returning `""`. So statusline shows just words/chars until accurate cache populates, then reading time appears.

- [ ] **Step 4: Verify all tests still pass**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/basic_spec.lua
```

Expected: same pass/fail counts as after Task 2.

- [ ] **Step 5: Smoke-test the statusline visually**

Open Neovim on a markdown file with substantial content (at least 200 words so reading time is ≥ 1 min). The statusline should show `⚡ N words  󰬶 M chars  ⏱ ~K min` or similar based on the accurate cache. Wait a moment for accurate mode to populate.

If the statusline doesn't show reading time:
- Verify `config.reading_time.statusline = true` (default).
- Verify the buffer has > 0 cached words (try writing more content, save, see if it updates).
- Check `:lua print(vim.inspect(require("writing-metrics.config").config.reading_time))` to confirm config loaded.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/basic.lua
git commit -m "feat(basic): append reading-time suffix to statusline string

Adds ' ⏱ ~5 min' (or spoken/both variants) to the statusline component
based on reading_time.statusline_profile config. Visual-selection mode
omits the suffix since reading-time of a selection isn't meaningful at
the same scope."
```

---

## Task 5: Add reading time rows to the full readability report

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua` — append rows to `format_basic_section`

- [ ] **Step 1: Locate format_basic_section**

Read `display.lua` to find `function M.format_basic_section(basic)`. It builds a markdown table with rows for Words, Characters, Sentences, Paragraphs, Lines. Find the line that inserts the "Lines" row (or whichever is the last row before the closing `table.insert(lines, "")`).

- [ ] **Step 2: Append reading time rows**

After the existing `| Lines |` row (or the last metric row), and BEFORE the empty line that closes the table, insert:

```lua
  -- Append reading time rows if enabled
  local rt_config = require("writing-metrics.config").config.reading_time
  if rt_config and rt_config.enabled and basic.words and basic.words > 0
     and rt_config.wpm_silent > 0 and rt_config.wpm_spoken > 0 then
    local silent_min = math.ceil(basic.words / rt_config.wpm_silent)
    local spoken_min = math.ceil(basic.words / rt_config.wpm_spoken)
    table.insert(lines, string.format(
      "| Reading time (silent, %d wpm) | **~%d min** |",
      rt_config.wpm_silent, silent_min
    ))
    table.insert(lines, string.format(
      "| Reading time (spoken, %d wpm) | **~%d min** |",
      rt_config.wpm_spoken, spoken_min
    ))
  end
```

This duplicates the calculation logic (math.ceil) from `basic.get_reading_time` rather than calling it. Justified because:
- `format_basic_section` receives `basic` data directly (no bufnr context to fetch cache).
- The calculation is two lines; centralizing would require threading bufnr through `format_basic_section` for marginal benefit.
- If you ever want reading time in additional render paths, refactor then.

- [ ] **Step 3: Verify all tests still pass**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh
```

Expected: same pre-existing pass/fail counts. New tests from prior tasks still pass.

- [ ] **Step 4: Smoke-test the full report**

In Neovim on a markdown file with substantial content, run `:ReadabilityReport` (or press `<leader>mr`). The Basic Statistics section should now show two new rows:

```
| Reading time (silent, 200 wpm) | **~5 min** |
| Reading time (spoken, 150 wpm) | **~7 min** |
```

WPM values should match your configured `wpm_silent` and `wpm_spoken`.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/display.lua
git commit -m "feat(display): add reading time rows to Basic Statistics section

Both silent (200 wpm default) and spoken (150 wpm default) profiles
appear in the readability report. WPM values annotated parenthetically
so the numbers are self-documenting. Skipped cleanly when disabled or
no word count is available."
```

---

## Task 6: Add `<leader>mT` keymap in nvim config

**Files:**
- Modify: `~/.config/nvim/lua/plugins/writing-metrics.lua` — add new `keys` entry

**NOTE:** `~/.config/nvim/` is NOT a git repository. Do not attempt to commit; just save the file.

- [ ] **Step 1: Read the existing keys table**

Open `~/.config/nvim/lua/plugins/writing-metrics.lua`. Find the `keys = { ... }` block. It should contain entries for `<leader>mc`, `<leader>mr`, `<leader>mt`.

- [ ] **Step 2: Add the new keymap**

Append a new entry to the `keys` table (after the `<leader>mt` entry):

```lua
      { "<leader>mT", "<cmd>ReadingTime<cr>", desc = "metrics: reading time" },
```

The capital `T` distinguishes it from `<leader>mt` (toggle fast/accurate). Mnemonic: lowercase t = toggle, uppercase T = Time.

- [ ] **Step 3: Verify the spec file still parses**

```bash
nvim --headless -c "luafile /home/jkeim/.config/nvim/lua/plugins/writing-metrics.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output (file loads cleanly).

- [ ] **Step 4: Manual verification**

Restart Neovim. In a markdown buffer, press `<leader>mT`. Expected: the same toast as `:ReadingTime` from Task 3 — `~N min silent · ~M min spoken (X words at 200/150 wpm)`.

If which-key shows `<leader>mT` correctly labeled as "metrics: reading time", that's a bonus signal that the entry is well-formed.

- [ ] **Step 5: No commit needed**

`~/.config/nvim/` is not a git repo. The change is live as soon as the file is saved.

---

## Task 7: Remove nvim-prose

**Files:**
- Delete: `~/.config/nvim/lua/plugins/nvim-prose.lua`

**NOTE:** Not a git repo; no commit. Just remove the file and run `:Lazy clean` once to drop the cached plugin source.

- [ ] **Step 1: Confirm nothing else references nvim-prose**

```bash
grep -rn "nvim-prose\|prose_word_count\|prose_reading_time" ~/.config/nvim/ --include="*.lua"
```

Expected: only `lua/plugins/nvim-prose.lua` appears (the file we're about to delete). If anything else shows up, STOP and investigate — there may be a consumer we missed.

- [ ] **Step 2: Delete the plugin spec file**

```bash
rm ~/.config/nvim/lua/plugins/nvim-prose.lua
```

- [ ] **Step 3: Drop the cached plugin source via Lazy**

```bash
nvim --headless -c "Lazy! clean" -c "qa!" 2>&1 | tail -10
```

Expected output mentions that `nvim-prose` was cleaned. The directory `~/.local/share/nvim/lazy/nvim-prose/` should be gone after this:

```bash
ls -d ~/.local/share/nvim/lazy/nvim-prose 2>&1
```

Expected: `ls: cannot access '/home/jkeim/.local/share/nvim/lazy/nvim-prose': No such file or directory`.

If `Lazy! clean` doesn't remove it (e.g., because the lockfile still references it), open Neovim interactively, run `:Lazy clean`, confirm any prompts.

- [ ] **Step 4: Verify lazy-lock.json no longer mentions nvim-prose**

```bash
grep -n "nvim-prose" ~/.config/nvim/lazy-lock.json 2>&1
```

Expected: empty (lazy regenerated the lockfile during clean).

If it still appears, run Neovim with `:Lazy sync` or restart and let lazy update.

- [ ] **Step 5: Final smoke test**

Start Neovim. Open a markdown buffer. Verify:
- Statusline shows reading time (from Task 4).
- `:ReadingTime` works (from Task 3).
- `<leader>mT` works (from Task 6).
- `:ReadabilityReport` shows reading time rows (from Task 5).
- No errors about nvim-prose in `:messages`.

- [ ] **Step 6: No commit needed**

Both the file deletion and the lazy-lock.json regeneration live in `~/.config/nvim/`, which is not a git repo.

---

## Summary

7 tasks. 5 commits land on `main` of `~/projects/nvim-writing-metrics/`. 2 tasks edit `~/.config/nvim/` without commits. Estimated 1-2 hours of focused work.

After completion:
- Statusline shows reading time alongside word/char counts (toggleable, profile-selectable).
- Full readability report includes reading time rows.
- `<leader>mT` / `:ReadingTime` give a quick toast.
- `nvim-prose` is gone — one fewer plugin, no orphaned dependency.

Net effect: better reading-time data (Pandoc-stripped vs raw wordcount), more visibility surfaces (3 vs 1), two WPM profiles vs one. Strict improvement over what `nvim-prose` would have offered.
