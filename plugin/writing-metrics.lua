-- plugin/writing-metrics.lua
-- Plugin initialization, commands, and autocommands for nvim-writing-metrics
--
-- This file is automatically loaded by Neovim when the plugin is installed.
-- For lazy.nvim users, set vim.g.writing_metrics_lazy = true and use opts table.

-- Prevent loading twice
if vim.g.loaded_writing_metrics then
  return
end

-- ============================================================================
-- Command Registration
-- ============================================================================

local function setup_commands()
  -- Primary commands
  vim.api.nvim_create_user_command("WordCount", function(opts)
    local basic = require("writing-metrics.basic")
    if opts.range == 2 then
      -- Visual mode: show selection count
      basic.show_comparison(vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2])
    else
      -- Normal mode: show full document count
      basic.show_comparison()
    end
  end, {
    desc = "Show word count (basic metrics)",
    range = true,
  })

  vim.api.nvim_create_user_command("ReadabilityReport", function(opts)
    local full = require("writing-metrics.full")
    if opts.range == 2 then
      -- Visual mode: analyze selection
      full.show_report(vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2])
    else
      -- Normal mode: analyze full document
      full.show_report()
    end
  end, {
    desc = "Generate comprehensive readability report",
    range = true,
  })

  vim.api.nvim_create_user_command("ReadingTime", function()
    require("writing-metrics.basic").show_reading_time()
  end, { desc = "Show reading time toast (silent + spoken)" })

  vim.api.nvim_create_user_command("WritingMetrics", function()
    local config = require("writing-metrics.config")
    local utils = require("writing-metrics.utils")

    local pandoc_status = vim.fn.executable("pandoc") == 1
      and "✓ Available"
      or "✗ Not found (install for full functionality)"

    local lines = {
      "# Writing Metrics Plugin",
      "",
      "**Version:** 1.0.0",
      "**Pandoc:** " .. pandoc_status,
      "",
      "## Commands",
      "",
      "| Command | Description |",
      "|---------|-------------|",
      "| `:WordCount` | Show basic word count (works in visual mode) |",
      "| `:ReadabilityReport` | Generate comprehensive report |",
      "| `:WritingMetricsToggle` | Toggle fast/accurate mode |",
      "| `:WritingMetricsCache` | Show cache status and statistics |",
      "| `:WritingMetricsClear` | Clear all caches |",
      "",
      "## Backward Compatibility",
      "",
      "| Old Command | New Command |",
      "|-------------|-------------|",
      "| `:AccurateWordCount` | `:WordCount` |",
      "| `:ToggleWordCountMode` | `:WritingMetricsToggle` |",
      "",
      "## Keybindings (suggested)",
      "",
      "```lua",
      "vim.keymap.set('n', '<leader>mc', '<cmd>WordCount<cr>')",
      "vim.keymap.set('v', '<leader>mc', '<cmd>WordCount<cr>')",
      "vim.keymap.set('n', '<leader>mr', '<cmd>ReadabilityReport<cr>')",
      "vim.keymap.set('n', '<leader>mt', '<cmd>WritingMetricsToggle<cr>')",
      "```",
      "",
      "## Configuration",
      "",
      "**Cache strategy:**",
      "- Statusline: Basic metrics cached for " .. config.config.cache.basic_ttl .. "ms",
      "- Reports: Always compute fresh (no cache)",
      "",
      "**Enabled features:**",
      "- Basic metrics: " .. (config.config.features.basic and "✓" or "✗"),
      "- Readability formulas: " .. (config.config.features.readability and "✓" or "✗"),
      "- Passive voice detection: " .. (config.config.features.passive_voice and "✓" or "✗"),
      "- Nominalization detection: " .. (config.config.features.nominalizations and "✓" or "✗"),
      "- Vocabulary analysis: " .. (config.config.features.vocabulary and "✓" or "✗"),
      "- Sentence variety: " .. (config.config.features.sentence_variety and "✓" or "✗"),
      "",
      "---",
      "",
      "Press `q` to close | See `:help writing-metrics` for full documentation",
    }

    local bufnr = utils.create_float_window({
      title = "Writing Metrics",
      lines = lines,
      border = config.config.display.float_border,
    })

    vim.bo[bufnr].filetype = "markdown"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, silent = true, nowait = true })
  end, {
    desc = "Show Writing Metrics help and status",
  })

  vim.api.nvim_create_user_command("WritingMetricsToggle", function()
    local basic = require("writing-metrics.basic")
    basic.toggle_statusline_mode()
  end, {
    desc = "Toggle between fast and accurate word count mode",
  })

  -- Backward compatibility aliases
  vim.api.nvim_create_user_command("AccurateWordCount", function(opts)
    local basic = require("writing-metrics.basic")
    if opts.range == 2 then
      basic.show_comparison(vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2])
    else
      basic.show_comparison()
    end
  end, {
    desc = "Show word count (backward compat alias)",
    range = true,
  })

  vim.api.nvim_create_user_command("ToggleWordCountMode", function()
    local basic = require("writing-metrics.basic")
    basic.toggle_statusline_mode()
  end, {
    desc = "Toggle word count mode (backward compat alias)",
  })

  vim.api.nvim_create_user_command("WritingMetricsCache", function()
    local cache = require("writing-metrics.cache")
    local config = require("writing-metrics.config")
    local utils = require("writing-metrics.utils")
    local stats = cache.get_statistics()

    local lines = {
      "# Cache Statistics",
      "",
      "## Basic Cache (Statusline Only)",
      "",
      "| Metric | Value |",
      "|--------|-------|",
      "| Entries | " .. stats.basic.count .. " |",
      "| Memory | " .. string.format("%.2f KB", stats.basic.memory / 1024) .. " |",
      "| TTL | " .. stats.basic.ttl .. "ms |",
      "",
      "## Cache Strategy",
      "",
      "- **Statusline:** Content-based cache (like Vim's wordcount) - valid until text changes",
      "- **Reports:** Always compute fresh (no cache)",
      "",
      "Cache is invalidated on text changes, not time-based expiration.",
      "",
      "---",
      "",
      "Press `q` to close | Use `:WritingMetricsClear` to clear cache",
    }

    local bufnr = utils.create_float_window({
      title = "Cache Status",
      lines = lines,
      border = config.config.display.float_border,
    })

    vim.bo[bufnr].filetype = "markdown"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, silent = true, nowait = true })
  end, {
    desc = "Show cache statistics and performance metrics",
  })

  vim.api.nvim_create_user_command("WritingMetricsClear", function(opts)
    local cache = require("writing-metrics.cache")
    local utils = require("writing-metrics.utils")

    if opts.bang then
      -- Force clear without confirmation
      cache.clear_all()
      utils.notify("All caches cleared", "info")
    else
      -- Ask for confirmation
      local choice = vim.fn.confirm(
        "Clear all Writing Metrics caches?",
        "&Yes\n&No",
        2
      )

      if choice == 1 then
        cache.clear_all()
        utils.notify("All caches cleared", "info")
      else
        utils.notify("Cache clear cancelled", "info")
      end
    end
  end, {
    desc = "Clear all caches (use ! to skip confirmation)",
    bang = true,
  })

  -- Backward compatibility aliases
  vim.api.nvim_create_user_command("AccurateWordCount", function(opts)
    vim.cmd("WordCount" .. (opts.range == 2 and " '<,'>" or ""))
  end, {
    desc = "DEPRECATED: Use :WordCount instead",
    range = true,
  })

  vim.api.nvim_create_user_command("ToggleWordCountMode", function()
    vim.cmd("WritingMetricsToggle")
  end, {
    desc = "DEPRECATED: Use :WritingMetricsToggle instead",
  })
end

-- ============================================================================
-- Autocommand Registration
-- ============================================================================

local function setup_autocommands()
  local group = vim.api.nvim_create_augroup("WritingMetrics", { clear = true })
  local cache = require("writing-metrics.cache")

  -- Cache invalidation on text changes
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    pattern = { "*.md", "*.txt", "*.tex", "*.fountain", "*.org", "*.asciidoc", "*.rst" },
    callback = function(ev)
      cache.invalidate(ev.buf)
    end,
    desc = "Invalidate cache on text changes",
  })

  -- Cache invalidation after insert mode
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    pattern = { "*.md", "*.txt", "*.tex", "*.fountain", "*.org", "*.asciidoc", "*.rst" },
    callback = function(ev)
      cache.invalidate(ev.buf)
    end,
    desc = "Invalidate cache after leaving insert mode",
  })

  -- Cache invalidation after save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = { "*.md", "*.txt", "*.tex", "*.fountain", "*.org", "*.asciidoc", "*.rst" },
    callback = function(ev)
      cache.invalidate(ev.buf)
    end,
    desc = "Invalidate cache after saving",
  })

  -- Cache cleanup on buffer deletion
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    pattern = { "*.md", "*.txt", "*.tex", "*.fountain", "*.org", "*.asciidoc", "*.rst" },
    callback = function(ev)
      cache.invalidate(ev.buf)
    end,
    desc = "Clean up cache on buffer deletion",
  })
end

-- ============================================================================
-- Plugin Initialization
-- ============================================================================

local function initialize(opts)
  -- Load main module
  local ok, wm = pcall(require, "writing-metrics")
  if not ok then
    vim.notify(
      "Writing Metrics: Failed to load main module: " .. tostring(wm),
      vim.log.levels.ERROR
    )
    return
  end

  -- Setup with provided opts (from lazy.nvim) or defaults
  local setup_ok = wm.setup(opts or {})
  if not setup_ok then
    vim.notify(
      "Writing Metrics: Setup failed - check dependencies",
      vim.log.levels.WARN
    )
    return
  end

  -- Register commands and autocommands
  setup_commands()
  setup_autocommands()

  -- Setup basic module (statusline integration)
  local basic_ok, basic = pcall(require, "writing-metrics.basic")
  if basic_ok then
    basic.setup()
  end

  -- Mark as loaded
  vim.g.loaded_writing_metrics = 1
end

-- ============================================================================
-- Auto-initialize or expose module for lazy.nvim
-- ============================================================================

if not vim.g.writing_metrics_lazy then
  -- Traditional plugin loading - initialize immediately
  initialize()
end

-- Export module for lazy.nvim config function
return {
  setup = initialize,
}
