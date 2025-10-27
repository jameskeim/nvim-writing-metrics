#!/usr/bin/env nvim -l
--- Test script for core modules
--- Run with: nvim -l test_core_modules.lua

print("=== Testing nvim-writing-metrics Core Modules ===\n")

-- Add plugin to runtimepath
local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
vim.opt.runtimepath:prepend(plugin_dir)

local success_count = 0
local fail_count = 0

local function test(name, func)
  io.write(string.format("Testing: %s ... ", name))
  local ok, err = pcall(func)
  if ok then
    print("✓")
    success_count = success_count + 1
  else
    print("✗")
    print("  Error: " .. tostring(err))
    fail_count = fail_count + 1
  end
end

-- Test 1: Config module loads
test("config module loads", function()
  local config = require("writing-metrics.config")
  assert(config.defaults, "Config should have defaults")
  assert(config.defaults.cache, "Config should have cache settings")
  assert(config.defaults.filetypes, "Config should have filetypes")
end)

-- Test 2: Auto-detect plugin directory
test("auto-detect plugin directory", function()
  local config = require("writing-metrics.config")
  local filter_path, err = config.find_filter()
  assert(filter_path, "Filter should be found: " .. tostring(err))
  print(string.format("\n    Filter found at: %s", filter_path))
end)

-- Test 3: Validate Pandoc
test("validate Pandoc installation", function()
  local config = require("writing-metrics.config")
  local ok, err = config.validate_pandoc()
  assert(ok, "Pandoc validation failed: " .. tostring(err))
end)

-- Test 4: Utils module loads
test("utils module loads", function()
  local utils = require("writing-metrics.utils")
  assert(utils.get_buffer_content, "Utils should have get_buffer_content")
  assert(utils.format_number, "Utils should have format_number")
  assert(utils.run_pandoc, "Utils should have run_pandoc")
end)

-- Test 5: Format utilities
test("format utilities work", function()
  local utils = require("writing-metrics.utils")
  assert(utils.format_number(12345) == "12,345", "Number formatting failed")
  assert(utils.format_percentage(45.678, 1) == "45.7%", "Percentage formatting failed")
  assert(utils.format_decimal(3.14159, 2) == "3.14", "Decimal formatting failed")
end)

-- Test 6: Cache module loads
test("cache module loads", function()
  local cache = require("writing-metrics.cache")
  assert(cache.get_basic, "Cache should have get_basic")
  assert(cache.get_full, "Cache should have get_full")
  assert(cache.set_basic, "Cache should have set_basic")
  assert(cache.invalidate, "Cache should have invalidate")
end)

-- Test 7: Cache statistics
test("cache statistics work", function()
  local cache = require("writing-metrics.cache")
  local stats = cache.get_stats()
  assert(type(stats.basic_entries) == "number", "Stats should have basic_entries count")
  assert(type(stats.full_entries) == "number", "Stats should have full_entries count")
end)

-- Test 8: Main module loads
test("main module loads", function()
  local metrics = require("writing-metrics")
  assert(metrics.setup, "Should have setup function")
  assert(metrics.get_metrics, "Should have get_metrics function")
  assert(metrics.show_basic_metrics, "Should have show_basic_metrics")
  assert(metrics.show_full_report, "Should have show_full_report")
end)

-- Test 9: Module initialization
test("module initialization", function()
  local metrics = require("writing-metrics")
  local ok = metrics.setup()
  assert(ok, "Setup should succeed")
  assert(metrics._initialized, "Module should be marked as initialized")
end)

-- Test 10: Compatibility shims
test("compatibility shims exist", function()
  assert(_G.accurate_wordcount, "Global accurate_wordcount should exist")
  assert(_G.text_metrics, "Global text_metrics should exist")
  assert(type(_G.accurate_wordcount) == "function", "accurate_wordcount should be a function")
  assert(type(_G.text_metrics) == "function", "text_metrics should be a function")
end)

-- Test 11: Statusline component
test("statusline component factory", function()
  local metrics = require("writing-metrics")
  local component = metrics.get_statusline_component()
  assert(type(component) == "function", "Should return a function")
end)

-- Test 12: Content hashing
test("content hashing works", function()
  local utils = require("writing-metrics.utils")
  -- Create a test buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Test content", "Second line" })
  local hash1 = utils.get_content_hash(bufnr)
  assert(type(hash1) == "string", "Hash should be a string")
  assert(#hash1 > 0, "Hash should not be empty")
  -- Same content should produce same hash
  local hash2 = utils.get_content_hash(bufnr)
  assert(hash1 == hash2, "Same content should produce same hash")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Summary
print("\n=== Test Summary ===")
print(string.format("✓ Passed: %d", success_count))
print(string.format("✗ Failed: %d", fail_count))
print(string.format("Total:    %d", success_count + fail_count))

if fail_count > 0 then
  os.exit(1)
else
  print("\n✓ All tests passed!")
  os.exit(0)
end
