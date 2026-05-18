--- Comprehensive full report module for nvim-writing-metrics
--- Displays detailed writing analysis with beautiful formatting
--- @module writing-metrics.full
local M = {}

--- Execute Pandoc in full mode and parse comprehensive metrics
--- Always computes fresh metrics (no caching for reports)
--- @param bufnr number|nil Buffer number (0 or nil for current)
--- @param callback function Callback(success, data_or_error)
function M.get_full_metrics(bufnr, callback)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local utils = require("writing-metrics.utils")

  -- Always compute fresh full metrics
  local content = utils.get_buffer_content(bufnr)
  local temp_file, err = utils.write_temp_file(content)

  if not temp_file then
    callback(false, err)
    return
  end

  -- Run Pandoc in full mode
  utils.run_pandoc(temp_file, "full", function(success, result)
    utils.cleanup_temp_file(temp_file)

    if not success then
      callback(false, result)
      return
    end

    -- Parse JSON output
    local data, parse_err = M.parse_full_metrics(result)
    if not data then
      callback(false, parse_err)
      return
    end

    -- Return fresh data (no caching)
    callback(true, data)
  end)
end

--- Parse full metrics JSON output from Pandoc
--- @param json_output string JSON string from Pandoc filter
--- @return table|nil Parsed metrics data
--- @return string|nil Error message if failed
function M.parse_full_metrics(json_output)
  if not json_output or json_output == "" then
    return nil, "Empty output from Pandoc"
  end

  local utils = require("writing-metrics.utils")
  local json_str = utils._extract_json(json_output)
  if not json_str then
    return nil, "No JSON found in output"
  end

  local ok, result = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, "Failed to parse JSON: " .. tostring(result)
  end

  -- Validate required sections
  if not result.basic then
    return nil, "Missing 'basic' section in metrics output"
  end

  return result
end

--- Show comprehensive report in configured window type
--- @param bufnr number|nil Buffer number (0 or nil for current)
function M.show_report(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local utils = require("writing-metrics.utils")

  -- Validation 1: Don't allow generating reports from report buffers
  if utils.is_report_buffer(bufnr) then
    utils.notify(
      "Switch to document buffer to regenerate report (press <leader>mr from your writing file)",
      vim.log.levels.WARN
    )
    return
  end

  -- Validation 2: Only generate reports for writing filetypes
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  if not utils.is_writing_filetype(ft) then
    utils.notify(
      "Not a writing buffer (filetype: " .. ft .. ")",
      vim.log.levels.WARN
    )
    return
  end

  -- Show "Generating report..." message
  utils.notify("Generating comprehensive report...", vim.log.levels.INFO)

  M.get_full_metrics(bufnr, function(success, result)
    if not success then
      utils.handle_error(result, "Failed to generate report")
      return
    end

    -- Format the report
    local display = require("writing-metrics.display")
    local lines = display.format_report(result, bufnr)

    -- Check if report already exists for this buffer
    local existing_report = display.find_existing_report(bufnr)

    if existing_report then
      -- Update existing report in-place
      display.update_report_buffer(existing_report, lines)

      -- Focus the report buffer if not visible
      local report_visible = false
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == existing_report then
          report_visible = true
          vim.api.nvim_set_current_win(win)
          break
        end
      end

      if not report_visible then
        -- Open the existing report in configured window type
        local config = require("writing-metrics.config")
        local window_type = config.get().display.report_window

        if window_type == "tab" then
          vim.cmd("tabnew")
        elseif window_type == "split" then
          vim.cmd("split")
        elseif window_type == "vsplit" then
          vim.cmd("vsplit")
        end

        vim.api.nvim_set_current_buf(existing_report)
      end

      utils.notify("Report updated", vim.log.levels.INFO)
    else
      -- Create new report buffer
      local config = require("writing-metrics.config")
      local window_type = config.get().display.report_window

      display.create_report_buffer(lines, {
        window_type = window_type,
        source_bufnr = bufnr,
      })
    end
  end)
end

-- Manual testing:
-- :lua require("writing-metrics.full").show_report()
-- :lua require("writing-metrics.full").get_full_metrics(0, function(s, r) print(vim.inspect(r)) end)

return M
