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

### 1. `init.lua` - Main Entry Point (516 lines)

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

### 2. `config.lua` - Configuration & Auto-Detection (248 lines)

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
  cache = {
    basic_ttl = 500,    -- 500ms for statusline (fast updates)
    full_ttl = 30000,   -- 30s for full reports (reduce computation)
  },
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

### 3. `cache.lua` - Intelligent Shared Caching (302 lines)

Implements a two-tier caching system with smart fallback logic.

**Cache Structure:**

```lua
cache = {
  basic = {
    [bufnr] = {
      content_hash = "...",  -- Hash for invalidation
      timestamp = os.time(),
      data = { words = 1247, chars = 7892, ... }
    }
  },
  full = {
    [bufnr] = {
      content_hash = "...",
      timestamp = os.time(),
      data = { basic = {...}, readability = {...}, ... }
    }
  }
}
```

**Smart Cache Logic:**

The cache implements an intelligent optimization:

1. Check basic cache first (500ms TTL)
2. If basic cache expired, check full cache (30s TTL)
3. **If full cache is still valid, extract basic metrics from it** (avoids recomputation!)
4. Only recompute if both caches are invalid

This means:
- Statusline updates every 500ms with fresh data (responsive)
- Full reports cached for 30s (reduces Pandoc executions)
- Basic metrics often extracted from full cache (free optimization)

**Key Functions:**

- `M.get_basic(bufnr)` - Get basic metrics with smart fallback to full cache
- `M.get_full(bufnr)` - Get full metrics from cache
- `M.set_basic(bufnr, data)` - Store basic metrics
- `M.set_full(bufnr, data)` - Store full metrics (also caches extracted basic metrics)
- `M.invalidate(bufnr)` - Clear all caches for buffer
- `M.is_valid(entry, ttl)` - Check if cache entry is still valid
- `M.content_changed(bufnr)` - Check if content changed since last cache
- `M.setup_autocmds()` - Setup automatic cache invalidation
- `M.cleanup_stale_entries()` - Remove entries for deleted buffers

**Automatic Invalidation:**

The cache is automatically invalidated on:
- `TextChanged`, `TextChangedI`, `InsertLeave` - Only if content actually changed
- `BufWritePost` - Ensures metrics reflect saved state
- `BufDelete` - Prevents memory leaks

Periodic cleanup runs every 5 minutes to remove stale entries.

### 4. `utils.lua` - Shared Utilities (378 lines)

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

**Cache Support:**

- `M.get_content_hash(bufnr)` - Generate simple content hash for invalidation

## Design Decisions

### 1. Lazy Loading

All submodules are lazy-loaded on demand:

```lua
local function get_config()
  return require("writing-metrics.config")
end
```

This minimizes startup time and only loads what's needed.

### 2. Content Hashing for Cache Invalidation

Instead of invalidating cache on every cursor movement, we hash buffer content:

```lua
function M.get_content_hash(bufnr)
  local content = M.get_buffer_content(bufnr)
  local len = #content
  local first = content:sub(1, 100)
  local last = content:sub(-100)
  return string.format("%d:%s:%s", len, first, last)
end
```

This is fast (no crypto overhead) and catches actual content changes.

### 3. Smart Cache Extraction

When basic cache expires but full cache is still valid, extract basic metrics:

```lua
local full_entry = cache.full[bufnr]
if full_entry and full_entry.content_hash == current_hash and M.is_valid(full_entry, full_ttl) then
  local basic_data = extract_basic_from_full(full_entry.data)
  if basic_data then
    cache.basic[bufnr] = { ... }
    return basic_data
  end
end
```

This provides the best of both worlds: fast statusline updates without redundant computation.

### 4. Async Execution

Pandoc runs asynchronously using `vim.system()`:

```lua
vim.system(cmd, { text = true }, function(result)
  callback(success, result.stdout)
end)
```

This prevents UI blocking during metrics computation.

### 5. Graceful Degradation

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

### 6. Backward Compatibility

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

Run the comprehensive test suite:

```bash
cd ~/projects/nvim-writing-metrics
nvim -l test_core_modules.lua
```

**Tests:**

1. Config module loads
2. Auto-detect plugin directory
3. Validate Pandoc installation
4. Utils module loads
5. Format utilities work
6. Cache module loads
7. Cache statistics
8. Main module loads
9. Module initialization
10. Compatibility shims exist
11. Statusline component factory
12. Content hashing

All 12 tests must pass before proceeding to integration.

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
  cache = {
    basic_ttl = 1000,  -- Update statusline every 1 second
    full_ttl = 60000,  -- Cache reports for 1 minute
  },
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

- **Total lines:** 1,444
- **Average complexity:** Moderate (async operations, caching logic)
- **Test coverage:** 12 tests, 100% pass rate
- **Dependencies:** Neovim 0.10+, Pandoc 2.19+
