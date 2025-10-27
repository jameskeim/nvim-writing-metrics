-- examples/vim-keybindings.lua
-- Keybinding examples for nvim-writing-metrics

-- ============================================================================
-- BASIC KEYBINDINGS
-- ============================================================================

-- Simple keybindings for common operations
vim.keymap.set("n", "<leader>mc", "<cmd>WordCount<cr>", { desc = "Word count" })
vim.keymap.set("v", "<leader>mc", "<cmd>WordCount<cr>", { desc = "Word count (selection)" })
vim.keymap.set("n", "<leader>mr", "<cmd>ReadabilityReport<cr>", { desc = "Readability report" })
vim.keymap.set("n", "<leader>mt", "<cmd>WritingMetricsToggle<cr>", { desc = "Toggle fast/accurate mode" })

-- ============================================================================
-- EXTENDED KEYBINDINGS
-- ============================================================================

-- Full set of keybindings for all commands
vim.keymap.set("n", "<leader>mc", "<cmd>WordCount<cr>", { desc = "Word count" })
vim.keymap.set("v", "<leader>mc", "<cmd>WordCount<cr>", { desc = "Word count (selection)" })
vim.keymap.set("n", "<leader>mr", "<cmd>ReadabilityReport<cr>", { desc = "Readability report" })
vim.keymap.set("v", "<leader>mr", "<cmd>ReadabilityReport<cr>", { desc = "Readability report (selection)" })
vim.keymap.set("n", "<leader>mt", "<cmd>WritingMetricsToggle<cr>", { desc = "Toggle word count mode" })
vim.keymap.set("n", "<leader>mi", "<cmd>WritingMetrics<cr>", { desc = "Plugin info" })
vim.keymap.set("n", "<leader>mC", "<cmd>WritingMetricsCache<cr>", { desc = "Cache status" })
vim.keymap.set("n", "<leader>mX", "<cmd>WritingMetricsClear!<cr>", { desc = "Clear cache" })

-- ============================================================================
-- WHICH-KEY INTEGRATION
-- ============================================================================

-- If you use which-key.nvim, register descriptions:
local wk = require("which-key")

wk.register({
  ["<leader>m"] = {
    name = "Metrics",
    c = { "<cmd>WordCount<cr>", "Word count" },
    r = { "<cmd>ReadabilityReport<cr>", "Readability report" },
    t = { "<cmd>WritingMetricsToggle<cr>", "Toggle mode" },
    i = { "<cmd>WritingMetrics<cr>", "Plugin info" },
    C = { "<cmd>WritingMetricsCache<cr>", "Cache status" },
    X = { "<cmd>WritingMetricsClear!<cr>", "Clear cache" },
  },
}, { mode = "n" })

-- Visual mode mappings
wk.register({
  ["<leader>m"] = {
    name = "Metrics",
    c = { "<cmd>WordCount<cr>", "Word count (selection)" },
    r = { "<cmd>ReadabilityReport<cr>", "Readability (selection)" },
  },
}, { mode = "v" })

-- ============================================================================
-- ALTERNATIVE KEY SCHEMES
-- ============================================================================

-- OPTION 1: Use <leader>w prefix (writing)
vim.keymap.set("n", "<leader>wc", "<cmd>WordCount<cr>", { desc = "Word count" })
vim.keymap.set("v", "<leader>wc", "<cmd>WordCount<cr>", { desc = "Word count (selection)" })
vim.keymap.set("n", "<leader>wr", "<cmd>ReadabilityReport<cr>", { desc = "Readability" })
vim.keymap.set("n", "<leader>wt", "<cmd>WritingMetricsToggle<cr>", { desc = "Toggle mode" })

-- OPTION 2: Use <leader>c prefix (counting)
vim.keymap.set("n", "<leader>cw", "<cmd>WordCount<cr>", { desc = "Word count" })
vim.keymap.set("v", "<leader>cw", "<cmd>WordCount<cr>", { desc = "Word count (selection)" })
vim.keymap.set("n", "<leader>cr", "<cmd>ReadabilityReport<cr>", { desc = "Readability" })

-- OPTION 3: Use g prefix (goto/generate)
vim.keymap.set("n", "gw", "<cmd>WordCount<cr>", { desc = "Word count" })
vim.keymap.set("v", "gw", "<cmd>WordCount<cr>", { desc = "Word count (selection)" })
vim.keymap.set("n", "gr", "<cmd>ReadabilityReport<cr>", { desc = "Readability" })

-- OPTION 4: Use function keys
vim.keymap.set("n", "<F5>", "<cmd>WordCount<cr>", { desc = "Word count" })
vim.keymap.set("v", "<F5>", "<cmd>WordCount<cr>", { desc = "Word count (selection)" })
vim.keymap.set("n", "<F6>", "<cmd>ReadabilityReport<cr>", { desc = "Readability" })
vim.keymap.set("n", "<F7>", "<cmd>WritingMetricsToggle<cr>", { desc = "Toggle mode" })

-- ============================================================================
-- LUA API KEYBINDINGS
-- ============================================================================

-- If you prefer calling Lua functions directly:
vim.keymap.set("n", "<leader>mc", function()
  require("writing-metrics.basic").show_comparison()
end, { desc = "Word count" })

vim.keymap.set("v", "<leader>mc", function()
  local start_line = vim.fn.getpos("'<")[2]
  local end_line = vim.fn.getpos("'>")[2]
  require("writing-metrics.basic").show_comparison(start_line, end_line)
end, { desc = "Word count (selection)" })

vim.keymap.set("n", "<leader>mr", function()
  require("writing-metrics.full").show_report()
end, { desc = "Readability report" })

vim.keymap.set("n", "<leader>mt", function()
  require("writing-metrics.basic").toggle_statusline_mode()
end, { desc = "Toggle mode" })

-- ============================================================================
-- CONTEXT-AWARE KEYBINDINGS
-- ============================================================================

-- Only enable keybindings for writing filetypes:
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "text", "tex", "fountain", "org" },
  callback = function(ev)
    local opts = { buffer = ev.buf, silent = true }

    vim.keymap.set("n", "<leader>mc", "<cmd>WordCount<cr>", vim.tbl_extend("force", opts, { desc = "Word count" }))
    vim.keymap.set("v", "<leader>mc", "<cmd>WordCount<cr>", vim.tbl_extend("force", opts, { desc = "Word count (selection)" }))
    vim.keymap.set("n", "<leader>mr", "<cmd>ReadabilityReport<cr>", vim.tbl_extend("force", opts, { desc = "Readability" }))
    vim.keymap.set("n", "<leader>mt", "<cmd>WritingMetricsToggle<cr>", vim.tbl_extend("force", opts, { desc = "Toggle mode" }))
  end,
})

-- ============================================================================
-- QUICK KEYBINDINGS (Single Key)
-- ============================================================================

-- For heavy writing workflows, use single-key bindings in normal mode:
-- WARNING: These override default Vim keys, use with caution

-- Option: Use <Space> prefix (if <Space> is your leader)
-- Already covered above with <leader>

-- Option: Use localleader (typically backslash)
vim.keymap.set("n", "<localleader>c", "<cmd>WordCount<cr>", { desc = "Word count" })
vim.keymap.set("n", "<localleader>r", "<cmd>ReadabilityReport<cr>", { desc = "Readability" })
vim.keymap.set("n", "<localleader>t", "<cmd>WritingMetricsToggle<cr>", { desc = "Toggle mode" })

-- ============================================================================
-- OPERATOR-PENDING KEYBINDINGS
-- ============================================================================

-- Create operator-pending mappings for advanced usage:
-- Example: "gwiw" = word count for inner word, "gwap" = word count for paragraph

-- Not directly supported by the plugin (counts need line ranges)
-- But you can use visual selection + command:
-- 1. Select text (viw, vap, etc.)
-- 2. Press <leader>mc

-- ============================================================================
-- AUTO-SHOW KEYBINDINGS
-- ============================================================================

-- Automatically show word count on save:
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = { "*.md", "*.txt", "*.tex" },
  callback = function()
    -- Brief notification (doesn't open window)
    local metrics = require("writing-metrics.basic").get_metrics(0)
    if metrics then
      local utils = require("writing-metrics.utils")
      utils.notify(
        string.format("Saved: %s words, %s characters", metrics.words_formatted, metrics.chars_formatted),
        "info"
      )
    end
  end,
})

-- ============================================================================
-- LAZY KEYBINDINGS
-- ============================================================================

-- If using lazy.nvim, define keybindings in the plugin spec:
-- See examples/lazy-nvim-config.lua

-- ============================================================================
-- RECOMMENDED SETUP
-- ============================================================================

-- Our recommendation for most users:
local function setup_writing_metrics_keys()
  -- Normal mode
  vim.keymap.set("n", "<leader>mc", "<cmd>WordCount<cr>", { desc = "Word count" })
  vim.keymap.set("n", "<leader>mr", "<cmd>ReadabilityReport<cr>", { desc = "Readability report" })
  vim.keymap.set("n", "<leader>mt", "<cmd>WritingMetricsToggle<cr>", { desc = "Toggle mode" })
  vim.keymap.set("n", "<leader>mi", "<cmd>WritingMetrics<cr>", { desc = "Plugin info" })

  -- Visual mode (selection analysis)
  vim.keymap.set("v", "<leader>mc", "<cmd>WordCount<cr>", { desc = "Word count (selection)" })
  vim.keymap.set("v", "<leader>mr", "<cmd>ReadabilityReport<cr>", { desc = "Readability (selection)" })
end

-- Call this function from your init.lua:
-- setup_writing_metrics_keys()
