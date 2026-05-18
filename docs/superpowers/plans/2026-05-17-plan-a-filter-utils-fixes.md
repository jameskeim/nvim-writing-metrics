# Plan A — Filter & utils bug fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix six bugs in `nvim-writing-metrics` — four in the Pandoc filter (`scripts/textmetrics.lua`) and two in the Lua plumbing (`utils.lua` + `full.lua`) — that were identified in the Tier 3 audit.

**Architecture:** All six fixes are localized edits, not refactors. Filter changes are verified end-to-end via `pandoc --lua-filter` invocations called through the existing `full.get_full_metrics` test harness. Plumbing changes get focused unit tests. One small helper (`extract_json`) is extracted into `utils.lua` so `full.lua` can delegate (eliminating the duplicate JSON-extraction logic).

**Tech Stack:** Lua 5.1 (LuaJIT in Neovim), plenary.busted for tests, Pandoc 2.x for the filter.

---

## Conventions

- **Plugin repo:** `~/projects/nvim-writing-metrics/` — git-tracked, commits land directly on `main`.
- **Run tests:** `cd ~/projects/nvim-writing-metrics && ./run-tests.sh` (all) or `-t tests/<spec>.lua` for one file.
- **Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-17-tier3-tier4-cleanup-design.md`
- **Baseline test counts (pre-plan):** 22 pass / 9 fail in `basic_spec.lua`; 14 pass / 4 fail in full suite. Pre-existing failures memorialized in `project_nvim_writing_metrics_stale_tests.md` and `project_nvim_writing_metrics_full_spec_failures.md`. New work must not increase the failure count.

Pre-existing facts the implementer should know going in:
- The filter has two modes (`basic` and `full`), selected via metadata `metrics_mode=basic|full`. Basic outputs space-separated values; full outputs JSON.
- Filter exit: the main `Pandoc(el)` function currently ends with `os.exit(0)` (the cause of issue #1). Until fixed, Pandoc's `plain` writer aborts mid-render with a cosmetic `table.concat` error on stderr.
- `full.get_full_metrics(bufnr, callback)` runs pandoc end-to-end and yields `callback(success, data)`. Tests use `helpers.wait_for_async(...)` to await the callback.
- Char counting (`chars` global) is accumulated across `Str`, `Space`, `SoftBreak`, and `LineBreak` element handlers. Currently `Str` uses `#el.text` (byte length).
- The full-mode JSON output is emitted as a single line via `print(json.encode(output))` (so JSON-line extraction is robust).

---

## Task 1: Fix #1 — Replace `os.exit(0)` with normal Pandoc return

**Files:**
- Modify: `~/projects/nvim-writing-metrics/scripts/textmetrics.lua:1101`
- Test: `~/projects/nvim-writing-metrics/tests/full_spec.lua` (add new describe block)

- [ ] **Step 1: Write the failing test**

Add this `describe` block at the end of the existing `describe("writing-metrics.full", function() ... end)` block in `~/projects/nvim-writing-metrics/tests/full_spec.lua` (just before the final closing `end)`):

```lua
  describe("filter exits cleanly", function()
    it("does not write cosmetic table.concat error to stderr", function()
      helpers.skip_without_pandoc()

      local temp_md = vim.fn.tempname() .. ".md"
      local f = io.open(temp_md, "w")
      f:write("# Test\n\nA paragraph with words.\n")
      f:close()

      local filter = vim.fn.fnamemodify("scripts/textmetrics.lua", ":p")

      local result = vim.system({
        "pandoc", temp_md,
        "--lua-filter", filter,
        "-M", "metrics=basic",
        "-t", "plain",
      }, { text = true }):wait()

      vim.fn.delete(temp_md)

      assert.equals(0, result.code, "pandoc should exit 0, got: " .. tostring(result.code))
      local stderr = result.stderr or ""
      assert.is_nil(stderr:find("table.concat", 1, true),
        "stderr should not contain table.concat error; got: " .. stderr)
    end)
  end)
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/full_spec.lua 2>&1 | grep -aE "table.concat|Failed.*table.concat|filter exits cleanly" | head -5
```

Expected: the test fails because stderr contains the `table.concat` error currently emitted by Pandoc's plain writer aborting mid-render.

- [ ] **Step 3: Apply the fix**

In `~/projects/nvim-writing-metrics/scripts/textmetrics.lua`, find line ~1101 (the very last line inside the `Pandoc(el)` function, before the closing `end`):

```lua
  os.exit(0)
end
```

Replace with:

```lua
  -- Return an empty Pandoc document instead of os.exit(0).
  -- os.exit aborted Pandoc's plain writer mid-render, producing a
  -- cosmetic table.concat error on stderr.
  return pandoc.Pandoc({}, el.meta)
end
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/full_spec.lua 2>&1 | tail -10
```

Expected: pass count increases by 1; failure count unchanged from baseline (4 in full suite).

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add scripts/textmetrics.lua tests/full_spec.lua
git commit -m "fix(filter): return Pandoc instead of os.exit to avoid writer abort

os.exit(0) terminated the filter before Pandoc's plain writer
finished rendering, producing a cosmetic table.concat error on
stderr. Returning an empty Pandoc document instead lets the writer
complete normally. Adds regression test asserting clean stderr."
```

---

## Task 2: Fix #4 — Cleanup temp file on `run_pandoc` early-return path

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua:117-151`

This task has no test — the bug only triggers when the Pandoc filter is missing, which is hard to simulate without monkey-patching `config.get_filter_path`. The fix is defensive cleanup.

- [ ] **Step 1: Read the current `run_pandoc` function**

Read `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua` around lines 113-151 to confirm the current shape.

- [ ] **Step 2: Change the function signature to receive the temp_file path so it can clean up**

This is the cleanest fix because callers ALREADY know which temp file they wrote. Currently `run_pandoc(input_file, mode, callback)` takes `input_file` but does not clean it up; the caller cleans up in the `vim.system` success path.

The bug: when `filter_path` is nil, `run_pandoc` returns early via `callback(false, ...)` WITHOUT giving the caller a chance to clean up — and the caller's cleanup is inside the `vim.system` callback that never runs.

The minimal fix: clean up `input_file` in the early-return path. In `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua`, change:

```lua
function M.run_pandoc(input_file, mode, callback)
  local config = require("writing-metrics.config")
  local filter_path = config.get_filter_path()

  if not filter_path then
    callback(false, "Pandoc filter not found")
    return
  end
```

To:

```lua
function M.run_pandoc(input_file, mode, callback)
  local config = require("writing-metrics.config")
  local filter_path = config.get_filter_path()

  if not filter_path then
    -- Caller's cleanup runs inside vim.system callback, which won't fire
    -- on early return. Clean up the temp file here to avoid leaking it.
    M.cleanup_temp_file(input_file)
    callback(false, "Pandoc filter not found")
    return
  end
```

(Only the `M.cleanup_temp_file(input_file)` line is added; everything else stays.)

- [ ] **Step 3: Verify the file still parses**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/utils.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 4: Run all tests to confirm no regressions**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -5
```

Expected: same pass/fail counts as before this task.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/utils.lua
git commit -m "fix(utils): clean up temp file on run_pandoc early return

When the Pandoc filter is missing, run_pandoc returned early via
callback(false, ...) without cleaning up the temp file. The caller's
cleanup lives inside the vim.system callback, which never fires on
early return. Now run_pandoc cleans up before the early-return
callback so the temp file does not leak."
```

---

## Task 3: Fix #3 — Robust JSON extraction (eliminate greedy `{→end` parse)

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua:201-221` (`parse_full_output`)
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/full.lua:49-74` (`parse_full_metrics`)
- Test: `~/projects/nvim-writing-metrics/tests/utils_spec.lua` (NEW FILE)

- [ ] **Step 1: Create a new test file and write the failing test**

Create `~/projects/nvim-writing-metrics/tests/utils_spec.lua` with:

```lua
-- Tests for writing-metrics.utils module
local helpers = require("tests.helpers")

describe("writing-metrics.utils", function()
  local utils

  before_each(function()
    package.loaded["writing-metrics.utils"] = nil
    utils = require("writing-metrics.utils")
  end)

  after_each(function()
    helpers.cleanup_buffers()
  end)

  describe("parse_full_output", function()
    it("parses JSON when a Pandoc warning containing { appears before it", function()
      -- Pandoc may emit warnings to the same stream as output. Warnings
      -- can legitimately contain '{', which would confuse a greedy
      -- find("{") strategy.
      local output = table.concat({
        "[WARNING] Some warning with { brace } in it",
        '{"basic": {"words": 5, "characters": 20, "sentences": 1, "paragraphs": 1, "lines": 1}, "readability": {"automated_readability": 0}}',
      }, "\n")

      local result, err = utils.parse_full_output(output)

      assert.is_nil(err, "should parse despite warning; got error: " .. tostring(err))
      assert.is_not_nil(result)
      assert.is_table(result.basic)
      assert.equals(5, result.basic.words)
      assert.equals(20, result.basic.characters)
    end)

    it("returns error for output without any JSON object", function()
      local result, err = utils.parse_full_output("just warnings, no JSON here")
      assert.is_nil(result)
      assert.is_string(err)
    end)

    it("returns error for empty output", function()
      local result, err = utils.parse_full_output("")
      assert.is_nil(result)
      assert.is_string(err)
    end)
  end)
end)
```

- [ ] **Step 2: Run the test and verify the warning-case test fails**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/utils_spec.lua 2>&1 | tail -10
```

Expected: the "parses JSON when a Pandoc warning..." test fails because `output:find("{")` matches the `{` inside `{ brace }` and `vim.json.decode` cannot parse `{ brace } in it\n{...}`. The other two tests (no JSON, empty) should pass.

- [ ] **Step 3: Add the JSON-extraction helper to utils.lua**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua`, add this private local function NEAR THE TOP of the module (after `local M = {}` and any other locals, before any `function M.foo`). This helper will be called by both `parse_full_output` (in utils.lua) and `parse_full_metrics` (in full.lua):

```lua
--- Extract the JSON object line from filter output.
--- The textmetrics filter emits JSON via print(json.encode(...)), which is
--- always a single line. Pandoc warnings may appear before the JSON and
--- may legitimately contain '{', so a greedy first-'{' search is unsafe.
--- Strategy: scan from the end and return the last line that both starts
--- with '{' (possibly preceded by whitespace) and ends with '}'.
--- @param str string Raw filter/pandoc output
--- @return string|nil The JSON line, or nil if not found
local function extract_json(str)
  if not str or str == "" then return nil end
  local lines = vim.split(str, "\n", { plain = true })
  for i = #lines, 1, -1 do
    local line = lines[i]:gsub("^%s+", ""):gsub("%s+$", "")
    if line:sub(1, 1) == "{" and line:sub(-1) == "}" then
      return line
    end
  end
  return nil
end

-- Exposed for use by other modules (e.g. full.lua).
M._extract_json = extract_json
```

- [ ] **Step 4: Update `parse_full_output` to use the helper**

Still in `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua`, replace the existing `M.parse_full_output` function (currently at lines ~201-221):

```lua
function M.parse_full_output(output)
  if not output or output == "" then
    return nil, "Empty output from Pandoc"
  end

  -- Extract JSON (ignore Pandoc warnings)
  local json_start = output:find("{")
  if not json_start then
    return nil, "No JSON found in output"
  end

  local json_str = output:sub(json_start)

  -- Parse JSON
  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, "Failed to parse JSON: " .. tostring(result)
  end

  return result
end
```

With:

```lua
function M.parse_full_output(output)
  if not output or output == "" then
    return nil, "Empty output from Pandoc"
  end

  local json_str = extract_json(output)
  if not json_str then
    return nil, "No JSON found in output"
  end

  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, "Failed to parse JSON: " .. tostring(result)
  end

  return result
end
```

- [ ] **Step 5: Update `full.parse_full_metrics` to delegate to the helper**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/full.lua`, replace the existing `M.parse_full_metrics` (currently at lines ~49-74):

```lua
function M.parse_full_metrics(json_output)
  if not json_output or json_output == "" then
    return nil, "Empty output from Pandoc"
  end

  -- Extract JSON (ignore any Pandoc warnings)
  local json_start = json_output:find("{")
  if not json_start then
    return nil, "No JSON found in output"
  end

  local json_str = json_output:sub(json_start)

  -- Parse JSON
  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, "Failed to parse JSON: " .. tostring(result)
  end

  -- Validate required sections
  if not result.basic then
    return nil, "Missing 'basic' section in metrics output"
  end

  return result
end
```

With:

```lua
function M.parse_full_metrics(json_output)
  if not json_output or json_output == "" then
    return nil, "Empty output from Pandoc"
  end

  local utils = require("writing-metrics.utils")
  local json_str = utils._extract_json(json_output)
  if not json_str then
    return nil, "No JSON found in output"
  end

  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, "Failed to parse JSON: " .. tostring(result)
  end

  -- Validate required sections
  if not result.basic then
    return nil, "Missing 'basic' section in metrics output"
  end

  return result
end
```

- [ ] **Step 6: Run all tests and verify the new tests pass**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: utils_spec.lua's 3 tests all pass. Pre-existing pass/fail counts elsewhere unchanged.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/utils.lua lua/writing-metrics/full.lua tests/utils_spec.lua
git commit -m "fix(utils,full): robust JSON extraction tolerant of warning preamble

Replace greedy output:find('{') with a last-line scan that returns
the last line that both starts with '{' and ends with '}'. The
filter prints JSON via json.encode() which is always single-line, so
this is robust. full.parse_full_metrics now delegates to the
helper, eliminating the duplicate extraction logic."
```

---

## Task 4: Fix #8 — Count characters as UTF-8 codepoints, not bytes

**Files:**
- Modify: `~/projects/nvim-writing-metrics/scripts/textmetrics.lua:813`
- Test: `~/projects/nvim-writing-metrics/tests/full_spec.lua` (add to existing `describe`)

- [ ] **Step 1: Write the failing test**

Add this test inside the existing `describe("writing-metrics.full", function() ... end)` block in `~/projects/nvim-writing-metrics/tests/full_spec.lua` (place it inside the existing `describe("filter exits cleanly", function() ... end)` block created in Task 1, or as a sibling):

```lua
  describe("char counting", function()
    it("counts UTF-8 characters as codepoints not bytes", function()
      helpers.skip_without_pandoc()

      -- 'café' is 4 codepoints but 5 bytes (é is U+00E9, 2 bytes in UTF-8).
      local content = "café"
      local bufnr = helpers.create_test_buffer(content)

      local result_data = nil
      require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
        if success then result_data = data end
      end)

      helpers.wait_for_async(function() return result_data ~= nil end, 5000)

      assert.is_not_nil(result_data, "filter should produce data")
      assert.is_table(result_data.basic)
      assert.equals(4, result_data.basic.characters,
        "char count should be 4 codepoints, not 5 bytes; got: "
        .. tostring(result_data.basic.characters))
    end)
  end)
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/full_spec.lua 2>&1 | tail -10
```

Expected: the new test fails with `characters = 5` (bytes) instead of `4` (codepoints).

- [ ] **Step 3: Apply the fix**

In `~/projects/nvim-writing-metrics/scripts/textmetrics.lua`, find line ~813 inside the `wordcount.Str` handler:

```lua
    -- Count all characters in text nodes (both modes)
    chars = chars + #el.text
```

Replace with:

```lua
    -- Count all characters in text nodes (both modes).
    -- Use utf8.len for codepoint count; #el.text is byte length which
    -- inflates counts for non-ASCII text (smart quotes, em-dashes, accents).
    -- Fall back to byte length if the text is not valid UTF-8.
    chars = chars + (utf8.len(el.text) or #el.text)
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/full_spec.lua 2>&1 | tail -10
```

Expected: the new test passes. Other tests' pass/fail counts unchanged.

- [ ] **Step 5: Check for any committed score fixtures that may need updating**

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "coleman_liau\|automated_readability\|ari" tests/ | grep -v "mock_pandoc_full" | head -10
```

Expected: no hard-coded score assertions tied to specific char counts. If any appear, update them in this same commit. (The `mock_pandoc_full` helper uses synthetic data and is not affected by filter behavior.)

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add scripts/textmetrics.lua tests/full_spec.lua
git commit -m "fix(filter): count chars as UTF-8 codepoints not bytes

Replace #el.text (byte length) with utf8.len(el.text) in the Str
handler. Fixes inflated char counts for non-ASCII text (smart
quotes, em-dashes, accented characters), which fed inflated ARI and
Coleman-Liau scores. Falls back to byte length when text is not
valid UTF-8."
```

---

## Task 5: Fix #16 — ARI uses letter chars, not all chars

**Files:**
- Modify: `~/projects/nvim-writing-metrics/scripts/textmetrics.lua:970`
- Test: `~/projects/nvim-writing-metrics/tests/full_spec.lua` (add to existing describe)

- [ ] **Step 1: Write the failing test**

Add this test inside the `describe("char counting", ...)` block created in Task 4 (or as a sibling describe):

```lua
  describe("ARI calculation", function()
    it("uses letter chars, not total chars (which includes spaces)", function()
      helpers.skip_without_pandoc()

      -- Controlled input: 2 words, 1 sentence, easy to verify.
      -- "Hello world." → Hello=5 letters, world=5 letters, total_word_chars=10.
      -- ARI with letter chars: 4.71 * (10/2) + 0.5 * (2/1) - 21.43
      --                      = 23.55 + 1 - 21.43 = 3.12
      -- ARI with total chars (~12 including space and period):
      --                      = 4.71 * (12/2) + 0.5 * (2/1) - 21.43
      --                      = 28.26 + 1 - 21.43 = 7.83
      -- The pre-fix value will be substantially higher; assert ARI < 5.
      local content = "Hello world."
      local bufnr = helpers.create_test_buffer(content)

      local result_data = nil
      require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
        if success then result_data = data end
      end)

      helpers.wait_for_async(function() return result_data ~= nil end, 5000)

      assert.is_not_nil(result_data, "filter should produce data")
      assert.is_table(result_data.readability)
      local ari = result_data.readability.automated_readability
      assert.is_number(ari)
      assert.is_true(ari < 5,
        "ARI should compute from letter chars (~3.12 for this input), "
        .. "not total chars (~7.83); got: " .. tostring(ari))
    end)
  end)
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/full_spec.lua 2>&1 | tail -10
```

Expected: the new test fails because ARI is being computed from the global `chars` accumulator (which includes spaces, soft-breaks, punctuation), making it higher than the letter-only calculation.

- [ ] **Step 3: Apply the fix**

In `~/projects/nvim-writing-metrics/scripts/textmetrics.lua`, find line ~970 inside the `readability = { ... }` table:

```lua
      automated_readability = calculate_ari(chars, words, sentences),
```

Replace with:

```lua
      -- ARI canonically uses letter count, not total chars (which would
      -- include spaces and punctuation). total_word_chars is already
      -- tracked for Coleman-Liau and is the correct denominator here.
      automated_readability = calculate_ari(total_word_chars, words, sentences),
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/full_spec.lua 2>&1 | tail -10
```

Expected: the new ARI test passes. Other tests' pass/fail counts unchanged.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add scripts/textmetrics.lua tests/full_spec.lua
git commit -m "fix(filter): ARI uses letter chars (total_word_chars), not all chars

The canonical Automated Readability Index uses the letter count of
words, not total characters in the text (which includes spaces,
punctuation, and line breaks). total_word_chars is already tracked
and used by Coleman-Liau for the same reason. Switch ARI to use it."
```

---

## Task 6: Fix #7 — Stop double-counting paragraphs in lists

**Files:**
- Modify: `~/projects/nvim-writing-metrics/scripts/textmetrics.lua:904-920` (`BulletList` and `OrderedList` handlers) + add `Plain` handler near `Para` handler at line ~885
- Test: `~/projects/nvim-writing-metrics/tests/full_spec.lua` (add to existing describe)

**Background:** In Pandoc, a *loose* list (blank lines between items) wraps each item in a `Para` block; a *compact* list wraps each item in a `Plain` block. Currently:

- `BulletList`/`OrderedList` handlers increment `paragraphs` once per item.
- `Para` handler also increments `paragraphs` once.
- No `Plain` handler exists.

Result: loose lists are counted at **2× per item** (list handler + Para). Compact lists are counted correctly at **1× per item** (only list handler).

The fix: remove the per-item increment from list handlers and add a `Plain` handler that increments once. Then loose-list items count via `Para`, compact-list items count via `Plain`, and lists themselves don't increment — every list item counts exactly once regardless of looseness.

- [ ] **Step 1: Write the failing test**

Add this test inside the existing `describe("writing-metrics.full", function() ... end)` block in `~/projects/nvim-writing-metrics/tests/full_spec.lua`:

```lua
  describe("list paragraph counting", function()
    it("counts loose list items once, not twice", function()
      helpers.skip_without_pandoc()

      -- Loose list: blank lines between items → Pandoc emits Para inside.
      -- Pre-fix bug: each item counts via BulletList AND via Para → 2× inflation.
      local content = table.concat({
        "- first item",
        "",
        "- second item",
        "",
        "- third item",
      }, "\n")
      local bufnr = helpers.create_test_buffer(content)

      local result_data = nil
      require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
        if success then result_data = data end
      end)

      helpers.wait_for_async(function() return result_data ~= nil end, 5000)

      assert.is_not_nil(result_data)
      assert.equals(3, result_data.basic.paragraphs,
        "3 loose list items should yield 3 paragraphs; got: "
        .. tostring(result_data.basic.paragraphs))
    end)

    it("counts compact list items once (regression guard)", function()
      helpers.skip_without_pandoc()

      -- Compact list: no blank lines between items → Pandoc emits Plain.
      -- Pre-fix: counted via BulletList only. Post-fix: counted via Plain only.
      -- Either way the count should be 3.
      local content = table.concat({
        "- first item",
        "- second item",
        "- third item",
      }, "\n")
      local bufnr = helpers.create_test_buffer(content)

      local result_data = nil
      require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
        if success then result_data = data end
      end)

      helpers.wait_for_async(function() return result_data ~= nil end, 5000)

      assert.is_not_nil(result_data)
      assert.equals(3, result_data.basic.paragraphs,
        "3 compact list items should yield 3 paragraphs; got: "
        .. tostring(result_data.basic.paragraphs))
    end)
  end)
```

- [ ] **Step 2: Run the tests and verify the loose-list test fails**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/full_spec.lua 2>&1 | tail -15
```

Expected: the "counts loose list items once, not twice" test fails (paragraphs = 6, expected 3). The compact-list test should already pass at baseline (3 from BulletList alone).

- [ ] **Step 3: Apply the fix**

In `~/projects/nvim-writing-metrics/scripts/textmetrics.lua`, make TWO changes inside the `blockcounter = { ... }` table (the `Para` handler is around line 885; the list handlers are around lines 904-920).

**Change 3a — add a `Plain` handler** right after the existing `Para` handler (around line 891, after `Para = function(el) ... end,`):

```lua
  Plain = function(el)
    -- Plain blocks appear inside compact list items (no blank line between).
    -- Treat them like single-paragraph units so compact lists count items
    -- without relying on the list handler to do paragraph counting.
    paragraphs = paragraphs + 1
    lines = lines + 1
    return el
  end,
```

**Change 3b — remove the per-item paragraph/line increment from list handlers.** Replace the existing `BulletList` and `OrderedList` handlers (around lines 904-920):

```lua
  BulletList = function(el)
    -- Each list item is like a mini-paragraph (both modes)
    for i,item in ipairs(el.content) do
      paragraphs = paragraphs + 1
      lines = lines + 1
    end
    return el
  end,

  OrderedList = function(el)
    -- Same as bullet list (both modes)
    for i,item in ipairs(el.content) do
      paragraphs = paragraphs + 1
      lines = lines + 1
    end
    return el
  end,
```

With:

```lua
  BulletList = function(el)
    -- Do not count items here. Items contain either Para (loose lists) or
    -- Plain (compact lists), both of which have their own handlers above
    -- that increment paragraphs/lines exactly once per item. Counting here
    -- as well would double-count loose lists.
    return el
  end,

  OrderedList = function(el)
    -- Same as BulletList: rely on inner Para/Plain handlers.
    return el
  end,
```

- [ ] **Step 4: Run the tests and verify both pass**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/full_spec.lua 2>&1 | tail -10
```

Expected: both list-counting tests pass (3 paragraphs each). All other tests' counts unchanged.

- [ ] **Step 5: Run the full suite to confirm no broader regressions**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -10
```

Expected: total pass count is up by all the tests added across Tasks 1, 3, 4, 5, 6 (8 new tests in total: 1 in Task 1, 3 in Task 3, 1 in Task 4, 1 in Task 5, 2 in Task 6). Pre-existing failure counts unchanged.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add scripts/textmetrics.lua tests/full_spec.lua
git commit -m "fix(filter): stop double-counting paragraphs in loose lists

BulletList/OrderedList handlers were incrementing paragraphs per
item, then Pandoc's walk recursed into the inner Para of each item,
incrementing again. Loose lists came out at 2x. Fix: remove the
list-handler increment and add a Plain handler so compact lists
(which use Plain instead of Para) still count correctly. Net result:
both loose and compact lists count exactly once per item."
```

---

## Final verification

After all six tasks land, run the full test suite one last time and confirm:

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | tail -5
```

**Expected pass count change from baseline:** +8 (1 stderr-clean + 3 JSON-extract + 1 UTF-8 + 1 ARI + 2 list-counting).
**Expected failure count change:** 0 (no regressions; pre-existing failures unchanged).

Also commit log review:

```bash
cd ~/projects/nvim-writing-metrics
git log --oneline 6448417..HEAD
```

Expected: 6 commits, one per task, all prefixed `fix(...)`.

---

## Summary

6 tasks. 6 commits land on `main` of `~/projects/nvim-writing-metrics/`. 8 new tests added (5 in `full_spec.lua`, 3 in a new `tests/utils_spec.lua`). Estimated 1.5–2 hours of focused work.

After completion:
- The cosmetic `table.concat` error on stderr is gone (#1).
- Temp files no longer leak when the filter is missing (#4).
- JSON parsing tolerates Pandoc warnings containing `{` (#3); duplicate extraction logic removed.
- UTF-8 text gets accurate char counts (#8); ARI and Coleman-Liau no longer inflated by non-ASCII.
- ARI matches its canonical formula by using letter count (#16).
- Loose lists no longer double-count paragraphs (#7); compact lists still count correctly.
