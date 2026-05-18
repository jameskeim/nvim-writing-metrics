# Plan G — `config_spec.lua` cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close all 6 failures in `tests/config_spec.lua` by adding the `M.get()` accessor, renaming `filter.custom_path` → `filter.path`, giving `filter.auto_detect = false` real semantics, and clearing the `_filter_path` cache in `setup()`; then sweep 13 direct `config.config.X` reads in the rest of `lua/` to use the new `config.get()` accessor for consistency.

**Architecture:** Three commits on `main` of `~/projects/nvim-writing-metrics/`. Commit 1 makes the four coupled config-module changes (one bundled commit so the failure-count drop is attributable to a coherent unit). Commit 2 is the pure mechanical migration of 13 call sites. Commit 3 adds a CHANGELOG entry. Per the convention established by Plans C, E, F, Plan G uses one holistic review at the end against the cumulative diff.

**Tech Stack:** Lua 5.1 (LuaJIT in Neovim), `vim.tbl_deep_extend` for opts merging, `vim.fn.filereadable` for path validation, `busted`/`plenary.test_harness` for tests.

---

## Conventions

- **Plugin repo:** `~/projects/nvim-writing-metrics/` — git-tracked, commits land directly on `main`.
- **Run tests:** `cd ~/projects/nvim-writing-metrics && ./run-tests.sh` (all specs).
- **Spec reference:** `~/.config/nvim/docs/superpowers/specs/2026-05-17-plan-g-config-spec-cleanup-design.md`
- **Baseline (HEAD `f376ed5`, post-Plan F):** 109 pass / 10 fail across the full suite; `config_spec.lua` is 6 pass / 6 fail.
- **Target:** 115 pass / 4 fail full suite; `config_spec.lua` is 12 pass / 0 fail. The remaining 4 failures all live in `full_spec.lua` (test-isolation cluster, separate plan).

**Verification after each task:**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected progression:

| After commit | config_spec | Full suite |
|---|---|---|
| Baseline (post Plan F) | 6 / 6 | 109 / 10 |
| Task 1 (config fixes) | 12 / 0 | 115 / 4 |
| Task 2 (migrations) | 12 / 0 | 115 / 4 (unchanged) |
| Task 3 (changelog) | 12 / 0 | 115 / 4 (unchanged) |

If a task's count diverges from the table, STOP and investigate before committing.

**Note on "write the failing test first" steps:** Plan G is a cleanup, not a feature. The 6 failing tests already exist in `tests/config_spec.lua`. The "red" step in each task is "confirm the targeted tests currently fail" — not writing new tests.

---

## Task 1: Four coupled config-module changes

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua` (4 in-file changes)
- Modify: `~/projects/nvim-writing-metrics/tests/config_spec.lua` (1 assertion relaxation at line 42)

**Failures closed:** 6 (all 6 in `config_spec.lua`).

The four implementation changes are coupled — they share a single test file and a single commit so the failure-count drop from 6 → 0 is attributable to one coherent unit.

- [ ] **Step 1: Confirm the 6 targeted tests currently fail**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh -t tests/config_spec.lua 2>&1 | grep -aE "Success: |Failed : "
```

Expected: `Success: 6` / `Failed : 6`. The 6 failures cover:
- `exports expected functions` (line 24, missing `config.get`)
- `has valid default settings` (line 32, crashes on `config.get()` call)
- `has filter configuration` (line 40, crashes on `config.get()` then would fail on `defaults.filter.path` even after get() exists)
- `has command configuration` (line 47, crashes on `config.get()` call)
- `allows disabling legacy commands` (line 61, crashes on `config.get()` call)
- `can use custom filter path` (line 119, even with key rename: filereadable check rejects the test's `/custom/path/filter.lua`)

- [ ] **Step 2: Add `M.get()` accessor in `config.lua`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua`, find this block (around line 80):

```lua
--- Current active configuration (merged with user opts)
M.config = vim.deepcopy(M.defaults)
```

Replace with:

```lua
--- Current active configuration (merged with user opts)
M.config = vim.deepcopy(M.defaults)

--- Get the live merged configuration (defaults + any user opts from setup()).
--- Returns M.config by reference; callers must not mutate the returned table.
--- @return table Current active config
function M.get()
  return M.config
end
```

This is the simplest possible accessor — one-line body returning the live table. Future semantic changes (deepcopy, validation, lazy resolution) can land in this single function without touching any call site.

- [ ] **Step 3: Rename `filter.custom_path` → `filter.path` in defaults**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua`, find this block in `M.defaults` (around line 67-70):

```lua
  -- Pandoc filter settings
  filter = {
    auto_detect = true, -- Automatically find bundled filter
    custom_path = nil, -- Override with custom path
  },
```

Replace with:

```lua
  -- Pandoc filter settings
  filter = {
    auto_detect = true, -- When true, search the fallback chain if no path is set or if path is unreadable. When false, trust filter.path even if missing (downstream Pandoc surfaces clear errors).
    path = nil,         -- Explicit filter path. nil = use auto-detect.
  },
```

- [ ] **Step 4: Rewrite `M.find_filter()`'s user-path branch with `auto_detect` semantics**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua`, find this block at the top of `M.find_filter()` (around lines 96-103):

```lua
  -- If custom path specified, use it
  if M.config.filter.custom_path then
    if vim.fn.filereadable(M.config.filter.custom_path) == 1 then
      return M.config.filter.custom_path
    else
      return nil, "Custom filter path not found: " .. M.config.filter.custom_path
    end
  end

  local candidates = {}
```

Replace with:

```lua
  -- If an explicit path is specified, use it.
  -- When auto_detect=false, trust the user even if the file is missing
  -- (downstream Pandoc invocation will surface a clear error if so).
  -- When auto_detect=true, validate readability and fall back to the
  -- candidate search below on miss.
  if M.config.filter.path then
    if M.config.filter.auto_detect == false then
      return M.config.filter.path
    end
    if vim.fn.filereadable(M.config.filter.path) == 1 then
      return M.config.filter.path
    else
      return nil, "Custom filter path not found: " .. M.config.filter.path
    end
  end

  -- If the user opted out of auto-detect but provided no path, that's an error.
  if M.config.filter.auto_detect == false then
    return nil, "filter.auto_detect is false but no filter.path was provided"
  end

  local candidates = {}
```

This change does three things:
1. Renames the key (5th and final reference of `custom_path` in this file — `find_filter` had 4 references; combined with the defaults rename in Step 3 that's all 5 in-file references gone).
2. Adds the `auto_detect = false` + `path` set → return unconditionally branch (the cluster-3 fix).
3. Adds the `auto_detect = false` + `path = nil` → error branch (covers the previously-unhandled fourth quadrant of the truth table).

- [ ] **Step 5: Clear `_filter_path` cache at start of `M.setup()`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/config.lua`, find the start of `M.setup()` (around line 222):

```lua
--- Setup configuration with user options
--- @param opts table|nil User configuration
function M.setup(opts)
  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Validate dependencies
  local ok, err = M.validate_dependencies()
```

Replace with:

```lua
--- Setup configuration with user options
--- @param opts table|nil User configuration
function M.setup(opts)
  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Explicitly clear the resolved-filter-path cache so re-configuring takes
  -- effect even if a future refactor changes the merge to mutate M.config
  -- in place (instead of replacing it as the line above does).
  M.config._filter_path = nil

  -- Validate dependencies
  local ok, err = M.validate_dependencies()
```

The cache clear is technically redundant today because the `M.config = vim.tbl_deep_extend(...)` line replaces the whole table (so the old `_filter_path` field on the old table is naturally discarded). The explicit clear documents intent and survives a future refactor that mutates in place.

- [ ] **Step 6: Relax the `defaults.filter.path` assertion in `tests/config_spec.lua`**

In `~/projects/nvim-writing-metrics/tests/config_spec.lua`, find this test body (around lines 40-44):

```lua
    it("has filter configuration", function()
      local defaults = config.get()

      assert.is_string(defaults.filter.path)
      assert.is_boolean(defaults.filter.auto_detect)
    end)
```

Replace with:

```lua
    it("has filter configuration", function()
      local defaults = config.get()

      -- filter.path is nil by default (auto-detect resolves at validate time),
      -- or a string when the user provides an explicit override.
      assert.is_true(
        defaults.filter.path == nil or type(defaults.filter.path) == "string",
        "filter.path should be nil (use auto-detect) or a string (explicit path)"
      )
      assert.is_boolean(defaults.filter.auto_detect)
    end)
```

The assertion honestly tests the real contract: `filter.path` defaults to nil, gets a string when the user sets one.

- [ ] **Step 7: Verify files parse**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/config.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile tests/config_spec.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output for either parse check.

- [ ] **Step 8: Confirm no stale `custom_path` references in the codebase**

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "custom_path" lua/ tests/ scripts/ plugin/ --include="*.lua"
```

Expected: zero matches. If anything remains, it's a missed reference — find and fix before continuing.

- [ ] **Step 9: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **115 pass / 4 fail** (was 109/10). Specifically: `config_spec` drops from 6/6 to 12/0. Other spec files unchanged.

If counts diverge, STOP and investigate before committing.

- [ ] **Step 10: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/config.lua tests/config_spec.lua
git commit -m "feat(config): add M.get(), rename filter.path, honor auto_detect, clear filter cache

Four coupled changes to lua/writing-metrics/config.lua plus one
test assertion relaxation in tests/config_spec.lua, closing all
6 of the config_spec failures:

1. Add M.get() returning M.config — the missing accessor the
   test suite has always expected. One-line body; callers must
   not mutate the returned table by convention.
2. Rename filter.custom_path -> filter.path across the defaults
   declaration and find_filter()'s user-path branch (5 in-file
   refs). filter.path is the convention the test schema documents
   and matches Neovim ecosystem norms (auto_detect + path as a
   natural pair).
3. Give filter.auto_detect real meaning: when path is set and
   auto_detect=false, return the path unconditionally (trust the
   user; downstream Pandoc surfaces typo errors). When path is
   nil and auto_detect=false, return an error (user opted out
   but provided no path). auto_detect was previously a no-op.
4. Explicitly clear M.config._filter_path at the start of setup()
   so re-configuring the filter path takes effect even if a
   future refactor changes the merge to mutate in place.

Test-side: tests/config_spec.lua:42 assertion relaxed from
is_string to nil-or-string — the real defaults.filter.path is
nil (use auto-detect), not a string. The original assertion was
written against a never-shipped contract that pre-resolved the
bundled filter path at module-load time.

CHANGELOG entry follows in a later commit.

Closes 6 / 6 config_spec failures. Full suite: 109/10 -> 115/4."
```

---

## Task 2: Migrate `config.config.X` reads to `config.get().X`

**Files:**
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` (2 sites)
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/full.lua` (2 sites)
- Modify: `~/projects/nvim-writing-metrics/lua/writing-metrics/commands.lua` (9 sites)

**Failures closed:** 0 (pure consistency refactor). Verifies no regression.

The migration is purely mechanical: every `config.config.X` (where X is any field access) becomes `config.get().X`. The values returned are identical because `M.get()` is a one-line `return M.config`. The benefit is eliminating the codebase split where tests use `config.get()` and production reads `config.config` directly.

- [ ] **Step 1: Find the current call sites to baseline against**

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "config\.config\." lua/ --include="*.lua" | grep -v "lua/writing-metrics/config.lua:"
```

Expected: 13 matches across 3 files (`init.lua`: 2, `full.lua`: 2, `commands.lua`: 9). Each will be migrated by this task.

- [ ] **Step 2: Migrate the 2 sites in `init.lua`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/init.lua`, find line 97 (inside `M.setup`, the commands.setup_commands call added by Plan F):

```lua
  require("writing-metrics.commands").setup_commands(config.config)
```

Replace with:

```lua
  require("writing-metrics.commands").setup_commands(config.get())
```

Then find line 567 (inside a statusline-related function — likely `M.get_statusline_format` or similar):

```lua
      local format = config.config.display.statusline_format
```

Replace with:

```lua
      local format = config.get().display.statusline_format
```

- [ ] **Step 3: Migrate the 2 sites in `full.lua`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/full.lua`, find line 131 (inside `M.show_report` or a window-opening helper):

```lua
        local window_type = config.config.display.report_window
```

Replace with:

```lua
        local window_type = config.get().display.report_window
```

Find line 148 (another window-opening site, same pattern):

```lua
      local window_type = config.config.display.report_window
```

Replace with:

```lua
      local window_type = config.get().display.report_window
```

(These two sites are identical strings except for one extra indent. Use `replace_all: true` after verifying both are intended for migration — both are.)

- [ ] **Step 4: Migrate the 9 sites in `commands.lua`**

In `~/projects/nvim-writing-metrics/lua/writing-metrics/commands.lua`, find these sites and update them.

**Site at line 69** (the legacy-commands gate inside `M.setup_commands`):

```lua
  if config.config.commands and config.config.commands.enable_legacy then
```

Replace with:

```lua
  if config.get().commands and config.get().commands.enable_legacy then
```

**Sites at lines 97-102** (the 6 features.X reads inside the `:WritingMetrics` help dialog). These are 6 adjacent lines:

```lua
      "- Basic metrics: " .. (config.config.features.basic and "✓" or "✗"),
      "- Readability formulas: " .. (config.config.features.readability and "✓" or "✗"),
      "- Passive voice detection: " .. (config.config.features.passive_voice and "✓" or "✗"),
      "- Nominalization detection: " .. (config.config.features.nominalizations and "✓" or "✗"),
      "- Vocabulary analysis: " .. (config.config.features.vocabulary and "✓" or "✗"),
      "- Sentence variety: " .. (config.config.features.sentence_variety and "✓" or "✗"),
```

For these 6 adjacent reads, introduce a local at the top of the block for readability — replace with:

```lua
      "- Basic metrics: " .. (config.get().features.basic and "✓" or "✗"),
      "- Readability formulas: " .. (config.get().features.readability and "✓" or "✗"),
      "- Passive voice detection: " .. (config.get().features.passive_voice and "✓" or "✗"),
      "- Nominalization detection: " .. (config.get().features.nominalizations and "✓" or "✗"),
      "- Vocabulary analysis: " .. (config.get().features.vocabulary and "✓" or "✗"),
      "- Sentence variety: " .. (config.get().features.sentence_variety and "✓" or "✗"),
```

(Pure substitution; keeping the per-line accessor call instead of introducing a local keeps the diff strictly mechanical. Reviewers can see at a glance that every line did the same substitution.)

**Site at line 112** (the `:WritingMetrics` float-window border):

```lua
      border = config.config.display.float_border,
```

Replace with:

```lua
      border = config.get().display.float_border,
```

**Site at line 160** (the `:WritingMetricsCache` float-window border, same shape):

```lua
      border = config.config.display.float_border,
```

Replace with:

```lua
      border = config.get().display.float_border,
```

(Lines 112 and 160 are identical strings. Use `replace_all: true` since both are intended for migration — both are.)

- [ ] **Step 5: Verify files parse**

```bash
cd ~/projects/nvim-writing-metrics
nvim --headless -c "luafile lua/writing-metrics/init.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile lua/writing-metrics/full.lua" -c "qa!" 2>&1 | head -5
nvim --headless -c "luafile lua/writing-metrics/commands.lua" -c "qa!" 2>&1 | head -5
```

Expected: no output for any of the three parse checks.

- [ ] **Step 6: Confirm migration completeness**

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "config\.config\." lua/ --include="*.lua" | grep -v "lua/writing-metrics/config.lua:"
```

Expected: **zero matches**. If anything remains in `init.lua`, `full.lua`, `commands.lua`, or any other file in `lua/`, it's a missed site — find and migrate before committing.

(Matches inside `lua/writing-metrics/config.lua` itself are correct — that file IS allowed to read `M.config` directly since it's the owning module.)

- [ ] **Step 7: Run the full test suite**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **115 pass / 4 fail** (UNCHANGED from Task 1). This task is purely structural — if any count moves, something behavior-changed inadvertently.

If counts diverge, STOP and investigate before committing.

- [ ] **Step 8: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add lua/writing-metrics/init.lua lua/writing-metrics/full.lua lua/writing-metrics/commands.lua
git commit -m "refactor: migrate config.config reads to config.get() accessor

After Plan G's Task 1 added M.get() as the canonical config
accessor, sweep the 13 direct config.config.X reads across lua/
to use config.get().X instead. Eliminates the inconsistency
where tests use the accessor and production code reads the raw
M.config table.

13 sites across 3 files:
- init.lua (2): commands.setup_commands call + display.statusline_format
- full.lua (2): two display.report_window reads
- commands.lua (9): commands.enable_legacy gate + 6 features.X
  reads in the :WritingMetrics help dialog + 2 display.float_border
  reads

Pure textual substitution; M.get() returns M.config by reference,
so values are identical. Failure count unchanged at 115/4."
```

---

## Task 3: Add CHANGELOG entry

**Files:**
- Modify: `~/projects/nvim-writing-metrics/CHANGELOG.md` (add entries under the `## [Unreleased]` section)

**Failures closed:** 0.

- [ ] **Step 1: Read the CHANGELOG's Unreleased section to find insertion point**

```bash
cd ~/projects/nvim-writing-metrics
sed -n '1,80p' CHANGELOG.md
```

Confirm the file uses Keep-a-Changelog format with `## [Unreleased]` containing `### Added` (and other section headings as needed). The existing `### Added` block in `[Unreleased]` already documents reading-time work; Plan G adds a new `### Changed` section for the rename + auto_detect activation, and a single line to `### Added` for `M.get()`.

- [ ] **Step 2: Add entries to the `## [Unreleased]` section**

In `~/projects/nvim-writing-metrics/CHANGELOG.md`, find the start of the existing `### Added` block under `## [Unreleased]`. The block begins with `- Reading time estimation derived from the cached word count...`.

Insert a new `M.get()` line at the top of `### Added` (alphabetical/recency ordering is not enforced; placement at the top makes Plan G's contribution easy to find):

Find:

```markdown
## [Unreleased]

### Added
- Reading time estimation derived from the cached word count, with two
```

Replace with:

```markdown
## [Unreleased]

### Added
- `config.get()` — public accessor on the config module returning the live
  merged configuration table. Internal modules now route reads through this
  accessor instead of reading `config.config` directly.
- Reading time estimation derived from the cached word count, with two
```

Then add a new `### Changed` section immediately after the `### Added` block ends. Find the line that closes the existing `### Added` block — the last bullet of the existing block (after the `basic.get_reading_time(bufnr)` line introduced by the reading-time work). Insert `### Changed` after that block but before any other `### Foo` section. The cleanest pattern: find the blank line that separates `### Added` from the next subsection (or from `## [1.0.0]` if `### Added` is the only subsection currently). Insert:

```markdown

### Changed
- `filter.custom_path` config key renamed to `filter.path`. The previous name
  was undocumented and only appeared inside `config.lua`; users who set
  `filter.custom_path` via `setup({ filter = { custom_path = ... } })` will
  silently lose their override after this release and should rename it to
  `filter.path`. No deprecation shim is provided.
- `filter.auto_detect = false` now has real semantics. Previously a no-op,
  it now means "trust `filter.path` even if the file is not readable; do not
  fall back to the search chain." Combined with `filter.path = nil`, an
  explicit `auto_detect = false` returns an error from dependency validation
  (the user opted out of auto-detect but provided no path).
```

The exact placement depends on what's already in the Unreleased section. If `### Changed` already exists, append the two bullets to it. If `### Removed` or `### Fixed` already exist, place `### Changed` between `### Added` and them (Keep-a-Changelog's standard order is Added → Changed → Deprecated → Removed → Fixed → Security).

- [ ] **Step 3: Verify the CHANGELOG is well-formed**

Visually inspect the result by reading the first 40 lines:

```bash
cd ~/projects/nvim-writing-metrics
sed -n '1,40p' CHANGELOG.md
```

Confirm:
- `## [Unreleased]` is still the section heading
- `### Added` block contains the new `config.get()` bullet at the top
- New `### Changed` block exists with two bullets (rename + auto_detect activation)
- No duplicated headings or broken markdown

- [ ] **Step 4: Run the full test suite (sanity check — should be unchanged)**

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: still **115 pass / 4 fail**. CHANGELOG edits don't affect tests.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/nvim-writing-metrics
git add CHANGELOG.md
git commit -m "docs(changelog): note Plan G's user-visible config changes

Three entries added to ## [Unreleased]:
- Added: config.get() public accessor returning the live merged config.
- Changed: filter.custom_path renamed to filter.path. Undocumented internal
  key with no published callers, but anyone who discovered it should know.
  No deprecation shim — direct rename.
- Changed: filter.auto_detect=false is now functional. Previously a no-op
  silently accepted and ignored; now means \"trust filter.path even if
  missing; error if path is nil\"."
```

---

## Final verification

After all three tasks land, run:

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh 2>&1 | grep -aE "Success: |Failed : "
```

Expected: full suite reports **115 pass / 4 fail**. Breakdown by spec file:
- `basic_spec`: 31 / 0 (unchanged, post-Plan-E)
- `cache_spec`: unchanged
- `compatibility_spec`: 17 / 0 (unchanged, post-Plan-F)
- `config_spec`: **12 / 0** (was 6 / 6 — all 6 closed)
- `display_spec`: unchanged
- `full_spec`: 19 / 4 (unchanged — separate plan)
- `init_spec`: unchanged
- `integration_spec`: 19 / 0 (unchanged, post-Plan-F)
- `utils_spec`: unchanged

```bash
cd ~/projects/nvim-writing-metrics
git log --oneline f376ed5..HEAD
```

Expected: 3 commits, prefixed `feat(config)`, `refactor:`, `docs(changelog)`.

```bash
cd ~/projects/nvim-writing-metrics
grep -rn "custom_path" . --include="*.lua" --include="*.md"
```

Expected: zero matches. If a stale `custom_path` reference remains anywhere (Lua source, tests, or docs), find and fix before declaring done.

---

## Holistic review

Per the spec, Plan G uses one holistic review at the end. Dispatch one code-reviewer subagent against the cumulative diff:

```bash
cd ~/projects/nvim-writing-metrics
git diff f376ed5 HEAD --stat
git diff f376ed5 HEAD
```

Reviewer focus areas:

- **Task 1 — M.get() correctness:** Returns `M.config` by reference (one line). Matches the test's `is_function` assertion. No subtle metatable or copy semantics added.
- **Task 1 — rename completeness:** Zero `custom_path` references remain anywhere in the repo. All 5 in-file `config.lua` sites moved cleanly.
- **Task 1 — auto_detect truth table:** The four-way combination (`auto_detect` × `path` set/nil) is fully covered:
  - `auto_detect = true` + `path` set: validate readability, fall back to candidate search on miss (unchanged from pre-Plan-G behavior).
  - `auto_detect = false` + `path` set: return the path unconditionally (the new cluster-3 fix).
  - `auto_detect = true` + `path` nil: search candidate chain (unchanged).
  - `auto_detect = false` + `path` nil: explicit error (new — previously fell through to the search chain, which silently contradicted the user's opt-out).
- **Task 1 — cache clear placement:** `M.config._filter_path = nil` immediately follows the deep-extend merge, so the cache is cleared on every `setup()` call regardless of whether validation succeeds or fails.
- **Task 1 — test assertion change:** The relaxed `is_true(... == nil or type(...) == "string", ...)` actually validates the intended contract instead of accepting anything.
- **Task 2 — migration completeness:** `grep -rn "config\.config\." lua/ --include="*.lua" | grep -v "lua/writing-metrics/config.lua:"` returns zero matches. Every site migrated.
- **Task 2 — no behavior drift:** Each migrated read returns the same value via `config.get()` as it did via `config.config` — verified by the failure count staying at 115/4 across Task 2.
- **Task 3 — CHANGELOG hygiene:** Entry is informative, follows the file's existing Keep-a-Changelog format, mentions all three user-visible changes (rename, auto_detect activation, M.get() new public API). Placed under `## [Unreleased]`, not under a released version.
- **No scope creep:** Diff doesn't touch `basic_spec.lua`, `full_spec.lua`, `compatibility_spec.lua`, or `integration_spec.lua`. No incidental refactoring of unrelated code.
- **Baseline preservation:** Every other spec file's pass/fail count is unchanged from baseline.

---

## After completion

Memory updates:

- Delete `~/.claude/projects/-home-jkeim--config-nvim/memory/project_nvim_writing_metrics_config_spec_failures.md` (all 6 failures closed; entry would mislead future sessions).
- Update `~/.claude/projects/-home-jkeim--config-nvim/memory/project_nvim_writing_metrics_full_spec_failures.md` baseline note from `109 / 10` to `115 / 4`.
- Update `~/.claude/projects/-home-jkeim--config-nvim/memory/MEMORY.md`: remove the deleted config-spec entry's line; update the full-spec entry's description if it references the old baseline.

## Summary

3 commits, ~25 lines of net code change in `lua/writing-metrics/config.lua` (4 implementation changes + 1 test-side assertion in Task 1) + 13 mechanical migrations across 3 files in Task 2 + a CHANGELOG entry in Task 3. Closes 6 of the 10 remaining failures and activates a previously-dormant config flag (`filter.auto_detect`). Estimated 30-45 minutes of focused work plus the holistic review.

After Plan G lands, the only outstanding failures are the 4 `full_spec.lua` isolation issues — a separate, smaller plan that completes the test-cleanup arc started in Plan E.
