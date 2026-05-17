-- Tests for writing-metrics.cache module
local helpers = require("tests.helpers")

describe("writing-metrics.cache", function()
  local cache

  before_each(function()
    -- Fresh require and clear caches
    package.loaded["writing-metrics.cache"] = nil
    cache = require("writing-metrics.cache")
    cache.clear_all()
  end)

  after_each(function()
    cache.clear_all()
    helpers.cleanup_buffers()
  end)

  describe("module loading", function()
    it("loads successfully", function()
      assert.is_not_nil(cache)
    end)
  end)

  describe("basic metrics cache", function()
    it("stores and retrieves basic metrics", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local data = { words = 100, chars = 500, sentences = 2, paragraphs = 1 }

      cache.set_basic(bufnr, data)
      local retrieved = cache.get_basic(bufnr)

      assert.is_not_nil(retrieved)
      assert.equals(100, retrieved.words)
      assert.equals(500, retrieved.chars)
    end)

    it("returns nil for uncached buffer", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local retrieved = cache.get_basic(bufnr)

      assert.is_nil(retrieved)
    end)

    it("overwrites existing cache", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      cache.set_basic(bufnr, { words = 100 })
      cache.set_basic(bufnr, { words = 200 })

      local retrieved = cache.get_basic(bufnr)
      assert.equals(200, retrieved.words)
    end)
  end)

  describe("cache invalidation", function()
    it("marks entry stale without deleting the data", function()
      -- invalidate() intentionally preserves the cached data so the
      -- statusline can keep showing the last-known counts while an
      -- async recompute is in flight. The mechanism the rest of the
      -- plugin uses to notice the invalidation is content_changed().
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      cache.set_basic(bufnr, { words = 100, chars = 500 })

      cache.invalidate(bufnr)

      local data, stale = cache.get_basic(bufnr)
      assert.is_not_nil(data, "invalidate should preserve last-known data")
      assert.equals(100, data.words)
      assert.is_true(stale, "invalidate should flip the stale flag")
      assert.is_true(cache.content_changed(bufnr),
        "content_changed should report true after invalidate()")
    end)

    it("clears all caches", function()
      local bufnr1 = helpers.create_test_buffer(helpers.test_documents.simple)
      local bufnr2 = helpers.create_test_buffer(helpers.test_documents.minimal)

      cache.set_basic(bufnr1, { words = 100 })
      cache.set_basic(bufnr2, { words = 200 })

      cache.clear_all()

      assert.is_nil(cache.get_basic(bufnr1))
      assert.is_nil(cache.get_basic(bufnr2))
    end)
  end)

  describe("buffer lifecycle", function()
    it("removes cache entries when buffer is deleted, not just marks stale", function()
      cache.setup_autocmds()  -- idempotently wires the autocmds

      local bufnr = helpers.create_test_buffer("Some text.")
      cache.set_basic(bufnr, { words = 2, chars = 10, sentences = 1, paragraphs = 1 })

      -- Sanity: cache has the entry.
      local before = cache.get_basic(bufnr)
      assert.is_not_nil(before)

      -- Delete the buffer; autocmd should fire and remove the cache entry.
      vim.api.nvim_buf_delete(bufnr, { force = true })

      -- After deletion, the entry must be gone (not just marked stale).
      local stats = cache.get_stats()
      assert.equals(0, stats.basic_entries,
        "expected 0 basic_entries after BufDelete, got " .. tostring(stats.basic_entries))
    end)
  end)

  describe("edge cases", function()
    it("handles invalid buffer numbers", function()
      local result = cache.get_basic(-1)
      assert.is_nil(result)
    end)

    it("handles nil data gracefully", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      -- Should not crash
      pcall(cache.set_basic, bufnr, nil)

      local retrieved = cache.get_basic(bufnr)
      -- Either nil or handles gracefully
      assert.is_true(retrieved == nil or type(retrieved) == "table")
    end)
  end)
end)
