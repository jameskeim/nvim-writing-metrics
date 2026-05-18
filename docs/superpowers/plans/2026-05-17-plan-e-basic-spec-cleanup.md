# Plan E — `basic_spec.lua` cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive `basic_spec.lua` from 22 pass / 9 fail to 31 pass / 0 fail by fixing one real implementation bug in `get_fast_count` and three stale test assertions, with zero behavior change visible to users.

**Architecture:** Four atomic clusters, one commit per cluster, on `main` of `~/projects/nvim-writing-metrics/`. After each commit, re-run the full suite and confirm the failure count drops monotonically without disturbing the 23 pre-existing failures in other spec files. Per the spec, Plan E uses one holistic review at the end (mirroring Plan C) instead of per-cluster spec/code-quality reviews.

**Tech Stack:** Lua 5.1 (LuaJIT in Neovim), `vim.api` buffer APIs, `vim.fn.strchars` for UTF-8-aware character counting, `busted`/`plenary.test_harness` for the test suite.

---

## Conventions

- **Plugin repo:** `~/projects/nvim-writing-metrics/` — git-tracked, commits land directly on `main`.
- **Run tests:** `cd ~/projects/nvim-writing-metrics && ./run-tests.sh` (all specs).
- **Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-17-plan-e-basic-spec-cleanup-design.md`
- **Baseline (HEAD `b819360`, post-Plan C):** 87 pass / 32 fail across the full suite; `basic_spec.lua` is 22 pass / 9 fail.
- **Target:** 96 pass / 23 fail full suite; `basic_spec.lua` is 31 pass / 0 fail. The 23 remaining failures all live in `full_spec.lua` (4) and config/compatibility/integration specs (19) and are out of scope for Plan E.

**Verification after each task** (boilerplate referenced from each task):

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected per-cluster (totals across the whole suite):

| After cluster | basic_spec | Full suite |
|---|---|---|
| Baseline | 22 / 9 | 87 / 32 |
| Cluster 1 | 26 / 5 | 91 / 28 |
| Cluster 2 | 29 / 2 | 94 / 25 |
| Cluster 3 | 30 / 1 | 95 / 24 |
| Cluster 4 | 31 / 0 | 96 / 23 |

If any cluster moves a count outside this table — particularly if another spec file's failure count changes — STOP and investigate; the shift is attributable to the just-landed commit.

**Note on "write the failing test first" steps:** Plan E is a cleanup, not a feature. The failing tests already exist in `tests/basic_spec.lua`. The "red" step in each task is "confirm the targeted tests currently fail" — not writing new tests.

---

## Task 1: Cluster 1 — Fix `get_fast_count` implementation bug

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua` (rewrite `M.get_fast_count` body, ~line 87-103)
- Test (existing, no changes): `~/projects/nvim-writing-metrics/tests/basic_spec.lua:40-79`

**What's broken:** `M.get_fast_count(bufnr)` accepts a `bufnr` argument but calls `vim.fn.wordcount()`, which always counts the current buffer and ignores the parameter. Tests create a buffer with `helpers.create_test_buffer()` (which does NOT make it current) and then call `get_fast_count(bufnr)`, expecting counts for the new buffer — they get counts for whatever buffer is current instead.

**What gets fixed:** Four tests in the `fast word count` describe block (`counts words in simple text`, `counts characters`, `handles single word`, `ignores markdown syntax in fast mode`).

- [ ] **Step 1: Confirm the four targeted tests currently fail**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "fast word count|Success: |Failed : " | head -20
```

Expected: tests for `counts words in simple text`, `counts characters`, `handles single word`, `ignores markdown syntax in fast mode` show as failures. `basic_spec.lua` overall reports 22 / 9.

- [ ] **Step 2: Rewrite `M.get_fast_count` body**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/basic.lua`, find the current function (around line 87):

```lua
--- Get fast count using Vim's native wordcount()
--- @param bufnr number|nil Buffer number (0 or nil for current)
--- @return table Basic metrics {words, chars, sentences, paragraphs}
function M.get_fast_count(bufnr)
  -- Normalize buffer number (0 and nil both mean current buffer)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local wc = vim.fn.wordcount()

  return {
    words = wc.words or 0,
    chars = wc.chars or 0,
    sentences = 0, -- Vim doesn't count these
    paragraphs = 0,
    avg_sentence_len = 0,
    avg_word_len = 0,
  }
end
```

Replace with:

```lua
--- Get fast count using direct buffer text scan.
--- Reads the passed buffer (defaults to current); does NOT rely on
--- vim.fn.wordcount(), which always operates on the current buffer
--- regardless of arguments.
--- @param bufnr number|nil Buffer number (0 or nil for current)
--- @return table Basic metrics {words, chars, sentences, paragraphs}
function M.get_fast_count(bufnr)
  -- Normalize buffer number (0 and nil both mean current buffer)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {
      words = 0,
      chars = 0,
      sentences = 0,
      paragraphs = 0,
      avg_sentence_len = 0,
      avg_word_len = 0,
    }
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local words, chars = 0, 0
  for _, line in ipairs(lines) do
    for _ in line:gmatch("%S+") do
      words = words + 1
    end
    chars = chars + vim.fn.strchars(line)
  end
  -- Count the newline between each pair of lines (matches vim.fn.wordcount).
  if #lines > 1 then
    chars = chars + (#lines - 1)
  end

  return {
    words = words,
    chars = chars,
    sentences = 0, -- This function never counted sentences.
    paragraphs = 0,
    avg_sentence_len = 0,
    avg_word_len = 0,
  }
end
```

- [ ] **Step 3: Verify the file parses**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/basic.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 4: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: `basic_spec.lua` reports 26 / 5 (was 22 / 9 — four fast-count tests now pass). Full suite reports 91 / 28. No other spec file's count moves. The two invalid-buffer tests at `basic_spec.lua:455,464` (`handles invalid buffer (-1)`, `handles non-existent buffer (99999)`) MUST still pass — the `nvim_buf_is_valid` guard preserves their behavior.

If any count is outside the expected values, STOP and investigate before committing.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/basic.lua
git commit -m "fix(basic): get_fast_count honors passed bufnr

vim.fn.wordcount() always operates on the current buffer and
ignored the bufnr argument, so get_fast_count(bufnr) silently
returned counts for whichever buffer happened to be current at
call time. Production statusline path is unaffected (always
passes bufnr=0). Internal callers in show_comparison become
correct when comparing a non-current buffer. Unblocks the four
fast-count tests in tests/basic_spec.lua that exercise the
documented contract."
```

---

## Task 2: Cluster 2 — Update statusline test assertions for new return shape

**Files:**
- Modify: `~/projects/nvim-writing-metrics/tests/basic_spec.lua` (the `statusline integration` describe block at ~line 175-227)

**What's broken:** `M.get_statusline_string(bufnr)` returns `""` (empty string) for non-writing filetypes and a `{ text = ..., color = ... }` table otherwise. Three tests assert `assert.is_string(str)`, which fails for the table return. Lualine consumes both shapes natively, so the implementation is correct — the test assertions never caught up.

**What gets fixed:** Three tests in the `statusline integration` describe block: `returns statusline string`, `contains word count indicator`, `mode affects statusline output`. The fourth test in that block (`toggles statusline mode`) does NOT touch the return shape and stays untouched.

- [ ] **Step 1: Confirm the three targeted tests currently fail**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "statusline integration|Success: |Failed : " | head -20
```

Expected: `returns statusline string`, `contains word count indicator`, `mode affects statusline output` show as failures. `basic_spec.lua` overall reports 26 / 5 (post-Task-1 baseline).

- [ ] **Step 2: Add a local helper at the top of the describe block and update the three failing tests**

In `~/projects/nvim-writing-metrics/tests/basic_spec.lua`, find the `statusline integration` describe block (starts at ~line 175):

```lua
  describe("statusline integration", function()
    it("returns statusline string", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local str = basic.get_statusline_string(bufnr)

      assert.is_string(str)
    end)

    it("contains word count indicator", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local str = basic.get_statusline_string(bufnr)

      -- Should contain either word count text or icon
      local has_indicator = string.find(str, "words") or string.find(str, "󰗊") or string.find(str, "%d+")
      assert.is_true(has_indicator ~= nil)
    end)

    it("toggles statusline mode", function()
      -- Get initial mode
      local initial_mode = basic.statusline_mode

      -- Toggle
      basic.toggle_statusline_mode()
      local new_mode = basic.statusline_mode

      assert.are_not.equals(initial_mode, new_mode)

      -- Toggle back
      basic.toggle_statusline_mode()
      assert.equals(initial_mode, basic.statusline_mode)
    end)

    it("mode affects statusline output", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      -- Get string in fast mode
      basic.statusline_mode = "fast"
      local fast_str = basic.get_statusline_string(bufnr)

      -- Get string in accurate mode
      basic.statusline_mode = "accurate"
      local accurate_str = basic.get_statusline_string(bufnr)

      -- Strings should be different (one uses cache, one triggers accurate)
      assert.is_string(fast_str)
      assert.is_string(accurate_str)
    end)
  end)
```

Replace the entire `describe("statusline integration", ...)` block with:

```lua
  describe("statusline integration", function()
    -- get_statusline_string returns either:
    --   - "" (empty string) for non-writing filetypes
    --   - { text = "...", color = "..." } table otherwise
    -- Lualine accepts both shapes natively.
    local function statusline_text(v)
      if type(v) == "table" then
        return v.text
      end
      return v
    end

    it("returns statusline string", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local result = basic.get_statusline_string(bufnr)

      local text = statusline_text(result)
      assert.is_string(text)
    end)

    it("contains word count indicator", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local result = basic.get_statusline_string(bufnr)

      local text = statusline_text(result)
      -- Should contain either word count text or icon
      local has_indicator = string.find(text, "words") or string.find(text, "󰗊") or string.find(text, "%d+")
      assert.is_true(has_indicator ~= nil)
    end)

    it("toggles statusline mode", function()
      -- Get initial mode
      local initial_mode = basic.statusline_mode

      -- Toggle
      basic.toggle_statusline_mode()
      local new_mode = basic.statusline_mode

      assert.are_not.equals(initial_mode, new_mode)

      -- Toggle back
      basic.toggle_statusline_mode()
      assert.equals(initial_mode, basic.statusline_mode)
    end)

    it("mode affects statusline output", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      -- Get string in fast mode
      basic.statusline_mode = "fast"
      local fast_result = basic.get_statusline_string(bufnr)

      -- Get string in accurate mode
      basic.statusline_mode = "accurate"
      local accurate_result = basic.get_statusline_string(bufnr)

      -- Strings should be different (one uses cache, one triggers accurate)
      assert.is_string(statusline_text(fast_result))
      assert.is_string(statusline_text(accurate_result))
    end)
  end)
```

The `toggles statusline mode` test is preserved verbatim (it doesn't reference the return value).

- [ ] **Step 3: Verify the file parses**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile tests/basic_spec.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 4: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: `basic_spec.lua` reports 29 / 2 (was 26 / 5 — three statusline tests now pass). Full suite reports 94 / 25. No other spec file's count moves.

If any count is outside expected, STOP and investigate before committing.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add tests/basic_spec.lua
git commit -m "test(basic): update statusline assertions for {text,color} shape

get_statusline_string returns a {text, color} table for writing
filetypes (and \"\" for non-writing). Tests asserted is_string on
the raw return, which fails for the table. Adds a local
statusline_text() helper that extracts .text from tables and
passes strings through, then routes the three failing assertions
through it. The empty-string non-writing-filetype path remains
covered by the string-passthrough branch. The toggles
statusline mode test is unchanged."
```

---

## Task 3: Cluster 3 — Fix async timing in "strips markdown" test

**Files:**
- Modify: `~/projects/nvim-writing-metrics/tests/basic_spec.lua` (the `strips markdown syntax` test at ~line 105-123)

**What's broken:** The test calls `helpers.wait_for_async(predicate, 3000)`, which returns silently on timeout. The next line dereferences `result_data.words` without first checking `result_data` is non-nil. If Pandoc hasn't completed within 3000ms (slow CI, slow Pandoc startup), the dereference crashes with `attempt to index a nil value` instead of a useful diagnostic. The abbreviation tests further down the file (lines 264, 282, 302) already use 5000ms for similar Pandoc-dependent assertions.

**What gets fixed:** One test (`strips markdown syntax`).

- [ ] **Step 1: Confirm the test currently fails**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "strips markdown|Success: |Failed : " | head -10
```

Expected: `strips markdown syntax` shows as failure. `basic_spec.lua` overall reports 29 / 2 (post-Task-2 baseline).

- [ ] **Step 2: Update the test's wait + add explicit nil check**

In `~/projects/nvim-writing-metrics/tests/basic_spec.lua`, find the test body (around line 105-123). The current `wait_for_async` call and assertion block:

```lua
      helpers.wait_for_async(function()
        return result_data ~= nil
      end, 3000)

      -- Accurate count should be less than fast count due to markdown stripping
      local fast_result = basic.get_fast_count(bufnr)
      assert.is_true(result_data.words <= fast_result.words)
    end)
```

Replace with:

```lua
      helpers.wait_for_async(function()
        return result_data ~= nil
      end, 5000)

      assert.is_not_nil(result_data, "Pandoc callback did not complete within 5000ms")

      -- Accurate count should be less than fast count due to markdown stripping
      local fast_result = basic.get_fast_count(bufnr)
      assert.is_true(result_data.words <= fast_result.words)
    end)
```

Two changes: timeout `3000` → `5000`, and a new explicit `assert.is_not_nil` before the dereference.

- [ ] **Step 3: Verify the file parses**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile tests/basic_spec.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 4: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: `basic_spec.lua` reports 30 / 1 (was 29 / 2 — the markdown-stripping test now passes). Full suite reports 95 / 24. No other spec file's count moves.

If any count is outside expected, STOP and investigate before committing.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add tests/basic_spec.lua
git commit -m "test(basic): raise async timeout + assert callback ran

The strips markdown syntax test waited 3000ms for the Pandoc
callback then dereferenced result_data.words without checking
that the callback actually fired. On slow CI the deref crashed
with attempt to index a nil value, masking the real timeout.
Raises the timeout to 5000ms (matching the abbreviation tests
at lines 264/282/302) and adds an explicit assert.is_not_nil
with a descriptive message so future timeouts surface clearly."
```

---

## Task 4: Cluster 4 — Fix lualine component assertion

**Files:**
- Modify: `~/projects/nvim-writing-metrics/tests/basic_spec.lua` (the `component has required fields` test at ~line 244-249)

**What's broken:** `M.lualine_component()` returns a table in lualine's documented format: `{ render_fn, cond = ..., color = ... }`. The render function is at `component[1]`, not `component.update`. The test was written against a different lualine convention.

**What gets fixed:** One test (`component has required fields`).

- [ ] **Step 1: Confirm the test currently fails**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "lualine integration|Success: |Failed : " | head -10
```

Expected: `component has required fields` shows as failure. `basic_spec.lua` overall reports 30 / 1 (post-Task-3 baseline).

- [ ] **Step 2: Update the assertion**

In `~/projects/nvim-writing-metrics/tests/basic_spec.lua`, find the test body (around line 244-249):

```lua
    it("component has required fields", function()
      local component = basic.lualine_component()

      -- Should be callable or have function field
      assert.is_true(type(component) == "function" or type(component.update) == "function")
    end)
```

Replace with:

```lua
    it("component has required fields", function()
      local component = basic.lualine_component()

      -- Lualine's documented format: { render_fn, cond = ..., color = ... }
      assert.is_function(component[1])
    end)
```

- [ ] **Step 3: Verify the file parses**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile tests/basic_spec.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output.

- [ ] **Step 4: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: `basic_spec.lua` reports 31 / 0 (was 30 / 1 — the lualine test now passes). Full suite reports 96 / 23. No other spec file's count moves.

If any count is outside expected, STOP and investigate before committing.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add tests/basic_spec.lua
git commit -m "test(basic): assert lualine render fn at component[1]

The previous assertion checked for component.update, but
lualine_component() returns lualine's standard format:
{ render_fn, cond = ..., color = ... } where the render function
lives at component[1]. Closes the final basic_spec failure and
takes basic_spec.lua to 31 / 0."
```

---

## Final verification

After all four tasks land, run:

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: 9 spec files with the breakdown matching the table — totals 96 / 23.

```bash
cd ~/projects/nvim-writing-metrics
git log --oneline b819360..HEAD
```

Expected: 4 commits, prefixed `fix(basic)`, `test(basic)`, `test(basic)`, `test(basic)`.

---

## Holistic review

Per the spec, Plan E uses one holistic review at the end. Dispatch one code-reviewer subagent against the cumulative diff:

```bash
cd ~/projects/nvim-writing-metrics
git diff b819360 HEAD --stat
git diff b819360 HEAD
```

Reviewer focus areas:

- **Cluster 1 correctness:** The rewritten `get_fast_count` loop matches `vim.fn.wordcount()`'s semantics closely enough that the existing tests pass — specifically the `chars > words` assertion in `counts characters`. The newline-count adjustment (`+1 per gap`) is consistent with how `vim.fn.wordcount()` returns `chars` (which counts newlines as one char each).
- **Cluster 1 boundary:** The `nvim_buf_is_valid` guard returns the zero-table shape and prevents the invalid-buffer tests (lines 455, 464) from regressing.
- **Cluster 2 test fidelity:** The `statusline_text` helper handles both shapes; the empty-string non-writing-filetype path is still implicitly covered by the string-passthrough branch. The `toggles statusline mode` test is unchanged.
- **Cluster 3 diagnostic quality:** The `assert.is_not_nil` message is descriptive enough to point at the real cause (Pandoc timeout vs implementation bug).
- **Cluster 4 assertion accuracy:** `assert.is_function(component[1])` matches lualine's documented component format.
- **No scope creep:** Diff contains only the four targeted clusters' edits; no incidental refactoring, no other spec files touched, no production code outside `get_fast_count`.
- **Baseline preservation:** Other spec files' pass/fail counts are unchanged from baseline.

---

## After completion

Delete the `project_nvim_writing_metrics_stale_tests.md` memory entry (it documented the 9 failures Plan E just fixed; keeping it would mislead future sessions). Update any in-flight plans' baseline notes from `87 / 32` to `96 / 23`.

## Summary

4 tasks, 4 commits on `main` of `~/projects/nvim-writing-metrics/`. ~50 lines of edits total (one production rewrite + ~25 lines of test updates). Zero production behavior change visible to users. Estimated 20-30 minutes of focused work plus the holistic review.
