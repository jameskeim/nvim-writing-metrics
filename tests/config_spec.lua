-- Tests for writing-metrics.config module
local helpers = require("tests.helpers")

describe("writing-metrics.config", function()
  local config

  before_each(function()
    -- Fresh require each test
    package.loaded["writing-metrics.config"] = nil
    config = require("writing-metrics.config")
  end)

  after_each(function()
    helpers.cleanup_buffers()
  end)

  describe("module loading", function()
    it("loads successfully", function()
      assert.is_not_nil(config)
    end)

    it("exports expected functions", function()
      assert.is_function(config.setup)
      assert.is_function(config.get)
      assert.is_function(config.validate_dependencies)
      assert.is_function(config.get_filter_path)
    end)
  end)

  describe("default configuration", function()
    it("has valid default settings", function()
      local defaults = config.get()

      assert.is_table(defaults)
      assert.is_table(defaults.cache)
      assert.is_table(defaults.filter)
      assert.is_table(defaults.commands)
    end)

    it("has reasonable cache TTL values", function()
      local defaults = config.get()

      assert.is_number(defaults.cache.basic_ttl)
      assert.is_number(defaults.cache.full_ttl)

      -- Basic should be shorter than full
      assert.is_true(defaults.cache.basic_ttl <= defaults.cache.full_ttl)

      -- Should be in milliseconds (reasonable range)
      assert.is_true(defaults.cache.basic_ttl >= 100)
      assert.is_true(defaults.cache.basic_ttl <= 10000)
    end)

    it("has filter configuration", function()
      local defaults = config.get()

      assert.is_string(defaults.filter.path)
      assert.is_boolean(defaults.filter.auto_detect)
    end)

    it("has command configuration", function()
      local defaults = config.get()

      assert.is_boolean(defaults.commands.enable_legacy)
    end)
  end)

  describe("user configuration", function()
    it("merges user options with defaults", function()
      config.setup({
        cache = {
          basic_ttl = 1000,
        },
      })

      local settings = config.get()

      assert.equals(1000, settings.cache.basic_ttl)
      -- Other defaults should still be present
      assert.is_number(settings.cache.full_ttl)
      assert.is_table(settings.filter)
    end)

    it("preserves nested options not overridden", function()
      config.setup({
        cache = {
          basic_ttl = 999,
        },
      })

      local settings = config.get()

      -- Modified value
      assert.equals(999, settings.cache.basic_ttl)
      -- Unmodified nested value
      assert.is_number(settings.cache.full_ttl)
    end)

    it("allows disabling legacy commands", function()
      config.setup({
        commands = {
          enable_legacy = false,
        },
      })

      local settings = config.get()
      assert.is_false(settings.commands.enable_legacy)
    end)
  end)

  describe("dependency validation", function()
    it("checks for Pandoc", function()
      local result = config.validate_dependencies()
      local has_pandoc = vim.fn.executable("pandoc") == 1

      assert.equals(has_pandoc, result)
    end)

    it("returns boolean", function()
      local result = config.validate_dependencies()
      assert.is_boolean(result)
    end)
  end)

  describe("filter path detection", function()
    it("returns a string path", function()
      local filter_path = config.get_filter_path()
      assert.is_string(filter_path)
    end)

    it("path contains textmetrics.lua", function()
      local filter_path = config.get_filter_path()
      assert.truthy(string.find(filter_path, "textmetrics%.lua"))
    end)

    it("can use custom filter path", function()
      config.setup({
        filter = {
          path = "/custom/path/filter.lua",
          auto_detect = false,
        },
      })

      local filter_path = config.get_filter_path()
      assert.equals("/custom/path/filter.lua", filter_path)
    end)
  end)
end)
