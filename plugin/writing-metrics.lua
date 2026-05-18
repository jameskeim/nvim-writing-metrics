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

  -- Register autocommands
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
