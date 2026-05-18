# Tier 1 + Tier 2 Code Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 3 BLOCKER and 12 HIGH findings from the code review of `nvim-writing-metrics` and `text-sharing.lua` — eliminating one LAN security exposure, two metric-corrupting filter bugs, and twelve correctness/lifecycle bugs across the two plugins.

**Architecture:** Two independent codebases. (1) `~/projects/nvim-writing-metrics/` — a Lua plugin with a Pandoc filter. Uses plenary.busted for tests, run via `./run-tests.sh`. (2) `~/.config/nvim/lua/plugins/text-sharing.lua` — a single-file plugin in the user's Neovim config (no tests; manual verification). Fix order: security first, then filter correctness (highest ROI on metrics), then cache/init plumbing, then display, then text-sharing remainder.

**Tech Stack:** Lua 5.1 (LuaJIT in Neovim), Pandoc Lua filter API, plenary.busted test framework, vim.system async API.

---

## Conventions

- **Plugin repo**: `~/projects/nvim-writing-metrics/` — has its own git history. All writing-metrics commits land here.
- **Config repo**: `~/.config/nvim/` — text-sharing fixes land here.
- **Run tests** (writing-metrics): `cd ~/projects/nvim-writing-metrics && ./run-tests.sh -t tests/<spec>.lua` for one spec, no args for all.
- **Test fixture filter run**: `pandoc /tmp/fixture.md --lua-filter=scripts/textmetrics.lua -t plain -M metrics_mode=basic` (basic mode emits 6 space-separated values to stdout).
- **Commit style**: imperative present, scope prefix (`fix:`, `test:`, `refactor:`). One task = one commit.

---

## Phase A: Security (Tier 1 BLOCKER #1)

### Task 1: Restrict HTTP server to loopback by default

**Files:**
- Modify: `/home/jkeim/.config/nvim/lua/plugins/text-sharing.lua:204`

The current command `python3 -m http.server %d --directory %s` binds to `0.0.0.0`, exposing the entire cwd to the LAN. Add `--bind 127.0.0.1` so the server is only reachable from the local machine. (Cross-device access via QR/Dropbox remains the primary intended share path; LAN-wide HTTP serving is rarely the right tool and never the right default.)

- [ ] **Step 1: Read the current cmd construction**

Read `/home/jkeim/.config/nvim/lua/plugins/text-sharing.lua` lines 197-225 to confirm the current code matches the assumption below.

- [ ] **Step 2: Replace the cmd line**

Edit `text-sharing.lua` line 204:

Old:
```lua
  local cmd = string.format("python3 -m http.server %d --directory %s", M.config.http_port, vim.fn.shellescape(cwd))
```

New:
```lua
  local cmd = string.format("python3 -m http.server %d --bind 127.0.0.1 --directory %s", M.config.http_port, vim.fn.shellescape(cwd))
```

- [ ] **Step 3: Update the notification to reflect loopback**

Same file, line 217-220. The current notification suggests using the LAN IP, which won't work with loopback binding. Update to print the loopback URL:

Old:
```lua
    local ip = vim.fn.system("hostname -I | awk '{print $1}'"):gsub("%s+", "")
    M.notify(
      string.format("HTTP server started on http://%s:%d\nServing: %s", ip, M.config.http_port, cwd),
      vim.log.levels.INFO
    )
```

New:
```lua
    M.notify(
      string.format("HTTP server started on http://127.0.0.1:%d (loopback only)\nServing: %s", M.config.http_port, cwd),
      vim.log.levels.INFO
    )
```

- [ ] **Step 4: Manual verification**

In a fresh nvim session in some non-sensitive directory:
1. `<leader>yh` — confirm notification reads "http://127.0.0.1:8000 (loopback only)".
2. From another device on the same network, try `curl http://<host-ip>:8000/` — should hang or refuse connection.
3. From the same machine: `curl http://127.0.0.1:8000/` — should return directory listing.
4. `<leader>yH` to stop the server.

- [ ] **Step 5: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/text-sharing.lua
git commit -m "fix(text-sharing): bind HTTP server to 127.0.0.1 by default

Previously exposed cwd to entire LAN. Loopback-only binding eliminates
network exposure; cross-device sharing should use QR or Dropbox paths."
```

---

## Phase B: Pandoc Filter Correctness (Tier 1 BLOCKER #2, #3 + Tier 2 HIGH #10, #11)

The Pandoc filter is the source of truth for all readability metrics. Four bugs here corrupt scores across all six formulas. Each gets a TDD-style task. Tests are added to `tests/full_spec.lua` (for metrics that surface in the full report) or `tests/basic_spec.lua` (for basic-mode metrics).

### Task 2: Stop counting words/chars/paragraphs in code blocks

**Files:**
- Modify: `~/projects/nvim-writing-metrics/scripts/textmetrics.lua` (Code + CodeBlock handlers)
- Test: `~/projects/nvim-writing-metrics/tests/basic_spec.lua` (add new `it()` block)

The filter currently increments `words`, `chars`, and `paragraphs` inside `Code` and `CodeBlock` handlers, contradicting the "clean prose only" docstring. A README with one large code fence gets denominator-polluted readability scores.

- [ ] **Step 1: Locate the Code and CodeBlock handlers**

Read `~/projects/nvim-writing-metrics/scripts/textmetrics.lua` and find the `Code = function(el)` and `CodeBlock = function(el)` blocks. (Per agent report: lines 791-810.) Confirm they currently call `el.text:gsub("%S+","")` to count words.

- [ ] **Step 2: Add a failing test**

Edit `~/projects/nvim-writing-metrics/tests/basic_spec.lua`. Inside the existing `describe("writing-metrics.basic", function() ... end)` block, near the other `describe("accurate word count", function()...)` group, add:

```lua
describe("accurate word count - code block exclusion", function()
  it("excludes fenced code block content from word counts", function()
    local content = [[
This is one prose sentence with five words.

```python
print("hello")
def foo():
    return 42
```

Another prose sentence with five words.
]]
    local bufnr = helpers.create_test_buffer(content)
    local done = false
    local result_words

    basic.get_accurate_count(bufnr, function(success, data)
      assert.is_true(success)
      result_words = data.words
      done = true
    end)

    helpers.wait_for_async(function() return done end, 5000)
    -- 10 prose words (5 + 5); 0 from code. Tolerate small parser-side variance (markdown headers, etc.).
    assert.is_true(result_words <= 12, "got " .. tostring(result_words) .. " words; code block likely not excluded")
    assert.is_true(result_words >= 10, "got " .. tostring(result_words) .. " words; prose appears under-counted")
  end)
end)
```

- [ ] **Step 3: Run test, expect failure**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/basic_spec.lua
```

Expected: the new test fails with a word count well above 12 (code-block words leaking in). All other tests still pass.

- [ ] **Step 4: Fix the filter**

In `scripts/textmetrics.lua`, replace both handlers. Find:

```lua
Code = function(el)
  _,n = el.text:gsub("%S+","")
  words = words + n
  chars = chars + #el.text
end,
CodeBlock = function(el)
  _,n = el.text:gsub("%S+","")
  words = words + n
  chars = chars + #el.text
  paragraphs = paragraphs + 1
end,
```

Replace with:

```lua
Code = function(el)
  -- Inline code is markup, not prose. Skip word/char/syllable counting.
  return el
end,
CodeBlock = function(el)
  -- Code blocks are not prose; exclude from readability denominators.
  return el
end,
```

- [ ] **Step 5: Run test, expect pass**

```bash
./run-tests.sh -t tests/basic_spec.lua
```

Expected: new test passes; all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add scripts/textmetrics.lua tests/basic_spec.lua
git commit -m "fix(filter): exclude code blocks from word/char/paragraph counts

Code and CodeBlock handlers were inflating readability denominators,
contradicting the 'clean prose only' contract. All six readability
formulas now compute on prose alone."
```

---

### Task 3: Fix sentence boundary on abbreviations and decimals

**Files:**
- Modify: `~/projects/nvim-writing-metrics/scripts/textmetrics.lua` (sentence-boundary logic in Str handler — agent reports line 754)
- Test: `~/projects/nvim-writing-metrics/tests/basic_spec.lua`

The Pandoc filter detects sentence boundaries via `el.text:match("[.!?]%s*$")` on each `Str` token. Pandoc emits "Dr.", "e.g.", "3.14" as standalone `Str` tokens, so every one is falsely classified as a sentence end.

- [ ] **Step 1: Locate the sentence-end logic**

Read `scripts/textmetrics.lua` around line 754. Find the block that increments `sentences` based on `[.!?]%s*$`. Note: you may need to read 20-30 lines of context to identify what state (e.g., a `current_sentence_text` table) is maintained across tokens.

- [ ] **Step 2: Add a failing test**

In `tests/basic_spec.lua`, add to the same `describe` block as Task 2:

```lua
describe("accurate word count - abbreviation handling", function()
  it("does not split sentences on common abbreviations", function()
    local content = "Dr. Smith arrived early. Mr. Jones was late. We use e.g., Python."
    local bufnr = helpers.create_test_buffer(content)
    local done, result_sentences = false, nil

    basic.get_accurate_count(bufnr, function(success, data)
      assert.is_true(success)
      result_sentences = data.sentences
      done = true
    end)

    helpers.wait_for_async(function() return done end, 5000)
    -- 3 sentences total; without the fix, abbreviations push this to 5+.
    assert.equals(3, result_sentences, "expected 3 sentences, got " .. tostring(result_sentences))
  end)

  it("does not split sentences on decimals", function()
    local content = "The price is $3.14 today. Tomorrow it rises to $4.20."
    local bufnr = helpers.create_test_buffer(content)
    local done, result_sentences = false, nil

    basic.get_accurate_count(bufnr, function(success, data)
      assert.is_true(success)
      result_sentences = data.sentences
      done = true
    end)

    helpers.wait_for_async(function() return done end, 5000)
    assert.equals(2, result_sentences, "expected 2 sentences, got " .. tostring(result_sentences))
  end)
end)
```

- [ ] **Step 3: Run test, expect failure**

```bash
./run-tests.sh -t tests/basic_spec.lua
```

Expected: both new tests fail with sentence counts inflated (5+ and 3+ respectively).

- [ ] **Step 4: Add abbreviation set and decimal guard in the filter**

In `scripts/textmetrics.lua`, near the top of the file (file-scope locals, before any handler functions), add:

```lua
-- Common English abbreviations that contain '.' but do not end sentences.
-- Compared case-insensitively against the token text with trailing '.' stripped.
local ABBREVIATIONS = {
  ["dr"] = true, ["mr"] = true, ["mrs"] = true, ["ms"] = true, ["jr"] = true, ["sr"] = true,
  ["e.g"] = true, ["i.e"] = true, ["etc"] = true, ["vs"] = true, ["cf"] = true,
  ["st"] = true, ["mt"] = true, ["fig"] = true, ["no"] = true, ["vol"] = true,
  ["ed"] = true, ["eds"] = true, ["op"] = true, ["pp"] = true, ["ch"] = true,
  ["u.s"] = true, ["u.s.a"] = true, ["u.k"] = true, ["a.m"] = true, ["p.m"] = true,
  ["ph.d"] = true, ["m.d"] = true, ["b.a"] = true, ["m.a"] = true,
}

-- Returns true if the token text (with optional surrounding punctuation) appears to be
-- a known abbreviation, not a true sentence terminator.
local function is_abbreviation(text)
  -- Strip trailing punctuation/whitespace; lowercase for case-insensitive match.
  local cleaned = text:gsub("[%s%.,;:!%?]+$", ""):lower()
  return ABBREVIATIONS[cleaned] == true
end

-- Returns true if the token is a decimal-bearing number like "3.14" or "$4.20".
-- Pattern: optional currency/leading non-digits, digits, dot, digits, optional trailing punct.
local function is_decimal_number(text)
  return text:match("%d+%.%d+") ~= nil
end
```

Then find the sentence-end check at line ~754. The current code (approximately):

```lua
if el.text:match("[.!?]%s*$") then
  sentences = sentences + 1
  -- ... reset current_sentence_text, etc.
end
```

Replace with:

```lua
if el.text:match("[.!?]%s*$")
   and not is_abbreviation(el.text)
   and not is_decimal_number(el.text) then
  sentences = sentences + 1
  -- ... existing reset logic unchanged
end
```

(Preserve all existing sentence-end side effects: resetting `current_sentence_text`, pushing to `sentence_lengths`, etc.)

- [ ] **Step 5: Run test, expect pass**

```bash
./run-tests.sh -t tests/basic_spec.lua
```

Expected: both new tests pass; existing tests still pass.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add scripts/textmetrics.lua tests/basic_spec.lua
git commit -m "fix(filter): handle abbreviations and decimals in sentence boundary detection

Previously, 'Dr.', 'e.g.', '3.14', etc. each falsely terminated a sentence.
This inflated the sentences denominator across all six readability formulas.
Added an abbreviation set and a decimal-number guard."
```

---

### Task 4: Stop excluding sentence-initial words as "proper nouns"

**Files:**
- Modify: `~/projects/nvim-writing-metrics/scripts/textmetrics.lua` (`is_complex` function — agent reports line 260)
- Test: `~/projects/nvim-writing-metrics/tests/full_spec.lua`

The `is_complex` function returns `false` for any word starting with a capital letter, treating it as a proper noun. But sentence-initial words are capitalized for syntactic reasons; they're often the most polysyllabic words. This systematically under-reports Gunning Fog and SMOG complex-word counts.

- [ ] **Step 1: Locate is_complex**

Read `scripts/textmetrics.lua` and find `local function is_complex` (~ line 260). Note that the function takes `word` and returns `false` for words starting with `%u`.

- [ ] **Step 2: Check whether sentence-start tracking already exists**

Search for `is_sentence_start` or similar state. The agent reports such a flag is maintained elsewhere in the filter (used by other handlers). If found, note the variable name — Task 3 (sentence boundaries) and this task share it. If not, this task must introduce it.

- [ ] **Step 3: Add a failing test**

In `tests/full_spec.lua`, add inside the main `describe` block:

```lua
describe("complex word counting - sentence-initial words", function()
  it("counts sentence-initial polysyllabic words as complex", function()
    -- 'Investigation', 'Researchers', 'Conclusions' are sentence-initial AND polysyllabic.
    -- They should be counted as complex words, not excluded as proper nouns.
    local content = [[
Investigation revealed serious problems.
Researchers conducted careful analysis.
Conclusions remain controversial.
]]
    local bufnr = helpers.create_test_buffer(content)
    local done, result = false, nil

    require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
      assert.is_true(success)
      result = data
      done = true
    end)

    helpers.wait_for_async(function() return done end, 5000)
    -- All three sentence-initial words ARE polysyllabic. None are proper nouns.
    -- Expect complex_words >= 3.
    assert.is_true(
      result.readability.complex_words >= 3,
      "expected >=3 complex words, got " .. tostring(result.readability.complex_words)
    )
  end)
end)
```

- [ ] **Step 4: Run test, expect failure**

```bash
./run-tests.sh -t tests/full_spec.lua
```

Expected: complex_words count is 0 or low, because each capitalized sentence-initial word is wrongly excluded.

- [ ] **Step 5: Fix is_complex to take a sentence_start flag**

In `scripts/textmetrics.lua`, change the `is_complex` signature and the proper-noun heuristic:

Old:
```lua
local function is_complex(word)
  -- Proper nouns excluded
  if word:match("^%u") then return false end
  -- ... rest of complexity check (syllables >= 3, etc.)
end
```

New:
```lua
local function is_complex(word, is_sentence_start)
  -- Proper-noun heuristic: capitalized AND not sentence-initial.
  -- Sentence-initial words are capitalized for syntactic reasons, not because they're names.
  if word:match("^%u") and not is_sentence_start then return false end
  -- ... rest of complexity check unchanged
end
```

Then find the call site(s) of `is_complex(word)` and thread the sentence-start flag through:

```lua
-- At the call site, where word_is_sentence_start is the existing flag:
if is_complex(word, word_is_sentence_start) then
  complex_words = complex_words + 1
end
```

If no such flag exists yet, introduce one: set it to `true` at the start of each sentence (initially `true`, set back to `true` after each sentence boundary increment, set to `false` after the first Str of a sentence is processed).

- [ ] **Step 6: Run test, expect pass**

```bash
./run-tests.sh -t tests/full_spec.lua
```

Expected: new test passes; existing tests still pass.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add scripts/textmetrics.lua tests/full_spec.lua
git commit -m "fix(filter): treat capitalized sentence-initial words as ordinary, not proper nouns

Gunning Fog and SMOG both depend on complex_words. Previously,
sentence-initial polysyllabic words were silently dropped from
the count via an over-broad proper-noun heuristic."
```

---

### Task 5: Fix variability monotonous-pattern average

**Files:**
- Modify: `~/projects/nvim-writing-metrics/scripts/textmetrics.lua` (variability detection, agent reports lines 625-650)
- Test: `~/projects/nvim-writing-metrics/tests/full_spec.lua`

The "monotonous pattern" detector reports `avg_length = (min + max) / 2`, which is the midpoint, not the mean. For a 6-sentence pattern `[15, 16, 15, 21, 15, 16]`, the code reports avg = 18 when the true mean is ~16.3.

- [ ] **Step 1: Locate the pattern-detection block**

Read `scripts/textmetrics.lua` lines 620-660. Find the loop that accumulates `pattern_count` and the table-insertion site that writes `avg_length = (min + max) / 2`.

- [ ] **Step 2: Add a failing test**

In `tests/full_spec.lua`:

```lua
describe("variability - monotonous pattern average", function()
  it("reports the actual mean, not (min+max)/2", function()
    -- Six sentences crafted so min+max midpoint differs from true mean.
    -- Lengths: 15, 16, 15, 21, 15, 16 → mean ≈ 16.33, midpoint = 18.
    local function s(n)
      local words = {}
      for i = 1, n do words[i] = "word" end
      return table.concat(words, " ") .. "."
    end
    local content = s(15) .. " " .. s(16) .. " " .. s(15) .. " " .. s(21) .. " " .. s(15) .. " " .. s(16)
    local bufnr = helpers.create_test_buffer(content)
    local done, result = false, nil

    require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
      assert.is_true(success)
      result = data
      done = true
    end)

    helpers.wait_for_async(function() return done end, 5000)

    local patterns = result.variability and result.variability.patterns or {}
    assert.is_true(#patterns >= 1, "expected at least one monotonous pattern detected")
    local avg = patterns[1].avg_length
    -- True mean is ~16.33. Tolerate +/- 1 for sentence-end-period tokenization variance.
    assert.is_true(
      math.abs(avg - 16.33) < 1.5,
      "expected avg ~16.3, got " .. tostring(avg) .. " (likely the (min+max)/2 = 18 bug)"
    )
  end)
end)
```

- [ ] **Step 3: Run test, expect failure**

```bash
./run-tests.sh -t tests/full_spec.lua
```

Expected: avg is ~18, not ~16.3.

- [ ] **Step 4: Fix the pattern accumulator**

In `scripts/textmetrics.lua`, find the variability pattern loop (~ line 625). The current logic maintains `pattern_start` and `pattern_count` but does not sum the lengths.

Add a `pattern_sum` accumulator that adds each sentence length as it joins the pattern, and use it for `avg_length`:

Locate the loop body where `pattern_count` is incremented. Add `pattern_sum = pattern_sum + sentence_lengths[i]` alongside. At pattern start, initialize `pattern_sum = sentence_lengths[i-1] + sentence_lengths[i]`.

Then in the table-insertion site, replace:

```lua
avg_length = (min_in_pattern + max_in_pattern) / 2,
```

with:

```lua
avg_length = pattern_sum / (pattern_count + 1),
```

(The `+ 1` is because `pattern_count` counts the number of *additional* sentences after the first.)

Reset `pattern_sum = 0` when the pattern ends.

- [ ] **Step 5: Run test, expect pass**

```bash
./run-tests.sh -t tests/full_spec.lua
```

Expected: new test passes; existing pattern-detection tests still pass.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add scripts/textmetrics.lua tests/full_spec.lua
git commit -m "fix(filter): report true mean for monotonous-pattern avg_length

Previously used (min+max)/2 (midpoint), which can diverge sharply from
the actual mean. Track running sum across the pattern and divide by
the sentence count."
```

---

## Phase C: Cache & Init Plumbing (Tier 2 HIGH #3-6)

### Task 6: Respect stale flag in get_metrics

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua:111-117`
- Test: `~/projects/nvim-writing-metrics/tests/integration_spec.lua`

`cache.get_basic()` returns `(data, is_stale)`. `init.lua:111-117` discards the stale flag and returns cached data unconditionally. After any `TextChanged`, `<leader>mc` returns stale metrics until something else overwrites the cache.

- [ ] **Step 1: Read the current code**

Read `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` lines 100-130 to see the `get_metrics` function and the cache check.

- [ ] **Step 2: Add a failing test**

In `~/projects/nvim-writing-metrics/tests/integration_spec.lua`, add:

```lua
describe("get_metrics - cache stale handling", function()
  it("recomputes after content change instead of returning stale data", function()
    local init = require("writing-metrics")
    local cache = require("writing-metrics.cache")

    local bufnr = helpers.create_test_buffer("Two words.")
    local first_result, second_result
    local done1, done2 = false, false

    -- First call: populates cache.
    init.get_metrics(bufnr, "basic", function(success, data)
      first_result = data
      done1 = true
    end)
    helpers.wait_for_async(function() return done1 end, 5000)
    assert.equals(2, first_result.words)

    -- Mark cache stale (simulates TextChanged).
    cache.invalidate(bufnr)

    -- Replace buffer content.
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Four words here now actually five." })

    -- Second call: must NOT return cached "Two words" data.
    init.get_metrics(bufnr, "basic", function(success, data)
      second_result = data
      done2 = true
    end)
    helpers.wait_for_async(function() return done2 end, 5000)

    assert.is_true(second_result.words > 2, "got " .. tostring(second_result.words) .. " words; cache returned stale data")
  end)
end)
```

- [ ] **Step 3: Run test, expect failure**

```bash
./run-tests.sh -t tests/integration_spec.lua
```

Expected: second_result.words equals 2 (stale), not 5.

- [ ] **Step 4: Fix init.lua to honor the stale flag**

Edit `lua/writing-metrics/init.lua`. Find the block (around line 111-117):

Old:
```lua
  if mode == "basic" then
    local cached = cache.get_basic(bufnr)
    if cached then
      callback(true, cached)
      return
    end
  end
```

New:
```lua
  if mode == "basic" then
    local cached, is_stale = cache.get_basic(bufnr)
    if cached and not is_stale then
      callback(true, cached)
      return
    end
  end
```

- [ ] **Step 5: Run test, expect pass**

```bash
./run-tests.sh -t tests/integration_spec.lua
```

Expected: new test passes; existing tests still pass.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/init.lua tests/integration_spec.lua
git commit -m "fix(init): respect cache stale flag in get_metrics

Previously, get_metrics returned cached data even when cache.invalidate
had marked it stale, so the statusline kept showing pre-edit counts.
Now treats stale as a miss and triggers fresh computation."
```

---

### Task 7: Remove cache entries on BufDelete (don't just mark stale)

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua:183-188`
- Test: `~/projects/nvim-writing-metrics/tests/cache_spec.lua`

The `BufDelete` autocmd currently calls `cache.invalidate(bufnr)` which only marks the entry stale. Entries leak across the entire Neovim session.

- [ ] **Step 1: Read the autocmd setup**

Read `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua` lines 170-200 to see the `setup_autocmds` function and the `BufDelete`/`BufWipeout` handlers.

- [ ] **Step 2: Add a failing test**

In `tests/cache_spec.lua`, inside the main `describe("writing-metrics.cache", function() ... end)`:

```lua
describe("buffer lifecycle", function()
  it("removes cache entries when buffer is deleted, not just marks stale", function()
    cache.setup_autocmds()  -- assuming this idempotently wires the autocmds

    local bufnr = helpers.create_test_buffer("Some text.")
    cache.set_basic(bufnr, { words = 2, chars = 10, sentences = 1, paragraphs = 1 })

    -- Sanity: cache has entry.
    local before = cache.get_basic(bufnr)
    assert.is_not_nil(before)

    -- Delete the buffer; autocmd should fire.
    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- After deletion, cache table should not contain this entry.
    -- We inspect the cache internals: cache.basic is the internal table.
    -- (If cache module doesn't expose internals, expose a `cache.size()` helper or use cache.get_statistics().)
    local stats = cache.get_statistics()
    assert.equals(0, stats.basic_entries, "expected 0 entries after BufDelete, got " .. tostring(stats.basic_entries))
  end)
end)
```

If `cache.get_statistics()` does not return `basic_entries`, add that field — see the existing function and extend it if needed.

- [ ] **Step 3: Run test, expect failure**

```bash
./run-tests.sh -t tests/cache_spec.lua
```

Expected: stats.basic_entries == 1 (stale entry lingers).

- [ ] **Step 4: Fix BufDelete handler to actually remove**

Edit `cache.lua`. Find the autocmd block (~ line 180-200). Where `M.invalidate(args.buf)` is called from `BufDelete`/`BufWipeout`, replace with an actual delete.

Add a new function near the existing API:

```lua
-- Remove all cached entries for a buffer (called on BufDelete/BufWipeout).
function M.remove(bufnr)
  M.basic[bufnr] = nil
  if M.full then M.full[bufnr] = nil end
end
```

Then in the autocmd setup, update both BufDelete and BufWipeout callbacks:

Old:
```lua
vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
  group = group,
  callback = function(args)
    M.invalidate(args.buf)
  end,
})
```

New:
```lua
vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
  group = group,
  callback = function(args)
    M.remove(args.buf)
  end,
})
```

Keep `invalidate()` for the text-change autocmds (TextChanged*, BufWritePost) — that's still its correct use.

- [ ] **Step 5: Run test, expect pass**

```bash
./run-tests.sh -t tests/cache_spec.lua
```

Expected: new test passes; existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lua/writing-metrics/cache.lua tests/cache_spec.lua
git commit -m "fix(cache): actually delete entries on BufDelete instead of marking stale

invalidate() was being used for buffer destruction, but it only flags
stale and never removes. Across a long session this leaked unbounded.
Added M.remove(bufnr) for buffer-lifetime cleanup; invalidate() remains
for text-change staleness."
```

---

### Task 8: Make setup() idempotent and merge later opts

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua:30-77`
- Test: `~/projects/nvim-writing-metrics/tests/config_spec.lua`

`setup()` early-returns on `M._initialized`, silently dropping user opts on the second call. The auto-init at line 514-521 fires with empty opts and races user-supplied `setup({...})` non-deterministically.

- [ ] **Step 1: Read setup()**

Read `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` lines 25-80 and lines 510-525 (the auto-init block).

- [ ] **Step 2: Add a failing test**

In `tests/config_spec.lua`:

```lua
describe("setup idempotency", function()
  it("merges opts from second setup() call instead of dropping them", function()
    package.loaded["writing-metrics"] = nil
    package.loaded["writing-metrics.config"] = nil
    local init = require("writing-metrics")
    local config = require("writing-metrics.config")

    -- First call: auto-init style, no opts.
    init.setup({})

    -- Second call: user provides explicit opts.
    init.setup({ features = { readability = false } })

    -- Verify user opts were applied.
    assert.equals(false, config.config.features.readability,
      "second setup() call did not apply user opts")
  end)
end)
```

- [ ] **Step 3: Run test, expect failure**

```bash
./run-tests.sh -t tests/config_spec.lua
```

Expected: features.readability is still true (default), since second `setup()` was a no-op.

- [ ] **Step 4: Fix setup() to re-apply config on every call**

Edit `lua/writing-metrics/init.lua`. Find:

Old:
```lua
function M.setup(opts)
  if M._initialized then return true end
  -- ... rest of setup
  M._initialized = true
  return true
end
```

New:
```lua
function M.setup(opts)
  -- Always merge opts via config.setup so subsequent calls override defaults.
  config.setup(opts or {})

  -- One-time side-effect initialization (autocmds, validators, etc.) below this guard.
  if M._initialized then return true end
  -- ... move only the truly-one-time setup (autocmds, pandoc validation, user-commands)
  -- here, leaving config merging above.
  M._initialized = true
  return true
end
```

You'll need to identify which lines in the existing `setup()` are config merging (move above guard) vs one-time side effects (leave below guard).

Also remove the auto-init block at lines 514-521 entirely — LazyVim's `ft` spec already triggers `require("writing-metrics")` and the user's `opts = {...}` config will call `setup()` explicitly via the LazyVim plugin spec. Auto-init was racing this.

- [ ] **Step 5: Run test, expect pass**

```bash
./run-tests.sh -t tests/config_spec.lua
```

Expected: new test passes; existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lua/writing-metrics/init.lua tests/config_spec.lua
git commit -m "fix(init): make setup() idempotent and remove racing auto-init

Auto-init via vim.schedule(M.setup) at module load was firing with empty
opts and racing user-supplied setup({...}) non-deterministically. Removed
the auto-init; setup() now always re-runs config merge so second calls
with explicit opts are honored. One-time side effects still guarded."
```

---

### Task 9: Short-circuit cache hash recompute on TextChangedI thrashing

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua:150` (TextChangedI handler)
- Test: existing `tests/cache_spec.lua` (manual perf observation only)

`TextChangedI` fires on every keystroke in insert mode. The handler runs `content_changed` → `get_content_hash` → `nvim_buf_get_lines` + `table.concat` + format. For a 10k-word doc this is wasted work after the cache is already stale.

- [ ] **Step 1: Read the autocmd block**

Read `~/projects/nvim-writing-metrics/lua/writing-metrics/cache.lua` lines 140-170 to identify the TextChangedI handler.

- [ ] **Step 2: Replace content-hash check with changedtick comparison**

Use `vim.b[bufnr].changedtick`, which is a monotonically increasing per-buffer integer maintained by Neovim. It's free to read and cannot collide.

In `cache.lua`, modify the `content_changed(bufnr)` function (existing function — find it):

Old (rough shape):
```lua
function M.content_changed(bufnr)
  local hash = utils.get_content_hash(bufnr)
  local entry = M.basic[bufnr]
  if not entry or entry.hash ~= hash then
    return true
  end
  entry.hash = hash
  return false
end
```

New:
```lua
function M.content_changed(bufnr)
  local tick = vim.b[bufnr].changedtick
  local entry = M.basic[bufnr]
  if not entry or entry.changedtick ~= tick then
    return true
  end
  return false
end
```

And update `M.set_basic` (find it) to store `changedtick`:

```lua
function M.set_basic(bufnr, data)
  M.basic[bufnr] = {
    data = data,
    timestamp = vim.uv.now(),  -- or vim.loop.now() if uv not present
    changedtick = vim.b[bufnr].changedtick,
    stale = false,
  }
end
```

Update `M.invalidate(bufnr)` to clear the changedtick so the next `content_changed` returns true:

```lua
function M.invalidate(bufnr)
  if M.basic[bufnr] then
    M.basic[bufnr].stale = true
    M.basic[bufnr].changedtick = -1  -- force mismatch on next check
  end
end
```

Now the per-keystroke `TextChangedI` handler short-circuits because `entry.changedtick` mismatches once stale; no expensive hash recompute.

- [ ] **Step 3: Run all cache tests to ensure nothing broke**

```bash
./run-tests.sh -t tests/cache_spec.lua
```

Expected: all tests pass. (No new test for this one; the perf improvement is structural.)

- [ ] **Step 4: Run full suite**

```bash
./run-tests.sh
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lua/writing-metrics/cache.lua
git commit -m "perf(cache): use changedtick instead of content-hash for staleness check

TextChangedI fires every keystroke. Computing a content hash on each
fire wasted CPU on large docs. vim.b[].changedtick is monotonic per
buffer, free to read, and collision-free."
```

---

## Phase D: Parser Hardening (Tier 2 HIGH #12)

### Task 10: Validate parse_basic_output values are numeric

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua:158-189`
- Test: `~/projects/nvim-writing-metrics/tests/integration_spec.lua` (or new spec file)

`parse_basic_output` calls `tonumber(value)` and inserts the result without checking for `nil`. A non-numeric token in the output produces a `nil` in the values table; downstream `format_number(nil)` returns `"0"`, so a parse error silently becomes "0 words".

- [ ] **Step 1: Read the parser**

Read `~/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua` lines 155-195 to see `parse_basic_output`.

- [ ] **Step 2: Add a failing test**

In `tests/integration_spec.lua`:

```lua
describe("parse_basic_output - input validation", function()
  local utils = require("writing-metrics.utils")

  it("returns nil + error for non-numeric tokens", function()
    -- A line with 6 tokens but one is non-numeric.
    local result, err = utils.parse_basic_output("1247 7892 65 42 NaN 6.33")
    assert.is_nil(result)
    assert.is_string(err)
    assert.is_true(err:lower():find("numeric") ~= nil or err:lower():find("invalid") ~= nil,
      "error should mention non-numeric: " .. tostring(err))
  end)

  it("parses a valid 6-value line", function()
    local result, err = utils.parse_basic_output("1247 7892 65 42 19.18 6.33")
    assert.is_nil(err)
    assert.is_not_nil(result)
    assert.equals(1247, result.words)
    assert.equals(6.33, result.avg_word_len)
  end)
end)
```

- [ ] **Step 3: Run test, expect failure**

```bash
./run-tests.sh -t tests/integration_spec.lua
```

Expected: first test fails because result is not nil — silently returns a table with `result.avg_sentence_len = nil`.

- [ ] **Step 4: Fix parse_basic_output**

In `utils.lua`, find:

Old:
```lua
for value in metrics_line:gmatch("%S+") do
  table.insert(values, tonumber(value))
end
```

New:
```lua
for value in metrics_line:gmatch("%S+") do
  local n = tonumber(value)
  if not n then
    return nil, "Non-numeric value in metrics output: " .. value
  end
  table.insert(values, n)
end
```

- [ ] **Step 5: Run test, expect pass**

```bash
./run-tests.sh -t tests/integration_spec.lua
```

Expected: new tests pass; existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lua/writing-metrics/utils.lua tests/integration_spec.lua
git commit -m "fix(utils): reject non-numeric tokens in parse_basic_output

Previously, tonumber failure silently inserted nil into the values table.
Downstream, format_number(nil) renders as '0', so parse errors masqueraded
as 'document has 0 words'. Now returns nil + error from the parser."
```

---

## Phase E: Display Fixes (Tier 2 HIGH #7-9)

These three fixes don't have natural unit tests (UI-level, depend on tab/window state). Each task uses **manual verification** with a specific scenario.

### Task 11: Pass source bufnr through to format_report

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua:75` (and call sites)
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/full.lua` (call site of `format_report`)

`format_report` uses `nvim_buf_get_name(0)` for the report header. Because reports are generated inside a `vim.system` callback (async), the user may have switched buffers — header shows the wrong filename.

- [ ] **Step 1: Read format_report signature and call site**

Read `display.lua` around line 75 to find:
```lua
function M.format_report(data)
  ...
  table.insert(lines, "**Buffer:** " .. vim.api.nvim_buf_get_name(0))
```

And read `full.lua` to find where `format_report(data)` is called (likely inside `show_report`).

- [ ] **Step 2: Add source_bufnr parameter**

Edit `display.lua`:

Old:
```lua
function M.format_report(data)
  local lines = {}
  ...
  table.insert(lines, "**Buffer:** " .. vim.api.nvim_buf_get_name(0))
```

New:
```lua
function M.format_report(data, source_bufnr)
  local lines = {}
  ...
  local source_name
  if source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
    source_name = vim.api.nvim_buf_get_name(source_bufnr)
  else
    source_name = "(unknown buffer)"
  end
  table.insert(lines, "**Buffer:** " .. source_name)
```

- [ ] **Step 3: Update call sites to pass source bufnr**

Edit `full.lua` to thread the source bufnr through. Inside `show_report` (or whichever function captures the source buffer), pass `source_bufnr` to `format_report`:

```lua
-- Where format_report is called:
local lines = display.format_report(data, source_bufnr)
```

The `source_bufnr` is the buffer that was active when the user pressed `<leader>mr`. It should already be captured at the top of `show_report` (likely via `vim.api.nvim_get_current_buf()`).

- [ ] **Step 4: Manual verification**

1. Open `~/Documents/test1.md` (any markdown file). Press `<leader>mr`.
2. Before the report finishes generating, switch to another buffer: `:edit ~/Documents/test2.md` (any other file).
3. When the report tab opens, check the "**Buffer:**" header line — it should show the path to `test1.md`, not `test2.md` or empty.

- [ ] **Step 5: Commit**

```bash
git add lua/writing-metrics/display.lua lua/writing-metrics/full.lua
git commit -m "fix(display): thread source buffer through format_report

Previously read the current buffer name inside an async callback,
so the report header showed whatever buffer was focused when the
Pandoc job completed — often the wrong file if the user switched."
```

---

### Task 12: Remove dangerous Esc keymap from report buffer

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua:750-751`

`<Esc>` is mapped to `:close`. Users press Esc reflexively (to clear search highlights, dismiss completion, break out of pending operations) — wiping the report by accident. Also fails with `E444` when the report is the only window in a tab.

- [ ] **Step 1: Locate the Esc keymap**

Read `display.lua` lines 745-765 to find both `q` and `<Esc>` mappings on the report buffer.

- [ ] **Step 2: Delete the Esc mapping; keep q**

Old:
```lua
vim.keymap.set("n", "q", "<cmd>close<cr>", opts)
vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", opts)
```

New:
```lua
vim.keymap.set("n", "q", "<cmd>close<cr>", opts)
-- <Esc> intentionally NOT mapped: users press it reflexively for unrelated
-- reasons (clearing search highlight, breaking out of pending ops). Use q.
```

- [ ] **Step 3: Manual verification**

1. Open a markdown file, press `<leader>mr` to generate a report.
2. In the report tab, press `<Esc>` — report should remain open.
3. Press `q` — report should close.

- [ ] **Step 4: Commit**

```bash
git add lua/writing-metrics/display.lua
git commit -m "fix(display): stop binding <Esc> to close on report buffer

Users press Esc reflexively (clear search highlight, break out of
pending ops). The mapping wiped reports unintentionally and also
failed with E444 when the report was the sole window in its tab."
```

---

### Task 13: Normalize tracking-table keys for unnamed and symlinked buffers

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/display.lua:733-737`
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua:51-69` (BufDelete cleanup may need to match)

`_G.writing_metrics_reports` is keyed by raw filepath. Symlinks, relative-vs-absolute paths, and unnamed buffers all break the "regenerate updates existing report in place" promise.

- [ ] **Step 1: Read the tracking key construction**

Read `display.lua` lines 730-745. Find where `source_filepath` is computed and used as a key into `_G.writing_metrics_reports`. Also read `init.lua:50-70` for the BufDelete cleanup iterating that table.

- [ ] **Step 2: Add a path-normalization helper**

In `display.lua`, near the top of the module (or wherever helpers live), add:

```lua
-- Normalize a buffer's identity into a stable tracking key.
-- Named buffers → absolute resolved path.
-- Unnamed buffers → "unnamed:<bufnr>".
local function tracking_key(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return "unnamed:" .. tostring(bufnr)
  end
  return vim.fn.fnamemodify(name, ":p")
end
```

- [ ] **Step 3: Replace raw-filepath keying with the helper**

Find the existing keying code in `display.lua` (around line 733):

Old:
```lua
local source_filepath = vim.api.nvim_buf_get_name(source_bufnr)
if source_filepath ~= "" then
  _G.writing_metrics_reports[source_filepath] = bufnr
end
```

New:
```lua
local key = tracking_key(source_bufnr)
_G.writing_metrics_reports[key] = bufnr
```

Find any read sites (`_G.writing_metrics_reports[some_path]`) and route them through `tracking_key(bufnr)` instead of raw paths.

- [ ] **Step 4: Update BufDelete cleanup**

In `init.lua` (lines ~50-70), the cleanup iterates `_G.writing_metrics_reports` to find entries to delete on BufDelete. Make sure the cleanup logic doesn't rely on key shape — it iterates by value (bufnr) to find entries to nil, so it should already be agnostic. Verify by reading the cleanup loop. If it does match keys, update accordingly.

- [ ] **Step 5: Manual verification**

1. Open `~/foo.md` (a real file). Press `<leader>mr` → report opens.
2. Press `<leader>mr` again → existing report regenerates in-place (no new tab).
3. Open a new scratch buffer (`:enew`), set filetype: `:set ft=markdown`, paste some prose. Press `<leader>mr` → report opens.
4. Press `<leader>mr` again from the scratch → existing scratch's report regenerates in-place.
5. Open `~/foo.md` via a symlink at `~/link-foo.md`. Press `<leader>mr` from `~/link-foo.md` → distinct report (different absolute path is fine; the bug is when two distinct buffers collide on the same key, not when the same file via different paths produces two).

- [ ] **Step 6: Commit**

```bash
git add lua/writing-metrics/display.lua lua/writing-metrics/init.lua
git commit -m "fix(display): normalize tracking keys to support unnamed buffers and absolute paths

Previously keyed by raw buffer name, so unnamed buffers couldn't
regenerate in place (always made a new report) and symlinked or
relative-path views collided in unintended ways. Now uses resolved
absolute path for named buffers, bufnr-suffixed sentinel for unnamed."
```

---

## Phase F: text-sharing Functional Fixes (Tier 2 HIGH #1-2 for text-sharing)

### Task 14: Make visual-mode keymaps actually use the selection

**Files:**
- Modify: `/home/jkeim/.config/nvim/lua/plugins/text-sharing.lua` (keymap registration around line 243, get_text logic at lines 13-39)

Current `{ "n", "v" }` keymaps with a single callback that reads `vim.fn.mode()` always fall through to "whole buffer" because by the time the callback runs, mode has reset. Fix by registering separate keymaps and reading the selection via the canonical yank-to-register pattern.

- [ ] **Step 1: Read the relevant blocks**

Read `text-sharing.lua` lines 13-50 (get_text) and lines 240-260 (setup_keybindings).

- [ ] **Step 2: Add a get_visual_text helper**

Insert near the existing `M.get_text`:

```lua
-- Get visual selection text by yanking into a scratch register.
-- Must be called from a visual-mode keymap callback (mode = "x" or "v").
function M.get_visual_text()
  -- Yank current selection into register 't' (scratch), preserving unnamed register.
  local saved = vim.fn.getreg('"')
  local saved_type = vim.fn.getregtype('"')
  vim.cmd('silent noautocmd normal! "ty')
  local text = vim.fn.getreg("t")
  vim.fn.setreg('"', saved, saved_type)
  vim.fn.setreg("t", "")
  return text
end
```

- [ ] **Step 3: Split share callbacks into normal vs visual entry points**

Wrap each user-facing action (share_to_dropbox, generate_qr_code) so it can be invoked from either mode with the right text source. Add small wrappers:

```lua
function M.share_to_dropbox_normal()
  M._share_text_to_dropbox(M.get_text("n"))
end

function M.share_to_dropbox_visual()
  M._share_text_to_dropbox(M.get_visual_text())
end

function M.generate_qr_code_normal()
  M._generate_qr_from_text(M.get_text("n"))
end

function M.generate_qr_code_visual()
  M._generate_qr_from_text(M.get_visual_text())
end
```

You'll need to refactor the bodies of the original `share_to_dropbox` and `generate_qr_code` to take the text as a parameter (`M._share_text_to_dropbox(text)`, `M._generate_qr_from_text(text)`). This is a focused extraction — pull the body unchanged.

- [ ] **Step 4: Replace dual-mode keymaps with mode-specific ones**

In `setup_keybindings`, replace:

Old:
```lua
vim.keymap.set({ "n", "v" }, "<leader>yd", M.share_to_dropbox, { desc = "yank: share to dropbox" })
...
vim.keymap.set({ "n", "v" }, "<leader>yq", M.generate_qr_code, { desc = "yank: generate qr code" })
```

New:
```lua
vim.keymap.set("n", "<leader>yd", M.share_to_dropbox_normal, { desc = "yank: share buffer to dropbox" })
vim.keymap.set("x", "<leader>yd", M.share_to_dropbox_visual, { desc = "yank: share selection to dropbox" })
...
vim.keymap.set("n", "<leader>yq", M.generate_qr_code_normal, { desc = "yank: qr code from buffer" })
vim.keymap.set("x", "<leader>yq", M.generate_qr_code_visual, { desc = "yank: qr code from selection" })
```

(Use mode `"x"` for visual-only, not `"v"` which includes select mode and behaves differently.)

- [ ] **Step 5: Manual verification**

1. Open a markdown file with multiple paragraphs.
2. Visually select one paragraph (`V`, j j j). Press `<leader>yd`.
3. Open `~/Dropbox/NvimShared/`. Verify the timestamped file contains *only the selected paragraph*, not the whole buffer.
4. Visually select a short string (< 300 chars). Press `<leader>yq`. Floating QR window should appear; the encoded data is the selection only.
5. Without visual selection, in normal mode, press `<leader>yd`. The shared file should contain the whole buffer.

- [ ] **Step 6: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/text-sharing.lua
git commit -m "fix(text-sharing): make visual-mode share keymaps use the actual selection

Combined {n,v} keymaps were calling vim.fn.mode() too late in the
event sequence, always falling through to whole-buffer. Split into
mode-specific keymaps and added get_visual_text() using the canonical
yank-to-register pattern."
```

---

### Task 15: Sandbox save_to_dropbox filename via basename

**Files:**
- Modify: `/home/jkeim/.config/nvim/lua/plugins/text-sharing.lua:97-121` (save_to_dropbox)

`vim.fn.fnameescape(filepath)` escapes Vim's special chars but does not strip `../`. A user-entered filename like `../../.ssh/authorized_keys` writes outside the Dropbox sandbox.

- [ ] **Step 1: Read save_to_dropbox**

Read `text-sharing.lua` lines 97-125. Identify where the user-supplied `filename` is concatenated with `M.config.dropbox_path`.

- [ ] **Step 2: Strip directory components from user input**

After receiving the filename from `vim.ui.input`, strip any path traversal by taking only the basename:

Find the existing callback inside `vim.ui.input`:

Old:
```lua
vim.ui.input({
  prompt = "Save to Dropbox as: ",
  default = default_name,
}, function(filename)
  if not filename or filename == "" then
    return
  end

  local filepath = M.config.dropbox_path .. "/" .. filename
  vim.cmd("write " .. vim.fn.fnameescape(filepath))
  M.notify("Saved to Dropbox: " .. filename)
end)
```

New:
```lua
vim.ui.input({
  prompt = "Save to Dropbox as: ",
  default = default_name,
}, function(filename)
  if not filename or filename == "" then
    return
  end

  -- Strip any directory components: user cannot escape the Dropbox folder.
  local safe_name = vim.fs.basename(filename)
  if safe_name == "" or safe_name == "." or safe_name == ".." then
    M.notify("Invalid filename: " .. filename, vim.log.levels.ERROR)
    return
  end

  local filepath = M.config.dropbox_path .. "/" .. safe_name
  vim.cmd("write " .. vim.fn.fnameescape(filepath))
  M.notify("Saved to Dropbox: " .. safe_name)
end)
```

Also update the `default_name` calculation a few lines earlier to apply `basename`:

Old:
```lua
local default_name = current_file ~= "" and current_file or M.generate_filename("document", extension)
```

New:
```lua
local default_name = current_file ~= "" and vim.fs.basename(current_file) or M.generate_filename("document", extension)
```

- [ ] **Step 3: Manual verification**

1. Open any file, say `~/.bashrc`. Press `<leader>yD`. At the prompt, the default should be `.bashrc` (basename only), not `/home/jkeim/.bashrc`.
2. Clear the prompt, type `../../tmp/escape.txt`. Press Enter. The file should be saved to `~/Dropbox/NvimShared/escape.txt` (basename used), not `/tmp/escape.txt`. Verify by `ls ~/Dropbox/NvimShared/` and `ls /tmp/escape.txt 2>/dev/null` — the latter should not exist.
3. Empty filename → no save (existing behavior).
4. Just `..` or `.` → error notification, no save.

- [ ] **Step 4: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/text-sharing.lua
git commit -m "fix(text-sharing): sandbox save_to_dropbox filename to basename

fnameescape doesn't strip ../ segments. A user typing or pasting a
path-traversal filename would silently write outside the Dropbox
folder. Now strips to basename and rejects . / .. /empty."
```

---

## Final verification

After all 15 tasks land, run both suites end to end:

- [ ] **Run the full writing-metrics test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh
```

Expected: every spec passes. Note any flaky or new failures and triage.

- [ ] **Manual smoke test in Neovim**

1. Open Neovim on a real markdown file.
2. Press `<leader>mc` → word count window appears.
3. Edit the document. Press `<leader>mc` again → counts updated (not stale).
4. Press `<leader>mr` → full report tab opens; header shows correct filename.
5. Press `q` (not Esc) → closes report.
6. Switch buffers and run `<leader>mr` on each → distinct reports per source.
7. Press `<leader>yh`, verify notification reads `127.0.0.1`.
8. Visually select text, press `<leader>yd`. Confirm only the selection landed in Dropbox.
9. Press `<leader>yD`, try to enter `../escape.txt` → blocked or stripped to basename.

- [ ] **Update CLAUDE.md**

Update `/home/jkeim/.config/nvim/CLAUDE.md` "Common Issues and Solutions" section to remove the `table.concat line 863` entry (now diagnosed and fixable separately) and reflect that the abbreviation/code-block/proper-noun bugs are resolved. Also remove the false "Smart cache extraction: Basic metrics extracted from full reports (~60% fewer Pandoc calls)" claim — this code path does not exist (or implement it as a follow-up task).

- [ ] **Final commit**

```bash
cd ~/.config/nvim
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md after tier 1/2 fixes

Removed the table.concat-line-863 known-issue entry (root-caused but
deferred); removed unimplemented 'smart cache extraction' claim."
```

---

## Summary

15 tasks: 3 BLOCKER + 12 HIGH. Estimated 3-5 hours total focused work, broken into atomic commits. After completion: no LAN-exposed HTTP server, accurate readability scores on documents with abbreviations/decimals/code blocks, working cache invalidation, working visual-mode share, no path traversal in Dropbox save, idempotent setup.

Deferred to a later pass: all MEDIUM and LOW/NIT findings (parse_full_output JSON greedy, get_content_hash collisions, HTTP server stale state, os.tmpname race, list-item double-counting, deprecated APIs, etc.). These are real bugs but not user-blocking.
