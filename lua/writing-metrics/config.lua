--- Configuration and auto-detection for nvim-writing-metrics
--- @module writing-metrics.config
local M = {}

--- Default configuration values
M.defaults = {
  -- Cache settings (single-tier for statusline only)
  cache = {
    basic_ttl = 500, -- 500ms for responsive statusline
    -- Reports always compute fresh (no cache)
  },

  -- Feature toggles
  features = {
    basic = true, -- Word count, characters, sentences
    readability = true, -- All readability formulas
    passive_voice = true, -- Passive voice detection
    nominalizations = true, -- Nominalization detection
    vocabulary = true, -- Vocabulary richness metrics
    sentence_variety = true, -- Sentence length variability
    ai_words = true, -- AI-associated word detection
  },

  -- File types to enable metrics for
  filetypes = {
    "markdown",
    "text",
    "tex",
    "fountain",
    "org",
    "asciidoc",
    "rst",
  },

  -- Display settings
  display = {
    float_border = "rounded", -- Border style for floating windows
    report_window = "tab", -- "tab", "split", "vsplit"
    statusline_format = "words", -- "words", "chars", "both"
  },

  -- Target ranges for different writing types
  targets = {
    grant = {
      flesch_kincaid = { min = 11, max = 14 },
      flesch_reading_ease = { min = 40, max = 60 },
      passive_voice = { max = 10 }, -- Max percentage
      nominalizations = { max = 5 }, -- Max percentage
      sentence_variability = { min = 6 },
    },
    creative = {
      flesch_kincaid = { min = 7, max = 9 },
      flesch_reading_ease = { min = 60, max = 80 },
      sentence_variability = { min = 8 },
    },
    academic = {
      flesch_kincaid = { min = 12, max = 16 },
      flesch_reading_ease = { min = 30, max = 50 },
      passive_voice = { max = 20 },
    },
  },

  -- Reading time estimation
  reading_time = {
    enabled = true,                 -- compute reading time at all
    wpm_silent = 200,               -- average silent reading speed
    wpm_spoken = 150,               -- presentation / spoken delivery rate
    statusline = true,              -- show in statusline
    statusline_profile = "silent",  -- "silent" | "spoken" | "both"
  },

  -- Pandoc filter settings
  filter = {
    auto_detect = true, -- Automatically find bundled filter
    custom_path = nil, -- Override with custom path
  },
}

--- Current active configuration (merged with user opts)
M.config = vim.deepcopy(M.defaults)

--- Get the plugin directory by introspecting the source file path
--- @return string|nil Plugin directory path
local function get_plugin_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  if not source or source == "" then
    return nil
  end
  -- Go up 3 levels: config.lua -> writing-metrics/ -> lua/ -> plugin_root/
  return vim.fn.fnamemodify(source, ":h:h:h")
end

--- Find the Pandoc filter using a fallback chain
--- @return string|nil Filter path if found
--- @return string|nil Error message if not found
function M.find_filter()
  -- If custom path specified, use it
  if M.config.filter.custom_path then
    if vim.fn.filereadable(M.config.filter.custom_path) == 1 then
      return M.config.filter.custom_path
    else
      return nil, "Custom filter path not found: " .. M.config.filter.custom_path
    end
  end

  local candidates = {}

  -- 1. Bundled filter (plugin_dir/scripts/textmetrics.lua)
  local plugin_dir = get_plugin_dir()
  if plugin_dir then
    table.insert(candidates, vim.fn.fnamemodify(plugin_dir .. "/scripts/textmetrics.lua", ":p"))
  end

  -- 2. XDG data dir (~/.local/share/nvim/textmetrics.lua)
  local xdg_data = vim.fn.stdpath("data")
  table.insert(candidates, xdg_data .. "/textmetrics.lua")

  -- 3. User bin (~/bin/textmetrics.lua)
  local home = vim.fn.expand("~")
  table.insert(candidates, home .. "/bin/textmetrics.lua")

  -- 4. System-wide (/usr/local/share/nvim/textmetrics.lua)
  table.insert(candidates, "/usr/local/share/nvim/textmetrics.lua")

  -- Check each candidate
  for _, path in ipairs(candidates) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  -- Not found - provide helpful error
  local err = "Pandoc filter not found. Searched locations:\n"
  for _, path in ipairs(candidates) do
    err = err .. "  - " .. path .. "\n"
  end
  err = err .. "\nPlease ensure scripts/textmetrics.lua exists in the plugin directory."

  return nil, err
end

--- Check if Pandoc is installed and meets minimum version
--- @return boolean Success
--- @return string|nil Error message if failed
function M.validate_pandoc()
  -- Check if pandoc is in PATH
  if vim.fn.executable("pandoc") ~= 1 then
    return false,
      [[
Pandoc not found in PATH. Please install Pandoc >= 2.19.

Installation instructions:
  Ubuntu/Debian:  sudo apt install pandoc
  Arch Linux:     sudo pacman -S pandoc
  macOS:          brew install pandoc
  Windows:        choco install pandoc (or download from https://pandoc.org)
]]
  end

  -- Check version
  local version_output = vim.fn.system("pandoc --version")
  local version = version_output:match("pandoc (%d+%.%d+)")

  if not version then
    return false, "Could not determine Pandoc version"
  end

  local major, minor = version:match("(%d+)%.(%d+)")
  major, minor = tonumber(major), tonumber(minor)

  if major < 2 or (major == 2 and minor < 19) then
    return false,
      string.format(
        [[
Pandoc version %s found, but >= 2.19 is required for Lua filter support.

Please upgrade Pandoc:
  Ubuntu/Debian:  sudo apt update && sudo apt upgrade pandoc
  Arch Linux:     sudo pacman -Syu pandoc
  macOS:          brew upgrade pandoc
  Windows:        choco upgrade pandoc
]],
        version
      )
  end

  return true
end

--- Validate all dependencies (Pandoc + filter)
--- @return boolean Success
--- @return string|nil Error message if failed
function M.validate_dependencies()
  -- Check Pandoc first
  local ok, err = M.validate_pandoc()
  if not ok then
    return false, err
  end

  -- Check filter exists
  local filter_path, filter_err = M.find_filter()
  if not filter_path then
    return false, filter_err
  end

  M.config._filter_path = filter_path

  return true
end

--- Get the resolved filter path
--- @return string|nil Filter path
function M.get_filter_path()
  if not M.config._filter_path then
    local path, _ = M.find_filter()
    M.config._filter_path = path
  end
  return M.config._filter_path
end

--- Setup configuration with user options
--- @param opts table|nil User configuration
function M.setup(opts)
  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Validate dependencies
  local ok, err = M.validate_dependencies()
  if not ok then
    vim.notify("writing-metrics: " .. err, vim.log.levels.ERROR)
    return false
  end

  return true
end

--- Check if a filetype is enabled for metrics
--- @param ft string Filetype to check
--- @return boolean
function M.is_enabled_filetype(ft)
  return vim.tbl_contains(M.config.filetypes, ft)
end

--- Get target ranges for a writing type
--- @param writing_type string "grant", "creative", "academic"
--- @return table|nil Target ranges
function M.get_targets(writing_type)
  return M.config.targets[writing_type]
end

-- Manual testing:
-- :lua require("writing-metrics.config").validate_dependencies()
-- :lua print(vim.inspect(require("writing-metrics.config").defaults))
-- :lua local ok, err = require("writing-metrics.config").validate_pandoc(); print(ok, err)
-- :lua local path, err = require("writing-metrics.config").find_filter(); print(path or err)

return M
