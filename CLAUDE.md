# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

nvim-writing-metrics is a Neovim plugin providing comprehensive writing metrics and readability analysis for prose documents. It uses Pandoc with a custom Lua filter to analyze text, offering both fast basic metrics and detailed readability reports.

**Key Dependencies:**
- Neovim >= 0.10
- Pandoc >= 2.19 (with Lua filter support)
- snacks.nvim >= 2.0 (for UI components)

## Architecture

### Module Structure

The plugin follows a modular architecture with clear separation of concerns:

**Core modules** (`lua/writing-metrics/`):
- `init.lua` - Main entry point, public API, plugin initialization
- `config.lua` - Configuration management, dependency validation (Pandoc + filter detection)
- `cache.lua` - Content-based caching system (similar to Vim's native wordcount)
- `basic.lua` - Fast word counting with statusline integration, supports fast/accurate modes
- `full.lua` - Comprehensive report generation (always fresh, no caching)
- `utils.lua` - Shared utilities (Pandoc execution, file I/O, formatting, notifications)
- `commands.lua` - User command registration; called from init.lua's setup() (idempotent)
- `display.lua` - Report formatting and buffer management

**Key architectural patterns:**
1. **Two-tier metric system**: Basic (fast, cached for statusline) vs Full (comprehensive, always fresh)
2. **Async execution**: All Pandoc calls use `vim.system()` with callbacks to prevent UI blocking
3. **Content-based caching**: Cache invalidates on actual text changes (via autocmds), not time-based
4. **Report buffer tracking**: Global table maps source file paths to report buffer numbers for in-place updates

### Pandoc Filter System

The plugin's core analysis happens in `scripts/textmetrics.lua`, a dual-mode Pandoc Lua filter:

**Mode 1 - Basic** (`-M metrics_mode=basic`):
- Fast word/char/sentence/paragraph counts
- Space-separated output: `words chars sentences paragraphs avg_sentence_len avg_word_len`
- Used for statusline integration (cached)

**Mode 2 - Full** (`-M metrics_mode=full`):
- All basic counts plus 6 readability formulas (Coleman-Liau, ARI, Flesch Reading Ease, Flesch-Kincaid, Gunning Fog, SMOG)
- Advanced analysis: passive voice, nominalizations, vocabulary richness, sentence variety, AI-word detection
- JSON output with structured data
- Used for comprehensive reports (always fresh)

The filter is auto-detected in this order:
1. `plugin_dir/scripts/textmetrics.lua` (bundled)
2. `~/.local/share/nvim/textmetrics.lua`
3. `~/bin/textmetrics.lua`
4. `/usr/local/share/nvim/textmetrics.lua`

### Cache Strategy

**Statusline cache** (basic metrics only):
- **Content-based caching**: Cache remains valid as long as buffer content hasn't changed
- **No time-based expiration**: TTL values exist in config but are NOT used for cache validation
- Cache invalidates immediately on text changes via autocmds (`TextChanged`, `TextChangedI`, `InsertLeave`, `BufWritePost`)
- When invalidated, cache is marked "stale" but preserves last count for display
- Cache entry structure: `{changedtick, timestamp, data, stale}`
- See `cache.lua:45-63` for implementation

**Report generation** (full metrics):
- **Always computes fresh** - no caching
- Every `:ReadabilityReport` invocation runs Pandoc analysis
- Report buffers tracked globally by source filepath for in-place updates
- See `full.lua:10-43` for implementation

### Backward Compatibility

The plugin maintains backward compatibility with a previous `accurate-wordcount.lua` script:
- Global `_G.accurate_wordcount` callable table — `_G.accurate_wordcount()` returns the cached word count (function shape), `_G.accurate_wordcount.<method>(bufnr)` exposes basic-module methods (table shape). Both contracts preserved from the prior `accurate_wordcount.lua` plugin.
- Command aliases: `:AccurateWordCount` → `:WordCount`, `:ToggleWordCountMode` → `:WritingMetricsToggle`
- Legacy lualine integration functions

## Plan History

The plugin has a per-feature design-spec history under `docs/superpowers/specs/` and implementation plans under `docs/superpowers/plans/`. Each spec corresponds to a single Plan (letter-named: A, B, C, ...) and to one commit on `main`.

Use `git log --oneline` to find which commit shipped a given plan, or read the spec files directly for the design rationale.

## Development Commands

### Running Tests

The test suite uses plenary.nvim with 118 test cases across 9 test files (118 passing, 0 failing after Plan H).

**Run all tests:**
```bash
./run-tests.sh
```

**Run with verbose output:**
```bash
./run-tests.sh -v
```

**Run specific test file:**
```bash
./run-tests.sh -t tests/cache_spec.lua
```

**Test files:**
- `tests/config_spec.lua` - Configuration and validation
- `tests/cache_spec.lua` - Cache behavior and TTL
- `tests/basic_spec.lua` - Basic metrics tests
- `tests/full_spec.lua` - Full metrics tests
- `tests/integration_spec.lua` - End-to-end integration
- `tests/compatibility_spec.lua` - Backward compatibility

**From within Neovim:**
```vim
:PlenaryBustedDirectory tests/
:PlenaryBustedFile tests/cache_spec.lua
```

### Manual Testing Commands

**Module testing:**
```vim
" Test basic word count
:lua require("writing-metrics.basic").get_accurate_count(0, vim.print)
:lua require("writing-metrics.basic").show_comparison(0)

" Test full report
:lua require("writing-metrics.full").show_report()

" Test cache
:lua print(vim.inspect(require("writing-metrics.cache").get_stats()))
:lua print(vim.inspect(require("writing-metrics.cache").inspect(0)))
:lua require("writing-metrics.cache").invalidate(0)

" Test statusline
:lua print(require("writing-metrics.basic").get_statusline_string(0))
:lua require("writing-metrics.basic").toggle_statusline_mode()

" Test config
:lua require("writing-metrics.config").validate_dependencies()
:lua local path, err = require("writing-metrics.config").find_filter(); print(path or err)
```

## Common Development Patterns

### Adding a New Metric

1. **Update the Pandoc filter** (`scripts/textmetrics.lua`):
   - Add counter/data structure in global section
   - Implement collection logic in appropriate filter function
   - Add to JSON output in `full_mode_output()`

2. **Update parsing** (`utils.lua` or `full.lua`):
   - Add parsing logic for new metric in `parse_full_output()`
   - Validate data structure

3. **Update display** (`display.lua`):
   - Add formatting logic in `format_report()`
   - Add visual presentation (headers, formatting)

4. **Add tests** (new or existing test file):
   - Test metric calculation accuracy
   - Test edge cases (empty input, special chars)
   - Test display formatting

### Modifying Cache Behavior

Cache logic lives in `cache.lua` and `basic.lua`:

- **Invalidation triggers**: Modify `cache.lua:setup_autocmds()` (TextChanged, InsertLeave, BufWritePost)
- **Cache storage**: Modify `cache.basic` table structure and `set_basic()`/`get_basic()` methods
- **Stale handling**: Cache marks entries stale but preserves data; modify in `get_basic()` return signature

### Working with Reports

Reports are managed by `full.lua` and `display.lua`:

- **Report buffer tracking**: Global `_G.writing_metrics_reports` maps `source_filepath → report_bufnr`
- **In-place updates**: `display.update_report_buffer()` replaces content without creating new buffer
- **Window types**: Configurable via `config.display.report_window` ("tab", "split", "vsplit")

## Important Implementation Details

### Statusline Integration

The plugin provides multiple statusline modes:

**Fast mode** (default):
- Uses Vim's native `wordcount()` - instant, always fresh
- Icon: ⚡

**Accurate mode**:
- Uses Pandoc filter via cache
- Shows freshness indicator: 🎯 (fresh) or ⚠️ (stale)
- Toggle with `:WritingMetricsToggle`

**Visual mode**:
- Automatically shows selection count when in visual mode
- Uses `wordcount().visual_words` and `wordcount().visual_chars`

### Buffer Lifecycle

Report buffers have special handling:

1. Created with `buftype=nofile` and `bufhidden=hide` (not wipe, to enable reuse)
2. Named with pattern: `Report: {source_filename}`
3. Tracked in global table by source filepath (not buffer number)
4. Cleaned up via autocmds on `BufDelete` and `BufWipeout`
5. Can be updated in-place when regenerating from same source file

### Async Patterns

All Pandoc execution is async using `vim.system()`:

**How `utils.run_pandoc()` works** (`utils.lua:117-151`):
```lua
function M.run_pandoc(input_file, mode, callback)
  local cmd = { "pandoc", input_file, "--lua-filter", filter_path, ... }

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()  -- Wraps callback in vim.schedule
      if result.code ~= 0 then
        callback(false, "Pandoc failed")
        return
      end
      callback(true, result.stdout)
    end)
  end)
end
```

**Calling pattern** (e.g., `basic.lua:55-77`):
```lua
utils.run_pandoc(temp_path, "basic", function(success, output)
  -- Already in vim.schedule context from run_pandoc
  utils.cleanup_temp_file(temp_path)

  if not success then
    callback(nil, "error")
    return
  end

  local parsed = utils.parse_basic_output(output)
  cache.set_basic(bufnr, parsed)
  callback(parsed, "fresh")
end)
```

Key points:
- `run_pandoc()` wraps your callback in `vim.schedule()` automatically
- Calling code should NOT add another `vim.schedule()` wrapper
- Always clean up temp files in the callback
- Use callback pattern (not promises) for consistency

**⚠️ CRITICAL: Avoid Double-Wrapping vim.schedule()**

The `utils.run_pandoc()` function already wraps its callback in `vim.schedule()`. Do NOT wrap the callback again in calling code:

```lua
-- ❌ WRONG - Double wrapping causes temp file deletion before Pandoc reads it
utils.run_pandoc(temp_file, mode, function(success, result)
  vim.schedule(function()  -- <- Second wrap is wrong!
    -- ...
  end)
end)

-- ✅ CORRECT - Single wrap inside run_pandoc is sufficient
utils.run_pandoc(temp_file, mode, function(success, result)
  -- Already in vim.schedule context
  -- Safe to call Vimscript functions here
end)
```

Double-wrapping can cause race conditions where temp files are deleted before Pandoc finishes reading them.

### Syllable Counting Algorithm

The Pandoc filter uses a simple heuristic approach (~85% accuracy) for syllable counting:

**Algorithm** (`scripts/textmetrics.lua`):
```lua
local function count_syllables(word)
  word = word:lower()
  word = word:gsub("[^a-z]", "")  -- Remove non-letters

  if #word == 0 then return 0 end
  if #word <= 3 then return 1 end

  -- Count vowel groups
  local count = 0
  local previous_was_vowel = false

  for i = 1, #word do
    local char = word:sub(i, i)
    local is_vowel = char:match("[aeiouy]")

    if is_vowel and not previous_was_vowel then
      count = count + 1
    end

    previous_was_vowel = is_vowel
  end

  -- Adjust for silent 'e'
  if word:sub(-1) == "e" then
    count = count - 1
  end

  return math.max(count, 1)  -- Minimum 1 syllable
end
```

**Examples:**
- "the" → 1 (correct)
- "running" → 2 (correct: run-ning)
- "calculate" → 3 (correct: cal-cu-late, silent e handled)
- "communication" → 5 (correct: com-mu-ni-ca-tion)

**Trade-off:** Fast and simple vs. perfect accuracy. Errors average out across full documents, providing reliable aggregate metrics.

### Complex Word Detection

For the Gunning Fog Index, the filter identifies "complex words" (3+ syllables with exclusions):

**Algorithm** (`scripts/textmetrics.lua`):
```lua
local function is_complex(word, syllables)
  if syllables < 3 then return false end

  -- Exclude proper nouns (capitalized)
  if word:match("^%u") then return false end

  -- Exclude common suffixes that add syllables but not complexity
  if word:match("ed$") or word:match("es$") or word:match("ing$") then
    local base = word:gsub("ed$", ""):gsub("es$", ""):gsub("ing$", "")
    if count_syllables(base) < 3 then return false end
  end

  return true
end
```

**Examples:**
- "development" (4 syllables) → complex ✓
- "created" (3 with suffix, 2 base) → not complex ✓
- "University" (capitalized) → not complex (proper noun)
- "understanding" (4 syllables) → complex ✓

### Filter Metadata Recognition

The Pandoc filter accepts mode specification via YAML frontmatter:

**Supported metadata fields:**
- `metrics_mode: basic` or `metrics_mode: full`
- `metrics: basic` or `metrics: full` (alternative)

**Example:**
```yaml
---
metrics_mode: full
---

Your document text here...
```

The filter checks both field names for backward compatibility. This allows documents to specify their preferred analysis mode without requiring command-line flags.

## Interpretation Guidelines

### Readability Score Targets by Genre

Different writing types have different readability requirements:

**Grant Writing:**
- **Flesch-Kincaid Grade Level:** 11-14 (college level, but clear)
- **Flesch Reading Ease:** 50-60 (fairly difficult)
- **Coleman-Liau Index:** 11-14
- **Gunning Fog Index:** 12-15 (professional complexity acceptable)
- **Goal:** Professional tone while remaining accessible to reviewers

**Fiction Writing:**
- **Flesch-Kincaid Grade Level:** 7-9 (general audience)
- **Flesch Reading Ease:** 60-80 (standard to fairly easy)
- **Goal:** Accessible to most readers while maintaining literary quality

**Creative Writing:**
- **Flesch-Kincaid Grade Level:** 7-9
- **Flesch Reading Ease:** 60-80
- **High sentence variability:** CV > 50% for engaging rhythm

**Academic Writing:**
- **Flesch-Kincaid Grade Level:** 12-16 (graduate level)
- **Flesch Reading Ease:** 30-50 (difficult)
- **Passive voice:** Max 20% acceptable

### Sentence Variability Interpretation

Variability metrics help identify monotonous writing and improve rhythm:

**Standard Deviation (σ):**
- **σ < 5**: Very uniform (potentially monotonous)
- **σ = 5-8**: Moderate variation (typical for grants)
- **σ = 8-12**: Good variation (engaging prose)
- **σ > 12**: High variation (literary/experimental)

**Coefficient of Variation (CV):**
- **CV < 30%**: Low variation (monotonous)
- **CV = 30-50%**: Moderate variation (acceptable for grants)
- **CV = 50-70%**: High variation (good for fiction)
- **CV > 70%**: Very high variation (experimental)

**Example:**
```
Mean: 18.5 words/sentence
Std Dev: 9.2 words
CV = (9.2 / 18.5) × 100 = 49.7%
→ Good variation (upper end of moderate)
```

**Range (Min/Max):**
- Identifies extremes
- **Fiction:** Mix short (impact) and long (flow) sentences
- **Grants:** Avoid extremes (< 8 or > 35 words)

### Distribution Histogram Guidance

Ideal sentence length distributions vary by genre:

**Grant Writing (Normal Distribution):**
```
Very short (1-5):   5%
Short (6-10):      15%
Medium (11-20):    55%  ← Most sentences
Long (21-30):      20%
Very long (31+):    5%
```

**Fiction Writing (Skewed Distribution):**
```
Very short (1-5):  10%  ← Punchy impact
Short (6-10):      25%
Medium (11-20):    40%
Long (21-30):      20%
Very long (31+):    5%
```

### AI-Word Detection Tiers

The plugin detects 80+ AI-associated words organized into 7 tiers:

**Tier 1 (Most Notorious):**
- delve, tapestry, landscape, realm, navigate, showcase
- These are the most obvious AI markers

**Tier 2 (Action Verbs):**
- leverage, elevate, foster, embark, unleash
- Overused business/academic jargon

**Tier 3 (Descriptive Adjectives):**
- vibrant, pivotal, meticulous, multifaceted, intriguing
- Excessive formality markers

**Tier 4 (Business Jargon):**
- revolutionize, game-changer, cutting-edge, optimize, streamline
- Corporate buzzwords

**Tier 5 (Academic Overuse):**
- aforementioned, paramount, quintessential, myriad, plethora
- Over-formal academic language

**Tiers 6-7:**
- Creative clichés, metaphors, transitions, hedging language

**Recommendations:**
- **0 instances:** Authentic, natural voice ✓
- **1-3 instances:** Minor review needed
- **4+ instances:** Significant revision recommended

## Technical Specifications

### Performance Targets

**Basic Mode (statusline):**
- **< 100ms** for documents under 5,000 words
- **< 500ms** for documents under 50,000 words
- Async execution prevents UI blocking
- Aggressive caching minimizes recalculation

**Full Mode (comprehensive reports):**
- **< 500ms** for documents under 5,000 words
- **< 2s** for documents under 50,000 words
- User expects slight delay for comprehensive analysis
- Fresh calculation on every invocation

### Cache Implementation Details

**Changedtick-based caching:**
- Cache validation reads `vim.b[bufnr].changedtick` — Neovim's built-in per-buffer modification counter
- Cache remains valid indefinitely until buffer content actually changes; cursor moves and mode changes don't invalidate
- See `cache.content_changed()` in `lua/writing-metrics/cache.lua`

**Cache Invalidation:**
- Driven by `changedtick` comparison; the prior cached tick is stored alongside the data
- Autocmds (`TextChanged`, `TextChangedI`, `InsertLeave`, `BufWritePost`) trigger recompute attempts; cache is marked "stale" so the statusline shows the last known count while updating

**No Report Cache:**
- Reports always compute fresh on every `:ReadabilityReport` invocation
- No caching — full Pandoc analysis every time, so output always reflects the current document state

### Output Format Specifications

**Basic Mode (space-separated values):**
```
words chars sentences paragraphs avg_sentence_len avg_word_len
```

Example output:
```
1247 7892 65 42 19.18 6.33
```

Parsing in `utils.lua:parse_basic_output()`:
- Split on whitespace
- Convert to numbers
- Return structured table with named fields

**Full Mode (JSON):**
```json
{
  "basic": {
    "words": 1247,
    "chars": 7892,
    "sentences": 65,
    "paragraphs": 42,
    "avg_sentence_len": 19.18,
    "avg_word_len": 6.33
  },
  "readability": {
    "coleman_liau": 12.3,
    "ari": 11.8,
    "flesch_reading_ease": 54.2,
    "flesch_kincaid": 12.1,
    "gunning_fog": 13.5,
    "smog": 12.8
  },
  "sentence_variety": {
    "std_dev": 8.7,
    "coefficient_variation": 43.5,
    "min_length": 3,
    "max_length": 42,
    "distribution": {...}
  },
  "ai_words": {
    "count": 11,
    "percentage": 0.88
  }
}
```

## Troubleshooting

### Common Issues and Solutions

**Issue: "Failed to parse metrics: Could not find metrics in output"**

**Cause:** Filter output format mismatch or wrong filter version.

**Solution:**
1. Verify filter location: `:lua print(require("writing-metrics.config").find_filter())`
2. Ensure filter outputs 6 values in basic mode (not 5)
3. Check Pandoc version >= 2.19

**Issue: "E5560: Vimscript function must not be called in a fast event context"**

**Cause:** Vimscript functions called without `vim.schedule()` wrapper.

**Solution:** Ensure `utils.run_pandoc()` wraps its callback in `vim.schedule()` (already implemented). Do NOT add additional wrapping in calling code.

**Issue: Empty Pandoc output despite temp file existing**

**Cause:** Double `vim.schedule()` wrapping causing temp file deletion before Pandoc reads it.

**Solution:** Remove redundant `vim.schedule()` wrapper. Only wrap once in `utils.run_pandoc()`, not in calling code. See "Async Patterns" section above.

**Issue: Stale word counts in statusline**

**Cause:** Cache not invalidating on text changes.

**Solution:**
1. Check autocmds are active: `:autocmd WritingMetricsCache`
2. Verify cache invalidation: `:lua require("writing-metrics.cache").content_changed(0)`
3. Clear cache manually: `:WritingMetricsClear`

**Issue: Reports showing "Not a writing buffer"**

**Cause:** Current filetype not in enabled filetypes list.

**Solution:**
1. Check current filetype: `:set filetype?`
2. Add to config if needed:
```lua
require("writing-metrics").setup({
  filetypes = { "markdown", "text", "yourtype" }
})
```

## Workflow Examples

### Grant Writing Workflow

**Phase 1: Draft Phase**
- Statusline shows basic word count (tracking toward word limits)
- Focus on content, not metrics
- Fast mode provides instant feedback

**Phase 2: Revision Phase**
```vim
:ReadabilityReport
```

**Initial review output:**
```
READABILITY SCORES
  Coleman-Liau:        15.8  (16th grade) ⚠ TOO COMPLEX
  Flesch Reading Ease: 42.1  (Difficult)  ⚠ TOO COMPLEX
  Flesch-Kincaid:      15.2  (15th grade) ⚠ TOO COMPLEX

ASSESSMENT: ✗ Too complex for grant writing (target: 11-14, Flesch 50-60)

SENTENCE VARIABILITY
  Std dev: 5.2  ⚠ LOW VARIATION (monotonous)

PATTERNS
  ⚠ 3 monotonous patterns detected
```

**Action:** Simplify vocabulary, shorten sentences, add variety

**Phase 3: Final Polish**
```vim
:ReadabilityReport
```

**Target achieved:**
```
READABILITY SCORES
  Coleman-Liau:        12.3  ✓
  Flesch Reading Ease: 54.2  ✓
  Flesch-Kincaid:      12.1  ✓

ASSESSMENT: ✓ Appropriate for grant writing

SENTENCE VARIABILITY
  Std dev: 8.7  ✓ Good variation
```

### Fiction Writing Workflow

**Phase 1: First Draft**
- Statusline word count tracks progress toward daily goal
- Ignore readability (focus on story)
- Fast mode for minimal distraction

**Phase 2: Developmental Editing**
```vim
:ReadabilityReport
```

**Check pacing:**
```
SENTENCE VARIABILITY
  Std dev: 12.4  ✓ High variation (good for fiction)

DISTRIBUTION
  1-5 words:   15%  ← Good mix of punchy sentences
  6-10 words:  28%
  11-20 words: 40%
  21-30 words: 14%
  31+ words:    3%

ASSESSMENT: ✓ Good variety for fiction

PATTERNS
  ⚠ Lines 245-253: All 18-22 words
  → Consider adding a short sentence for impact
```

**Action:** Add short sentence for rhythm: "She stopped. The room fell silent."

**Phase 3: Readability Check**
```
READABILITY SCORES
  Flesch Reading Ease: 68.5  ✓ (Target: 60-80 for fiction)
  Flesch-Kincaid:       8.2  ✓ (Target: 7-9 for general audience)
```

### Multiple Document Analysis Workflow

The plugin supports analyzing multiple documents simultaneously:

**Generate first report:**
```vim
:edit ~/documents/grant-proposal.md
<leader>mr  " Opens "Report: grant-proposal.md" in new tab
```

**Generate second report:**
```vim
:tabnew
:edit ~/documents/research-paper.md
<leader>mr  " Opens "Report: research-paper.md" in another tab
```

**Switch between reports:**
- Use `gt`/`gT` to cycle through tabs
- Both reports persist and can be viewed side-by-side

**Regenerate after edits:**
```vim
:edit ~/documents/grant-proposal.md
" Make changes...
<leader>mr  " Updates existing "Report: grant-proposal.md" in-place
```

**Features:**
- Unlimited simultaneous reports
- Unique report buffers per document
- Smart regeneration (updates existing report)
- Automatic cleanup when buffers deleted

### AI-Word Detection Workflow

The plugin provides statistical analysis of AI-associated words in the readability report.

**Workflow:**
1. Generate readability report with `<leader>mr` or `:ReadabilityReport`
2. Review the "AI-Associated Words" section showing:
   - Total count of AI-words detected
   - Percentage of total words
   - Specific words found with frequencies (sorted)
3. Identify overused AI-associated words
4. Replace with more specific, concrete, authentic alternatives
5. Regenerate report to verify improvements

**Example output in report:**
```
AI-ASSOCIATED WORDS
  Total: 11 instances (0.88% of document)

  Words detected:
    - delve (3)
    - landscape (2)
    - leverage (2)
    - tapestry (1)
    - navigate (1)
    - multifaceted (1)
    - showcase (1)
```

**Note:** This plugin only provides statistical detection in reports. For interactive highlighting of AI-words during editing, you would need to integrate with a separate tool like vim-wordy in your personal Neovim configuration.

## Plugin Commands and Keybindings

### User Commands

The plugin provides these commands:

- `:WordCount` - Show basic metrics (words, chars, sentences, paragraphs, averages) in floating window
- `:ReadabilityReport` - Generate comprehensive analysis report in new tab
- `:WritingMetricsToggle` - Toggle between fast (Vim native) and accurate (Pandoc) word count modes
- `:WritingMetrics` - Show plugin status, configuration, and help
- `:WritingMetricsCache` - Display cache statistics
- `:WritingMetricsClear` - Clear all caches (use `!` to skip confirmation)

### Suggested Keybindings

The plugin does NOT set keybindings automatically. Users should configure them in their `lazy.nvim` spec or init.lua:

**Recommended setup:**
```lua
keys = {
  { "<leader>mc", "<cmd>WordCount<cr>", desc = "Show word count" },
  { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability report" },
  { "<leader>mt", "<cmd>WritingMetricsToggle<cr>", desc = "Toggle fast/accurate mode" },
}
```

See `examples/vim-keybindings.lua` for additional keybinding schemes and options.

### Backward Compatibility Commands

For users migrating from `accurate-wordcount.lua`:

- `:AccurateWordCount` → Alias for `:WordCount`
- `:ToggleWordCountMode` → Alias for `:WritingMetricsToggle`

## File Type Support

Enabled by default for:
- `markdown`, `text`, `tex`, `fountain`, `org`, `asciidoc`, `rst`

Configured in `config.lua:defaults.filetypes`.

## Known Quirks

1. **Report buffer names**: Use `vim.fn.fnamemodify(bufname, ":t")` to extract tail when checking for "Report:" prefix, as absolute paths vary
2. **Debug logging**: `basic.lua` has debug file logging to `/tmp/statusline_debug.txt` (can be removed if not needed)
3. **Pandoc version check**: Requires >= 2.19 for Lua filter support; checked in `config.validate_pandoc()`
