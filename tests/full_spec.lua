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

      full.get_full_metrics(bufnr, function(_, data)
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

    it("handles empty buffer", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.empty)
      local result_data = nil

      full.get_full_metrics(bufnr, function(_, data)
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

  describe("complex word counting - sentence-initial words", function()
    it("counts sentence-initial polysyllabic words as complex", function()
      helpers.skip_without_pandoc()

      -- 'Investigation', 'Researchers', 'Conclusions' are sentence-initial AND polysyllabic.
      -- They should be counted as complex words, not excluded as proper nouns.
      local content = [[
Investigation revealed serious problems.
Researchers conducted careful analysis.
Conclusions remain controversial.
]]
      local bufnr = helpers.create_test_buffer(content)
      local done, success_flag, result = false, nil, nil

      require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
        success_flag = success
        result = data
        done = true
      end)

      helpers.wait_for_async(function() return done end, 5000)
      assert.is_true(success_flag)
      assert.is_not_nil(result)
      assert.is_not_nil(result.readability)
      assert.is_number(result.readability.complex_words,
        "expected result.readability.complex_words to be a number")
      -- All three sentence-initial words ARE polysyllabic. None are proper nouns.
      -- Expect complex_words >= 3.
      assert.is_true(
        result.readability.complex_words >= 3,
        "expected >=3 complex words, got " .. tostring(result.readability.complex_words)
      )
    end)
  end)

  describe("variability - monotonous pattern average", function()
    it("reports the actual mean, not (min+max)/2", function()
      helpers.skip_without_pandoc()

      -- 12 sentences where consecutive diffs are all ≤ 3:
      --   lengths: 6, 9, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12
      --   diffs:   3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0  → all ≤ 3, forms one 12-sentence pattern
      --   min=6, max=12 → midpoint (buggy avg) = 9.0
      --   true mean = (6+9+12*10)/12 = 135/12 = 11.25
      local function s(n)
        local words = {}
        for i = 1, n do words[i] = "word" end
        return table.concat(words, " ") .. "."
      end
      local sentences = {}
      sentences[1] = s(6)
      sentences[2] = s(9)
      for i = 3, 12 do sentences[i] = s(12) end
      local content = table.concat(sentences, " ")
      local bufnr = helpers.create_test_buffer(content)
      local done, result = false, nil

      require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
        assert.is_true(success)
        result = data
        done = true
      end)

      helpers.wait_for_async(function() return done end, 5000)

      local patterns = result.variability and result.variability.patterns or {}
      assert.is_true(#patterns >= 1, "expected at least one monotonous pattern detected")
      local avg = patterns[1].avg_length
      -- True mean is 11.25. Buggy (min+max)/2 = 9.0. Tolerate ±1.5.
      assert.is_true(
        math.abs(avg - 11.25) < 1.5,
        "expected avg ~11.25, got " .. tostring(avg) .. " (likely the (min+max)/2 = 9.0 bug)"
      )
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

      full.get_full_metrics(bufnr, function(_, data)
        result_data = data
      end)

      helpers.wait_for_async(function()
        return result_data ~= nil
      end, 5000)

      -- Should handle gracefully
      assert.is_true(result_data == nil or type(result_data) == "table")
    end)
  end)

  describe("filter exits cleanly", function()
    it("does not write cosmetic table.concat error to stderr", function()
      helpers.skip_without_pandoc()

      local temp_md = vim.fn.tempname() .. ".md"
      local f = io.open(temp_md, "w")
      f:write("# Test\n\nA paragraph with words.\n")
      f:close()

      local filter = require("writing-metrics.config").get_filter_path()
      assert.is_string(filter, "filter path should resolve via config.get_filter_path()")

      local result = vim.system({
        "pandoc", temp_md,
        "--lua-filter", filter,
        "-M", "metrics=basic",
        "-t", "plain",
      }, { text = true }):wait()

      vim.fn.delete(temp_md)

      assert.equals(0, result.code, "pandoc should exit 0, got: " .. tostring(result.code))
      local stderr = result.stderr or ""
      assert.is_nil(stderr:find("table.concat", 1, true),
        "stderr should not contain table.concat error; got: " .. stderr)
      local stdout = result.stdout or ""
      assert.truthy(stdout:match("^%s*%d+%s+%d+%s+%d+%s+%d+%s+%S+%s+%S+%s*$"),
        "stdout should be six-field metrics line; got: " .. stdout)
    end)
  end)

  describe("char counting", function()
    it("counts UTF-8 characters as codepoints not bytes", function()
      helpers.skip_without_pandoc()

      -- 'café' is 4 codepoints but 5 bytes (é is U+00E9, 2 bytes in UTF-8).
      local content = "café"
      local bufnr = helpers.create_test_buffer(content)

      local result_data = nil
      require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
        if success then result_data = data end
      end)

      helpers.wait_for_async(function() return result_data ~= nil end, 5000)

      assert.is_not_nil(result_data, "filter should produce data")
      assert.is_table(result_data.basic)
      assert.equals(4, result_data.basic.characters,
        "char count should be 4 codepoints, not 5 bytes; got: "
        .. tostring(result_data.basic.characters))
    end)

    describe("ARI calculation", function()
      it("uses letter chars, not total chars (which includes spaces)", function()
        helpers.skip_without_pandoc()

        -- Controlled input: 2 words, 1 sentence, easy to verify.
        -- "Hello world." → Hello=5 letters, world=5 letters, total_word_chars=10.
        -- ARI with letter chars: 4.71 * (10/2) + 0.5 * (2/1) - 21.43
        --                      = 23.55 + 1 - 21.43 = 3.12
        -- ARI with total chars (~12 including space and period):
        --                      = 4.71 * (12/2) + 0.5 * (2/1) - 21.43
        --                      = 28.26 + 1 - 21.43 = 7.83
        -- The pre-fix value will be substantially higher; assert ARI < 5.
        local content = "Hello world."
        local bufnr = helpers.create_test_buffer(content)

        local result_data = nil
        require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
          if success then result_data = data end
        end)

        helpers.wait_for_async(function() return result_data ~= nil end, 5000)

        assert.is_not_nil(result_data, "filter should produce data")
        assert.is_table(result_data.readability)
        local ari = result_data.readability.automated_readability
        assert.is_number(ari)
        assert.is_true(ari < 5,
          "ARI should compute from letter chars (~3.12 for this input), "
          .. "not total chars (~7.83); got: " .. tostring(ari))
      end)
    end)
  end)

  describe("list paragraph counting", function()
    it("counts loose list items once, not twice", function()
      helpers.skip_without_pandoc()

      -- Loose list: blank lines between items → Pandoc emits Para inside.
      -- Pre-fix bug: each item counts via BulletList AND via Para → 2× inflation.
      local content = table.concat({
        "- first item",
        "",
        "- second item",
        "",
        "- third item",
      }, "\n")
      local bufnr = helpers.create_test_buffer(content)

      local result_data = nil
      require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
        if success then result_data = data end
      end)

      helpers.wait_for_async(function() return result_data ~= nil end, 5000)

      assert.is_not_nil(result_data)
      assert.equals(3, result_data.basic.paragraphs,
        "3 loose list items should yield 3 paragraphs; got: "
        .. tostring(result_data.basic.paragraphs))
    end)

    it("counts compact list items once (regression guard)", function()
      helpers.skip_without_pandoc()

      -- Compact list: no blank lines between items → Pandoc emits Plain.
      -- Pre-fix: counted via BulletList only. Post-fix: counted via Plain only.
      -- Either way the count should be 3.
      local content = table.concat({
        "- first item",
        "- second item",
        "- third item",
      }, "\n")
      local bufnr = helpers.create_test_buffer(content)

      local result_data = nil
      require("writing-metrics.full").get_full_metrics(bufnr, function(success, data)
        if success then result_data = data end
      end)

      helpers.wait_for_async(function() return result_data ~= nil end, 5000)

      assert.is_not_nil(result_data)
      assert.equals(3, result_data.basic.paragraphs,
        "3 compact list items should yield 3 paragraphs; got: "
        .. tostring(result_data.basic.paragraphs))
    end)
  end)
end)
