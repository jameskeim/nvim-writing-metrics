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

    it("exports expected functions", function()
      assert.is_function(cache.get_basic)
      assert.is_function(cache.set_basic)
      assert.is_function(cache.get_full)
      assert.is_function(cache.set_full)
      assert.is_function(cache.invalidate)
      assert.is_function(cache.clear_all)
      assert.is_function(cache.get_statistics)
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

  describe("full metrics cache", function()
    it("stores and retrieves full metrics", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local data = {
        basic = { words = 100, chars = 500 },
        readability = { coleman_liau = 12.3 },
      }

      cache.set_full(bufnr, data)
      local retrieved = cache.get_full(bufnr)

      assert.is_not_nil(retrieved)
      assert.is_table(retrieved.basic)
      assert.equals(100, retrieved.basic.words)
    end)

    it("extracts basic from full cache", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      local full_data = {
        basic = { words = 100, chars = 500, sentences = 2, paragraphs = 1 },
        readability = { coleman_liau = 12.3 },
      }

      cache.set_full(bufnr, full_data)

      -- Basic cache should be auto-populated
      local basic = cache.get_basic(bufnr)
      assert.is_not_nil(basic)
      assert.equals(100, basic.words)
      assert.equals(500, basic.chars)
    end)
  end)

  describe("TTL expiration", function()
    it("respects custom TTL", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local data = { words = 100, chars = 500 }

      -- Set with 50ms TTL
      cache.set_basic(bufnr, data, 50)

      -- Immediate retrieval should work
      assert.is_not_nil(cache.get_basic(bufnr))

      -- Wait for expiration
      helpers.wait(100)

      -- Should be expired
      assert.is_nil(cache.get_basic(bufnr))
    end)

    it("uses default TTL when not specified", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)
      local data = { words = 100, chars = 500 }

      cache.set_basic(bufnr, data)

      -- Should still be valid after short delay
      helpers.wait(100)
      assert.is_not_nil(cache.get_basic(bufnr))
    end)
  end)

  describe("cache invalidation", function()
    it("invalidates specific buffer cache", function()
      local bufnr1 = helpers.create_test_buffer(helpers.test_documents.simple)
      local bufnr2 = helpers.create_test_buffer(helpers.test_documents.minimal)

      cache.set_basic(bufnr1, { words = 100 })
      cache.set_basic(bufnr2, { words = 200 })

      cache.invalidate(bufnr1)

      assert.is_nil(cache.get_basic(bufnr1))
      assert.is_not_nil(cache.get_basic(bufnr2))
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

    it("invalidates both basic and full cache", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      cache.set_basic(bufnr, { words = 100 })
      cache.set_full(bufnr, { basic = { words = 100 } })

      cache.invalidate(bufnr)

      assert.is_nil(cache.get_basic(bufnr))
      assert.is_nil(cache.get_full(bufnr))
    end)
  end)

  describe("cache statistics", function()
    it("provides statistics", function()
      local stats = cache.get_statistics()

      assert.is_table(stats)
      assert.is_table(stats.basic)
      assert.is_table(stats.full)
    end)

    it("reports cache counts", function()
      local bufnr1 = helpers.create_test_buffer(helpers.test_documents.simple)
      local bufnr2 = helpers.create_test_buffer(helpers.test_documents.minimal)

      cache.set_basic(bufnr1, { words = 100 })
      cache.set_basic(bufnr2, { words = 200 })
      cache.set_full(bufnr1, { basic = { words = 100 } })

      local stats = cache.get_statistics()

      assert.equals(2, stats.basic.count)
      assert.equals(1, stats.full.count)
    end)

    it("reports hits and misses", function()
      local bufnr = helpers.create_test_buffer(helpers.test_documents.simple)

      -- Miss
      cache.get_basic(bufnr)

      -- Set and hit
      cache.set_basic(bufnr, { words = 100 })
      cache.get_basic(bufnr)

      local stats = cache.get_statistics()

      assert.is_number(stats.basic.hits)
      assert.is_number(stats.basic.misses)
      assert.is_true(stats.basic.hits >= 1)
      assert.is_true(stats.basic.misses >= 1)
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
