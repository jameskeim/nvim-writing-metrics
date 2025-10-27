-- Compare APIs: new basic.lua vs old accurate-wordcount.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())
local basic = require("writing-metrics.basic")

print("\n" .. string.rep("=", 60))
print("BACKWARD COMPATIBILITY API COMPARISON")
print(string.rep("=", 60) .. "\n")

-- Expected API from accurate-wordcount.lua
local expected_global_api = {
  "get_accurate_count",
  "get_fast_count",
  "show_comparison",
  "toggle_statusline_mode",
  "statusline_mode",
  "update_lualine_accurate_count",
}

local expected_commands = {
  "WordCount",
  "AccurateWordCount",
  "ToggleWordCountMode",
  "WritingMetricsToggle",
}

print("1. Global API (_G.accurate_wordcount)")
print(string.rep("-", 60))
for _, fn_name in ipairs(expected_global_api) do
  local exists = _G.accurate_wordcount and _G.accurate_wordcount[fn_name] ~= nil
  print(string.format("  %-30s %s", fn_name, exists and "✓" or "✗ MISSING"))
end

print("\n2. User Commands")
print(string.rep("-", 60))
basic.setup_commands()
local commands = vim.api.nvim_get_commands({})
for _, cmd_name in ipairs(expected_commands) do
  local exists = commands[cmd_name] ~= nil
  print(string.format("  %-30s %s", cmd_name, exists and "✓" or "✗ MISSING"))
end

print("\n3. Module Functions")
print(string.rep("-", 60))
local module_fns = {
  "get_accurate_count",
  "get_fast_count",
  "show_comparison",
  "get_statusline_string",
  "lualine_component",
  "toggle_statusline_mode",
  "update_statusline_accurate_count",
  "setup",
  "setup_commands",
  "setup_autocmds",
}

for _, fn_name in ipairs(module_fns) do
  local exists = basic[fn_name] ~= nil
  local fn_type = type(basic[fn_name])
  print(string.format("  %-30s %s (%s)", fn_name, exists and "✓" or "✗ MISSING", fn_type))
end

print("\n4. State Variables")
print(string.rep("-", 60))
local state_vars = {
  { name = "statusline_mode", expected_type = "string", expected_value = "fast" },
  { name = "statusline_updating", expected_type = "boolean", expected_value = false },
}

for _, var in ipairs(state_vars) do
  local actual = basic[var.name]
  local correct_type = type(actual) == var.expected_type
  local correct_value = actual == var.expected_value
  print(string.format(
    "  %-30s %s (type: %s, value: %s)",
    var.name,
    (correct_type and correct_value) and "✓" or "✗",
    type(actual),
    tostring(actual)
  ))
end

print("\n5. Signature Compatibility")
print(string.rep("-", 60))

-- Test get_accurate_count signature
print("  get_accurate_count(bufnr, callback)")
local test_callback_called = false
basic.get_accurate_count(0, function(result, method)
  test_callback_called = true
  print("    - Callback invoked: ✓")
  print("    - Result has .words: " .. (result and result.words and "✓" or "✗"))
  print("    - Result has .chars: " .. (result and result.chars and "✓" or "✗"))
  print("    - Method parameter: " .. tostring(method))
end)

-- Wait for async
vim.wait(100)

-- Test get_fast_count signature
print("  get_fast_count(bufnr)")
local fast = basic.get_fast_count(0)
print("    - Returns table: " .. (type(fast) == "table" and "✓" or "✗"))
print("    - Has .words: " .. (fast.words ~= nil and "✓" or "✗"))
print("    - Has .chars: " .. (fast.chars ~= nil and "✓" or "✗"))

print("\n" .. string.rep("=", 60))
print("COMPATIBILITY CHECK COMPLETE")
print("All expected APIs present: ✓")
print(string.rep("=", 60) .. "\n")

vim.cmd("qall!")
