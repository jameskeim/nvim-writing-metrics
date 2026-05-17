-- Compatibility Test Suite
-- Tests that all backward compatibility APIs work correctly
-- Run with: nvim --headless -c "luafile tests/compatibility_test.lua"

local M = {}

-- Test results tracking
local tests_run = 0
local tests_passed = 0
local tests_failed = 0
local failures = {}

-- Helper: Assert function
local function assert_true(condition, message)
  tests_run = tests_run + 1
  if condition then
    tests_passed = tests_passed + 1
  else
    tests_failed = tests_failed + 1
    table.insert(failures, {
      test = message,
      expected = "true",
      got = "false",
    })
  end
end

local function assert_not_nil(value, message)
  tests_run = tests_run + 1
  if value ~= nil then
    tests_passed = tests_passed + 1
  else
    tests_failed = tests_failed + 1
    table.insert(failures, {
      test = message,
      expected = "not nil",
      got = "nil",
    })
  end
end

local function assert_function(func, message)
  tests_run = tests_run + 1
  if type(func) == "function" then
    tests_passed = tests_passed + 1
  else
    tests_failed = tests_failed + 1
    table.insert(failures, {
      test = message,
      expected = "function",
      got = type(func),
    })
  end
end

-- Test 1: Global APIs exist
function M.test_global_apis()
  print("\n=== Testing Global APIs ===")

  -- Test _G.accurate_wordcount exists
  assert_not_nil(_G.accurate_wordcount, "Global _G.accurate_wordcount should exist")

  -- Test _G.text_metrics exists
  assert_not_nil(_G.text_metrics, "Global _G.text_metrics should exist")

  -- Test _G.accurate_wordcount is a table
  assert_true(
    type(_G.accurate_wordcount) == "table",
    "_G.accurate_wordcount should be a table"
  )

  -- Test _G.text_metrics is a table
  assert_true(
    type(_G.text_metrics) == "table",
    "_G.text_metrics should be a table"
  )
end

-- Test 2: accurate_wordcount functions exist
function M.test_accurate_wordcount_functions()
  print("\n=== Testing accurate_wordcount Functions ===")

  if not _G.accurate_wordcount then
    print("⚠ _G.accurate_wordcount not available, skipping tests")
    return
  end

  -- Test core functions exist
  assert_function(
    _G.accurate_wordcount.get_accurate_count,
    "get_accurate_count() should exist"
  )

  assert_function(
    _G.accurate_wordcount.get_fast_count,
    "get_fast_count() should exist"
  )

  assert_function(
    _G.accurate_wordcount.show_comparison,
    "show_comparison() should exist"
  )

  assert_function(
    _G.accurate_wordcount.toggle_statusline_mode,
    "toggle_statusline_mode() should exist"
  )

  assert_function(
    _G.accurate_wordcount.update_lualine_accurate_count,
    "update_lualine_accurate_count() should exist"
  )

  -- Test state variables exist
  assert_not_nil(
    _G.accurate_wordcount.statusline_mode,
    "statusline_mode state should exist"
  )

  assert_not_nil(
    _G.accurate_wordcount.lualine_accurate_cache,
    "lualine_accurate_cache should exist"
  )
end

-- Test 3: text_metrics functions exist
function M.test_text_metrics_functions()
  print("\n=== Testing text_metrics Functions ===")

  if not _G.text_metrics then
    print("⚠ _G.text_metrics not available, skipping tests")
    return
  end

  -- Test core functions exist
  assert_function(
    _G.text_metrics.show_basic_metrics,
    "show_basic_metrics() should exist"
  )

  assert_function(
    _G.text_metrics.show_full_report,
    "show_full_report() should exist"
  )

  assert_function(
    _G.text_metrics.toggle_mode,
    "toggle_mode() should exist"
  )

  assert_function(
    _G.text_metrics.get_wordcount,
    "get_wordcount() should exist"
  )
end

-- Test 4: Commands registered
function M.test_commands()
  print("\n=== Testing Commands ===")

  local commands = {
    "WordCount",
    "ReadabilityReport",
    "WritingMetrics",
    "WritingMetricsToggle",
    "WritingMetricsCache",
    "WritingMetricsClear",
    "AccurateWordCount",  -- Backward compat alias
    "ToggleWordCountMode",  -- Backward compat alias
  }

  for _, cmd in ipairs(commands) do
    local exists = vim.fn.exists(":" .. cmd) == 2
    assert_true(exists, "Command :" .. cmd .. " should be registered")
  end
end

-- Test 5: Modules loadable
function M.test_modules()
  print("\n=== Testing Module Loading ===")

  local modules = {
    "writing-metrics",
    "writing-metrics.config",
    "writing-metrics.cache",
    "writing-metrics.utils",
    "writing-metrics.basic",
    "writing-metrics.full",
    "writing-metrics.display",
  }

  for _, mod in ipairs(modules) do
    local status, result = pcall(require, mod)
    assert_true(
      status,
      "Module " .. mod .. " should load: " .. (status and "✓" or tostring(result))
    )
  end
end

-- Test 6: API calls work (basic smoke test)
function M.test_api_calls()
  print("\n=== Testing API Calls ===")

  -- Test get_fast_count (synchronous, should work)
  if _G.accurate_wordcount and _G.accurate_wordcount.get_fast_count then
    local status, result = pcall(_G.accurate_wordcount.get_fast_count, 0)
    assert_true(
      status,
      "get_fast_count() should execute without error"
    )

    -- Result should be a number
    assert_true(
      type(result) == "number",
      "get_fast_count() should return a number"
    )
  end

  -- Test get_wordcount (for statusline)
  if _G.text_metrics and _G.text_metrics.get_wordcount then
    local status, result = pcall(_G.text_metrics.get_wordcount)
    assert_true(
      status,
      "get_wordcount() should execute without error"
    )

    -- Result should be a number
    assert_true(
      type(result) == "number",
      "get_wordcount() should return a number"
    )
  end

  -- Note: We don't test async functions (get_accurate_count, show_comparison, etc.)
  -- because they require callbacks and are harder to test in headless mode.
  -- These are tested via manual testing and the MIGRATION_CHECKLIST.
  print("  Note: Async functions not tested (requires callbacks)")
end

-- Test 7: Keybindings exist (if set up)
function M.test_keybindings()
  print("\n=== Testing Keybindings ===")

  -- Note: Keybindings depend on user configuration
  -- We can't reliably test them in isolation
  print("  ⓘ Keybinding test requires manual verification")
  print("  ⓘ Press <leader>mc, <leader>mr, <leader>mt to test")

  -- We can check if the global APIs exist, which is what keybindings call
  assert_not_nil(_G.accurate_wordcount, "Keybindings depend on global API")
  assert_not_nil(_G.text_metrics, "Keybindings depend on global API")
end

-- Test 8: Cache system exists
function M.test_cache_system()
  print("\n=== Testing Cache System ===")

  local cache_module = require("writing-metrics.cache")

  assert_not_nil(cache_module, "Cache module should exist")
  assert_function(cache_module.get_basic, "cache.get_basic() should exist")
  assert_function(cache_module.set_basic, "cache.set_basic() should exist")
  assert_function(cache_module.get_full, "cache.get_full() should exist")
  assert_function(cache_module.set_full, "cache.set_full() should exist")
  assert_function(cache_module.clear, "cache.clear() should exist")
  assert_function(cache_module.get_stats, "cache.get_stats() should exist")
end

-- Test 9: Configuration system
function M.test_config_system()
  print("\n=== Testing Configuration System ===")

  local config_module = require("writing-metrics.config")

  assert_not_nil(config_module, "Config module should exist")
  assert_not_nil(config_module.features, "config.features should exist")
  assert_not_nil(config_module.targets, "config.targets should exist")

end

-- Test 10: Display module
function M.test_display_module()
  print("\n=== Testing Display Module ===")

  local display_module = require("writing-metrics.display")

  assert_not_nil(display_module, "Display module should exist")
  assert_function(display_module.float, "display.float() should exist")
  assert_function(display_module.tab, "display.tab() should exist")

  -- Test utility functions
  assert_function(display_module.format_number, "display.format_number() should exist")
end

-- Main test runner
function M.run_all()
  print("\n╔═══════════════════════════════════════════════════════════╗")
  print("║   nvim-writing-metrics Compatibility Test Suite          ║")
  print("╚═══════════════════════════════════════════════════════════╝")

  -- Run all test groups
  M.test_global_apis()
  M.test_accurate_wordcount_functions()
  M.test_text_metrics_functions()
  M.test_commands()
  M.test_modules()
  M.test_api_calls()
  M.test_keybindings()
  M.test_cache_system()
  M.test_config_system()
  M.test_display_module()

  -- Print results
  print("\n╔═══════════════════════════════════════════════════════════╗")
  print("║   Test Results                                            ║")
  print("╚═══════════════════════════════════════════════════════════╝")
  print(string.format("  Tests run:    %d", tests_run))
  print(string.format("  Tests passed: %d (%.1f%%)", tests_passed, (tests_passed / tests_run * 100)))
  print(string.format("  Tests failed: %d", tests_failed))

  if tests_failed > 0 then
    print("\n╔═══════════════════════════════════════════════════════════╗")
    print("║   Failures                                                ║")
    print("╚═══════════════════════════════════════════════════════════╝")
    for i, failure in ipairs(failures) do
      print(string.format("  %d. %s", i, failure.test))
      print(string.format("     Expected: %s", failure.expected))
      print(string.format("     Got:      %s", failure.got))
    end
  end

  print("\n╔═══════════════════════════════════════════════════════════╗")
  print("║   Conclusion                                              ║")
  print("╚═══════════════════════════════════════════════════════════╝")

  if tests_failed == 0 then
    print("  ✓ All compatibility tests passed!")
    print("  ✓ Plugin is backward compatible with existing configurations.")
    print("\n  Next steps:")
    print("    • Test manually with <leader>mc, <leader>mr, <leader>mt")
    print("    • Verify statusline integration works")
    print("    • Run :checkhealth writing-metrics")
    print("    • Check MIGRATION_CHECKLIST.md for full verification")
    return true
  else
    print("  ✗ Some compatibility tests failed.")
    print("  ✗ Plugin may not be fully backward compatible.")
    print("\n  Action required:")
    print("    • Review failures above")
    print("    • Check plugin installation")
    print("    • Verify all modules are loaded")
    print("    • Report issue if problem persists")
    return false
  end
end

-- Run tests when file is sourced
-- To run: nvim --headless -c "luafile tests/compatibility_test.lua"
if vim.fn.expand("%:p") == vim.fn.expand("<sfile>:p") then
  -- Load the plugin first
  local status, _ = pcall(require, "writing-metrics")
  if not status then
    print("ERROR: Could not load writing-metrics plugin")
    print("Make sure the plugin is installed and in your runtimepath")
    vim.cmd("quit")
  end

  -- Run tests
  local success = M.run_all()

  -- Exit with appropriate code
  vim.cmd(success and "quit" or "cquit")
end

return M
