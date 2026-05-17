-- examples/statusline-integration.lua
-- Integration examples for various statusline plugins

-- ============================================================================
-- LUALINE - Recommended
-- ============================================================================

-- See examples/lualine-integration.lua for comprehensive lualine examples

require("lualine").setup({
  sections = {
    lualine_x = {
      require("writing-metrics.basic").lualine_component(),
      "encoding",
      "fileformat",
      "filetype",
    },
  },
})

-- ============================================================================
-- NATIVE VIM STATUSLINE
-- ============================================================================

-- For users who prefer Vim's built-in statusline:

-- Option 1: Simple integration
vim.o.statusline = table.concat({
  "%f",                           -- File path
  " %m",                          -- Modified flag
  "%=",                           -- Right align
  "%{v:lua.accurate_wordcount()}", -- Word count (backward compat API)
  " %y",                          -- File type
  " %l:%c",                       -- Line:column
}, "")

-- Option 2: Full custom statusline
function _G.custom_statusline()
  local parts = {}

  -- Left side
  table.insert(parts, "%f")  -- File path
  table.insert(parts, " %m") -- Modified flag

  -- Center
  table.insert(parts, "%=")

  -- Right side - Writing metrics
  local ft = vim.bo.filetype
  if vim.tbl_contains({ "markdown", "text", "tex", "fountain", "org" }, ft) then
    local metrics_str = require("writing-metrics.basic").get_statusline_string(0)
    if metrics_str and metrics_str ~= "" then
      table.insert(parts, metrics_str)
      table.insert(parts, "  ")
    end
  end

  -- Right side - Standard info
  table.insert(parts, "%y")      -- File type
  table.insert(parts, " %l:%c")  -- Line:column
  table.insert(parts, " %p%%")   -- Percentage

  return table.concat(parts, "")
end

vim.o.statusline = "%{%v:lua.custom_statusline()%}"

-- ============================================================================
-- AIRLINE (vim-airline)
-- ============================================================================

-- For vim-airline users (Vimscript plugin):
-- Add this to your vimrc or init.vim:
--
-- function! WordCountSection()
--   if index(['markdown', 'text', 'tex', 'fountain', 'org'], &filetype) >= 0
--     return luaeval('require("writing-metrics.basic").get_statusline_string(0)')
--   endif
--   return ''
-- endfunction
--
-- " Add to airline config
-- let g:airline_section_x = airline#section#create_right(['%{WordCountSection()}', 'filetype'])

-- ============================================================================
-- GALAXYLINE
-- ============================================================================

-- For galaxyline users:
local gl = require("galaxyline")
local gls = gl.section

-- Add to your galaxyline config
gls.right[5] = {
  WritingMetrics = {
    provider = function()
      local ft = vim.bo.filetype
      if not vim.tbl_contains({ "markdown", "text", "tex", "fountain", "org" }, ft) then
        return ""
      end

      return require("writing-metrics.basic").get_statusline_string(0)
    end,
    separator = " ",
    separator_highlight = { "NONE", "NONE" },
    highlight = { "#9ece6a", "NONE" },
  },
}

-- ============================================================================
-- FELINE
-- ============================================================================

-- For feline.nvim users:
local feline = require("feline")

-- Add to your components
local writing_metrics_component = {
  provider = function()
    local ft = vim.bo.filetype
    if not vim.tbl_contains({ "markdown", "text", "tex", "fountain", "org" }, ft) then
      return ""
    end

    return require("writing-metrics.basic").get_statusline_string(0)
  end,
  hl = {
    fg = "#9ece6a",
  },
  left_sep = " ",
}

-- Add to your feline setup
local components = {
  active = {
    {
      -- Left components
    },
    {
      -- Right components
      writing_metrics_component,
      -- Other components...
    },
  },
}

feline.setup({
  components = components,
})

-- ============================================================================
-- HEIRLINE
-- ============================================================================

-- For heirline.nvim users:
local conditions = require("heirline.conditions")

local WritingMetrics = {
  condition = function()
    local ft = vim.bo.filetype
    return vim.tbl_contains({ "markdown", "text", "tex", "fountain", "org" }, ft)
  end,
  provider = function()
    return require("writing-metrics.basic").get_statusline_string(0)
  end,
  hl = { fg = "#9ece6a" },
}

-- Add to your statusline configuration
local statusline = {
  -- ... other components
  { provider = " " },
  WritingMetrics,
  -- ... other components
}

require("heirline").setup({
  statusline = statusline,
})

-- ============================================================================
-- STALINE
-- ============================================================================

-- For staline.nvim users:
require("staline").setup({
  sections = {
    left = { "-mode", "left_sep_double", " ", "branch" },
    mid = { "file_name" },
    right = {
      function()
        local ft = vim.bo.filetype
        if not vim.tbl_contains({ "markdown", "text", "tex" }, ft) then
          return ""
        end
        return require("writing-metrics.basic").get_statusline_string(0)
      end,
      "right_sep_double",
      "-line_column",
    },
  },
})

-- ============================================================================
-- CUSTOM STATUSLINE (Advanced)
-- ============================================================================

-- Build your own statusline with writing metrics:
local M = {}

function M.get_statusline()
  local parts = {}

  -- Left section
  local mode_map = {
    n = "NORMAL",
    i = "INSERT",
    v = "VISUAL",
    V = "V-LINE",
    [""] = "V-BLOCK",
    c = "COMMAND",
    R = "REPLACE",
  }
  local mode = mode_map[vim.fn.mode()] or "UNKNOWN"
  table.insert(parts, string.format(" %s ", mode))

  -- File info
  table.insert(parts, " %f")
  if vim.bo.modified then
    table.insert(parts, " [+]")
  end

  -- Center align
  table.insert(parts, "%=")

  -- Writing metrics (right side)
  local ft = vim.bo.filetype
  if vim.tbl_contains({ "markdown", "text", "tex", "fountain", "org" }, ft) then
    local metrics = require("writing-metrics.basic").get_metrics(0)
    if metrics then
      table.insert(parts, string.format(" 󰗊 %s  󰬶 %s ", metrics.words_formatted, metrics.chars_formatted))
    end
  end

  -- Standard info
  table.insert(parts, " %y")
  table.insert(parts, " %l:%c ")
  table.insert(parts, " %p%% ")

  return table.concat(parts, "")
end

-- Set the statusline
vim.o.statusline = "%{%v:lua.require('my_statusline').get_statusline()%}"

-- ============================================================================
-- MINIMAL STATUSLINE
-- ============================================================================

-- Absolutely minimal statusline with just word count:
function _G.minimal_statusline()
  local parts = { "%f", "%=" }

  local ft = vim.bo.filetype
  if vim.tbl_contains({ "markdown", "text", "tex" }, ft) then
    local metrics = require("writing-metrics.basic").get_metrics(0)
    if metrics then
      table.insert(parts, string.format("%s words ", metrics.words_formatted))
    end
  end

  table.insert(parts, "%l:%c")
  return table.concat(parts, "")
end

vim.o.statusline = "%{%v:lua.minimal_statusline()%}"

-- ============================================================================
-- PERFORMANCE NOTES
-- ============================================================================

-- The plugin uses intelligent caching to minimize performance impact:
-- - Basic metrics cached per-buffer; revalidated only when changedtick changes
-- - Cursor moves, mode changes, and window events don't trigger recomputation
-- - Statusline calls return immediately from cache when content hasn't changed
-- - No blocking computation in statusline rendering
--
-- If you experience performance issues with very large files (> 100K words):
-- 1. Use "fast" mode instead of "accurate" mode
-- 2. Disable statusline integration and use commands only
--
-- Example performance tuning:
-- opts = {
--   statusline = { mode = "fast" }, -- Use fast counting
-- }

-- ============================================================================
-- TROUBLESHOOTING
-- ============================================================================

-- If statusline shows nothing:
-- 1. Check filetype: :set filetype?
-- 2. Test function directly: :lua print(require("writing-metrics.basic").get_statusline_string(0))
-- 3. Check cache status: :WritingMetricsCache
-- 4. Clear cache: :WritingMetricsClear!
--
-- If statusline shows stale values:
-- 1. Clear the cache: :WritingMetricsClear!
-- 2. Switch to "fast" mode (no Pandoc overhead)

-- ============================================================================
-- BACKWARD COMPATIBILITY
-- ============================================================================

-- If you were using the old accurate_wordcount() API:
-- The plugin still provides this for backward compatibility:
vim.o.statusline = table.concat({
  "%f",
  "%=",
  "%{v:lua.accurate_wordcount()}", -- Still works
  " %y %l:%c",
}, "")

-- But the new API is recommended:
vim.o.statusline = table.concat({
  "%f",
  "%=",
  "%{v:lua.require('writing-metrics.basic').get_statusline_string(0)}",
  " %y %l:%c",
}, "")
