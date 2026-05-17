--- Basic word counting module with statusline integration
--- Provides fast, cached word counting with backward compatibility
--- @module writing-metrics.basic
local M = {}

--- Global state for statusline mode
--- @type "fast"|"accurate"
M.statusline_mode = "fast"

--- Loading state for statusline display
--- @type boolean
M.statusline_updating = false

--- Cache for visual mode selections (no persistence needed)
--- Note: Currently unused, reserved for future visual mode enhancements
-- local selection_cache = {}

-- ═══════════════════════════════════════════════════════════════
-- CORE COUNTING FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

--- Get accurate document metrics using Pandoc in basic mode
--- @param bufnr number Buffer number (0 for current)
--- @param callback function Callback(result, method) called with result
---   result: {words, chars, sentences, paragraphs, avg_sentence_len, avg_word_len} or nil on error
---   method: "pandoc" or "fallback" or "error"
function M.get_accurate_count(bufnr, callback)
  -- Normalize buffer number (0 and nil both mean current buffer)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local cache = require("writing-metrics.cache")
  local utils = require("writing-metrics.utils")

  -- Check cache first - only use if fresh (not stale)
  local cached, is_stale = cache.get_basic(bufnr)
  if cached and not is_stale then
    vim.schedule(function()
      callback(cached, "cached")
    end)
    return
  end

  -- Get buffer content and write to temp file
  local content = utils.get_buffer_content(bufnr)
  local temp_path, err = utils.write_temp_file(content, ".md")

  if not temp_path then
    callback(nil, "error")
    utils.handle_error(err, "Failed to create temp file")
    return
  end

  -- Execute Pandoc with basic mode
  utils.run_pandoc(temp_path, "basic", function(success, output)
    -- Clean up temp file (already in vim.schedule from run_pandoc)
    utils.cleanup_temp_file(temp_path)

    if not success then
      -- Pandoc failed, fall back to fast mode
      local fast_result = M.get_fast_count(bufnr)
      cache.set_basic(bufnr, fast_result)  -- Cache fallback result
      callback(fast_result, "fallback")
      return
    end

    -- Parse output
    local result, parse_err = utils.parse_basic_output(output)
    if not result then
      utils.handle_error(parse_err, "Failed to parse metrics")
      local fast_result = M.get_fast_count(bufnr)
      cache.set_basic(bufnr, fast_result)  -- Cache fallback result
      callback(fast_result, "fallback")
      return
    end

    -- Cache the result
    cache.set_basic(bufnr, result)
    callback(result, "pandoc")
  end)
end

--- Get fast count using Vim's native wordcount()
--- @param bufnr number|nil Buffer number (0 or nil for current)
--- @return table Basic metrics {words, chars, sentences, paragraphs}
function M.get_fast_count(bufnr)
  -- Normalize buffer number (0 and nil both mean current buffer)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local wc = vim.fn.wordcount()

  return {
    words = wc.words or 0,
    chars = wc.chars or 0,
    sentences = 0, -- Vim doesn't count these
    paragraphs = 0,
    avg_sentence_len = 0,
    avg_word_len = 0,
  }
end

--- Compute reading time for a buffer.
--- Reads cached word count; returns nil if reading_time is disabled or no
--- cached count exists. Returned strings are pre-formatted ("~5 min").
--- Stale cached counts are used without warning; callers should add a
--- staleness indicator if needed (see get_statusline_string).
--- @param bufnr integer Buffer to compute for (0 or nil = current buffer)
--- @return table|nil { silent_minutes, spoken_minutes, silent, spoken }
function M.get_reading_time(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr

  local config = require("writing-metrics.config").config.reading_time
  if not config or not config.enabled then
    return nil
  end

  local wpm_silent = config.wpm_silent or 200
  local wpm_spoken = config.wpm_spoken or 150
  if wpm_silent <= 0 or wpm_spoken <= 0 then
    return nil
  end

  local cache = require("writing-metrics.cache")
  local cached, _is_stale = cache.get_basic(bufnr)
  if not cached or not cached.words or cached.words <= 0 then
    return nil
  end

  local silent_min = math.ceil(cached.words / wpm_silent)
  local spoken_min = math.ceil(cached.words / wpm_spoken)

  return {
    silent_minutes = silent_min,
    spoken_minutes = spoken_min,
    silent = string.format("~%d min", silent_min),
    spoken = string.format("~%d min", spoken_min),
  }
end

--- Show a vim.notify toast with both reading-time profiles.
--- Triggers an accurate word count via the standard pipeline; falls
--- back to vim.fn.wordcount() if the accurate path fails.
function M.show_reading_time()
  local config = require("writing-metrics.config").config.reading_time
  if not config or not config.enabled then
    vim.notify("Reading time is disabled in config (reading_time.enabled = false)", vim.log.levels.WARN)
    return
  end

  local utils = require("writing-metrics.utils")
  local bufnr = vim.api.nvim_get_current_buf()

  local function format_toast(words, prefix)
    local silent_min = math.ceil(words / config.wpm_silent)
    local spoken_min = math.ceil(words / config.wpm_spoken)
    return string.format(
      "%s~%d min silent · ~%d min spoken  (%s words at %d/%d wpm)",
      prefix or "",
      silent_min,
      spoken_min,
      utils.format_number(words),
      config.wpm_silent,
      config.wpm_spoken
    )
  end

  M.get_accurate_count(bufnr, function(result, _method)
    if result and result.words and result.words > 0 then
      vim.notify(format_toast(result.words), vim.log.levels.INFO)
      return
    end

    -- Fallback: raw fast count, marked clearly
    local wc = vim.fn.wordcount()
    local words = wc.words or 0
    if words > 0 then
      vim.notify(format_toast(words, "(fast) "), vim.log.levels.WARN)
    else
      vim.notify("No words to count in current buffer", vim.log.levels.WARN)
    end
  end)
end

--- Get visual mode selection count
--- @param callback function|nil Optional callback (for async consistency)
function M.get_selection_count(callback)
  local utils = require("writing-metrics.utils")

  -- Get selection content
  local selection = utils.get_selection_content()
  if not selection or selection == "" then
    utils.notify("No selection", vim.log.levels.WARN)
    return
  end

  -- Write to temp file
  local temp_path, err = utils.write_temp_file(selection, ".md")
  if not temp_path then
    utils.handle_error(err, "Failed to create temp file for selection")
    return
  end

  -- Show loading notification
  utils.notify("Counting selection...", vim.log.levels.INFO)

  -- Execute Pandoc
  utils.run_pandoc(temp_path, "basic", function(success, output)
    -- Already in vim.schedule() context from run_pandoc
    utils.cleanup_temp_file(temp_path)

    if not success then
      utils.notify("Failed to count selection", vim.log.levels.ERROR)
      if callback then
        callback(nil, "error")
      end
      return
    end

    local result, parse_err = utils.parse_basic_output(output)
    if not result then
      utils.handle_error(parse_err, "Failed to parse selection metrics")
      if callback then
        callback(nil, "error")
      end
      return
    end

    -- Format and show result
    local msg = string.format(
      "Selection: %s words  %s chars  %s sentences  %s ¶",
      utils.format_number(result.words),
      utils.format_number(result.chars),
      utils.format_number(result.sentences),
      utils.format_number(result.paragraphs)
    )

    utils.notify(msg, vim.log.levels.INFO)

    if callback then
      callback(result, "pandoc")
    end
  end)
end

-- ═══════════════════════════════════════════════════════════════
-- DISPLAY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

--- Show comparison window with all metrics
--- @param bufnr number|nil Buffer number (0 or nil for current)
function M.show_comparison(bufnr)
  -- Normalize buffer number (0 and nil both mean current buffer)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local utils = require("writing-metrics.utils")

  -- Get fast count (immediate)
  local fast_wc = vim.fn.wordcount()
  local fast_words = fast_wc.words or 0
  local fast_chars = fast_wc.chars or 0
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  -- Show loading message
  utils.notify("Calculating accurate metrics...", vim.log.levels.INFO)

  -- Get accurate count (async)
  M.get_accurate_count(bufnr, function(result, method)
    if not result then
      utils.notify("Failed to calculate accurate metrics", vim.log.levels.ERROR)
      return
    end

    -- Extract metrics
    local acc_words = result.words or 0
    local acc_chars = result.chars or 0
    local acc_sents = result.sentences or 0
    local acc_paras = result.paragraphs or 0

    -- Calculate differences
    local word_diff = fast_words - acc_words
    local char_diff = fast_chars - acc_chars
    local word_percent = fast_words > 0 and (word_diff / fast_words * 100) or 0
    local char_percent = fast_chars > 0 and (char_diff / fast_chars * 100) or 0

    -- Calculate averages
    local words_per_sent = acc_sents > 0 and (acc_words / acc_sents) or 0
    local words_per_para = acc_paras > 0 and (acc_words / acc_paras) or 0
    local chars_per_word = acc_words > 0 and (acc_chars / acc_words) or 0

    -- Build display content
    local lines = {
      "", -- Top padding
      "  WORDS",
      string.format("    Accurate:  %s words", utils.format_number(acc_words)),
      string.format("    Raw Count: %s words", utils.format_number(fast_words)),
      string.format("    Excluded:  %s words (%.1f%%)", utils.format_number(word_diff), word_percent),
      "",
      "  CHARACTERS",
      string.format("    Accurate:  %s chars", utils.format_number(acc_chars)),
      string.format("    Raw Count: %s chars", utils.format_number(fast_chars)),
      string.format("    Excluded:  %s chars (%.1f%%)", utils.format_number(char_diff), char_percent),
      "",
      "  STRUCTURE",
      string.format("    Sentences:     %s sentences", utils.format_number(acc_sents)),
      string.format("    Paragraphs:    %s ¶", utils.format_number(acc_paras)),
      string.format("    Lines (total): %s lines", utils.format_number(total_lines)),
      "",
      "  AVERAGES",
      string.format("    Words/Sentence:  %.1f words", words_per_sent),
      string.format("    Words/Paragraph: %.1f words", words_per_para),
      string.format("    Chars/Word:      %.1f chars", chars_per_word),
      "",
      string.format("  Method: %s", method == "pandoc" and "Pandoc + Lua filter" or method),
    }

    -- Add fallback note if using fast mode
    if method == "fallback" then
      table.insert(lines, "")
      table.insert(lines, "  Note: Using fast mode (Pandoc unavailable)")
    end

    -- Create floating window
    utils.create_float_window(lines, {
      title = " Document Metrics ",
      border = "rounded",
      width = 40,
    })
  end)
end

-- ═══════════════════════════════════════════════════════════════
-- STATUSLINE INTEGRATION
-- ═══════════════════════════════════════════════════════════════

--- Build the statusline reading-time suffix (e.g., "  ⏱ ~5 min").
--- Returns "" if disabled, no cached words, or invalid config.
--- @param bufnr integer
--- @return string
local function statusline_reading_time_suffix(bufnr)
  local config = require("writing-metrics.config").config.reading_time
  if not config or not config.enabled or not config.statusline then
    return ""
  end

  local rt = M.get_reading_time(bufnr)
  if not rt then return "" end

  local profile = config.statusline_profile or "silent"
  if profile == "spoken" then
    return string.format("  🎤 %s", rt.spoken)
  elseif profile == "both" then
    -- Compact form: ⏱ ~5/~7 min
    return string.format("  ⏱ ~%d/~%d min", rt.silent_minutes, rt.spoken_minutes)
  else
    -- Default: silent
    return string.format("  ⏱ %s", rt.silent)
  end
end

--- Get formatted statusline string for current buffer
--- @param bufnr number|nil Buffer number (0 or nil for current)
--- @return string Formatted statusline component
function M.get_statusline_string(bufnr)
  -- Normalize buffer number (0 and nil both mean current buffer)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local utils = require("writing-metrics.utils")

  -- Check if we're in a writing filetype
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
  if not utils.is_writing_filetype(ft) then
    return ""
  end

  -- Check if we're in visual mode (selection count)
  local mode = vim.fn.mode()
  if mode:match("[vV]") then
    local wc = vim.fn.wordcount()
    local visual_words = wc.visual_words or 0
    local visual_chars = wc.visual_chars or 0

    return {
      text = string.format(
        "󰒉 %s words  󰬷 %s chars (sel)",
        utils.format_number(visual_words),
        utils.format_number(visual_chars)
      ),
      color = "green", -- Visual selections are always fresh/instant
    }
  end

  -- Fast mode: use vim.fn.wordcount() (instant, always fresh)
  if M.statusline_mode == "fast" then
    local wc = vim.fn.wordcount()
    return {
      text = string.format(
        "⚡ %s words  󰬶 %s chars",
        utils.format_number(wc.words or 0),
        utils.format_number(wc.chars or 0)
      ) .. statusline_reading_time_suffix(bufnr),
      color = "green", -- Always fresh in fast mode
    }
  end

  -- Accurate mode: check cache and staleness
  local cache = require("writing-metrics.cache")
  local cached, is_stale = cache.get_basic(bufnr)

  if cached then
    -- Have cached data - show with appropriate freshness indicator
    local icon = is_stale and "⚠️" or "🎯"
    local color = is_stale and "orange" or "green"
    return {
      text = string.format(
        "%s %s words  󰬶 %s chars",
        icon,
        utils.format_number(cached.words),
        utils.format_number(cached.chars)
      ) .. statusline_reading_time_suffix(bufnr),
      color = color,
    }
  end

  -- No cache at all - show fast mode as stale fallback
  local wc = vim.fn.wordcount()
  return {
    text = string.format(
      "⚠️ %s words  󰬶 %s chars",
      utils.format_number(wc.words or 0),
      utils.format_number(wc.chars or 0)
    ) .. statusline_reading_time_suffix(bufnr),
    color = "orange", -- Stale/approximate
  }
end

--- Get lualine component configuration
--- @return table Lualine component spec
function M.lualine_component()
  return {
    function()
      return M.get_statusline_string(0)
    end,
    cond = function()
      local ft = vim.api.nvim_buf_get_option(0, "filetype")
      local utils = require("writing-metrics.utils")
      return utils.is_writing_filetype(ft)
    end,
    color = function()
      -- Visual mode: different color
      local mode = vim.fn.mode()
      if mode:match("[vV]") then
        return { fg = "#7dcfff", gui = "bold" }
      end
      return { fg = "#9ece6a" }
    end,
  }
end

--- Update accurate count for statusline display
--- Called on TextChanged, InsertLeave, BufWritePost
function M.update_statusline_accurate_count()
  -- Only run if in accurate mode
  if M.statusline_mode ~= "accurate" then
    return
  end

  -- Prevent concurrent updates (debounce)
  if M.statusline_updating then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()

  -- Set updating flag (for debouncing only, not for display)
  M.statusline_updating = true

  -- Run accurate count async
  M.get_accurate_count(bufnr, function(result, method)
    -- Clear updating flag
    M.statusline_updating = false

    if not result then
      vim.cmd.redrawstatus()
      return
    end

    -- Cache is already updated by get_accurate_count
    -- Just refresh statusline
    vim.cmd.redrawstatus()
  end)
end

--- Toggle between fast and accurate statusline modes
function M.toggle_statusline_mode()
  local utils = require("writing-metrics.utils")

  if M.statusline_mode == "fast" then
    M.statusline_mode = "accurate"

    -- Initialize accurate cache by running count immediately
    M.update_statusline_accurate_count()

    utils.notify("🎯 Accurate mode: Pandoc-based metrics (updates on edit)", vim.log.levels.INFO)
  else
    M.statusline_mode = "fast"
    utils.notify("⚡ Fast mode: Instant Vim native metrics", vim.log.levels.INFO)
  end

  -- Refresh statusline
  vim.cmd.redrawstatus()
end

-- ═══════════════════════════════════════════════════════════════
-- BACKWARD COMPATIBILITY
-- ═══════════════════════════════════════════════════════════════

--- Global API for backward compatibility with accurate-wordcount.lua
--- This allows existing configs to work without changes
_G.accurate_wordcount = {
  get_accurate_count = M.get_accurate_count,
  get_fast_count = M.get_fast_count,
  get_reading_time = M.get_reading_time,
  show_reading_time = M.show_reading_time,
  show_comparison = M.show_comparison,
  toggle_statusline_mode = M.toggle_statusline_mode,
  statusline_mode = M.statusline_mode,
  update_lualine_accurate_count = M.update_statusline_accurate_count,
}

-- ═══════════════════════════════════════════════════════════════
-- AUTOCOMMANDS & SETUP
-- ═══════════════════════════════════════════════════════════════

--- Setup autocommands for cache invalidation and updates
function M.setup_autocmds()
  local cache = require("writing-metrics.cache")

  local group = vim.api.nvim_create_augroup("WritingMetricsBasic", { clear = true })

  -- Update accurate count in accurate mode
  -- Only fires after changes in Normal mode
  vim.api.nvim_create_autocmd("TextChanged", {
    group = group,
    callback = function(args)
      local ft = vim.api.nvim_buf_get_option(args.buf, "filetype")
      local utils = require("writing-metrics.utils")

      if utils.is_writing_filetype(ft) then
        M.update_statusline_accurate_count()
      end
    end,
  })

  -- Update when leaving insert mode (finished typing)
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function(args)
      local ft = vim.api.nvim_buf_get_option(args.buf, "filetype")
      local utils = require("writing-metrics.utils")

      if utils.is_writing_filetype(ft) then
        M.update_statusline_accurate_count()
      end
    end,
  })

  -- Update on save
  -- Note: cache.invalidate() is handled by cache.lua autocmds
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      local ft = vim.api.nvim_buf_get_option(args.buf, "filetype")
      local utils = require("writing-metrics.utils")

      if utils.is_writing_filetype(ft) then
        M.update_statusline_accurate_count()
      end
    end,
  })

  -- Redraw statusline on mode change (for visual mode detection)
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      vim.cmd.redrawstatus()
    end,
  })
end

-- ═══════════════════════════════════════════════════════════════
-- USER COMMANDS
-- ═══════════════════════════════════════════════════════════════

--- Create user commands for backward compatibility
-- ═══════════════════════════════════════════════════════════════
-- MODULE INITIALIZATION
-- ═══════════════════════════════════════════════════════════════

--- Initialize the basic module
--- Note: Commands are registered in plugin/writing-metrics.lua
function M.setup()
  M.setup_autocmds()

  -- Setup cache autocmds
  local cache = require("writing-metrics.cache")
  cache.setup_autocmds()
end

-- Manual testing commands:
-- :lua require("writing-metrics.basic").get_accurate_count(0, vim.print)
-- :lua require("writing-metrics.basic").show_comparison(0)
-- :lua print(require("writing-metrics.basic").get_statusline_string(0))
-- :lua require("writing-metrics.basic").toggle_statusline_mode()
-- Visual mode: :'<,'>lua require("writing-metrics.basic").get_selection_count()

return M
