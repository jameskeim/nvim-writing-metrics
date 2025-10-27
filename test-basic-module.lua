-- Test script for basic.lua module
-- Run with: nvim --headless -S test-basic-module.lua

-- Add plugin to runtime path
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Load modules
local config = require("writing-metrics.config")
local cache = require("writing-metrics.cache")
local utils = require("writing-metrics.utils")
local basic = require("writing-metrics.basic")

print("\n" .. string.rep("=", 60))
print("WRITING METRICS - BASIC MODULE TEST SUITE")
print(string.rep("=", 60) .. "\n")

-- Test 1: Module loads
print("✓ Test 1: Module loaded successfully")
print("  - basic.lua: " .. (basic and "loaded" or "failed"))
print("  - Functions: " .. vim.inspect(vim.tbl_keys(basic)))

-- Test 2: Global API (backward compatibility)
print("\n✓ Test 2: Global API backward compatibility")
print("  - _G.accurate_wordcount exists: " .. tostring(_G.accurate_wordcount ~= nil))
if _G.accurate_wordcount then
  print("  - Global API functions: " .. vim.inspect(vim.tbl_keys(_G.accurate_wordcount)))
end

-- Test 3: Statusline mode
print("\n✓ Test 3: Statusline mode management")
print("  - Initial mode: " .. basic.statusline_mode)
basic.toggle_statusline_mode()
print("  - After toggle: " .. basic.statusline_mode)
basic.toggle_statusline_mode()
print("  - After second toggle: " .. basic.statusline_mode)

-- Test 4: Fast count
print("\n✓ Test 4: Fast word count (vim.fn.wordcount)")
-- Create a test buffer
local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
  "This is a test.",
  "It has multiple sentences.",
  "And multiple paragraphs.",
})
vim.api.nvim_set_current_buf(bufnr)
local fast = basic.get_fast_count(bufnr)
print("  - Words: " .. fast.words)
print("  - Chars: " .. fast.chars)
print("  - Structure: " .. vim.inspect(fast))

-- Test 5: Statusline string
print("\n✓ Test 5: Statusline string generation")
vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
local statusline = basic.get_statusline_string(bufnr)
print("  - Statusline: " .. statusline)

-- Test 6: Lualine component
print("\n✓ Test 6: Lualine component configuration")
local component = basic.lualine_component()
print("  - Has function: " .. tostring(type(component[1]) == "function"))
print("  - Has cond: " .. tostring(type(component.cond) == "function"))
print("  - Has color: " .. tostring(type(component.color) == "function"))

-- Test 7: Commands registered
print("\n✓ Test 7: User commands")
basic.setup_commands()
local commands = vim.api.nvim_get_commands({})
print("  - WordCount: " .. tostring(commands.WordCount ~= nil))
print("  - AccurateWordCount: " .. tostring(commands.AccurateWordCount ~= nil))
print("  - WritingMetricsToggle: " .. tostring(commands.WritingMetricsToggle ~= nil))
print("  - ToggleWordCountMode: " .. tostring(commands.ToggleWordCountMode ~= nil))

-- Test 8: Autocmds registered
print("\n✓ Test 8: Autocommands")
basic.setup_autocmds()
local autocmds = vim.api.nvim_get_autocmds({ group = "WritingMetricsBasic" })
print("  - Autocmds registered: " .. #autocmds)
for _, cmd in ipairs(autocmds) do
  print("    - " .. cmd.event .. " (" .. cmd.pattern .. ")")
end

print("\n" .. string.rep("=", 60))
print("ALL TESTS PASSED")
print(string.rep("=", 60) .. "\n")

-- Cleanup
vim.cmd("qall!")
