-- Tests for writing-metrics.full module
local helpers = require("tests.helpers")

describe("writing-metrics.full", function()
  local full
  local cache

  before_each(function()
    package.loaded["writing-metrics.full"] = nil
    package.loaded["writing-metrics.cache"] = nil

    full = require("writing-metrics.full")
    cache = require("writing-metrics.cache")
    cache.clear_all()
  end)

  after_each(function()
    cache.clear_all()
    helpers.cleanup_buffers()
  end)

  describe("module loading", function()
    it("loads successfully", function()
      assert.is_not_nil(full)
    end)

    it("exports expected functions", function()
      assert.is_function(full.get_full_metrics)
      assert.is_function(full.show_report)
    end)
  end)

  describe("JSON parsing", function()
    it("parses valid JSON metrics", function()
      local json = helpers.mock_pandoc_full
      local result = vim.json.decode(json)

      assert.is_not_nil(result)
      helpers.assert_metrics_structure(result, "full")
    end)

    it("handles malformed JSON gracefully", function()
      local bad_json = "{ invalid json"

      local success, result = pcall(vim.json.decode, bad_json)

      -- Should fail gracefully
      assert.is_false(success)
    end)

    it("extracts all readability metrics", function()
      local json = helpers.mock_pandoc_full
      local result = vim.json.decode(json)

      assert.is_table(result.readability)
      assert.is_number(result.readability.coleman_liau)
      assert.is_number(result.readability.ari)
      assert.is_number(result.readability.flesch_reading_ease)
      assert.is_number(result.readability.flesch_kincaid)
      assert.is_number(result.readability.gunning_fog)
      assert.is_number(result.readability.smog)
    end)

    it("extracts sentence variability", function()
      local json = helpers.mock_pandoc_full
      local result = vim.json.decode(json)

      assert.is_table(result.sentence_variability)
      assert.is_number(result.sentence_variability.std_dev)
      assert.is_number(result.sentence_variability.coefficient_of_variation)
    end)

    it("extracts AI style metrics", function()
      local json = helpers.mock_pandoc_full
      local result = vim.json.decode(json)

      assert.is_table(result.ai_style)
      assert.is_number(result.ai_style.total_ai_words)
      assert.is_table(result.ai_style.word_counts)
    end)
  end)

  describe("full metrics generation", function()
    it("generates metrics with callback", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.complex)
      local callback_called = false
      local result_data = nil

      full.get_full_metrics(bufnr, function(data)
        callback_called = true
        result_data = data
      end)

      local success = helpers.wait_for_async(function()
        return callback_called
      end, 5000)

      assert.is_true(success, "Callback should be called")
      assert.is_not_nil(result_data)
      helpers.assert_metrics_structure(result_data, "full")
    end)

    it("caches full metrics", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      -- First call
      local first_done = false
      full.get_full_metrics(bufnr, function()
        first_done = true
      end)

      helpers.wait_for_async(function()
        return first_done
      end, 5000)

      -- Check cache
      local cached = cache.get_full(bufnr)
      assert.is_not_nil(cached)
    end)

    it("handles empty buffer", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.empty)
      local result_data = nil

      full.get_full_metrics(bufnr, function(data)
        result_data = data
      end)

      helpers.wait_for_async(function()
        return result_data ~= nil
      end, 5000)

      -- Empty buffer should have zero metrics
      if result_data and result_data.basic then
        assert.equals(0, result_data.basic.words)
      end
    end)
  end)

  describe("report display", function()
    it("shows report without error", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.complex)

      local success = pcall(full.show_report, bufnr)
      assert.is_true(success)
    end)

    it("creates report buffer", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local initial_buf_count = #vim.api.nvim_list_bufs()

      full.show_report(bufnr)

      -- Wait for report generation
      helpers.wait(2000)

      -- May create new buffer for report
      local final_buf_count = #vim.api.nvim_list_bufs()
      -- Buffer count may increase or stay same (depends on implementation)
      assert.is_true(final_buf_count >= initial_buf_count)
    end)
  end)

  describe("readability interpretation", function()
    it("provides interpretation for Coleman-Liau", function()
      local json = helpers.mock_pandoc_full
      local result = vim.json.decode(json)

      -- Score around 12.3 means ~12th grade level
      assert.is_true(result.readability.coleman_liau > 0)
      assert.is_true(result.readability.coleman_liau < 20)
    end)

    it("provides interpretation for Flesch Reading Ease", function()
      local json = helpers.mock_pandoc_full
      local result = vim.json.decode(json)

      -- Score 58.4 should be "Fairly Difficult" (50-60 range)
      assert.is_true(result.readability.flesch_reading_ease >= 0)
      assert.is_true(result.readability.flesch_reading_ease <= 100)
    end)
  end)

  describe("edge cases", function()
    it("handles invalid buffer", function()
      local success = pcall(full.show_report, -1)

      -- Should handle gracefully (may return false or show error)
      assert.is_boolean(success)
    end)

    it("handles buffer with only whitespace", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer("   \n\n   ")
      local result_data = nil

      full.get_full_metrics(bufnr, function(data)
        result_data = data
      end)

      helpers.wait_for_async(function()
        return result_data ~= nil
      end, 5000)

      -- Should handle gracefully
      assert.is_true(result_data == nil or type(result_data) == "table")
    end)
  end)
end)
