# nvim-writing-metrics

> Comprehensive writing metrics and readability analysis for Neovim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-green.svg)](https://neovim.io/)
[![Pandoc](https://img.shields.io/badge/Pandoc-2.19%2B-blue.svg)](https://pandoc.org/)
[![Tests](https://github.com/jkeim/nvim-writing-metrics/workflows/Tests/badge.svg)](https://github.com/jkeim/nvim-writing-metrics/actions)
[![Test Coverage](https://img.shields.io/badge/tests-106%20passed-brightgreen.svg)](tests/)

A powerful Neovim plugin that provides detailed writing metrics and readability analysis for prose documents. Designed for writers working on grants, creative writing, academic papers, and professional documentation.

## Features

### Basic Metrics
- **Word count** - Total words with intelligent caching
- **Character count** - Total characters (with and without spaces)
- **Sentence count** - Accurate sentence detection
- **Paragraph count** - Paragraph enumeration
- **Average metrics** - Words per sentence, characters per word, sentences per paragraph

### Readability Formulas

Six comprehensive readability formulas to assess your writing:

**Tier 1 - Fast (no syllable counting):**
- **Coleman-Liau Index** - Grade level based on letter count and sentence length
- **Automated Readability Index (ARI)** - Grade level based on character-to-word ratio

**Tier 2 - Comprehensive (with syllable counting):**
- **Flesch Reading Ease** - 0-100 scale (higher = easier to read)
- **Flesch-Kincaid Grade Level** - US grade level required to understand text
- **Gunning Fog Index** - Years of education needed, emphasizes complex words
- **SMOG Index** - Simple Measure of Gobbledygook, estimates comprehension difficulty

### Advanced Analysis

- **Passive voice detection** - Identifies passive constructions with percentage
- **Nominalization detection** - Flags noun forms of verbs (e.g., "decision" vs "decide")
- **Vocabulary richness** - Type-token ratio and unique word percentage
- **Sentence variety** - Standard deviation, coefficient of variation, distribution histogram
- **Monotonous pattern detection** - Flags 4+ consecutive similar-length sentences
- **AI-style detection** - Frequency analysis of 80+ AI-associated words

### Performance Features

- **Intelligent caching** - Two-tier cache system (500ms statusline, 30s reports)
- **Async execution** - Non-blocking analysis prevents UI lag
- **Pandoc-powered** - Uses Pandoc Lua filter for accurate markup stripping
- **Statusline integration** - Real-time word count in statusline with minimal overhead

## Requirements

- **Neovim** >= 0.10
- **Pandoc** >= 2.19 (for text analysis)
- **snacks.nvim** >= 2.0 (for UI components)
- Unix-like system (Linux, macOS, WSL)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim) (recommended)

**Full configuration:**

```lua
{
  "jkeim/nvim-writing-metrics",
  dependencies = { "folke/snacks.nvim" },
  ft = { "markdown", "text", "tex", "org", "asciidoc" },
  opts = {
    -- Cache TTL in milliseconds
    cache_ttl_statusline = 500,  -- Fast updates for statusline
    cache_ttl_reports = 30000,   -- 30 seconds for full reports

    -- Feature flags
    enable_statusline = true,
    enable_readability = true,
    enable_advanced = true,

    -- Target thresholds (optional)
    targets = {
      grant_writing = {
        flesch_kincaid = { min = 10, max = 12 },
        gunning_fog = { min = 10, max = 14 },
        ai_words = { max = 0 },
      },
      creative_writing = {
        sentence_variety_cv = { min = 50 },
        flesch_reading_ease = { min = 60, max = 80 },
      },
    },
  },
  keys = {
    { "<leader>mc", "<cmd>WordCount<cr>", desc = "Show word count" },
    { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability report" },
    { "<leader>mt", "<cmd>WritingMetricsToggle<cr>", desc = "Toggle fast/accurate mode" },
  },
}
```

**Minimal configuration:**

```lua
{
  "jkeim/nvim-writing-metrics",
  dependencies = { "folke/snacks.nvim" },
  ft = { "markdown", "text" },
  opts = {},
  keys = {
    { "<leader>mc", "<cmd>WordCount<cr>", desc = "Word count" },
    { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability" },
  },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "jkeim/nvim-writing-metrics",
  requires = { "folke/snacks.nvim" },
  ft = { "markdown", "text", "tex", "org" },
  config = function()
    require("writing-metrics").setup({
      cache_ttl_statusline = 500,
      cache_ttl_reports = 30000,
      enable_statusline = true,
    })
  end,
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'folke/snacks.nvim'
Plug 'jkeim/nvim-writing-metrics'

" In your init.vim or init.lua:
lua << EOF
require("writing-metrics").setup({})
EOF
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:WordCount` | Show basic metrics (words, chars, sentences, paragraphs, averages) |
| `:ReadabilityReport` | Comprehensive analysis (all formulas + variability + AI-style) |
| `:WritingMetricsToggle` | Toggle between fast and accurate word count modes |
| `:WritingMetricsCache` | Show cache statistics and clear cache |

### Keybindings (suggested)

```lua
vim.keymap.set("n", "<leader>mc", "<cmd>WordCount<cr>", { desc = "Show word count" })
vim.keymap.set("n", "<leader>mr", "<cmd>ReadabilityReport<cr>", { desc = "Readability report" })
vim.keymap.set("n", "<leader>mt", "<cmd>WritingMetricsToggle<cr>", { desc = "Toggle mode" })
```

### Workflow Examples

**Quick check while writing:**
```
1. Press <leader>mc to see basic word count
2. Floating window shows stats without interrupting flow
3. Stats cached for 500ms to prevent lag
```

**Comprehensive analysis before submission:**
```
1. Press <leader>mr for full readability report
2. Opens in new tab with complete analysis:
   - Basic statistics
   - All 6 readability scores with interpretation
   - Sentence variability with pattern detection
   - AI-word usage with recommendations
3. Review suggestions, revise text
4. Press q to close report
```

**Target ranges by writing type:**
- **General writing:** Flesch Reading Ease 60-70 (8-9th grade)
- **Grant proposals:** Flesch-Kincaid 10-12 (college level, but clear)
- **Creative writing:** Higher variability (CV > 50%), varied sentence lengths
- **AI-words:** 0 instances ideal for authentic voice

### Statusline Integration

#### lualine.nvim

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      {
        function()
          local metrics = require("writing-metrics")
          if metrics.is_writing_buffer() then
            return metrics.get_statusline_component()
          end
          return ""
        end,
      },
    },
  },
})
```

#### heirline.nvim

```lua
local WritingMetrics = {
  condition = function()
    return require("writing-metrics").is_writing_buffer()
  end,
  provider = function()
    return require("writing-metrics").get_statusline_component()
  end,
  hl = { fg = "green" },
}
```

#### Custom statusline

```lua
-- In your statusline function:
local metrics = require("writing-metrics")
if metrics.is_writing_buffer() then
  statusline = statusline .. metrics.get_statusline_component()
end
```

## Configuration

### Default Configuration

```lua
require("writing-metrics").setup({
  -- Cache configuration
  cache_ttl_statusline = 500,     -- 500ms cache for statusline updates
  cache_ttl_reports = 30000,      -- 30 second cache for full reports

  -- Feature flags
  enable_statusline = true,       -- Enable statusline component
  enable_readability = true,      -- Enable readability formulas
  enable_advanced = true,         -- Enable advanced analysis (passive voice, etc.)

  -- Pandoc configuration
  pandoc_cmd = "pandoc",          -- Pandoc executable name/path
  filter_path = nil,              -- Auto-detected: ~/.local/bin/textmetrics.lua

  -- File type configuration
  filetypes = {                   -- File types to analyze
    "markdown", "text", "tex", "org", "asciidoc",
  },

  -- Display configuration
  float_opts = {                  -- Floating window options for :WordCount
    border = "rounded",
    relative = "cursor",
    width = 50,
    height = 10,
  },

  report_opts = {                 -- Report buffer options for :ReadabilityReport
    filetype = "markdown",
    modifiable = false,
  },

  -- Target thresholds (optional, for highlighting)
  targets = {
    grant_writing = {
      flesch_kincaid = { min = 10, max = 12 },
      gunning_fog = { min = 10, max = 14 },
      ai_words = { max = 0 },
    },
    creative_writing = {
      sentence_variety_cv = { min = 50 },
      flesch_reading_ease = { min = 60, max = 80 },
    },
    academic_writing = {
      flesch_kincaid = { min = 12, max = 16 },
      passive_voice_percent = { max = 10 },
    },
  },
})
```

### Configuration Options

#### Cache TTL

Control how often metrics are recalculated:

```lua
cache_ttl_statusline = 500   -- Statusline: recalculate every 500ms
cache_ttl_reports = 30000    -- Reports: recalculate every 30 seconds
```

**Recommendations:**
- **Large files (10,000+ words):** Increase statusline TTL to 1000-2000ms
- **Small files (< 1,000 words):** Can use 100-200ms for more responsive updates
- **Report TTL:** Keep at 30 seconds unless you need instant updates

#### Feature Flags

Disable features you don't need:

```lua
enable_statusline = false    -- Disable statusline integration
enable_readability = false   -- Disable readability formulas (basic metrics only)
enable_advanced = false      -- Disable passive voice, nominalization, AI detection
```

#### Target Thresholds

Define target ranges for different writing contexts. Metrics outside these ranges will be highlighted in reports:

```lua
targets = {
  grant_writing = {
    flesch_kincaid = { min = 10, max = 12 },        -- Target grade level
    gunning_fog = { min = 10, max = 14 },           -- Education years needed
    ai_words = { max = 0 },                         -- No AI-sounding language
    passive_voice_percent = { max = 5 },            -- Minimal passive voice
  },
  creative_writing = {
    sentence_variety_cv = { min = 50 },             -- High variability
    flesch_reading_ease = { min = 60, max = 80 },   -- Moderate readability
  },
}
```

Access targets in commands:
```vim
:ReadabilityReport grant_writing
:ReadabilityReport creative_writing
```

## Troubleshooting

### "Pandoc not found" error

**Problem:** Plugin can't find Pandoc executable.

**Solution:**
```lua
-- Specify full path to Pandoc
require("writing-metrics").setup({
  pandoc_cmd = "/usr/local/bin/pandoc",  -- or "/opt/homebrew/bin/pandoc" on M1 Mac
})
```

Or install Pandoc:
```bash
# Arch Linux
sudo pacman -S pandoc

# Ubuntu/Debian
sudo apt install pandoc

# macOS
brew install pandoc
```

### "Filter not found" error

**Problem:** Pandoc Lua filter (`textmetrics.lua`) not found.

**Solution:**
1. Check if filter exists: `ls ~/.local/bin/textmetrics.lua`
2. If missing, specify custom path:
```lua
require("writing-metrics").setup({
  filter_path = "/path/to/your/textmetrics.lua",
})
```

### Performance issues with large files

**Problem:** Metrics calculation is slow or causes lag.

**Solution:**
```lua
-- Increase cache TTL to reduce recalculation frequency
require("writing-metrics").setup({
  cache_ttl_statusline = 2000,   -- Update every 2 seconds
  cache_ttl_reports = 60000,     -- Update reports every minute
})
```

Or disable statusline integration:
```lua
require("writing-metrics").setup({
  enable_statusline = false,  -- Use :WordCount command instead
})
```

### Cache not updating

**Problem:** Metrics don't update after editing.

**Solution:**
1. Check cache status: `:WritingMetricsCache`
2. Clear cache manually: `:lua require("writing-metrics").clear_cache()`
3. Ensure autocommands are active: `:autocmd WritingMetrics`

## API Reference

### Public Functions

```lua
local metrics = require("writing-metrics")

-- Get cached metrics for current buffer
local data = metrics.get_metrics()
-- Returns: { words = 1247, chars = 7892, sentences = 42, ... }

-- Get metrics asynchronously (bypasses cache)
metrics.get_metrics_async(function(data)
  print("Words:", data.words)
end)

-- Check if current buffer is a writing file type
local is_writing = metrics.is_writing_buffer()

-- Get statusline component string
local statusline_text = metrics.get_statusline_component()

-- Clear cache for current buffer
metrics.clear_cache()

-- Clear all caches
metrics.clear_all_caches()
```

See `:help writing-metrics-api` for complete API documentation.

## Interpreting Results

### Readability Score Guidelines

**Flesch Reading Ease (0-100, higher = easier):**
- 90-100: Very easy (5th grade)
- 80-89: Easy (6th grade)
- 70-79: Fairly easy (7th grade)
- 60-69: Standard (8th-9th grade)
- 50-59: Fairly difficult (10th-12th grade)
- 30-49: Difficult (college)
- 0-29: Very difficult (graduate level)

**Flesch-Kincaid Grade Level:**
- Direct mapping to US grade level
- 8.0 = 8th grade reading level
- 12.0 = High school senior level
- 16.0 = College graduate level

**Gunning Fog Index:**
- Years of formal education needed
- 12 = High school senior
- 16 = College graduate
- 20+ = Graduate level

**Coleman-Liau & ARI:**
- Similar to Flesch-Kincaid
- US grade level estimates

**SMOG Index:**
- Conservative estimate (often higher than other formulas)
- Focuses on polysyllabic words

### Sentence Variety Interpretation

**Coefficient of Variation (CV):**
- < 30%: Low variability (monotonous)
- 30-50%: Moderate variability (acceptable)
- > 50%: High variability (engaging rhythm)

**Monotonous patterns:**
- Plugin flags 4+ consecutive sentences of similar length
- Vary sentence length for better flow

### AI-Style Detection

**AI-associated words detected:**
- Tier 1 (most notorious): delve, tapestry, landscape, realm, leverage, showcase
- Tier 2 (business jargon): revolutionize, game-changer, cutting-edge, optimize
- Tier 3 (academic overuse): aforementioned, paramount, quintessential, myriad
- Tiers 4-7: Creative clichés, metaphors, transitions, hedging

**Recommendations:**
- 0 instances = Authentic, natural voice
- 1-3 instances = Minor review needed
- 4+ instances = Significant revision recommended

## Testing

This plugin includes a comprehensive test suite using plenary.nvim.

### Running Tests Locally

**Install test dependencies:**
```bash
# plenary.nvim is installed automatically when running tests
```

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

### Test Coverage

The test suite includes:
- **106 test cases** across 6 test files
- **45 test suites** covering all modules
- Configuration and validation tests
- Cache behavior and TTL tests
- Basic and full metrics tests
- End-to-end integration tests
- Backward compatibility tests
- Performance benchmarks

### From Within Neovim

```vim
:PlenaryBustedDirectory tests/      " Run all tests
:PlenaryBustedFile tests/cache_spec.lua  " Run specific file
```

### CI/CD

Tests run automatically on:
- Push to `main` or `develop` branches
- Pull requests to `main`
- Multiple OS (Ubuntu, macOS)
- Multiple Neovim versions (stable, nightly)

See [tests/README.md](tests/README.md) for detailed testing documentation.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- **Bug reports:** Open an issue with reproduction steps
- **Feature requests:** Open an issue with use case description
- **Pull requests:** Fork, create feature branch, submit PR

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by the need for comprehensive writing analysis in Neovim
- Built on the robust Pandoc text processing ecosystem
- Integrates with LazyVim and modern Neovim plugin infrastructure

## Related Projects

- [vim-wordy](https://github.com/preservim/vim-wordy) - Style checking dictionaries
- [ltex-ls](https://github.com/valentjn/ltex-ls) - Grammar checking via Language Server Protocol
- [vale](https://vale.sh/) - Prose linting with style guides

---

**Author:** Jordan Keim
**Repository:** [https://github.com/jkeim/nvim-writing-metrics](https://github.com/jkeim/nvim-writing-metrics)
**Issues:** [https://github.com/jkeim/nvim-writing-metrics/issues](https://github.com/jkeim/nvim-writing-metrics/issues)
