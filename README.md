# nvim-writing-metrics

Comprehensive writing metrics and readability analysis for Neovim

[Documentation in progress]

## Features

- Real-time word count with intelligent caching
- 6 readability formulas (Coleman-Liau, ARI, Flesch Reading Ease, Flesch-Kincaid, Gunning Fog, SMOG)
- Sentence variability analysis with pattern detection
- AI-style detection (80+ AI-associated words)
- Statusline integration
- Two-tier caching system for performance
- Pandoc Lua filter for accurate analysis

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "jkeim/nvim-writing-metrics",
  dependencies = { "folke/snacks.nvim" },
  opts = {},
}
```

## Usage

[Documentation in progress]

## Configuration

[Documentation in progress]

## Requirements

- Neovim >= 0.9.0
- Pandoc (for accurate metrics)
- [snacks.nvim](https://github.com/folke/snacks.nvim) (for UI components)

## License

MIT License - see LICENSE file for details
