-- examples/lualine-integration.lua
-- Integration examples for lualine statusline

-- ============================================================================
-- OPTION 1: RECOMMENDED - Use Built-in Component
-- ============================================================================

-- The plugin provides a pre-configured lualine component that:
-- - Shows word and character counts for writing files
-- - Auto-detects filetypes (markdown, text, tex, fountain, org)
-- - Uses cached values for performance
-- - Includes proper icons and colors

require("lualine").setup({
  sections = {
    lualine_x = {
      -- Add writing metrics component
      require("writing-metrics.basic").lualine_component(),

      -- Your other components
      "encoding",
      "fileformat",
      "filetype",
    },
  },
})

-- ============================================================================
-- OPTION 2: CUSTOM COMPONENT - Full Control
-- ============================================================================

-- If you need custom formatting, colors, or conditions:

require("lualine").setup({
  sections = {
    lualine_x = {
      {
        -- The function to call for component text
        function()
          return require("writing-metrics.basic").get_statusline_string(0)
        end,

        -- Only show for writing filetypes
        cond = function()
          local ft = vim.bo.filetype
          return vim.tbl_contains({
            "markdown",
            "text",
            "tex",
            "fountain",
            "org",
            "asciidoc",
            "rst"
          }, ft)
        end,

        -- Custom colors (Tokyo Night green)
        color = { fg = "#9ece6a" },

        -- Icons already included in get_statusline_string()
      },

      "encoding",
      "fileformat",
      "filetype",
    },
  },
})

-- ============================================================================
-- OPTION 3: ADD TO EXISTING CONFIG
-- ============================================================================

-- If you already have lualine configured and don't want to rewrite it:

local config = require("lualine").get_config()

-- Insert writing metrics at the beginning of lualine_x
table.insert(
  config.sections.lualine_x,
  1,  -- Position (1 = leftmost in lualine_x)
  require("writing-metrics.basic").lualine_component()
)

-- Reapply config
require("lualine").setup(config)

-- ============================================================================
-- OPTION 4: CUSTOM FORMATTING - Words Only
-- ============================================================================

-- Show only word count (no characters):

require("lualine").setup({
  sections = {
    lualine_x = {
      {
        function()
          local metrics = require("writing-metrics.basic").get_metrics(0)
          if not metrics then return "" end

          -- Custom format: just words
          return string.format("󰗊 %s", metrics.words_formatted)
        end,
        cond = function()
          local ft = vim.bo.filetype
          return vim.tbl_contains({ "markdown", "text", "tex" }, ft)
        end,
        color = { fg = "#9ece6a" },
      },
      "encoding",
      "fileformat",
      "filetype",
    },
  },
})

-- ============================================================================
-- OPTION 5: DETAILED FORMAT - With Reading Time
-- ============================================================================

-- Show words, characters, and estimated reading time:

require("lualine").setup({
  sections = {
    lualine_x = {
      {
        function()
          local metrics = require("writing-metrics.basic").get_metrics(0)
          if not metrics then return "" end

          -- Calculate reading time (200 WPM)
          local reading_time = math.ceil(metrics.words / 200)

          return string.format(
            "󰗊 %s  󰬶 %s  󰔟 %dm",
            metrics.words_formatted,
            metrics.chars_formatted,
            reading_time
          )
        end,
        cond = function()
          local ft = vim.bo.filetype
          return vim.tbl_contains({ "markdown", "text", "tex" }, ft)
        end,
        color = { fg = "#9ece6a" },
      },
      "encoding",
      "fileformat",
      "filetype",
    },
  },
})

-- ============================================================================
-- OPTION 6: CONDITIONAL COLORS - Based on Word Count
-- ============================================================================

-- Change color based on word count targets:

require("lualine").setup({
  sections = {
    lualine_x = {
      {
        function()
          return require("writing-metrics.basic").get_statusline_string(0)
        end,
        cond = function()
          local ft = vim.bo.filetype
          return vim.tbl_contains({ "markdown", "text", "tex" }, ft)
        end,
        color = function()
          local metrics = require("writing-metrics.basic").get_metrics(0)
          if not metrics then
            return { fg = "#9ece6a" }  -- Green (default)
          end

          -- Color coding based on word count
          if metrics.words < 1000 then
            return { fg = "#7aa2f7" }  -- Blue (under 1k)
          elseif metrics.words < 5000 then
            return { fg = "#9ece6a" }  -- Green (1k-5k)
          else
            return { fg = "#e0af68" }  -- Yellow (5k+)
          end
        end,
      },
      "encoding",
      "fileformat",
      "filetype",
    },
  },
})

-- ============================================================================
-- OPTION 7: MULTIPLE SECTIONS - Split Display
-- ============================================================================

-- Show words in lualine_x and characters in lualine_y:

require("lualine").setup({
  sections = {
    lualine_x = {
      {
        function()
          local metrics = require("writing-metrics.basic").get_metrics(0)
          if not metrics then return "" end
          return string.format("󰗊 %s", metrics.words_formatted)
        end,
        cond = function()
          local ft = vim.bo.filetype
          return vim.tbl_contains({ "markdown", "text", "tex" }, ft)
        end,
        color = { fg = "#9ece6a" },
      },
      "encoding",
      "fileformat",
      "filetype",
    },
    lualine_y = {
      {
        function()
          local metrics = require("writing-metrics.basic").get_metrics(0)
          if not metrics then return "" end
          return string.format("󰬶 %s", metrics.chars_formatted)
        end,
        cond = function()
          local ft = vim.bo.filetype
          return vim.tbl_contains({ "markdown", "text", "tex" }, ft)
        end,
        color = { fg = "#7aa2f7" },
      },
      "progress",
    },
    lualine_z = { "location" },
  },
})

-- ============================================================================
-- ICONS REFERENCE
-- ============================================================================

-- Available icons for custom formatting:
--   󰗊  Words icon
--   󰬶  Characters icon
--   󰔟  Clock/time icon
--   󰈙  Document icon
--   󰦨  Paragraph icon

-- ============================================================================
-- COLOR REFERENCE (Tokyo Night)
-- ============================================================================

-- Common Tokyo Night colors for statusline:
--   #9ece6a  Green (default for metrics)
--   #7aa2f7  Blue (info/secondary)
--   #e0af68  Yellow (warning)
--   #f7768e  Red (error/alert)
--   #bb9af7  Purple (special)
--   #73daca  Teal (accent)
