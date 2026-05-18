-- plugin/writing-metrics.lua
-- Bootstrap: load the plugin unless the user opted into lazy.nvim's opts flow.
--
-- All side effects (commands, autocmds, shims, basic.setup) live inside
-- require("writing-metrics").setup(). This file just calls setup() once
-- for traditional plugin-manager users.

if vim.g.loaded_writing_metrics then
  return
end

if not vim.g.writing_metrics_lazy then
  -- Traditional plugin loading — initialize with default opts.
  require("writing-metrics").setup({})
end
