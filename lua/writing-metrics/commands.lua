--- User command registration for nvim-writing-metrics
--- @module writing-metrics.commands
local M = {}

--- Register all user commands. Idempotent — nvim_create_user_command
--- overwrites on redefine, so calling twice is safe.
--- @param cfg table Resolved config. Used at registration time to decide
---   whether to register or de-register the legacy alias commands.
---   Command callbacks themselves re-read live config via require() for everything
---   else.
function M.setup_commands(cfg)
  -- Primary commands

  vim.api.nvim_create_user_command("WordCount", function(opts)
    local basic = require("writing-metrics.basic")
    if opts.range == 2 then
      basic.show_comparison(vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2])
    else
      basic.show_comparison()
    end
  end, {
    desc = "Show word count (basic metrics)",
    range = true,
  })

  vim.api.nvim_create_user_command("ReadabilityReport", function(opts)
    local full = require("writing-metrics.full")
    if opts.range == 2 then
      full.show_report(vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2])
    else
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
      "| `:ReadingTime` | Show reading time toast (silent + spoken) |",
      "| `:WritingMetricsToggle` | Toggle fast/accurate mode |",
      "| `:WritingMetricsCache` | Show cache status and statistics |",
      "| `:WritingMetricsClear` | Clear all caches |",
      "",
    }

    if config.get().commands and config.get().commands.enable_legacy then
      table.insert(lines, "## Backward Compatibility")
      table.insert(lines, "")
      table.insert(lines, "| Old Command | New Command |")
      table.insert(lines, "|-------------|-------------|")
      table.insert(lines, "| `:AccurateWordCount` | `:WordCount` |")
      table.insert(lines, "| `:ToggleWordCountMode` | `:WritingMetricsToggle` |")
      table.insert(lines, "")
    end

    vim.list_extend(lines, {
      "## Keybindings (suggested)",
      "",
      "```lua",
      "vim.keymap.set('n', '<leader>mc', '<cmd>WordCount<cr>')",
      "vim.keymap.set('v', '<leader>mc', '<cmd>WordCount<cr>')",
      "vim.keymap.set('n', '<leader>mr', '<cmd>ReadabilityReport<cr>')",
      "vim.keymap.set('n', '<leader>mt', '<cmd>WritingMetricsToggle<cr>')",
      "vim.keymap.set('n', '<leader>mT', '<cmd>ReadingTime<cr>')",
      "```",
      "",
      "## Configuration",
      "",
      "**Cache strategy:**",
      "- Statusline: Basic metrics cached until buffer content changes (changedtick)",
      "- Reports: Always compute fresh (no cache)",
      "",
      "**Enabled features:**",
      "- Basic metrics: " .. (config.get().features.basic and "✓" or "✗"),
      "- Readability formulas: " .. (config.get().features.readability and "✓" or "✗"),
      "- Passive voice detection: " .. (config.get().features.passive_voice and "✓" or "✗"),
      "- Nominalization detection: " .. (config.get().features.nominalizations and "✓" or "✗"),
      "- Vocabulary analysis: " .. (config.get().features.vocabulary and "✓" or "✗"),
      "- Sentence variety: " .. (config.get().features.sentence_variety and "✓" or "✗"),
      "",
      "---",
      "",
      "Press `q` to close | See `:help writing-metrics` for full documentation",
    })

    local bufnr = utils.create_float_window({
      title = "Writing Metrics",
      lines = lines,
      border = config.get().display.float_border,
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
      border = config.get().display.float_border,
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
      cache.clear_all()
      utils.notify("All caches cleared", "info")
    else
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

  -- Legacy aliases (gated by config)
  if cfg.commands and cfg.commands.enable_legacy then
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
  else
    -- Explicitly remove legacy commands if they exist from a prior setup()
    -- call with enable_legacy = true. nvim_del_user_command errors if the
    -- command does not exist, so guard with pcall.
    pcall(vim.api.nvim_del_user_command, "AccurateWordCount")
    pcall(vim.api.nvim_del_user_command, "ToggleWordCountMode")
  end
end

return M
