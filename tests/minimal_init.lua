-- Minimal init for running tests
-- This is used by plenary.nvim to set up a clean testing environment

-- Reset runtime path
vim.cmd([[set runtimepath=$VIMRUNTIME]])
vim.cmd([[set packpath=/tmp/nvim-writing-metrics-test/site]])

local package_root = "/tmp/nvim-writing-metrics-test/site/pack"
local install_path = package_root .. "/vendor/start/plenary.nvim"

-- Install plenary.nvim if not already present
if vim.fn.isdirectory(install_path) == 0 then
  print("Installing plenary.nvim for testing...")
  vim.fn.system({
    "git",
    "clone",
    "--depth=1",
    "https://github.com/nvim-lua/plenary.nvim",
    install_path,
  })
end

-- Add plenary to runtime
vim.cmd("packadd plenary.nvim")

-- Add the plugin under test to runtime
vim.opt.rtp:append(".")

-- Load plenary test harness
require("plenary.busted")

-- Ensure test utilities are available
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/tests")

-- Set up minimal vim options for testing
vim.opt.swapfile = false
vim.opt.hidden = true

-- Suppress unnecessary output
vim.opt.shortmess:append("c")

print("Test environment initialized")
