-- Integration tests for writing-metrics
local helpers = require("tests.helpers")

describe("writing-metrics integration", function()
  local metrics
  local cache

  before_each(function()
    package.loaded["writing-metrics"] = nil
    package.loaded["writing-metrics.cache"] = nil

    metrics = require("writing-metrics")
    cache = require("writing-metrics.cache")
    cache.clear_all()
  end)

  after_each(function()
    cache.clear_all()
    helpers.cleanup_buffers()
  end)

  describe("plugin setup", function()
    it("sets up without error", function()
      local success = pcall(metrics.setup, {})
      assert.is_true(success)
    end)

    it("accepts configuration options", function()
      local success = pcall(metrics.setup, {
        features = {
          basic = true,
        },
      })
      assert.is_true(success)
    end)

    it("validates dependencies", function()
      metrics.setup()

      local has_pandoc = vim.fn.executable("pandoc") == 1
      -- Setup should check for Pandoc
      assert.is_boolean(has_pandoc)
    end)
  end)

  describe("full workflow: basic metrics", function()
    it("buffer → metrics → cache → display", function()
      helpers.skip_without_pandoc()

      -- Create buffer
      local bufnr = helpers.create_test_buffer(helpers.test_documents.complex)

      -- Get basic metrics
      local basic = require("writing-metrics.basic")
      local metrics_received = false
      local result_data = nil

      basic.get_accurate_count(bufnr, function(data)
        metrics_received = true
        result_data = data
      end)

      -- Wait for async
      local success = helpers.wait_for_async(function()
        return metrics_received
      end, 3000)

      assert.is_true(success)
      helpers.assert_metrics_structure(result_data, "basic")

      -- Check cache
      local cached = cache.get_basic(bufnr)
      assert.is_not_nil(cached)

      -- Display should work
      local display_success = pcall(basic.show_comparison, bufnr)
      assert.is_true(display_success)
    end)
  end)

  describe("full workflow: full metrics", function()
    it("buffer → full metrics → cache → report", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.complex)

      -- Get full metrics
      local full = require("writing-metrics.full")
      local metrics_received = false
      local result_data = nil

      full.get_full_metrics(bufnr, function(ok, data)
        if ok then
          metrics_received = true
          result_data = data
        end
      end)

      local success = helpers.wait_for_async(function()
        return metrics_received
      end, 5000)

      assert.is_true(success)
      helpers.assert_metrics_structure(result_data, "full")

      -- Show report
      local report_success = pcall(full.show_report, bufnr)
      assert.is_true(report_success)
    end)
  end)

  describe("cache persistence", function()
    it("metrics persist across multiple calls", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local basic = require("writing-metrics.basic")

      -- First call
      local first_done = false
      basic.get_accurate_count(bufnr, function()
        first_done = true
      end)

      helpers.wait_for_async(function()
        return first_done
      end, 3000)

      -- Second call uses cache
      local second_done = false
      local start_time = vim.uv.hrtime()

      basic.get_accurate_count(bufnr, function()
        second_done = true
      end)

      helpers.wait_for_async(function()
        return second_done
      end, 100)

      local elapsed = (vim.uv.hrtime() - start_time) / 1e6

      assert.is_true(second_done)
      assert.is_true(elapsed < 50, "Cached call should be instant")
    end)

    it("cache invalidates on buffer modification", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local basic = require("writing-metrics.basic")

      -- Get metrics
      local first_done = false
      basic.get_accurate_count(bufnr, function()
        first_done = true
      end)

      helpers.wait_for_async(function()
        return first_done
      end, 3000)

      -- Modify buffer
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Modified text" })

      -- Cache should now be marked stale (soft-stale design: data preserved
      -- so statusline can show last-known-good while a fresh count computes).
      cache.invalidate(bufnr)
      local entry, stale = cache.get_basic(bufnr)
      assert.is_not_nil(entry, "cached entry should still be present after invalidate")
      assert.is_true(stale, "cached entry should be marked stale after invalidate")
    end)
  end)

  describe("command registration", function()
    it("registers WordCount command", function()
      metrics.setup()

      local exists = vim.fn.exists(":WordCount") == 2
      assert.is_true(exists)
    end)

    it("registers ReadabilityReport command", function()
      metrics.setup()

      local exists = vim.fn.exists(":ReadabilityReport") == 2
      assert.is_true(exists)
    end)

    it("registers WritingMetricsToggle command", function()
      metrics.setup()

      local exists = vim.fn.exists(":WritingMetricsToggle") == 2
      assert.is_true(exists)
    end)

    it("registers legacy commands when enabled", function()
      metrics.setup({ commands = { enable_legacy = true } })

      local commands = {
        "AccurateWordCount",
        "ToggleWordCountMode",
      }

      for _, cmd in ipairs(commands) do
        local exists = vim.fn.exists(":" .. cmd) == 2
        assert.is_true(exists, "Command :" .. cmd .. " not found")
      end
    end)
  end)

  describe("error handling", function()
    it("handles Pandoc not installed gracefully", function()
      if helpers.has_pandoc() then
        pending("Pandoc is installed, cannot test fallback")
      end

      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local basic = require("writing-metrics.basic")

      -- Should not crash
      local success = pcall(basic.get_accurate_count, bufnr, function() end)
      assert.is_true(success)
    end)

    it("handles invalid buffer gracefully", function()
      local basic = require("writing-metrics.basic")

      local success = pcall(basic.get_fast_count, -1)
      assert.is_true(success)
    end)

    it("handles empty callback", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local basic = require("writing-metrics.basic")

      -- Should not crash with nil callback
      local success = pcall(basic.get_accurate_count, bufnr, nil)
      assert.is_true(success)
    end)
  end)

  describe("get_metrics - cache stale handling", function()
    it("recomputes after content change instead of returning stale data", function()
      helpers.skip_without_pandoc()

      local init = require("writing-metrics")
      local cache_mod = require("writing-metrics.cache")

      local bufnr = helpers.create_test_buffer("Two words.")
      local first_result, second_result
      local done1, done2 = false, false

      -- First call: populates cache.
      init.get_metrics(bufnr, "basic", function(success, data)
        first_result = data
        done1 = true
      end)
      helpers.wait_for_async(function() return done1 end, 5000)
      assert.equals(2, first_result.words)

      -- Mark cache stale (simulates TextChanged).
      cache_mod.invalidate(bufnr)

      -- Replace buffer content with longer text.
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Four words here now actually five words." })

      -- Second call: must NOT return cached "Two words" data.
      init.get_metrics(bufnr, "basic", function(success, data)
        second_result = data
        done2 = true
      end)
      helpers.wait_for_async(function() return done2 end, 5000)

      assert.is_true(
        second_result.words > 2,
        "got " .. tostring(second_result.words) .. " words; cache returned stale data"
      )
    end)
  end)

  describe("performance", function()
    it("fast count is instant", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.complex)
      local basic = require("writing-metrics.basic")

      local start_time = vim.uv.hrtime()
      basic.get_fast_count(bufnr)
      local elapsed = (vim.uv.hrtime() - start_time) / 1e6

      -- Should be under 10ms
      assert.is_true(elapsed < 10, "Fast count should be instant")
    end)

    it("handles large documents", function()
      helpers.skip_without_pandoc()

      -- Create large document (1000 lines)
      local large_text = string.rep(helpers.test_documents.complex .. "\n\n", 50)
      local bufnr = helpers.create_test_buffer(large_text)

      local basic = require("writing-metrics.basic")
      local done = false

      basic.get_accurate_count(bufnr, function()
        done = true
      end)

      -- Should complete within reasonable time
      local success = helpers.wait_for_async(function()
        return done
      end, 10000)

      assert.is_true(success, "Should handle large documents")
    end)
  end)

  describe("parse_basic_output - input validation", function()
    local utils = require("writing-metrics.utils")

    it("returns nil + error for non-numeric tokens", function()
      -- A line with 6 tokens but one is non-numeric.
      local result, err = utils.parse_basic_output("1247 7892 65 42 NaN 6.33")
      assert.is_nil(result)
      assert.is_string(err)
      assert.is_true(
        err:lower():find("numeric") ~= nil or err:lower():find("invalid") ~= nil,
        "error should mention non-numeric: " .. tostring(err)
      )
    end)

    it("parses a valid 6-value line", function()
      local result, err = utils.parse_basic_output("1247 7892 65 42 19.18 6.33")
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.equals(1247, result.words)
      assert.equals(6.33, result.avg_word_len)
    end)
  end)
end)
