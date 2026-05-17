# Quick Start Guide

## Installation

### Using lazy.nvim (Recommended)

Add to your `lazy.nvim` configuration:

```lua
{
  "jameskeim/nvim-writing-metrics",
  dependencies = { "folke/snacks.nvim" },  -- Optional but recommended
  cmd = { "WordCount", "ReadabilityReport" },
  ft = { "markdown", "text", "tex", "fountain", "org" },
  keys = {
    { "<leader>mc", "<cmd>WordCount<cr>", mode = { "n", "v" }, desc = "Word count" },
    { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability report" },
    { "<leader>mt", "<cmd>WritingMetricsToggle<cr>", desc = "Toggle mode" },
  },
}
```

### Using packer.nvim

```lua
use {
  "jameskeim/nvim-writing-metrics",
  requires = { "folke/snacks.nvim" },
  cmd = { "WordCount", "ReadabilityReport" },
  ft = { "markdown", "text", "tex" },
  config = function()
    require("writing-metrics").setup()
  end,
}
```

### Using vim-plug

```vim
Plug 'jameskeim/nvim-writing-metrics'
```

## Basic Usage

### 1. Word Count

Open any writing file (markdown, text, etc.) and run:

```vim
:WordCount
```

This shows:
- Word count (fast and accurate)
- Character count
- Sentence count
- Paragraph count
- Average word and sentence length

**Visual mode:** Select text and run `:WordCount` to analyze just the selection.

### 2. Comprehensive Analysis

For detailed readability metrics:

```vim
:ReadabilityReport
```

This generates a full report with:
- All 6 readability formulas (Coleman-Liau, ARI, Flesch Reading Ease, Flesch-Kincaid, Gunning Fog, SMOG)
- Sentence variability analysis
- Passive voice detection
- Nominalization detection
- Vocabulary richness
- AI-word detection

### 3. Statusline Integration

The plugin automatically adds word/character counts to your statusline for writing files.

To toggle between fast and accurate modes:

```vim
:WritingMetricsToggle
```

## Keybindings

The plugin doesn't create keybindings automatically. Add these to your config:

```lua
vim.keymap.set("n", "<leader>mc", "<cmd>WordCount<cr>", { desc = "Word count" })
vim.keymap.set("v", "<leader>mc", "<cmd>WordCount<cr>", { desc = "Word count (selection)" })
vim.keymap.set("n", "<leader>mr", "<cmd>ReadabilityReport<cr>", { desc = "Readability report" })
vim.keymap.set("n", "<leader>mt", "<cmd>WritingMetricsToggle<cr>", { desc = "Toggle mode" })
```

Or use lazy.nvim's `keys` specification (see Installation above).

## Lualine Integration

If you use lualine, add the plugin's component:

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      require("writing-metrics.basic").lualine_component(),
      "encoding",
      "fileformat",
      "filetype",
    },
  },
})
```

## Configuration

The plugin works out of the box with sensible defaults. To customize:

```lua
{
  "jameskeim/nvim-writing-metrics",
  opts = {
    features = {
      basic = true,
      readability = true,
      passive_voice = true,
      nominalizations = true,
      vocabulary = true,
      sentence_variety = true,
    },
    display = {
      float_border = "rounded",
      report_window = "tab",  -- or "split", "vsplit"
    },
  },
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:WordCount` | Show basic word count (works in visual mode) |
| `:ReadabilityReport` | Generate comprehensive readability report |
| `:WritingMetricsToggle` | Toggle fast/accurate word count mode |
| `:WritingMetrics` | Show plugin info and help |
| `:WritingMetricsCache` | Show cache statistics |
| `:WritingMetricsClear` | Clear all caches |

## Workflows

### Grant Writing

1. Write your grant proposal in markdown
2. Press `<leader>mr` to generate readability report
3. Check Flesch-Kincaid grade level (target: 11-14 for most grants)
4. Check passive voice percentage (target: < 10%)
5. Review flagged AI-words and replace with concrete language

### Creative Writing

1. Write your story/essay in markdown
2. Press `<leader>mc` to check word count against target
3. Press `<leader>mr` to analyze sentence variability
4. Target high variability (coefficient > 50%) for engaging rhythm

### Blog Posts

1. Write in markdown
2. Check word count (target: 1,000-2,000 words for SEO)
3. Check Flesch Reading Ease (target: 60-70 for general audience)
4. Verify no AI-sounding language

## Troubleshooting

### No word count showing in statusline

1. Check filetype: `:set filetype?`
2. Verify it's a writing filetype (markdown, text, tex, etc.)
3. Try manually: `:lua print(require("writing-metrics.basic").get_statusline_string(0))`

### Readability report fails

1. Check Pandoc is installed: `pandoc --version`
2. Install Pandoc: `sudo pacman -S pandoc` (Arch) or `brew install pandoc` (Mac)
3. Verify filter is found: `:WritingMetrics`

### Stale word counts

1. Clear cache: `:WritingMetricsClear!`
2. Reduce cache TTL in config
3. Switch to fast mode: `:WritingMetricsToggle`

## Performance

The plugin is optimized for large documents:

- **Statusline:** Updates cached every 500ms (no lag)
- **Basic metrics:** Uses Vim's native counting (instant)
- **Full reports:** Cached for 30s (expensive Pandoc analysis runs once)

For very large files (100K+ words):

```lua
opts = {
  statusline = {
    mode = "fast",  -- Use fast counting (no Pandoc)
  },
}
```

## Next Steps

- See `examples/lazy-nvim-config.lua` for detailed configuration examples
- See `examples/lualine-integration.lua` for statusline integration
- See `examples/vim-keybindings.lua` for keybinding ideas
- Run `:WritingMetrics` for plugin status and help

## Support

- Report issues: https://github.com/jameskeim/nvim-writing-metrics/issues
- Read docs: `:help writing-metrics` (TODO: create help docs)
- Check examples: `examples/` directory in plugin repository
