--- Utility functions for nvim-writing-metrics
--- @module writing-metrics.utils
local M = {}

--- Extract the JSON object line from filter output.
--- The textmetrics filter emits JSON via print(json.encode(...)), which is
--- always a single line. Pandoc warnings may appear before the JSON and
--- may legitimately contain '{', so a greedy first-'{' search is unsafe.
--- Strategy: scan from the end and return the last line that both starts
--- with '{' (possibly preceded by whitespace) and ends with '}'.
--- @param str string Raw filter/pandoc output
--- @return string|nil The JSON line, or nil if not found
local function extract_json(str)
  if not str or str == "" then return nil end
  local lines = vim.split(str, "\n", { plain = true })
  for i = #lines, 1, -1 do
    local line = lines[i]:gsub("^%s+", ""):gsub("%s+$", "")
    if line:sub(1, 1) == "{" and line:sub(-1) == "}" then
      return line
    end
  end
  return nil
end

-- Exposed for use by other modules (e.g. full.lua).
M._extract_json = extract_json

--- Get the content of a buffer as a single string
--- @param bufnr number|nil Buffer number (0 or nil for current)
--- @return string Buffer content
function M.get_buffer_content(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

--- Get the currently selected text in visual mode
--- @return string|nil Selection content
function M.get_selection_content()
  -- Get visual selection marks
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  if start_pos[2] == 0 or end_pos[2] == 0 then
    return nil
  end

  local start_line = start_pos[2] - 1
  local end_line = end_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_col = end_pos[3]

  local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line + 1, false)

  if #lines == 0 then
    return nil
  end

  -- Handle single line selection
  if #lines == 1 then
    return lines[1]:sub(start_col + 1, end_col)
  end

  -- Handle multi-line selection
  lines[1] = lines[1]:sub(start_col + 1)
  lines[#lines] = lines[#lines]:sub(1, end_col)

  return table.concat(lines, "\n")
end

--- Check if a filetype is a writing filetype
--- @param ft string Filetype to check
--- @return boolean
function M.is_writing_filetype(ft)
  local config = require("writing-metrics.config")
  return config.is_enabled_filetype(ft)
end

--- Check if a buffer is a writing metrics report buffer
--- @param bufnr number|nil Buffer number (0 or nil for current)
--- @return boolean
function M.is_report_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check if buffer is valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Report buffers have buftype=nofile and name starts with "Report:"
  local ok_buftype, buftype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = bufnr })
  if not ok_buftype or buftype ~= "nofile" then
    return false
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  -- Extract just the tail (filename) to check for "Report:" prefix
  -- This handles both "Report: test.md" and "/path/to/Report: test.md"
  local tail = vim.fn.fnamemodify(bufname, ":t")
  return tail:match("^Report:") ~= nil
end

--- Write content to a temporary file
--- @param content string Content to write
--- @param extension string|nil File extension (default: ".md")
--- @return string|nil Temporary file path
--- @return string|nil Error message if failed
function M.write_temp_file(content, extension)
  extension = extension or ".md"

  -- Create temp file
  local temp_path = vim.fn.tempname() .. extension

  -- Temp file created successfully

  -- Write content
  local file, err = io.open(temp_path, "w")
  if not file then
    return nil, "Failed to create temp file: " .. (err or "unknown error")
  end

  file:write(content)
  file:close()

  return temp_path
end

--- Clean up a temporary file
--- @param path string Path to temporary file
function M.cleanup_temp_file(path)
  if path and vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
end

--- Execute Pandoc with the textmetrics filter
--- @param input_file string Path to input file
--- @param mode string "basic" or "full"
--- @param callback function Callback(success, result_or_error)
function M.run_pandoc(input_file, mode, callback)
  local config = require("writing-metrics.config")
  local filter_path = config.get_filter_path()

  if not filter_path then
    -- Caller's cleanup runs inside vim.system callback, which won't fire
    -- on early return. Clean up the temp file here to avoid leaking it.
    M.cleanup_temp_file(input_file)
    callback(false, "Pandoc filter not found")
    return
  end

  -- Using filter in specified mode

  -- Build Pandoc command
  local cmd = {
    "pandoc",
    input_file,
    "--lua-filter",
    filter_path,
    "-t",
    "plain",
    "--metadata",
    "metrics_mode=" .. mode,
  }

  -- Execute Pandoc asynchronously
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(false, "Pandoc failed: " .. (result.stderr or "unknown error"))
        return
      end

      callback(true, result.stdout)
    end)
  end)
end

--- Parse basic metrics output (space-separated values)
--- Format: words chars sentences paragraphs avg_sentence_len avg_word_len
--- @param output string Pandoc output
--- @return table|nil Parsed metrics
--- @return string|nil Error message if failed
function M.parse_basic_output(output)
  if not output or output == "" then
    return nil, "Empty output from Pandoc"
  end

  -- Trim trailing whitespace/newlines
  output = output:gsub("%s+$", "")

  -- Extract the metrics line (last non-empty line, ignoring Pandoc warnings)
  local metrics_line = output:match("[^\n]+$")
  if not metrics_line then
    return nil, "Could not find metrics in output"
  end

  local values = {}
  for value in metrics_line:gmatch("%S+") do
    local n = tonumber(value)
    -- tonumber("NaN") returns a real NaN float in LuaJIT (truthy).
    -- NaN is the only value that does not equal itself, hence `n ~= n`.
    if not n or n ~= n then
      return nil, "Non-numeric value in metrics output: " .. value
    end
    table.insert(values, n)
  end

  if #values < 6 then
    return nil, "Invalid basic metrics format: expected 6 values, got " .. #values
  end

  return {
    words = values[1],
    chars = values[2],
    sentences = values[3],
    paragraphs = values[4],
    avg_sentence_len = values[5],
    avg_word_len = values[6],
  }
end

--- Parse full metrics output (JSON)
--- @param output string Pandoc output
--- @return table|nil Parsed metrics
--- @return string|nil Error message if failed
function M.parse_full_output(output)
  if not output or output == "" then
    return nil, "Empty output from Pandoc"
  end

  local json_str = extract_json(output)
  if not json_str then
    return nil, "No JSON found in output"
  end

  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, "Failed to parse JSON: " .. tostring(result)
  end

  return result
end

--- Create a floating window with specified content
--- @param content string|table Content (string or lines table) OR opts table with 'lines' key
--- @param opts table|nil Options (title, width, height, border) - optional if content is opts table
--- @return number Buffer number
--- @return number Window ID
function M.create_float_window(content, opts)
  -- Handle both calling conventions:
  -- 1. create_float_window(lines, opts) - old style
  -- 2. create_float_window({lines=..., title=..., border=...}) - new style
  if type(content) == "table" and content.lines then
    opts = content
    content = content.lines
  end

  opts = opts or {}

  -- Convert string to lines
  local lines = type(content) == "string" and vim.split(content, "\n", { plain = true }) or content

  -- Calculate dimensions
  local width = opts.width or math.min(100, vim.o.columns - 10)
  local height = opts.height or math.min(30, vim.o.lines - 5)

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })

  -- Create window
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = opts.border or "rounded",
    title = opts.title or "",
    title_pos = "center",
  }

  local winid = vim.api.nvim_open_win(bufnr, true, win_opts)

  -- Set buffer-local keymaps to close
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = bufnr, silent = true })

  return bufnr, winid
end

--- Open a report in a new tab/split
--- @param content string|table Report content
--- @param opts table|nil Options (window_type, filetype, title)
function M.open_report_tab(content, opts)
  opts = opts or {}

  local window_type = opts.window_type or "tab"
  local lines = type(content) == "string" and vim.split(content, "\n", { plain = true }) or content

  -- Open new window
  if window_type == "tab" then
    vim.cmd("tabnew")
  elseif window_type == "split" then
    vim.cmd("new")
  elseif window_type == "vsplit" then
    vim.cmd("vnew")
  end

  -- Set content
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Set buffer options
  vim.api.nvim_set_option_value("filetype", opts.filetype or "markdown", { buf = bufnr })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })

  if opts.title then
    vim.api.nvim_buf_set_name(bufnr, opts.title)
  end

  -- Set buffer-local keymap to close
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, silent = true })
end

--- Send a notification using Snacks.nvim or vim.notify fallback
--- @param message string Notification message
--- @param level number|nil Log level (vim.log.levels)
function M.notify(message, level)
  level = level or vim.log.levels.INFO

  -- Try Snacks.nvim first
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.notify then
    snacks.notify(message, { level = level })
  else
    -- Fallback to vim.notify
    vim.notify(message, level)
  end
end

--- Handle errors with consistent formatting
--- @param err string Error message
--- @param context string|nil Context description
function M.handle_error(err, context)
  local msg = context and (context .. ": " .. err) or err
  M.notify(msg, vim.log.levels.ERROR)
  vim.api.nvim_err_writeln("writing-metrics: " .. msg)
end

--- Validate Pandoc is available
--- @return boolean Success
--- @return string|nil Error message
function M.validate_pandoc()
  local config = require("writing-metrics.config")
  return config.validate_pandoc()
end

--- Validate filter exists
--- @return boolean Success
--- @return string|nil Error message or filter path
function M.validate_filter()
  local config = require("writing-metrics.config")
  local path, err = config.find_filter()
  if path then
    return true, path
  else
    return false, err
  end
end

--- Format a number with thousands separators
--- @param num number Number to format
--- @return string Formatted number
function M.format_number(num)
  if not num then
    return "0"
  end

  -- Round to integer
  num = math.floor(num + 0.5)

  -- Add thousands separators
  local formatted = tostring(num)
  local k
  while true do
    formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then
      break
    end
  end
  return formatted
end

--- Format a percentage
--- @param num number Number to format (0-100)
--- @param decimals number|nil Decimal places (default: 1)
--- @return string Formatted percentage
function M.format_percentage(num, decimals)
  if not num then
    return "0.0%"
  end
  decimals = decimals or 1
  return string.format("%." .. decimals .. "f%%", num)
end

--- Format a decimal number
--- @param num number Number to format
--- @param decimals number|nil Decimal places (default: 2)
--- @return string Formatted number
function M.format_decimal(num, decimals)
  if not num then
    return "0.00"
  end
  decimals = decimals or 2
  return string.format("%." .. decimals .. "f", num)
end

-- Manual testing:
-- :lua print(require("writing-metrics.utils").get_buffer_content(0))
-- :lua print(require("writing-metrics.utils").format_number(12345678))
-- :lua print(require("writing-metrics.utils").format_percentage(45.678))
-- :lua require("writing-metrics.utils").notify("Test notification", vim.log.levels.INFO)

return M
