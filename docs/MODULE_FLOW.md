# Module Interaction Flow

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         User Code                            │
│  (lualine, keybindings, commands, writing modes)            │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   init.lua (Public API)                      │
│  - setup()                                                   │
│  - get_metrics(bufnr, mode, callback)                       │
│  - show_basic_metrics() / show_full_report()                │
│  - get_statusline_component()                               │
│  - Global shims: accurate_wordcount(), text_metrics()       │
└─────┬───────────────┬──────────────┬────────────────────────┘
      │               │              │
      ▼               ▼              ▼
┌──────────┐   ┌──────────┐   ┌──────────┐
│ config   │   │  cache   │   │  utils   │
│          │   │          │   │          │
│ - Setup  │   │ - Store  │   │ - Pandoc │
│ - Detect │   │ - Fetch  │   │ - Format │
│ - Valid  │   │ - Invalid│   │ - Files  │
└────┬─────┘   └────┬─────┘   └────┬─────┘
     │              │              │
     └──────────────┴──────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │  scripts/textmetrics  │
        │  (Pandoc Lua filter)  │
        └───────────────────────┘
```

## Detailed Flow: Getting Metrics

### Flow 1: Statusline Update (Fast Path)

```
User opens markdown file
  │
  ├─> Lualine calls get_statusline_component()
  │     │
  │     ├─> Check if writing buffer (is_writing_buffer)
  │     │     └─> config.is_enabled_filetype(ft)
  │     │
  │     ├─> Check basic cache (cache.get_basic)
  │     │     │
  │     │     ├─> Basic cache valid? → Return cached data ✓ (< 0.1ms)
  │     │     │
  │     │     └─> Basic cache expired?
  │     │           └─> Check full cache (smart optimization!)
  │     │                 │
  │     │                 ├─> Full cache valid? → Extract basic metrics ✓
  │     │                 │
  │     │                 └─> Both invalid? → Return "..." (trigger background update)
  │     │
  │     └─> Format and return string (format_number, icons)
  │
  └─> Background update triggered (if cache miss)
        │
        ├─> get_metrics(bufnr, "basic", callback)
        │     │
        │     ├─> Get buffer content (utils.get_buffer_content)
        │     ├─> Write temp file (utils.write_temp_file)
        │     ├─> Run Pandoc async (utils.run_pandoc)
        │     │     └─> vim.system(["pandoc", "--lua-filter", ...])
        │     ├─> Parse output (utils.parse_basic_output)
        │     └─> Store in cache (cache.set_basic)
        │
        └─> Next statusline refresh shows updated data
```

### Flow 2: Full Report (Comprehensive Path)

```
User presses <leader>mr
  │
  ├─> show_full_report()
  │     │
  │     ├─> get_metrics(bufnr, "full", callback)
  │     │     │
  │     │     ├─> Check full cache (cache.get_full)
  │     │     │     │
  │     │     │     ├─> Cache valid? → Return immediately ✓
  │     │     │     │
  │     │     │     └─> Cache invalid? → Compute fresh
  │     │     │           │
  │     │     │           ├─> Get buffer content
  │     │     │           ├─> Write temp file
  │     │     │           ├─> Run Pandoc with mode="full"
  │     │     │           ├─> Parse JSON output
  │     │     │           └─> Store in cache (cache.set_full)
  │     │     │                 └─> Also extracts and caches basic metrics!
  │     │     │
  │     │     └─> Callback with full metrics data
  │     │
  │     ├─> Format full report (format_full_report)
  │     │     ├─> Basic statistics section
  │     │     ├─> Readability scores section
  │     │     ├─> Sentence variety section
  │     │     ├─> Passive voice section
  │     │     ├─> Nominalizations section
  │     │     ├─> Vocabulary section
  │     │     └─> AI words section
  │     │
  │     └─> Display in tab/split (utils.open_report_tab)
  │
  └─> User reviews report
```

## Cache Optimization Strategy

### Scenario: User Opens File and Waits 5 Seconds

```
t=0s:    User opens file
         └─> Statusline requests basic metrics
              └─> Cache miss → Trigger Pandoc (mode="basic")
              └─> Show "..." in statusline

t=0.1s:  Pandoc completes
         └─> Store in basic cache (TTL: 500ms)
         └─> Statusline updates: "1,247 words"

t=0.6s:  Statusline refresh
         └─> Basic cache expired (TTL: 500ms)
         └─> Check full cache → Empty
         └─> Trigger Pandoc (mode="basic")

t=0.7s:  Pandoc completes
         └─> Store in basic cache

t=1.2s:  Statusline refresh
         └─> Basic cache expired
         └─> Trigger Pandoc (mode="basic")

t=3s:    User presses <leader>mr (full report)
         └─> Full cache miss
         └─> Trigger Pandoc (mode="full")

t=3.5s:  Pandoc completes (full metrics)
         └─> Store in full cache (TTL: 30s)
         └─> Extract and store basic metrics
         └─> Display report

t=4s:    Statusline refresh
         └─> Basic cache expired
         └─> Check full cache → VALID! ✓
         └─> Extract basic from full (no Pandoc needed!)
         └─> Update basic cache

t=4.5s:  Statusline refresh
         └─> Basic cache valid → Use cached ✓

t=5s:    Statusline refresh
         └─> Basic cache expired
         └─> Check full cache → VALID! ✓
         └─> Extract basic from full (optimization!)

... continues extracting from full cache until t=33.5s (full TTL expires)
```

**Key Insight:** After requesting a full report, the statusline gets "free" updates for 30 seconds by extracting from the full cache instead of re-running Pandoc.

## Automatic Cache Invalidation

```
User types in buffer
  │
  ├─> TextChanged/TextChangedI/InsertLeave autocmd
  │     │
  │     ├─> cache.content_changed(bufnr)
  │     │     │
  │     │     ├─> Generate current content hash
  │     │     ├─> Compare with cached hash
  │     │     │
  │     │     └─> Hash different?
  │     │           └─> cache.invalidate(bufnr)
  │     │                 ├─> Clear basic cache
  │     │                 └─> Clear full cache
  │     │
  │     └─> Next metrics request triggers fresh computation
  │
  └─> Statusline shows updated metrics after Pandoc completes
```

## Module Dependencies

```
init.lua
  ├─> Depends on: config, cache, utils
  └─> Provides: Public API, global shims

config.lua
  ├─> Depends on: (none, standalone)
  └─> Provides: Configuration, validation, auto-detection

cache.lua
  ├─> Depends on: utils (for content hashing)
  └─> Provides: Two-tier caching with smart extraction

utils.lua
  ├─> Depends on: config (for filter path)
  └─> Provides: File ops, Pandoc execution, formatting, UI
```

## Execution Times (Typical)

| Operation | Time | Path |
|-----------|------|------|
| Cache hit (basic) | < 0.1ms | Memory lookup |
| Cache hit (full) | < 0.1ms | Memory lookup |
| Extract basic from full | < 0.5ms | JSON traversal |
| Content hash generation | 1-2ms | String operations |
| Pandoc (basic mode) | 50-100ms | External process |
| Pandoc (full mode) | 200-500ms | External process |
| Display floating window | 1-2ms | Neovim API |
| Open report in tab | 2-5ms | Neovim API |

## Memory Usage (Per Buffer)

```
Basic cache entry:   ~1 KB
  ├─> content_hash:  100 bytes
  ├─> timestamp:     8 bytes
  └─> data:          ~900 bytes (6 numbers + metadata)

Full cache entry:    ~5-10 KB
  ├─> content_hash:  100 bytes
  ├─> timestamp:     8 bytes
  └─> data:          ~5-10 KB (all metrics, depends on text length)

Total per buffer:    ~6-11 KB (both caches)
```

**For 10 open writing buffers:** ~60-110 KB total memory usage

## Error Handling Flow

```
User requests metrics
  │
  ├─> Validation checks
  │     │
  │     ├─> Not a writing buffer?
  │     │     └─> Return error: "Not a writing buffer"
  │     │
  │     ├─> Pandoc not installed?
  │     │     └─> Return helpful error with installation instructions
  │     │
  │     └─> Filter not found?
  │           └─> Return error with search locations
  │
  ├─> Temp file creation fails?
  │     └─> Return error: "Failed to create temp file"
  │
  ├─> Pandoc execution fails?
  │     └─> Return error: "Pandoc failed: <stderr>"
  │
  └─> Output parsing fails?
        └─> Return error: "Invalid output format"
```

All errors are:
1. Logged to Neovim error buffer
2. Displayed via notification (Snacks.nvim or vim.notify)
3. Returned to callback for programmatic handling

## Initialization Sequence

```
First require("writing-metrics")
  │
  ├─> Load init.lua
  │     └─> Schedule auto-initialization
  │
  └─> vim.schedule() deferred execution
        │
        ├─> Check if already initialized
        │
        └─> Call setup() with defaults
              │
              ├─> Load config module
              │     ├─> Merge user opts with defaults
              │     ├─> Validate Pandoc installation
              │     └─> Auto-detect filter path
              │
              ├─> Load cache module
              │     └─> Setup autocmds for invalidation
              │
              └─> Mark as initialized
```

This ensures the plugin "just works" without explicit setup() call, while still allowing customization.
