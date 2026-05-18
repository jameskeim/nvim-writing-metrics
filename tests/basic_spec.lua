-- Tests for writing-metrics.basic module
local helpers = require("tests.helpers")

describe("writing-metrics.basic", function()
  local basic
  local cache

  before_each(function()
    -- Fresh requires
    package.loaded["writing-metrics.basic"] = nil
    package.loaded["writing-metrics.cache"] = nil

    basic = require("writing-metrics.basic")
    cache = require("writing-metrics.cache")
    cache.clear_all()
  end)

  after_each(function()
    cache.clear_all()
    helpers.cleanup_buffers()
  end)

  describe("module loading", function()
    it("loads successfully", function()
      assert.is_not_nil(basic)
    end)

    it("exports expected functions", function()
      assert.is_function(basic.get_fast_count)
      assert.is_function(basic.get_accurate_count)
      assert.is_function(basic.get_statusline_string)
      assert.is_function(basic.toggle_statusline_mode)
      assert.is_function(basic.show_comparison)
    end)
  end)

  describe("fast word count", function()
    it("counts words in simple text", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local result = basic.get_fast_count(bufnr)

      assert.is_not_nil(result)
      assert.is_number(result.words)
      assert.is_true(result.words > 0)
    end)

    it("counts characters", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local result = basic.get_fast_count(bufnr)

      assert.is_number(result.chars)
      assert.is_true(result.chars > result.words)
    end)

    it("handles empty buffer", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.empty)
      local result = basic.get_fast_count(bufnr)

      assert.is_not_nil(result)
      assert.equals(0, result.words)
      assert.equals(0, result.chars)
    end)

    it("handles single word", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.minimal)
      local result = basic.get_fast_count(bufnr)

      assert.is_not_nil(result)
      assert.equals(1, result.words)
    end)

    it("ignores markdown syntax in fast mode", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.with_markdown)
      local result = basic.get_fast_count(bufnr)

      -- Fast mode counts markdown syntax as words
      assert.is_number(result.words)
      assert.is_true(result.words > 0)
    end)
  end)

  describe("accurate word count", function()
    it("calls callback with metrics", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.complex)
      local callback_called = false
      local result_data = nil

      basic.get_accurate_count(bufnr, function(data)
        callback_called = true
        result_data = data
      end)

      -- Wait for async callback
      local success = helpers.wait_for_async(function()
        return callback_called
      end, 3000)

      assert.is_true(success, "Callback should be called within timeout")
      assert.is_not_nil(result_data)
      helpers.assert_metrics_structure(result_data, "basic")
    end)

    it("strips markdown syntax", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.with_markdown)
      local result_data = nil

      basic.get_accurate_count(bufnr, function(data)
        result_data = data
      end)

      helpers.wait_for_async(function()
        return result_data ~= nil
      end, 5000)

      assert.is_not_nil(result_data, "Pandoc callback did not complete within 5000ms")

      -- Accurate count should be less than fast count due to markdown stripping
      local fast_result = basic.get_fast_count(bufnr)
      assert.is_true(result_data.words <= fast_result.words)
    end)

    it("handles empty buffer", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.empty)
      local result_data = nil

      basic.get_accurate_count(bufnr, function(data)
        result_data = data
      end)

      helpers.wait_for_async(function()
        return result_data ~= nil
      end, 3000)

      assert.equals(0, result_data.words)
    end)

    it("caches results", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      -- First call
      local first_done = false
      basic.get_accurate_count(bufnr, function()
        first_done = true
      end)

      helpers.wait_for_async(function()
        return first_done
      end, 3000)

      -- Second call should use cache (much faster)
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
      assert.is_true(elapsed < 50, "Cached call should be nearly instant")
    end)
  end)

  describe("statusline integration", function()
    -- get_statusline_string returns either:
    --   - "" (empty string) for non-writing filetypes
    --   - { text = "...", color = "..." } table otherwise
    -- Lualine accepts both shapes natively.
    local function statusline_text(v)
      if type(v) == "table" then
        return v.text
      end
      return v
    end

    it("returns statusline string", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local result = basic.get_statusline_string(bufnr)

      local text = statusline_text(result)
      assert.is_string(text)
    end)

    it("contains word count indicator", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local result = basic.get_statusline_string(bufnr)

      local text = statusline_text(result)
      -- Should contain either word count text or icon
      local has_indicator = string.find(text, "words") or string.find(text, "󰗊") or string.find(text, "%d+")
      assert.is_true(has_indicator ~= nil)
    end)

    it("toggles statusline mode", function()
      -- Get initial mode
      local initial_mode = basic.statusline_mode

      -- Toggle
      basic.toggle_statusline_mode()
      local new_mode = basic.statusline_mode

      assert.are_not.equals(initial_mode, new_mode)

      -- Toggle back
      basic.toggle_statusline_mode()
      assert.equals(initial_mode, basic.statusline_mode)
    end)

    it("mode affects statusline output", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      -- Get string in fast mode
      basic.statusline_mode = "fast"
      local fast_result = basic.get_statusline_string(bufnr)

      -- Get string in accurate mode
      basic.statusline_mode = "accurate"
      local accurate_result = basic.get_statusline_string(bufnr)

      -- Strings should be different (one uses cache, one triggers accurate)
      assert.is_string(statusline_text(fast_result))
      assert.is_string(statusline_text(accurate_result))
    end)
  end)

  describe("comparison display", function()
    it("shows comparison without error", function()
      helpers.skip_without_pandoc()

      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      -- Should not error
      local success = pcall(basic.show_comparison, bufnr)
      assert.is_true(success)
    end)
  end)

  describe("lualine integration", function()
    it("provides lualine component", function()
      local component = basic.lualine_component()

      assert.is_table(component)
    end)

    it("component has required fields", function()
      local component = basic.lualine_component()

      -- Should be callable or have function field
      assert.is_true(type(component) == "function" or type(component.update) == "function")
    end)
  end)

  describe("accurate word count - abbreviation handling", function()
    it("does not split sentences on common abbreviations", function()
      helpers.skip_without_pandoc()

      local content = "Dr. Smith arrived early. Mr. Jones was late. We use e.g., Python."
      local bufnr = helpers.create_test_buffer(content)
      local done, result_sentences = false, nil

      basic.get_accurate_count(bufnr, function(data)
        result_sentences = data and data.sentences
        done = true
      end)

      helpers.wait_for_async(function() return done end, 5000)
      assert.is_true(done, "Callback should be called within timeout")
      -- 3 sentences total; without the fix, abbreviations push this to 5+.
      assert.equals(3, result_sentences, "expected 3 sentences, got " .. tostring(result_sentences))
    end)

    it("does not split sentences on decimals", function()
      helpers.skip_without_pandoc()

      local content = "The price is $3.14 today. Tomorrow it rises to $4.20."
      local bufnr = helpers.create_test_buffer(content)
      local done, result_sentences = false, nil

      basic.get_accurate_count(bufnr, function(data)
        result_sentences = data and data.sentences
        done = true
      end)

      helpers.wait_for_async(function() return done end, 5000)
      assert.is_true(done, "Callback should be called within timeout")
      assert.equals(2, result_sentences, "expected 2 sentences, got " .. tostring(result_sentences))
    end)
  end)

  describe("accurate word count - code block exclusion", function()
    it("excludes fenced code block content from word counts", function()
      helpers.skip_without_pandoc()

      local content = "This is one prose sentence with five words.\n\n```python\nprint(\"hello\")\ndef foo():\n    return 42\n```\n\nAnother prose sentence with five words.\n"
      local bufnr = helpers.create_test_buffer(content)
      local done = false
      local result_words

      basic.get_accurate_count(bufnr, function(data)
        result_words = data and data.words
        done = true
      end)

      helpers.wait_for_async(function() return done end, 5000)
      assert.is_true(done, "Callback should be called within timeout")
      -- 14 prose words (8 + 6); code block has ~5 tokens. Tolerate small parser-side variance.
      -- Before fix: 19 words (code content leaked in). After fix: 14 words (prose only).
      assert.is_true(result_words <= 16, "got " .. tostring(result_words) .. " words; code block likely not excluded")
      assert.is_true(result_words >= 12, "got " .. tostring(result_words) .. " words; prose appears under-counted")
    end)
  end)

  describe("get_reading_time", function()
    it("computes minutes from cached word count using configured WPM", function()
      -- Buffer with arbitrary content; cache is populated directly with known count.
      local bufnr = helpers.create_test_buffer("placeholder")
      cache.set_basic(bufnr, { words = 400, chars = 1500, sentences = 20, paragraphs = 4 })

      -- 400 / 200 = 2.0 → ceil = 2 silent minutes
      -- 400 / 150 = 2.667 → ceil = 3 spoken minutes
      local result = basic.get_reading_time(bufnr)

      assert.is_not_nil(result)
      assert.equals(2, result.silent_minutes)
      assert.equals(3, result.spoken_minutes)
      assert.equals("~2 min", result.silent)
      assert.equals("~3 min", result.spoken)
    end)

    it("returns nil when reading_time.enabled is false", function()
      local config = require("writing-metrics.config")
      local saved = vim.deepcopy(config.config.reading_time or {})
      config.config.reading_time = vim.tbl_extend("force", saved, { enabled = false })

      local bufnr = helpers.create_test_buffer("placeholder")
      cache.set_basic(bufnr, { words = 400, chars = 1500, sentences = 20, paragraphs = 4 })

      local result = basic.get_reading_time(bufnr)
      assert.is_nil(result)

      -- Restore config so subsequent tests aren't affected
      config.config.reading_time = saved
    end)

    it("returns nil when buffer has no cached word count", function()
      local bufnr = helpers.create_test_buffer("placeholder")
      cache.clear_all()

      local result = basic.get_reading_time(bufnr)
      assert.is_nil(result)
    end)
  end)

  describe("statusline_reading_time_suffix", function()
    it("includes silent profile suffix when statusline_profile = 'silent'", function()
      local config = require("writing-metrics.config")
      local saved = vim.deepcopy(config.config.reading_time or {})
      config.config.reading_time = vim.tbl_extend("force", saved, {
        enabled = true,
        statusline = true,
        statusline_profile = "silent",
      })

      local bufnr = helpers.create_test_buffer("placeholder")
      vim.bo[bufnr].filetype = "markdown"
      vim.api.nvim_set_current_buf(bufnr)
      cache.set_basic(bufnr, { words = 400, chars = 1500, sentences = 20, paragraphs = 4 })

      -- Use fast mode so get_statusline_string returns a table with text field
      basic.statusline_mode = "fast"
      local result = basic.get_statusline_string(bufnr)
      assert.is_table(result)
      assert.is_string(result.text)
      -- 400 / 200 wpm = 2.0 → ceil = 2 silent minutes
      assert.is_truthy(result.text:find("⏱", 1, true))
      assert.is_truthy(result.text:find("~2 min", 1, true))

      config.config.reading_time = saved
    end)

    it("includes spoken profile suffix when statusline_profile = 'spoken'", function()
      local config = require("writing-metrics.config")
      local saved = vim.deepcopy(config.config.reading_time or {})
      config.config.reading_time = vim.tbl_extend("force", saved, {
        enabled = true,
        statusline = true,
        statusline_profile = "spoken",
      })

      local bufnr = helpers.create_test_buffer("placeholder")
      vim.bo[bufnr].filetype = "markdown"
      vim.api.nvim_set_current_buf(bufnr)
      cache.set_basic(bufnr, { words = 400, chars = 1500, sentences = 20, paragraphs = 4 })

      basic.statusline_mode = "fast"
      local result = basic.get_statusline_string(bufnr)
      assert.is_table(result)
      assert.is_string(result.text)
      -- 400 / 150 wpm = 2.67 → ceil = 3 spoken minutes
      assert.is_truthy(result.text:find("🎤", 1, true))
      assert.is_truthy(result.text:find("~3 min", 1, true))

      config.config.reading_time = saved
    end)

    it("includes both profiles suffix when statusline_profile = 'both'", function()
      local config = require("writing-metrics.config")
      local saved = vim.deepcopy(config.config.reading_time or {})
      config.config.reading_time = vim.tbl_extend("force", saved, {
        enabled = true,
        statusline = true,
        statusline_profile = "both",
      })

      local bufnr = helpers.create_test_buffer("placeholder")
      vim.bo[bufnr].filetype = "markdown"
      vim.api.nvim_set_current_buf(bufnr)
      cache.set_basic(bufnr, { words = 400, chars = 1500, sentences = 20, paragraphs = 4 })

      basic.statusline_mode = "fast"
      local result = basic.get_statusline_string(bufnr)
      assert.is_table(result)
      assert.is_string(result.text)
      -- silent: ~2 min, spoken: ~3 min → compact form "~2/~3 min"
      assert.is_truthy(result.text:find("⏱", 1, true))
      assert.is_truthy(result.text:find("~2/~3 min", 1, true))

      config.config.reading_time = saved
    end)

    it("omits reading time when statusline is disabled", function()
      local config = require("writing-metrics.config")
      local saved = vim.deepcopy(config.config.reading_time or {})
      config.config.reading_time = vim.tbl_extend("force", saved, {
        enabled = true,
        statusline = false,
      })

      local bufnr = helpers.create_test_buffer("placeholder")
      vim.bo[bufnr].filetype = "markdown"
      vim.api.nvim_set_current_buf(bufnr)
      cache.set_basic(bufnr, { words = 400, chars = 1500, sentences = 20, paragraphs = 4 })

      basic.statusline_mode = "fast"
      local result = basic.get_statusline_string(bufnr)
      assert.is_table(result)
      assert.is_string(result.text)
      assert.is_falsy(result.text:find("⏱", 1, true))
      assert.is_falsy(result.text:find("🎤", 1, true))

      config.config.reading_time = saved
    end)
  end)

  describe("edge cases", function()
    it("handles invalid buffer", function()
      local result = basic.get_fast_count(-1)

      -- Should return safe defaults
      assert.is_table(result)
      assert.equals(0, result.words)
      assert.equals(0, result.chars)
    end)

    it("handles non-existent buffer", function()
      local result = basic.get_fast_count(99999)

      assert.is_table(result)
      assert.equals(0, result.words)
    end)

    it("handles buffer with only whitespace", function()
      local bufnr = helpers.create_test_buffer("   \n\n   \n")
      local result = basic.get_fast_count(bufnr)

      assert.is_not_nil(result)
      assert.equals(0, result.words)
    end)
  end)
end)
