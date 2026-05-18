--- Main entry point for nvim-writing-metrics
--- Public API for retrieving and displaying writing metrics
--- @module writing-metrics
local M = {}

--- Global tracking table for report buffers.
--- Keys are normalized: absolute resolved path for named buffers,
--- "unnamed:<bufnr>" for unnamed buffers (see display.tracking_key).
--- The table is reset to {} inside setup() so :Lazy reload doesn't
--- preserve stale buffer numbers from a previous load. This line
--- ensures the table exists for code paths that touch it before
--- setup() runs.
--- @type table<string, number>
_G.writing_metrics_reports = _G.writing_metrics_reports or {}

--- Plugin initialization state
M._initialized = false

--- Lazy-load submodules
local function get_config()
  return require("writing-metrics.config")
end

local function get_cache()
  return require("writing-metrics.cache")
end

local function get_utils()
  return require("writing-metrics.utils")
end

--- Initialize the plugin
--- @param opts table|nil User configuration
--- @return boolean Success
function M.setup(opts)
  -- Always merge opts so subsequent calls with explicit opts are honored.
  local config = get_config()
  local ok = config.setup(opts or {})

  if not ok then
    return false
  end

  -- Reset report tracking unconditionally so :Lazy reload (which re-requires
  -- this module but preserves _G across the reload) starts each setup with
  -- a fresh table. Without this, stale buffer numbers from the prior load
  -- can collide with newly-allocated bufnrs or point to wiped buffers.
  _G.writing_metrics_reports = {}

  -- Register user commands on every setup() call so opts (e.g. enable_legacy)
  -- take effect even when setup() is called multiple times. nvim_create_user_command
  -- overwrites on redefine, so this is safe to call repeatedly.
  require("writing-metrics.commands").setup_commands(get_config().config)

  -- One-time side effects (autocmds, validators).
  if M._initialized then
    return true
  end

  -- Setup cache invalidation autocmds
  local cache = get_cache()
  cache.setup_autocmds()

  --- Setup cleanup autocmds for report tracking
  local function setup_report_cleanup()
    local group = vim.api.nvim_create_augroup("WritingMetricsReportCleanup", { clear = true })

    -- Clean up tracking table when buffers are deleted
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
      group = group,
      callback = function(args)
        local bufnr = args.buf

        -- If this is a source buffer, remove its report mapping (by normalized key).
        -- Use the same normalization as display.tracking_key: absolute path for named
        -- buffers, "unnamed:<bufnr>" sentinel for unnamed buffers.
        local name = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
        local key
        if name ~= "" then
          key = vim.fn.fnamemodify(name, ":p")
        else
          key = "unnamed:" .. tostring(bufnr)
        end
        if _G.writing_metrics_reports[key] then
          _G.writing_metrics_reports[key] = nil
        end

        -- If this is a report buffer, remove all mappings pointing to it
        for source_filepath, report_bufnr in pairs(_G.writing_metrics_reports) do
          if report_bufnr == bufnr then
            _G.writing_metrics_reports[source_filepath] = nil
          end
        end
      end,
    })
  end

  -- Call setup function
  setup_report_cleanup()

  M._initialized = true
  return true
end

--- Check if a buffer is a writing buffer
--- @param bufnr number|nil Buffer number (0 or nil for current)
--- @return boolean
function M.is_writing_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  local utils = get_utils()
  return utils.is_writing_filetype(ft)
end

--- Get metrics for a buffer (async)
--- @param bufnr number|nil Buffer number
--- @param mode string "basic" or "full"
--- @param callback function Callback(success, data_or_error)
function M.get_metrics(bufnr, mode, callback)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  mode = mode or "basic"

  if not M._initialized then
    M.setup()
  end

  -- Check if this is a writing buffer
  if not M.is_writing_buffer(bufnr) then
    callback(false, "Not a writing buffer")
    return
  end

  local cache = get_cache()
  local utils = get_utils()

  -- Only check cache for basic mode (statusline)
  if mode == "basic" then
    local cached, is_stale = cache.get_basic(bufnr)
    if cached and not is_stale then
      callback(true, cached)
      return
    end
  end
  -- Full mode always computes fresh (no cache)

  -- Compute metrics
  local content = utils.get_buffer_content(bufnr)
  local temp_file, err = utils.write_temp_file(content)

  if not temp_file then
    callback(false, err)
    return
  end

  -- Run Pandoc
  utils.run_pandoc(temp_file, mode, function(success, result)
    -- Clean up temp file
    utils.cleanup_temp_file(temp_file)

    if not success then
      callback(false, result)
      return
    end

    -- Parse output
    local data, parse_err
    if mode == "basic" then
      data, parse_err = utils.parse_basic_output(result)
    else
      data, parse_err = utils.parse_full_output(result)
    end

    if not data then
      callback(false, parse_err)
      return
    end

    -- Store in cache (basic mode only)
    if mode == "basic" then
      cache.set_basic(bufnr, data)
    end

    callback(true, data)
  end)
end

--- Get metrics (Promise-style async)
--- @param bufnr number|nil Buffer number
--- @param mode string "basic" or "full"
--- @return table Promise-like object with `after` method
function M.get_metrics_async(bufnr, mode)
  local promise = {}

  function promise.after(on_success, on_error)
    M.get_metrics(bufnr, mode, function(success, result)
      if success then
        if on_success then
          on_success(result)
        end
      else
        if on_error then
          on_error(result)
        end
      end
    end)
    return promise
  end

  return promise
end

--- Format basic metrics for display
--- @param data table Basic metrics data
--- @return table Lines for display
local function format_basic_metrics(data)
  local utils = get_utils()
  local lines = {
    "# Writing Metrics",
    "",
    "## Basic Statistics",
    "",
    string.format("**Words:** %s", utils.format_number(data.words)),
    string.format("**Characters:** %s", utils.format_number(data.chars)),
    string.format("**Sentences:** %s", utils.format_number(data.sentences)),
    string.format("**Paragraphs:** %s", utils.format_number(data.paragraphs)),
    "",
    "## Averages",
    "",
    string.format("**Average Sentence Length:** %s words", utils.format_decimal(data.avg_sentence_len, 1)),
    string.format("**Average Word Length:** %s characters", utils.format_decimal(data.avg_word_len, 1)),
  }

  return lines
end

--- Format full metrics report
--- @param data table Full metrics data
--- @return table Lines for display
local function format_full_report(data)
  local utils = get_utils()
  local lines = {
    "# Writing Metrics - Comprehensive Report",
    "",
  }

  -- Basic statistics
  if data.basic then
    table.insert(lines, "## Basic Statistics")
    table.insert(lines, "")
    table.insert(lines, string.format("- **Words:** %s", utils.format_number(data.basic.words)))
    table.insert(lines, string.format("- **Characters:** %s", utils.format_number(data.basic.chars)))
    table.insert(lines, string.format("- **Sentences:** %s", utils.format_number(data.basic.sentences)))
    table.insert(lines, string.format("- **Paragraphs:** %s", utils.format_number(data.basic.paragraphs)))
    table.insert(
      lines,
      string.format("- **Average Sentence Length:** %s words", utils.format_decimal(data.basic.avg_sentence_len, 1))
    )
    table.insert(
      lines,
      string.format("- **Average Word Length:** %s characters", utils.format_decimal(data.basic.avg_word_len, 1))
    )
    table.insert(lines, "")
  end

  -- Readability scores
  if data.readability then
    table.insert(lines, "## Readability Analysis")
    table.insert(lines, "")

    if data.readability.coleman_liau then
      table.insert(
        lines,
        string.format("- **Coleman-Liau Index:** %s", utils.format_decimal(data.readability.coleman_liau, 1))
      )
    end

    if data.readability.ari then
      table.insert(
        lines,
        string.format("- **Automated Readability Index:** %s", utils.format_decimal(data.readability.ari, 1))
      )
    end

    if data.readability.flesch_reading_ease then
      table.insert(
        lines,
        string.format(
          "- **Flesch Reading Ease:** %s",
          utils.format_decimal(data.readability.flesch_reading_ease, 1)
        )
      )
    end

    if data.readability.flesch_kincaid then
      table.insert(
        lines,
        string.format("- **Flesch-Kincaid Grade:** %s", utils.format_decimal(data.readability.flesch_kincaid, 1))
      )
    end

    if data.readability.gunning_fog then
      table.insert(
        lines,
        string.format("- **Gunning Fog Index:** %s", utils.format_decimal(data.readability.gunning_fog, 1))
      )
    end

    if data.readability.smog then
      table.insert(lines, string.format("- **SMOG Index:** %s", utils.format_decimal(data.readability.smog, 1)))
    end

    table.insert(lines, "")
  end

  -- Sentence variety
  if data.sentence_variety then
    table.insert(lines, "## Sentence Variety")
    table.insert(lines, "")
    local sv = data.sentence_variety

    if sv.std_dev then
      table.insert(lines, string.format("- **Standard Deviation:** %s", utils.format_decimal(sv.std_dev, 2)))
    end

    if sv.coefficient_variation then
      table.insert(
        lines,
        string.format("- **Coefficient of Variation:** %s%%", utils.format_decimal(sv.coefficient_variation, 1))
      )
    end

    if sv.min_length and sv.max_length then
      table.insert(lines, string.format("- **Range:** %d - %d words", sv.min_length, sv.max_length))
    end

    table.insert(lines, "")
  end

  -- Passive voice
  if data.passive_voice then
    table.insert(lines, "## Passive Voice")
    table.insert(lines, "")
    table.insert(
      lines,
      string.format("- **Instances:** %d", data.passive_voice.count or 0)
    )
    table.insert(
      lines,
      string.format("- **Percentage:** %s", utils.format_percentage(data.passive_voice.percentage or 0))
    )
    table.insert(lines, "")
  end

  -- Nominalizations
  if data.nominalizations then
    table.insert(lines, "## Nominalizations")
    table.insert(lines, "")
    table.insert(
      lines,
      string.format("- **Instances:** %d", data.nominalizations.count or 0)
    )
    table.insert(
      lines,
      string.format("- **Percentage:** %s", utils.format_percentage(data.nominalizations.percentage or 0))
    )
    table.insert(lines, "")
  end

  -- Vocabulary
  if data.vocabulary then
    table.insert(lines, "## Vocabulary Richness")
    table.insert(lines, "")
    table.insert(
      lines,
      string.format("- **Unique Words:** %s", utils.format_number(data.vocabulary.unique_words or 0))
    )
    table.insert(
      lines,
      string.format("- **Type-Token Ratio:** %s", utils.format_decimal(data.vocabulary.type_token_ratio or 0, 3))
    )
    table.insert(lines, "")
  end

  -- AI words
  if data.ai_words then
    table.insert(lines, "## AI-Associated Words")
    table.insert(lines, "")
    table.insert(
      lines,
      string.format("- **Instances:** %d", data.ai_words.count or 0)
    )
    table.insert(
      lines,
      string.format("- **Percentage:** %s", utils.format_percentage(data.ai_words.percentage or 0, 2))
    )
    table.insert(lines, "")
  end

  return lines
end

--- Show basic metrics in a floating window
--- @param bufnr number|nil Buffer number
function M.show_basic_metrics(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  M.get_metrics(bufnr, "basic", function(success, result)
    if not success then
      local utils = get_utils()
      utils.handle_error(result, "Failed to get metrics")
      return
    end

    local lines = format_basic_metrics(result)
    local utils = get_utils()
    utils.create_float_window(lines, {
      title = " Writing Metrics ",
      width = 50,
      height = 15,
    })
  end)
end

--- Show comprehensive report using new full module
--- @param bufnr number|nil Buffer number
function M.show_full_report(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Use new full report module for comprehensive display
  local full = require("writing-metrics.full")
  full.show_report(bufnr)
end

--- Global state for statusline mode toggle
M._statusline_mode = "fast" -- "fast" or "accurate"

--- Toggle between fast (cached) and accurate (always fresh) word count
--- @return string New mode
function M.toggle_mode()
  if M._statusline_mode == "fast" then
    M._statusline_mode = "accurate"
    local utils = get_utils()
    utils.notify("Word count mode: Accurate (always fresh)", vim.log.levels.INFO)
  else
    M._statusline_mode = "fast"
    local utils = get_utils()
    utils.notify("Word count mode: Fast (cached)", vim.log.levels.INFO)
  end
  return M._statusline_mode
end

--- Get statusline component function
--- @return function Component function for lualine/other statuslines
function M.get_statusline_component()
  return function()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Check if writing buffer
    if not M.is_writing_buffer(bufnr) then
      return ""
    end

    local cache = get_cache()
    local cached = cache.get_basic(bufnr)

    if cached then
      -- Format based on config
      local config = get_config()
      local format = config.config.display.statusline_format

      if format == "words" then
        return string.format("󰗊 %d", cached.words)
      elseif format == "chars" then
        return string.format("󰬶 %d", cached.chars)
      else -- "both"
        return string.format("󰗊 %d 󰬶 %d", cached.words, cached.chars)
      end
    end

    -- No cache - trigger async update
    if M._statusline_mode == "accurate" then
      M.get_metrics(bufnr, "basic", function() end)
    end

    return "󰗊 …"
  end
end

--- Clear cache for specific buffer
--- @param bufnr number|nil Buffer number
function M.clear_cache(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cache = get_cache()
  cache.invalidate(bufnr)
end

--- Clear all caches
function M.clear_all_caches()
  local cache = get_cache()
  cache.clear_all()
end

--- Compatibility shim for accurate_wordcount global function
--- Used by existing lualine configuration
_G.accurate_wordcount = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache = get_cache()
  local cached = cache.get_basic(bufnr)

  if cached then
    return cached.words or 0
  end

  return 0
end

--- Compatibility shim for text_metrics global function
_G.text_metrics = function()
  local bufnr = vim.api.nvim_get_current_buf()

  if not M.is_writing_buffer(bufnr) then
    return ""
  end

  local cache = get_cache()
  local cached = cache.get_basic(bufnr)

  if cached then
    local utils = get_utils()
    return string.format(
      "󰗊 %s words  󰬶 %s chars",
      utils.format_number(cached.words),
      utils.format_number(cached.chars)
    )
  end

  return "󰗊 …"
end

-- Manual testing:
-- :lua require("writing-metrics").setup()
-- :lua require("writing-metrics").show_basic_metrics()
-- :lua require("writing-metrics").show_full_report()
-- :lua print(require("writing-metrics").is_writing_buffer(0))
-- :lua print(require("writing-metrics").toggle_mode())
-- :lua print(require("writing-metrics").get_statusline_component()())

return M
