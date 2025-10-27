-- Verify statusline performance and caching

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local config = require("writing-metrics.config")
local cache = require("writing-metrics.cache")
local basic = require("writing-metrics.basic")

print("\n" .. string.rep("=", 60))
print("STATUSLINE PERFORMANCE VERIFICATION")
print(string.rep("=", 60) .. "\n")

-- Create test buffer with substantial content
local bufnr = vim.api.nvim_create_buf(false, true)
local lines = {}
for i = 1, 100 do
  table.insert(lines, "This is paragraph " .. i .. ". It contains multiple sentences. Each sentence has several words.")
end
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
vim.api.nvim_set_current_buf(bufnr)

-- Test 1: Fast mode performance (should be < 1ms)
print("Test 1: Fast mode performance")
basic.statusline_mode = "fast"
local start = vim.loop.hrtime()
for i = 1, 100 do
  basic.get_statusline_string(bufnr)
end
local elapsed = (vim.loop.hrtime() - start) / 1000000 -- Convert to ms
print(string.format("  - 100 calls: %.2fms (avg: %.3fms per call)", elapsed, elapsed / 100))
print("  - Status: " .. (elapsed / 100 < 1.0 and "✓ PASS" or "✗ FAIL (too slow)"))

-- Test 2: Cache hit performance
print("\nTest 2: Cache hit performance (accurate mode)")
basic.statusline_mode = "accurate"

-- Pre-populate cache
cache.set_basic(bufnr, {
  words = 1234,
  chars = 8765,
  sentences = 56,
  paragraphs = 12,
  avg_sentence_len = 22,
  avg_word_len = 7.1,
})

start = vim.loop.hrtime()
for i = 1, 100 do
  basic.get_statusline_string(bufnr)
end
elapsed = (vim.loop.hrtime() - start) / 1000000
print(string.format("  - 100 calls: %.2fms (avg: %.3fms per call)", elapsed, elapsed / 100))
print("  - Status: " .. (elapsed / 100 < 0.5 and "✓ PASS" or "✗ FAIL (too slow)"))

-- Test 3: Visual mode detection
print("\nTest 3: Visual mode detection")
-- Can't actually enter visual mode in headless, but test the code path
local statusline = basic.get_statusline_string(bufnr)
print("  - Normal mode output: " .. statusline)
print("  - Contains 'calculating' or count: " .. tostring(statusline:match("calculating") or statusline:match("words")))

-- Test 4: Filetype filtering
print("\nTest 4: Filetype filtering")
vim.api.nvim_buf_set_option(bufnr, "filetype", "lua")
statusline = basic.get_statusline_string(bufnr)
print("  - Non-writing filetype (lua): '" .. statusline .. "'")
print("  - Empty string: " .. tostring(statusline == ""))

vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
statusline = basic.get_statusline_string(bufnr)
print("  - Writing filetype (markdown): '" .. statusline .. "'")
print("  - Has content: " .. tostring(statusline ~= ""))

-- Test 5: Cache stats
print("\nTest 5: Cache statistics")
local stats = cache.get_stats()
print("  - Basic cache entries: " .. stats.basic_entries)
print("  - Full cache entries: " .. stats.full_entries)

-- Test 6: Lualine component conditional
print("\nTest 6: Lualine component conditional")
local component = basic.lualine_component()
vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
print("  - Markdown file shows: " .. tostring(component.cond()))
vim.api.nvim_buf_set_option(bufnr, "filetype", "lua")
print("  - Lua file shows: " .. tostring(component.cond()))
vim.api.nvim_buf_set_option(bufnr, "filetype", "tex")
print("  - TeX file shows: " .. tostring(component.cond()))

print("\n" .. string.rep("=", 60))
print("PERFORMANCE VERIFICATION COMPLETE")
print(string.rep("=", 60) .. "\n")

vim.cmd("qall!")
