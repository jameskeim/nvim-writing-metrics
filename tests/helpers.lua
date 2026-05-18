-- Test helpers and utilities
local M = {}

-- Create test buffer with content
M.create_test_buffer = function(content)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(content, "\n")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
  return bufnr
end

-- Sample test documents
M.test_documents = {
  simple = "This is a simple test. It has two sentences.",

  complex = [[# Test Document

This is a more complex test document with multiple paragraphs.

## Section 1

The study was conducted over six months. Data were collected from three sources.
Results were analyzed using standard methods.

This paragraph uses nominalizations like implementation and investigation.

## Section 2

We need to optimize our approach. The landscape is changing rapidly.
Let's delve into the details and unlock the potential.]],

  minimal = "Word",

  empty = "",

  with_markdown = [[# Title

**Bold text** and *italic text*.

- List item 1
- List item 2

Code: `inline code`

> Quote block

Paragraph with [link](http://example.com).]],
}

-- Wait for async operations with timeout
M.wait_for_async = function(condition_fn, timeout_ms)
  timeout_ms = timeout_ms or 1000
  local start = vim.uv.hrtime()

  while true do
    if condition_fn() then
      return true
    end

    local elapsed = (vim.uv.hrtime() - start) / 1e6
    if elapsed > timeout_ms then
      return false
    end

    vim.wait(10)
  end
end

-- Simple wait
M.wait = function(ms)
  vim.wait(ms, function() return false end)
end

-- Assert metrics structure
M.assert_metrics_structure = function(metrics, mode)
  assert.is_not_nil(metrics, "Metrics should not be nil")
  assert.is_table(metrics, "Metrics should be a table")

  if mode == "basic" then
    assert.is_number(metrics.words, "words should be a number")
    assert.is_number(metrics.chars, "chars should be a number")
    assert.is_number(metrics.sentences, "sentences should be a number")
    assert.is_number(metrics.paragraphs, "paragraphs should be a number")

    -- All should be non-negative
    assert.is_true(metrics.words >= 0, "words should be non-negative")
    assert.is_true(metrics.chars >= 0, "chars should be non-negative")
  elseif mode == "full" then
    assert.is_table(metrics.basic, "basic should be a table")
    assert.is_table(metrics.readability, "readability should be a table")

    -- Check basic structure
    assert.is_number(metrics.basic.words)
    assert.is_number(metrics.basic.characters)

    -- Check readability structure
    assert.is_number(metrics.readability.coleman_liau)
    assert.is_number(metrics.readability.automated_readability)
  end
end

-- Mock Pandoc output for basic mode (space-separated values)
M.mock_pandoc_basic = "100 500 5 2"

-- Mock Pandoc output for full mode (JSON)
M.mock_pandoc_full = [[{
  "basic": {
    "words": 100,
    "chars": 500,
    "characters": 500,
    "sentences": 5,
    "paragraphs": 2,
    "words_per_sentence": 20.0,
    "words_per_paragraph": 50.0,
    "avg_words_per_sentence": 20.0,
    "avg_words_per_paragraph": 50.0
  },
  "readability": {
    "coleman_liau": 12.3,
    "ari": 11.8,
    "automated_readability": 11.8,
    "flesch_reading_ease": 58.4,
    "flesch_kincaid": 10.2,
    "flesch_kincaid_grade": 10.2,
    "gunning_fog": 13.5,
    "smog": 11.9
  },
  "sentence_variability": {
    "std_dev": 5.2,
    "coefficient_of_variation": 26.0,
    "min_length": 8,
    "max_length": 28,
    "range": 20,
    "monotonous_sequences": []
  },
  "ai_style": {
    "total_ai_words": 3,
    "ai_words_per_100": 3.0,
    "word_counts": {
      "delve": 1,
      "landscape": 1,
      "optimize": 1
    }
  }
}]]

-- Check if Pandoc is available
M.has_pandoc = function()
  return vim.fn.executable("pandoc") == 1
end

-- Skip test if Pandoc not available
M.skip_without_pandoc = function()
  if not M.has_pandoc() then
    pending("Pandoc not installed")
  end
end

-- Clean up test buffers
M.cleanup_buffers = function()
  local buffers = vim.api.nvim_list_bufs()
  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and not vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
end

return M
