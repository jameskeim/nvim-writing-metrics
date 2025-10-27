-- test-plugin-loader.lua
-- Test the plugin loader system

print("=== Testing Plugin Loader ===\n")

-- Set vim.g to prevent actual initialization (we'll test manually)
vim.g.writing_metrics_lazy = true

-- Load the plugin file
print("1. Loading plugin/writing-metrics.lua...")
local plugin_path = vim.fn.getcwd() .. "/plugin/writing-metrics.lua"
print("   Path: " .. plugin_path)
local ok, err = pcall(dofile, plugin_path)
if ok then
  print("   ✓ Plugin loader loaded successfully")
else
  print("   ✗ Failed to load plugin loader: " .. tostring(err))
  os.exit(1)
end

-- Test that it didn't auto-initialize
print("\n2. Checking lazy loading...")
if vim.g.loaded_writing_metrics then
  print("   ✗ Plugin auto-initialized (should not happen with lazy flag)")
else
  print("   ✓ Plugin did not auto-initialize (correct)")
end

-- Test manual initialization
print("\n3. Testing manual initialization...")
if _G.WritingMetricsInitialize then
  print("   ✓ Initialization function available")

  -- Initialize
  _G.WritingMetricsInitialize()

  if vim.g.loaded_writing_metrics then
    print("   ✓ Plugin initialized successfully")
  else
    print("   ✗ Plugin initialization failed")
  end
else
  print("   ✗ Initialization function not found")
end

-- Test commands are registered
print("\n4. Testing command registration...")
local commands = {
  "WordCount",
  "ReadabilityReport",
  "WritingMetrics",
  "WritingMetricsToggle",
  "WritingMetricsCache",
  "WritingMetricsClear",
  "AccurateWordCount",  -- Backward compat
  "ToggleWordCountMode", -- Backward compat
}

for _, cmd in ipairs(commands) do
  local exists = vim.fn.exists(":" .. cmd) == 2
  if exists then
    print(string.format("   ✓ :%s registered", cmd))
  else
    print(string.format("   ✗ :%s NOT registered", cmd))
  end
end

-- Test autocommands are registered
print("\n5. Testing autocommand registration...")
local autocmds = vim.api.nvim_get_autocmds({ group = "WritingMetrics" })
if #autocmds > 0 then
  print(string.format("   ✓ %d autocommands registered", #autocmds))

  local events = {}
  for _, autocmd in ipairs(autocmds) do
    events[autocmd.event] = (events[autocmd.event] or 0) + 1
  end

  for event, count in pairs(events) do
    print(string.format("     - %s: %d autocommand(s)", event, count))
  end
else
  print("   ✗ No autocommands registered")
end

-- Test backward compatibility API
print("\n6. Testing backward compatibility API...")
if _G.accurate_wordcount then
  print("   ✓ _G.accurate_wordcount() available")
else
  print("   ✗ _G.accurate_wordcount() NOT available")
end

if _G.text_metrics then
  print("   ✓ _G.text_metrics() available")
else
  print("   ✗ _G.text_metrics() NOT available")
end

-- Test command help functionality
print("\n7. Testing :WritingMetrics command...")
local test_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(test_buf)
vim.bo[test_buf].filetype = "markdown"

local cmd_ok, cmd_err = pcall(vim.cmd, "WritingMetrics")
if cmd_ok then
  print("   ✓ :WritingMetrics executed successfully")
  -- Check if window was created
  local wins = vim.api.nvim_list_wins()
  local float_win = false
  for _, win in ipairs(wins) do
    local config = vim.api.nvim_win_get_config(win)
    if config.relative ~= "" then
      float_win = true
      break
    end
  end
  if float_win then
    print("   ✓ Floating window created")
    vim.cmd("close")
  else
    print("   ⚠ No floating window (unexpected)")
  end
else
  print("   ✗ :WritingMetrics failed: " .. tostring(cmd_err))
end

-- Test cache statistics command
print("\n8. Testing :WritingMetricsCache command...")
cmd_ok, cmd_err = pcall(vim.cmd, "WritingMetricsCache")
if cmd_ok then
  print("   ✓ :WritingMetricsCache executed successfully")
  vim.cmd("close")
else
  print("   ✗ :WritingMetricsCache failed: " .. tostring(cmd_err))
end

-- Summary
print("\n" .. string.rep("=", 50))
print("Plugin Loader Test Complete")
print(string.rep("=", 50))
