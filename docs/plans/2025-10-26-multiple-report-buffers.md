# Multiple Report Buffers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix E95 buffer naming conflict by supporting multiple simultaneous report buffers (one per source document) with smart regeneration via `<leader>mr`.

**Architecture:** Global tracking table maps source_bufnr → report_bufnr. Each report buffer has unique name based on source filename. Regeneration checks for existing report and updates in-place. Validation prevents generation from report buffers.

**Tech Stack:** Neovim Lua API, buffer management, autocmds

---

## Task 1: Initialize Global Tracking Table

**Files:**
- Modify: `/home/jkeim/projects/nvim-writing-metrics/lua/writing-metrics/init.lua:1-10`

**Step 1: Add global tracking table at module initialization**

Add after line 3 (after `local M = {}`):

```lua
--- Global tracking table for report buffers
--- Maps source_bufnr → report_bufnr
--- @type table<number, number>
_G.writing_metrics_reports = _G.writing_metrics_reports or {}
```

**Step 2: Verify initialization**

Run in Neovim:
```vim
:lua print(vim.inspect(_G.writing_metrics_reports))
```

Expected output: `{}`

**Step 3: Commit**

```bash
cd /home/jkeim/projects/nvim-writing-metrics
git add lua/writing-metrics/init.lua
git commit -m "feat: add global tracking table for report buffers"
```

---

## Task 2: Add Report Buffer Detection Helper

**Files:**
- Modify: `/home/jkeim/projects/nvim-writing-metrics/lua/writing-metrics/utils.lua:54-70`

**Step 1: Add is_report_buffer() function**

Add after `is_writing_filetype()` function (around line 54):

```lua
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
  local ok_buftype, buftype = pcall(vim.api.nvim_buf_get_option, bufnr, "buftype")
  if not ok_buftype or buftype ~= "nofile" then
    return false
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  return bufname:match("^Report:") ~= nil
end
```

**Step 2: Test the helper function**

Create test report buffer and verify detection:
```vim
:tabnew
:set buftype=nofile
:file Report: test.md
:lua print(require("writing-metrics.utils").is_report_buffer(0))
```

Expected output: `true`

Test with regular buffer:
```vim
:tabnew /tmp/test.md
:lua print(require("writing-metrics.utils").is_report_buffer(0))
```

Expected output: `false`

**Step 3: Commit**

```bash
git add lua/writing-metrics/utils.lua
git commit -m "feat: add is_report_buffer() helper function"
```

---

## Task 3: Add Report Buffer Utilities to display.lua

**Files:**
- Modify: `/home/jkeim/projects/nvim-writing-metrics/lua/writing-metrics/display.lua:1-50`

**Step 1: Add helper function to find existing report**

Add after the `M = {}` line (around line 3):

```lua
--- Find existing report buffer for a source buffer
--- @param source_bufnr number Source buffer number
--- @return number|nil Report buffer number if exists and valid
function M.find_existing_report(source_bufnr)
  local report_bufnr = _G.writing_metrics_reports[source_bufnr]

  if report_bufnr and vim.api.nvim_buf_is_valid(report_bufnr) then
    return report_bufnr
  end

  -- Clean up stale reference
  if report_bufnr then
    _G.writing_metrics_reports[source_bufnr] = nil
  end

  return nil
end
```

**Step 2: Add function to generate unique report buffer name**

Add after `find_existing_report()`:

```lua
--- Generate unique buffer name for report
--- @param source_bufnr number Source buffer number
--- @return string Buffer name like "Report: filename.md"
function M.generate_report_name(source_bufnr)
  local source_name = vim.api.nvim_buf_get_name(source_bufnr)

  if source_name == "" then
    return "Report: [No Name]"
  end

  -- Get just the filename (tail)
  local filename = vim.fn.fnamemodify(source_name, ":t")

  -- If filename is empty or very common, include parent directory
  if filename == "" or filename == "README.md" or filename == "draft.md" then
    filename = vim.fn.fnamemodify(source_name, ":~:.")
  end

  return "Report: " .. filename
end
```

**Step 3: Add function to update report buffer in-place**

Add after `generate_report_name()`:

```lua
--- Update existing report buffer with new content
--- @param report_bufnr number Report buffer to update
--- @param lines table New content lines
function M.update_report_buffer(report_bufnr, lines)
  -- Make buffer temporarily modifiable
  vim.api.nvim_buf_set_option(report_bufnr, "modifiable", true)

  -- Replace all content
  vim.api.nvim_buf_set_lines(report_bufnr, 0, -1, false, lines)

  -- Restore unmodifiable state
  vim.api.nvim_buf_set_option(report_bufnr, "modifiable", false)
end
```

**Step 4: Test helper functions manually**

```vim
:lua local d = require("writing-metrics.display")
:lua print(d.generate_report_name(vim.api.nvim_get_current_buf()))
```

Expected: Shows "Report: <current-filename>"

**Step 5: Commit**

```bash
git add lua/writing-metrics/display.lua
git commit -m "feat: add report buffer management utilities"
```

---

## Task 4: Refactor show_report() with Validation and Reuse Logic

**Files:**
- Modify: `/home/jkeim/projects/nvim-writing-metrics/lua/writing-metrics/full.lua:76-105`

**Step 1: Replace show_report() function**

Replace the entire `show_report()` function (lines 78-104) with:

```lua
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
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
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
    local lines = display.format_report(result)

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
        local window_type = config.config.display.report_window

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
      local window_type = config.config.display.report_window

      display.create_report_buffer(lines, {
        window_type = window_type,
        source_bufnr = bufnr,
      })
    end
  end)
end
```

**Step 2: Test validation errors**

Test from report buffer:
```vim
" Open any markdown file
:edit /tmp/test.md
" Generate report
:lua require("writing-metrics.full").show_report()
" Now try from report buffer
:lua require("writing-metrics.full").show_report()
```

Expected: Warning message "Switch to document buffer..."

Test from non-writing buffer:
```vim
:edit /tmp/test.lua
:lua require("writing-metrics.full").show_report()
```

Expected: Warning message "Not a writing buffer..."

**Step 3: Commit**

```bash
git add lua/writing-metrics/full.lua
git commit -m "feat: add validation and reuse logic to show_report()"
```

---

## Task 5: Update create_report_buffer() for Unique Naming

**Files:**
- Modify: `/home/jkeim/projects/nvim-writing-metrics/lua/writing-metrics/display.lua:641-674`

**Step 1: Update function signature and add unique naming**

Replace the `create_report_buffer()` function (lines 644-674) with:

```lua
--- Create report buffer and display it
--- @param lines table Lines to display
--- @param opts table Options (window_type, source_bufnr)
function M.create_report_buffer(lines, opts)
  opts = opts or {}
  local window_type = opts.window_type or "tab"
  local source_bufnr = opts.source_bufnr

  -- Open new window
  if window_type == "tab" then
    vim.cmd("tabnew")
  elseif window_type == "split" then
    vim.cmd("split")
  elseif window_type == "vsplit" then
    vim.cmd("vsplit")
  end

  local bufnr = vim.api.nvim_get_current_buf()

  -- Set content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

  -- Set unique buffer name based on source
  if source_bufnr then
    local buffer_name = M.generate_report_name(source_bufnr)
    vim.api.nvim_buf_set_name(bufnr, buffer_name)

    -- Store mapping in global tracking table
    _G.writing_metrics_reports[source_bufnr] = bufnr
  end

  -- Set buffer-local keymaps
  M.setup_report_keymaps(bufnr)
end
```

**Step 2: Test unique buffer names**

```vim
" Open two markdown files
:edit /tmp/test1.md
:lua require("writing-metrics.full").show_report()
" Check buffer name
:echo bufname('%')

" Switch to second file
:edit /tmp/test2.md
:lua require("writing-metrics.full").show_report()
" Check buffer name
:echo bufname('%')
```

Expected: "Report: test1.md" and "Report: test2.md" (no E95 error)

**Step 3: Commit**

```bash
git add lua/writing-metrics/display.lua
git commit -m "feat: use unique buffer names for reports"
```

---

## Task 6: Remove 'r' Keymap and Update Footer

**Files:**
- Modify: `/home/jkeim/projects/nvim-writing-metrics/lua/writing-metrics/display.lua:74` (footer text)
- Modify: `/home/jkeim/projects/nvim-writing-metrics/lua/writing-metrics/display.lua:676-699` (keymaps)

**Step 1: Update footer text**

Find and replace line 74:

```lua
-- OLD:
table.insert(lines, "**Navigation:** Press `q` to close | `r` to refresh | `1`-`8` to jump to sections")

-- NEW:
table.insert(lines, "**Navigation:** Press `q` to close | `<leader>mr` from document to regenerate | `1`-`8` to jump to sections")
```

**Step 2: Remove 'r' keymap from setup_report_keymaps()**

Find the `setup_report_keymaps()` function (around line 678) and remove these lines (686-688):

```lua
-- REMOVE THESE LINES:
-- Refresh report
vim.keymap.set("n", "r", function()
  require("writing-metrics.full").show_report(0)
end, vim.tbl_extend("force", opts, { desc = "Refresh report" }))
```

**Step 3: Test footer text and keymaps**

```vim
:edit /tmp/test.md
:lua require("writing-metrics.full").show_report()
```

Expected:
- Footer shows "`<leader>mr` from document to regenerate"
- Pressing 'r' does NOT refresh (no keymap)
- Pressing `q` closes report

**Step 4: Commit**

```bash
git add lua/writing-metrics/display.lua
git commit -m "feat: remove 'r' refresh keymap, update footer instructions"
```

---

## Task 7: Add Cleanup Autocmds

**Files:**
- Modify: `/home/jkeim/projects/nvim-writing-metrics/lua/writing-metrics/init.lua` (add autocmds)

**Step 1: Add cleanup autocmd group**

Add at the end of the `setup()` function (before `return M`):

```lua
--- Setup cleanup autocmds for report tracking
local function setup_report_cleanup()
  local group = vim.api.nvim_create_augroup("WritingMetricsReportCleanup", { clear = true })

  -- Clean up tracking table when source buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(args)
      local bufnr = args.buf

      -- If this is a source buffer, remove its report mapping
      if _G.writing_metrics_reports[bufnr] then
        _G.writing_metrics_reports[bufnr] = nil
      end

      -- If this is a report buffer, remove all mappings to it
      for source_bufnr, report_bufnr in pairs(_G.writing_metrics_reports) do
        if report_bufnr == bufnr then
          _G.writing_metrics_reports[source_bufnr] = nil
        end
      end
    end,
  })
end

-- Call setup function
setup_report_cleanup()
```

**Step 2: Test cleanup**

```vim
:lua _G.writing_metrics_reports = {5 = 10, 7 = 12}
:lua print(vim.inspect(_G.writing_metrics_reports))

" Delete buffer 5
:bdelete 5
:lua print(vim.inspect(_G.writing_metrics_reports))
```

Expected: Entry for buffer 5 should be removed

**Step 3: Commit**

```bash
git add lua/writing-metrics/init.lua
git commit -m "feat: add autocmds to clean up report tracking table"
```

---

## Task 8: Manual Testing

**No code changes - verification only**

**Test 1: Single document report generation**

```vim
:edit /tmp/test.md
:lua require("writing-metrics.full").show_report()
```

Expected: Report opens in new tab with name "Report: test.md"

**Test 2: Multiple document reports (no naming conflicts)**

```vim
:edit /tmp/test1.md
:lua require("writing-metrics.full").show_report()
:edit /tmp/test2.md
:lua require("writing-metrics.full").show_report()
:buffers
```

Expected: Two report buffers exist: "Report: test1.md" and "Report: test2.md", no E95 error

**Test 3: Regeneration updates in-place**

```vim
:edit /tmp/test.md
:lua require("writing-metrics.full").show_report()
" Note current buffer number
:echo bufnr('%')
" Make changes to test.md
:edit /tmp/test.md
iAdd new text<Esc>
:lua require("writing-metrics.full").show_report()
" Check buffer number again
:echo bufnr('%')
```

Expected: Same buffer number, content updated, no new buffer created

**Test 4: Error when pressing <leader>mr from report buffer**

```vim
:edit /tmp/test.md
:lua require("writing-metrics.full").show_report()
" Now in report buffer
:lua require("writing-metrics.full").show_report()
```

Expected: Warning "Switch to document buffer to regenerate report..."

**Test 5: Cleanup when buffers deleted**

```vim
:lua _G.writing_metrics_reports = {}
:edit /tmp/test.md
:lua require("writing-metrics.full").show_report()
:lua print(vim.inspect(_G.writing_metrics_reports))
" Delete source buffer
:edit /tmp/test.md
:bdelete
:lua print(vim.inspect(_G.writing_metrics_reports))
```

Expected: Tracking table is empty after deletion

**Test 6: 'r' keymap removed**

```vim
:edit /tmp/test.md
:lua require("writing-metrics.full").show_report()
" Press 'r' in normal mode
r
```

Expected: 'r' acts as normal Vim replace command, NOT refresh

**All tests pass?** → Done! Create final commit:

```bash
git add -A
git commit -m "docs: add manual testing verification"
git log --oneline -8
```

Expected: 8 commits from this implementation

---

## Success Criteria

- ✅ No E95 errors when generating reports for multiple documents
- ✅ Report buffers have unique names based on source filename
- ✅ Regenerating report updates existing buffer (no new buffer created)
- ✅ Error shown when trying to generate from report buffer
- ✅ Tracking table cleaned up when buffers deleted
- ✅ 'r' keymap removed, footer updated with `<leader>mr` instructions
- ✅ All manual tests pass
