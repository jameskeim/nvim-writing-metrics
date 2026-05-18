-- Backward compatibility tests
local helpers = require("tests.helpers")

describe("backward compatibility", function()
  local metrics

  before_each(function()
    package.loaded["writing-metrics"] = nil
    metrics = require("writing-metrics")

    -- Clear global functions
    _G.accurate_wordcount = nil
    _G.text_metrics = nil
  end)

  after_each(function()
    helpers.cleanup_buffers()
  end)

  describe("global function exports", function()
    it("provides _G.accurate_wordcount", function()
      metrics.setup()

      assert.is_not_nil(_G.accurate_wordcount)
    end)

    it("accurate_wordcount is callable", function()
      metrics.setup()

      -- accurate_wordcount is a callable table (has __call metamethod) so it
      -- satisfies both the function-form contract (used by lualine configs)
      -- and the table-form contract (used as a module API for methods).
      assert.is_true(
        type(_G.accurate_wordcount) == "table",
        "accurate_wordcount should be a table"
      )
      local ok = pcall(_G.accurate_wordcount)
      assert.is_true(ok, "accurate_wordcount should be callable via __call")
    end)

    it("provides _G.text_metrics", function()
      metrics.setup()

      assert.is_function(_G.text_metrics)
    end)

    it("text_metrics is callable", function()
      metrics.setup()

      local status, result = pcall(_G.text_metrics)
      assert.is_true(status, "text_metrics should be callable")
    end)
  end)

  describe("legacy commands", function()
    it("registers all standard commands", function()
      metrics.setup()

      local commands = {
        "WordCount",
        "ReadabilityReport",
        "WritingMetricsToggle",
      }

      for _, cmd in ipairs(commands) do
        local exists = vim.fn.exists(":" .. cmd) == 2
        assert.is_true(exists, "Command :" .. cmd .. " not found")
      end
    end)

    it("registers legacy commands when enabled", function()
      metrics.setup({ commands = { enable_legacy = true } })

      local legacy_commands = {
        "AccurateWordCount",
        "ToggleWordCountMode",
      }

      for _, cmd in ipairs(legacy_commands) do
        local exists = vim.fn.exists(":" .. cmd) == 2
        assert.is_true(exists, "Legacy command :" .. cmd .. " not found")
      end
    end)

    it("does not register legacy commands when disabled", function()
      metrics.setup({ commands = { enable_legacy = false } })

      local legacy_commands = {
        "AccurateWordCount",
        "ToggleWordCountMode",
      }

      for _, cmd in ipairs(legacy_commands) do
        local exists = vim.fn.exists(":" .. cmd) == 2
        assert.is_false(exists, "Legacy command :" .. cmd .. " should not exist")
      end
    end)
  end)

  describe("lualine component backward compatibility", function()
    it("provides lualine_component function", function()
      local basic = require("writing-metrics.basic")

      assert.is_function(basic.lualine_component)
    end)

    it("lualine component returns valid structure", function()
      local basic = require("writing-metrics.basic")
      local component = basic.lualine_component()

      assert.is_not_nil(component)
      -- Should be either a function or table with required fields
      assert.is_true(
        type(component) == "function" or type(component) == "table",
        "Component should be function or table"
      )
    end)
  end)

  describe("API compatibility", function()
    it("basic module exports expected functions", function()
      local basic = require("writing-metrics.basic")

      local expected_functions = {
        "get_fast_count",
        "get_accurate_count",
        "get_statusline_string",
        "toggle_statusline_mode",
        "show_comparison",
        "lualine_component",
      }

      for _, func_name in ipairs(expected_functions) do
        assert.is_function(basic[func_name], func_name .. " should be a function")
      end
    end)

    it("full module exports expected functions", function()
      local full = require("writing-metrics.full")

      local expected_functions = {
        "get_full_metrics",
        "show_report",
      }

      for _, func_name in ipairs(expected_functions) do
        assert.is_function(full[func_name], func_name .. " should be a function")
      end
    end)

    it("cache module exports expected functions", function()
      local cache = require("writing-metrics.cache")

      local expected_functions = {
        "get_basic",
        "set_basic",
        "get_full",
        "set_full",
        "invalidate",
        "clear_all",
        "get_statistics",
      }

      for _, func_name in ipairs(expected_functions) do
        assert.is_function(cache[func_name], func_name .. " should be a function")
      end
    end)
  end)

  describe("statusline mode compatibility", function()
    it("supports fast and accurate modes", function()
      local basic = require("writing-metrics.basic")

      -- Should have mode property
      assert.is_not_nil(basic.statusline_mode)

      -- Should be either fast or accurate
      assert.is_true(
        basic.statusline_mode == "fast" or basic.statusline_mode == "accurate",
        "Mode should be fast or accurate"
      )
    end)

    it("toggle switches between modes", function()
      local basic = require("writing-metrics.basic")

      local initial = basic.statusline_mode
      basic.toggle_statusline_mode()
      local after_toggle = basic.statusline_mode

      assert.are_not.equals(initial, after_toggle)
    end)
  end)

  describe("display function compatibility", function()
    it("show_comparison exists", function()
      local basic = require("writing-metrics.basic")

      assert.is_function(basic.show_comparison)
    end)

    it("show_report exists", function()
      local full = require("writing-metrics.full")

      assert.is_function(full.show_report)
    end)

    it("display functions don't crash on empty buffer", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.empty)

      local basic = require("writing-metrics.basic")
      local full = require("writing-metrics.full")

      local basic_success = pcall(basic.show_comparison, bufnr)
      local full_success = pcall(full.show_report, bufnr)

      assert.is_true(basic_success)
      assert.is_true(full_success)
    end)
  end)
end)
