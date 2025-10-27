# Migration Checklist

Use this checklist to track your migration from `text-metrics.lua` + `accurate-wordcount.lua` to the unified `nvim-writing-metrics` plugin.

## Pre-Migration Checklist

- [ ] **Backup your current Neovim configuration**
  ```bash
  cd ~/.config/nvim
  cp -r lua/plugins lua/plugins.backup
  ```

- [ ] **Document your current keybindings**
  - Note: `<leader>mc` → Show word count
  - Note: `<leader>mr` → Full readability report
  - Note: `<leader>mt` → Toggle fast/accurate mode

- [ ] **Document any custom lualine configuration**
  - Check `lua/plugins/lualine-mods.lua`
  - Note any custom formatting or colors

- [ ] **Check if you use `_G.accurate_wordcount` in custom scripts**
  ```vim
  :grep "_G.accurate_wordcount\|_G.text_metrics" ~/.config/nvim/**/*.lua
  ```

- [ ] **Check if you use global APIs elsewhere**
  ```vim
  :grep "accurate_wordcount\|text_metrics" ~/.config/nvim/**/*.lua
  ```

- [ ] **Save any custom word count settings**
  - Cache durations (if modified from defaults)
  - Custom Pandoc filter path (if not `~/bin/textmetrics.lua`)
  - Custom UI settings (float size, borders)

- [ ] **Verify Pandoc and filter are working**
  ```bash
  pandoc --version
  ls -la ~/bin/textmetrics.lua
  ```

- [ ] **Test current word count before migration**
  - Open a markdown file
  - Press `<leader>mc` → Note the count
  - Press `<leader>mr` → Verify full report works
  - Press `<leader>mt` → Toggle mode, test both

## Migration Steps

### Installation

- [ ] **Create new plugin spec file**
  - Create `~/.config/nvim/lua/plugins/writing-metrics.lua`
  - Add plugin specification (see MIGRATION.md)

- [ ] **Install nvim-writing-metrics via lazy.nvim**
  ```vim
  :Lazy sync
  ```

- [ ] **Remove old plugin files**
  ```bash
  rm ~/.config/nvim/lua/plugins/text-metrics.lua
  rm ~/.config/nvim/lua/plugins/accurate-wordcount.lua
  ```

- [ ] **Update lualine configuration (optional but recommended)**
  - Replace `_G.accurate_wordcount()` calls with new component
  - Use `require("writing-metrics.basic").lualine_component()`
  - See MIGRATION.md for examples

- [ ] **Restart Neovim**
  ```vim
  :quitall
  ```

### Verification

- [ ] **Check plugin loaded successfully**
  ```vim
  :Lazy
  # Verify nvim-writing-metrics is listed and loaded
  ```

- [ ] **Run health check**
  ```vim
  :checkhealth writing-metrics
  ```
  - [ ] All checks pass (green ✓)
  - [ ] No errors or warnings

- [ ] **Test basic word count (`<leader>mc`)**
  - Open a markdown file with known content
  - Press `<leader>mc`
  - [ ] Floating window appears
  - [ ] Word count matches previous count (±1 due to rounding)
  - [ ] Characters, sentences, paragraphs displayed
  - [ ] Window closes on `q`

- [ ] **Test full readability report (`<leader>mr`)**
  - Press `<leader>mr`
  - [ ] New tab opens with full report
  - [ ] All 6 readability formulas shown
  - [ ] Sentence variability section present
  - [ ] AI-style analysis present
  - [ ] Report closes on `q`

- [ ] **Test toggle mode (`<leader>mt`)**
  - Press `<leader>mt` to switch to accurate mode
  - [ ] Notification shows "📊 Accurate mode"
  - [ ] Statusline updates (may show "calculating..." briefly)
  - Press `<leader>mt` again to switch back
  - [ ] Notification shows "⚡ Fast mode"
  - [ ] Statusline updates immediately

- [ ] **Test statusline integration**
  - Open a markdown file
  - [ ] Statusline shows word count
  - [ ] Statusline shows character count
  - [ ] Format matches previous style (or custom style)
  - Edit some text
  - [ ] Word count updates after change (within cache TTL)

- [ ] **Test visual mode selection counting**
  - Select some text in visual mode
  - Press `<leader>mc`
  - [ ] Selection count displayed
  - [ ] Count is accurate for selection only

- [ ] **Verify cache is working**
  - Press `<leader>mr` (full report)
  - Immediately press `<leader>mc` (basic count)
  - [ ] Basic count appears instantly (< 50ms)
  - This confirms smart cache extraction is working

- [ ] **Check cache statistics**
  ```vim
  :WritingMetricsCache
  ```
  - [ ] Shows cache hit/miss rates
  - [ ] Shows last update times
  - [ ] Both basic and full caches initialized

- [ ] **Test all commands work**
  ```vim
  :WordCount
  :ReadabilityReport
  :WritingMetricsToggle
  :AccurateWordCount  # Backward compat alias
  :ToggleWordCountMode  # Backward compat alias
  ```

- [ ] **Verify no error messages**
  ```vim
  :messages
  ```
  - [ ] No errors related to writing-metrics
  - [ ] No "module not found" errors
  - [ ] No Pandoc errors

## Post-Migration Verification

### Functional Testing

- [ ] **Test in multiple file types**
  - [ ] Markdown (`.md`)
  - [ ] Plain text (`.txt`)
  - [ ] LaTeX (`.tex`)
  - [ ] Fountain (`.fountain`)
  - [ ] Org mode (`.org`)

- [ ] **Test edge cases**
  - [ ] Empty file (0 words)
  - [ ] Very long document (10,000+ words)
  - [ ] Document with YAML frontmatter
  - [ ] Document with code blocks
  - [ ] Document with LaTeX math

- [ ] **Test cache invalidation**
  - Open document
  - Note word count
  - Add text
  - [ ] Cache invalidates on TextChanged
  - [ ] New count reflects changes
  - Save file
  - [ ] Cache updates on BufWritePost

- [ ] **Test performance**
  - Open large document (5,000+ words)
  - Press `<leader>mc`
  - [ ] Response time < 1 second (first call)
  - Press `<leader>mc` again
  - [ ] Response time < 100ms (cached)

### Integration Testing

- [ ] **Test with writing modes** (if using writing-mode-toggles.lua)
  - Switch to Grant Mode
  - [ ] Word count still works
  - Switch to Creative Mode
  - [ ] Word count still works

- [ ] **Test with Zen Mode** (if using snacks.zen)
  - Enable Zen Mode
  - [ ] Statusline still visible
  - [ ] Word count updates work

- [ ] **Test with other writing plugins**
  - vim-pencil
  - render-markdown
  - obsidian.nvim
  - [ ] No conflicts or errors

### Regression Testing

- [ ] **Compare counts with old plugins**
  - Use the same document as pre-migration test
  - Basic count matches (±1%)
  - Full report has same metrics (±1%)

- [ ] **Verify no functionality lost**
  - All old features still work
  - No missing sections in reports
  - All keybindings respond correctly

## Rollback (if needed)

Only complete this section if you encounter critical issues:

- [ ] **Restore old plugin files from backup**
  ```bash
  cp ~/.config/nvim/lua/plugins.backup/*.lua ~/.config/nvim/lua/plugins/
  ```

- [ ] **Remove nvim-writing-metrics from plugin config**
  ```bash
  rm ~/.config/nvim/lua/plugins/writing-metrics.lua
  # Or comment out the plugin spec
  ```

- [ ] **Clean and sync plugin manager**
  ```vim
  :Lazy clean
  :Lazy sync
  ```

- [ ] **Restart Neovim**
  ```vim
  :quitall
  ```

- [ ] **Verify old plugins work**
  - Test `<leader>mc`
  - Test `<leader>mr`
  - Test `<leader>mt`

- [ ] **Report issue on GitHub**
  - [ ] Go to: https://github.com/yourusername/nvim-writing-metrics/issues
  - [ ] Create new issue with title: "Migration failed: [brief description]"
  - [ ] Include:
    - Error messages from `:messages`
    - Output of `:checkhealth` (if plugin loaded)
    - Your plugin configuration (opts table)
    - Neovim version: `:version`
    - Steps to reproduce the issue

## Success Criteria

Migration is complete when ALL of the following are true:

- [ ] ✅ Plugin loads without errors
- [ ] ✅ All keybindings work (`<leader>mc`, `<leader>mr`, `<leader>mt`)
- [ ] ✅ Statusline shows word count
- [ ] ✅ Basic count appears in < 100ms (cached)
- [ ] ✅ Full report opens and displays all sections
- [ ] ✅ Cache is working (verified via `:WritingMetricsCache`)
- [ ] ✅ No errors in `:messages`
- [ ] ✅ `:checkhealth writing-metrics` passes all checks
- [ ] ✅ Performance is same or better than old plugins
- [ ] ✅ You can write comfortably without noticing any difference

## Notes

Use this space to record any migration issues or observations:

---

**Migration started:** ___________________

**Migration completed:** ___________________

**Issues encountered:**

---

**Performance notes:**

---

**Configuration changes made:**

---

## Helpful Commands

Quick reference for troubleshooting:

```vim
" Check plugin status
:Lazy

" Verify health
:checkhealth writing-metrics

" Check cache
:WritingMetricsCache

" Clear cache and recalculate
:WritingMetricsClear

" View recent errors
:messages

" Test commands
:WordCount
:ReadabilityReport
:WritingMetricsToggle

" Check keybindings
:map <leader>mc
:map <leader>mr
:map <leader>mt

" Verify globals exist
:lua print(vim.inspect(_G.accurate_wordcount))
:lua print(vim.inspect(_G.text_metrics))
```

## Support

If you get stuck or encounter issues:

1. **Read the error message carefully** - Most errors explain exactly what's wrong
2. **Check `:messages`** - Previous errors may provide context
3. **Run `:checkhealth writing-metrics`** - Automated diagnostics
4. **Review MIGRATION.md** - Detailed troubleshooting section
5. **Check GitHub Issues** - Someone may have had the same problem
6. **Create new issue** - Provide full details for help
