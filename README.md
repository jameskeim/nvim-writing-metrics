# nvim-writing-metrics

Writing metrics and readability analysis for Neovim. Get accurate word counts, readability scores, and style feedback while you write.

## What It Does

This plugin analyzes your writing in real time and provides:

- **Accurate word counts** using Pandoc (handles contractions, hyphenated words, and punctuation correctly)
- **Readability formulas** (Coleman-Liau, Flesch-Kincaid, Gunning Fog, ARI, SMOG, Flesch Reading Ease)
- **Style analysis** (passive voice detection, nominalizations, sentence variety)
- **Vocabulary richness** (type-token ratio, most frequent words)
- **AI-word detection** (identifies 80+ AI-associated words and phrases)

Two modes:

- **Fast mode**: Instant counts using Vim's native `wordcount()` for statusline display
- **Accurate mode**: Pandoc-based analysis that handles prose properly

## Why Text Analysis Matters

Writers need feedback on readability and style. Grant writers target specific grade levels. Fiction writers manage pacing through sentence variety. Academic writers track passive voice usage.

This plugin brings those tools into your editor.

**Similar Neovim plugins:**

- [vim-wordy](https://github.com/preservim/vim-wordy) - Usage problem detector
- [vim-textobj-sentence](https://github.com/preservim/vim-textobj-sentence) - Sentence text objects for prose
- [vim-pencil](https://github.com/preservim/vim-pencil) - Prose-focused writing mode

## Interesting Techniques

### Content-Based Caching

Cache invalidates on actual text changes, not time-based expiration. Uses `vim.b[bufnr].changedtick` — Neovim's built-in per-buffer modification counter — so cursor moves and mode changes don't trigger recomputation.

### Async Pandoc Execution

All analysis runs asynchronously using [`vim.system()`](https://neovim.io/doc/user/lua.html#vim.system()) to prevent UI blocking. Results are delivered via callbacks wrapped in [`vim.schedule()`](https://neovim.io/doc/user/lua.html#vim.schedule()) for safe Vimscript API calls.

### Dual-Mode Lua Filter

Single Pandoc filter operates in two modes:

- **Basic mode**: Fast counts (6 space-separated values)
- **Full mode**: Comprehensive JSON analysis

Controlled via `--metadata metrics_mode=basic|full` flag.

### Report Buffer Tracking

Maintains global table mapping source filepaths to report buffer numbers. Enables in-place updates when regenerating reports. Uses [`buftype=nofile`](https://neovim.io/doc/user/options.html#'buftype') and `bufhidden=hide` for persistent reports across multiple files.

See [`examples/lualine-integration.lua`](examples/lualine-integration.lua) and [`examples/statusline-integration.lua`](examples/statusline-integration.lua) for integration examples.

### Statusline Integration

Two-tier system:

- Fast mode uses Vim's native `wordcount()` - instant
- Accurate mode uses cached Pandoc results with staleness indicators

## Technologies Used

### Pandoc with Lua Filters

[Pandoc](https://pandoc.org/) is a document converter that understands prose structure. Its Lua filters can traverse the document AST (Abstract Syntax Tree) and extract metrics.

Why Pandoc for word counting?

Standard string-splitting approaches fail on:

- Contractions ("don't" → 1 word, not 2)
- Hyphenated words ("well-known" → 1 word in some contexts, 2 in others)
- Possessives ("user's" → 1 word, not 2)
- Punctuation handling (em-dashes, ellipses, etc.)

Pandoc's parser handles these correctly.

See:

- [Pandoc Lua Filters](https://pandoc.org/lua-filters.html)
- [Why word counting is hard](https://www.stevefenton.co.uk/blog/2019/01/why-word-counting-is-hard/)
- [Unicode word boundary issues](https://stackoverflow.com/questions/1856785/characters-for-word-splitting-in-vim)

### snacks.nvim

UI notifications use [snacks.nvim](https://github.com/folke/snacks.nvim)'s notification system with fallback to `vim.notify()`.

### plenary.nvim (testing)

Test suite uses [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s test framework (106 test cases). Run with `./run-tests.sh`.

## Project Structure

```
nvim-writing-metrics/
├── lua/writing-metrics/    # Core plugin modules
├── plugin/                 # Plugin entry point and commands
├── scripts/                # Pandoc Lua filter
├── tests/                  # Test suite (106 tests)
├── examples/               # Integration examples
├── docs/                   # Architecture documentation
└── run-tests.sh            # Test runner
```

**[`lua/writing-metrics/`](lua/writing-metrics/)**: Six-module architecture with clear separation of concerns.

- [`init.lua`](lua/writing-metrics/init.lua) - Public API
- [`basic.lua`](lua/writing-metrics/basic.lua) - Statusline integration
- [`full.lua`](lua/writing-metrics/full.lua) - Comprehensive reports
- [`display.lua`](lua/writing-metrics/display.lua) - Output formatting
- [`cache.lua`](lua/writing-metrics/cache.lua) - Content-based caching
- [`utils.lua`](lua/writing-metrics/utils.lua) - Shared utilities

**[`scripts/textmetrics.lua`](scripts/textmetrics.lua)**: The Pandoc Lua filter (900+ lines). Implements syllable counting, readability formulas, passive voice detection, and AI-word identification. Operates in two modes controlled by metadata.

**[`tests/`](tests/)**: Comprehensive test suite using plenary.nvim. Covers basic metrics, full analysis, caching, configuration, backward compatibility, and integration scenarios.

**[`examples/`](examples/)**: Ready-to-use configurations for lazy.nvim, lualine, statusline integration, and keybindings.

## How to Use

### Requirements

- Neovim ≥ 0.10
- [Pandoc](https://pandoc.org/installing.html) ≥ 2.19 (for accurate counts)
- [snacks.nvim](https://github.com/folke/snacks.nvim) ≥ 2.0 (for notifications)

### Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jameskeim/nvim-writing-metrics",
  dependencies = { "folke/snacks.nvim" },
  ft = { "markdown", "text" },
  opts = {},
  keys = {
    { "<leader>mc", "<cmd>WordCount<cr>", desc = "Word count" },
    { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability report" },
    { "<leader>mt", "<cmd>WritingMetricsToggle<cr>", desc = "Toggle fast/accurate mode" },
  },
}
```

### Commands

- `:WordCount` - Show word count and basic metrics in floating window
- `:ReadabilityReport` - Generate comprehensive analysis in new tab
- `:ReadingTime` - Show a toast with silent and spoken reading-time estimates
- `:WritingMetricsToggle` - Switch between fast and accurate counting modes

### Reading Time

The plugin estimates reading time from the cached word count and surfaces it in three places:

- **Statusline:** appended after the word/char counts (e.g. `⏱ ~5 min`).
- **`:ReadingTime`:** a toast with both profiles (`~5 min silent · ~7 min spoken`).
- **`:ReadabilityReport`:** two rows in the Basic Statistics table, one per profile.

Defaults: **200 wpm silent** (typical adult silent reading), **150 wpm spoken** (typical presentation pace). Configure under the `reading_time` block (see Configuration below).

### Statusline Integration

Add to your lualine config:

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      require("writing-metrics.basic").lualine_component(),
    },
  },
})
```

See [`examples/lualine-integration.lua`](examples/lualine-integration.lua) for complete examples.

### Configuration

```lua
require("writing-metrics").setup({
  filetypes = { "markdown", "text", "tex", "fountain" },
  display = {
    report_window = "tab",  -- "tab", "split", or "vsplit"
  },
  reading_time = {
    enabled = true,                 -- master switch for the feature
    wpm_silent = 200,               -- silent reading speed
    wpm_spoken = 150,               -- presentation / spoken delivery rate
    statusline = true,              -- show suffix in statusline
    statusline_profile = "silent",  -- "silent" | "spoken" | "both"
  },
})
```

Full configuration options in [`lua/writing-metrics/config.lua`](lua/writing-metrics/config.lua).

## Readability Targets

Different writing needs different readability levels:

- **Grant Writing**: Flesch-Kincaid 11-14, Flesch Reading Ease 50-60
- **Fiction**: Flesch-Kincaid 7-9, Flesch Reading Ease 60-80
- **Academic**: Flesch-Kincaid 12-16, Flesch Reading Ease 30-50

The plugin's reports include interpretation guidance for each metric.

## License

MIT
