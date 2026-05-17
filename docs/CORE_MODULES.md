# Core Modules Documentation

This document describes the four core modules that power nvim-writing-metrics.

## Architecture Overview

```
nvim-writing-metrics/
├── lua/writing-metrics/
│   ├── init.lua       # Main entry point & public API
│   ├── config.lua     # Configuration & auto-detection
│   ├── cache.lua      # Intelligent shared caching
│   └── utils.lua      # Shared utilities
└── scripts/
    └── textmetrics.lua  # Unified Pandoc filter
```

## Module Descriptions

### 1. `init.lua` - Main Entry Point

The public API module that provides all user-facing functionality.

**Key Functions:**

- `M.setup(opts)` - Initialize plugin with user configuration
- `M.get_metrics(bufnr, mode, callback)` - Get metrics asynchronously
- `M.get_metrics_async(bufnr, mode)` - Promise-style async (returns object with `.after()` method)
- `M.show_basic_metrics(bufnr)` - Display floating window with basic metrics
- `M.show_full_report(bufnr)` - Display comprehensive report in tab/split
- `M.toggle_mode()` - Toggle statusline between fast (cached) and accurate (always fresh)
- `M.is_writing_buffer(bufnr)` - Check if buffer is a writing filetype
- `M.get_statusline_component()` - Factory for statusline integration
- `M.clear_cache(bufnr)` - Clear cache for specific buffer
- `M.clear_all_caches()` - Clear all caches

**Global Compatibility Shims:**

- `_G.accurate_wordcount()` - Returns word count for current buffer (lualine compatible)
- `_G.text_metrics()` - Returns formatted metrics string (lualine compatible)

**Auto-initialization:** The module auto-initializes on first require if not explicitly setup.

### 2. `config.lua` - Configuration & Auto-Detection

Handles configuration management and automatic detection of dependencies.

**Auto-Detection Logic:**

The module finds the bundled Pandoc filter using a fallback chain:

1. **Bundled filter** - `plugin_dir/scripts/textmetrics.lua` (detected via `debug.getinfo`)
2. **XDG data dir** - `~/.local/share/nvim/textmetrics.lua`
3. **User bin** - `~/bin/textmetrics.lua`
4. **System-wide** - `/usr/local/share/nvim/textmetrics.lua`

**Key Functions:**

- `M.find_filter()` - Find Pandoc filter using fallback chain
- `M.validate_pandoc()` - Check Pandoc >= 2.19 is installed
- `M.validate_dependencies()` - Validate both Pandoc and filter
- `M.get_filter_path()` - Get resolved filter path
- `M.setup(opts)` - Merge user config with defaults
- `M.is_enabled_filetype(ft)` - Check if filetype is enabled
- `M.get_targets(writing_type)` - Get target ranges for grant/creative/academic

**Default Configuration:**

```lua
M.defaults = {
  features = {
    basic = true,
    readability = true,
    passive_voice = true,
    nominalizations = true,
    vocabulary = true,
    sentence_variety = true,
    ai_words = true,
  },
  filetypes = {
    "markdown", "text", "tex", "fountain", "org", "asciidoc", "rst"
  },
  display = {
    float_border = "rounded",
    report_window = "tab",  -- or "split", "vsplit"
    statusline_format = "words",  -- "words", "chars", "both"
  },
  targets = {
    grant = {
      flesch_kincaid = { min = 11, max = 14 },
      flesch_reading_ease = { min = 40, max = 60 },
      passive_voice = { max = 10 },
      nominalizations = { max = 5 },
      sentence_variability = { min = 6 },
    },
    creative = { ... },
    academic = { ... },
  },
  filter = {
    auto_detect = true,
    custom_path = nil,  -- Override with custom path
  },
}
```

### 3. `cache.lua` - Per-Buffer Statusline Cache

A single-tier per-buffer cache for basic metrics, validated against Neovim's `b:changedtick`. Full readability reports are never cached — they always compute fresh.

**Cache Structure:**

```lua
cache = {
  basic = {
    [bufnr] = {
      changedtick = 42,        -- Snapshot of b:changedtick when cached
      timestamp = now(),       -- Wall-clock time (for stats only)
      data = { words = 1247, chars = 7892, ... },
      stale = false,           -- True if marked stale pending recompute
    }
  }
}
```

**Validation Logic:**

`M.content_changed(bufnr)` compares the current `vim.b[bufnr].changedtick` against the snapshot stored in the cache entry. The tick is an integer maintained by Neovim that increments on every buffer modification (edit, undo, paste) and never on cursor movement, mode changes, or window operations.

- Cache hit: same tick → return the cached data immediately.
- Cache miss / stale: tick differs → recompute (async) and return the previous data marked `stale=true` so the statusline can show the last known count while updating.

**Key Functions:**

- `M.get_basic(bufnr)` - Return cached basic metrics and a stale flag
- `M.set_basic(bufnr, data)` - Store basic metrics with the current changedtick
- `M.invalidate(bufnr)` - Mark an entry stale (preserves last-known data for display)
- `M.remove(bufnr)` - Drop the entry entirely
- `M.clear_all()` - Drop all entries
- `M.content_changed(bufnr)` - True if `b:changedtick` differs from the cached tick
- `M.get_stats()` / `M.get_statistics()` - Counters for cache-monitoring commands
- `M.setup_autocmds()` - Wire up cache-invalidation autocmds
- `M.cleanup_stale_entries()` - Drop entries for buffers that no longer exist
- `M.inspect(bufnr)` - Diagnostic dump for a single buffer

**Automatic Invalidation:**

Autocmds drive cache-invalidation attempts:
- `TextChanged`, `TextChangedI`, `InsertLeave` — recompute on actual content changes
- `BufWritePost` — ensure metrics reflect the saved state
- `BufDelete` — drop the entry to prevent leaks

A periodic timer (every 5 minutes) calls `cleanup_stale_entries` as a safety net for buffers that left without firing `BufDelete`.

**What's NOT cached:**

`M.show_full_report` always recomputes via `full.get_full_metrics`. Reports are user-triggered (`<leader>mr`) and benefit from up-to-date output more than from cache reuse.

### 4. `utils.lua` - Shared Utilities

Provides utility functions used across all modules.

**Buffer Operations:**

- `M.get_buffer_content(bufnr)` - Extract all buffer lines as string
- `M.get_selection_content()` - Get visual selection
- `M.is_writing_filetype(ft)` - Check if filetype is for writing

**File Operations:**

- `M.write_temp_file(content, extension)` - Write content to temp file
- `M.cleanup_temp_file(path)` - Delete temp file

**Pandoc Execution:**

- `M.run_pandoc(input_file, mode, callback)` - Execute Pandoc asynchronously
- `M.parse_basic_output(output)` - Parse space-separated basic metrics
- `M.parse_full_output(output)` - Parse JSON full metrics

**UI Helpers:**

- `M.create_float_window(content, opts)` - Create floating window
- `M.open_report_tab(content, opts)` - Open report in tab/split/vsplit
- `M.notify(message, level)` - Send notification (Snacks.nvim or vim.notify)

**Formatting:**

- `M.format_number(num)` - Add thousands separators (12,345)
- `M.format_percentage(num, decimals)` - Format as percentage (45.7%)
- `M.format_decimal(num, decimals)` - Format decimal (3.14)

**Error Handling:**

- `M.handle_error(err, context)` - Standardized error handling
- `M.validate_pandoc()` - Check Pandoc availability
- `M.validate_filter()` - Check filter exists

## Design Decisions

### 1. Lazy Loading

All submodules are lazy-loaded on demand:

```lua
local function get_config()
  return require("writing-metrics.config")
end
```

This minimizes startup time and only loads what's needed.

### 2. Changedtick-Based Cache Validation

The cache uses Neovim's built-in `b:changedtick` to decide whether the stored basic metrics are still valid:

```lua
function M.content_changed(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return true
  end
  local tick = vim.b[bufnr].changedtick
  local entry = cache.basic[bufnr]
  return not entry or entry.changedtick ~= tick
end
```

`b:changedtick` is maintained by Neovim — it increments on every actual buffer modification and doesn't move on cursor or window events. Comparing two integers is faster than hashing buffer content and avoids the false invalidations a naive autocmd-based scheme would suffer.

Full reports are not cached at all (see the cache.lua "What's NOT cached" note above): they're user-triggered and benefit more from fresh output than from cache reuse.

### 3. Async Execution

Pandoc runs asynchronously using `vim.system()`:

```lua
vim.system(cmd, { text = true }, function(result)
  callback(success, result.stdout)
end)
```

This prevents UI blocking during metrics computation.

### 4. Graceful Degradation

If Pandoc is missing or filter not found, the plugin provides helpful error messages:

```lua
if not ok then
  return false, [[
Pandoc not found in PATH. Please install Pandoc >= 2.19.

Installation instructions:
  Ubuntu/Debian:  sudo apt install pandoc
  Arch Linux:     sudo pacman -S pandoc
  macOS:          brew install pandoc
  Windows:        choco install pandoc
]]
end
```

### 5. Backward Compatibility

Global shims ensure existing configurations continue working:

```lua
_G.accurate_wordcount = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache = get_cache()
  local cached = cache.get_basic(bufnr)
  return cached and cached.words or 0
end
```

## Testing

Run the spec suite with plenary.busted:

```bash
cd ~/projects/nvim-writing-metrics
./run-tests.sh                          # all specs
./run-tests.sh -t tests/cache_spec.lua  # one file
```

**Spec files in `tests/`:**

- `basic_spec.lua` — basic-mode word/char/sentence counting
- `cache_spec.lua` — cache get/set/invalidate/content_changed
- `compatibility_spec.lua` — legacy `_G.text_metrics` and `_G.accurate_wordcount` shims
- `config_spec.lua` — default merging, filetype enablement, filter detection
- `display_spec.lua` — section heading helper, vocabulary div-by-zero guard, formatter output
- `full_spec.lua` — full-mode JSON parsing, syllable counting, list-paragraph counting
- `init_spec.lua` — `setup()` behavior (e.g., report-tracking reset on `:Lazy reload`)
- `integration_spec.lua` — end-to-end setup with user opts
- `utils_spec.lua` — buffer extraction, temp-file lifecycle, Pandoc invocation

A pre-existing failure cluster in `basic_spec.lua` and `full_spec.lua` is tracked separately; the goal for any new work is that the failure count does not increase.

## Usage Examples

### Basic Usage

```lua
-- Initialize plugin
require("writing-metrics").setup()

-- Get basic metrics
require("writing-metrics").get_metrics(0, "basic", function(success, data)
  if success then
    print(string.format("Words: %d", data.words))
  end
end)

-- Show floating window
require("writing-metrics").show_basic_metrics()

-- Show comprehensive report
require("writing-metrics").show_full_report()
```

### Statusline Integration

```lua
-- For lualine
require('lualine').setup({
  sections = {
    lualine_x = {
      require("writing-metrics").get_statusline_component(),
    }
  }
})

-- Or use global shim (backward compatible)
require('lualine').setup({
  sections = {
    lualine_x = {
      function() return _G.text_metrics() end,
    }
  }
})
```

### Custom Configuration

```lua
require("writing-metrics").setup({
  filetypes = {
    "markdown", "text", "tex", "org"  -- Only these filetypes
  },
  display = {
    report_window = "vsplit",  -- Open reports in vertical split
    statusline_format = "both",  -- Show both words and chars
  },
  filter = {
    custom_path = "/custom/path/to/textmetrics.lua"  -- Override filter location
  },
})
```

## Performance Characteristics

- **Startup time:** < 1ms (lazy-loaded modules)
- **Basic metrics (cached):** < 0.1ms (hash lookup)
- **Basic metrics (fresh):** 50-100ms (Pandoc execution)
- **Full metrics (fresh):** 200-500ms (Pandoc with all features)
- **Memory usage:** ~10KB per cached buffer
- **Cache cleanup:** Automatic, runs every 5 minutes

## Next Steps

With core modules complete, the next phases are:

1. **Track 3: Display Module** - Format and render metrics reports
2. **Track 4: Commands Module** - User commands and keybindings
3. **Track 5: Integration** - Lualine, writing modes, existing plugins
4. **Track 6: Testing** - Comprehensive test suite with plenary.nvim
5. **Track 7: Documentation** - README, help docs, examples

## Module Statistics

- **Total lines (core modules):** ~1,455 across `init.lua`, `config.lua`, `cache.lua`, `utils.lua`
- **Average complexity:** Moderate (async operations, caching logic)
- **Test coverage:** see `tests/*_spec.lua` (run via `./run-tests.sh`)
- **Dependencies:** Neovim 0.10+, Pandoc 2.19+
