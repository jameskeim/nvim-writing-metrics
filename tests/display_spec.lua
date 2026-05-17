-- Tests for writing-metrics.display module
local helpers = require("tests.helpers")

describe("writing-metrics.display", function()
  local display

  before_each(function()
    package.loaded["writing-metrics.display"] = nil
    display = require("writing-metrics.display")
  end)

  after_each(function()
    helpers.cleanup_buffers()
  end)

  describe("format_vocabulary_section", function()
    it("does not produce nan% or inf% when total_words is 0", function()
      -- Edge case: vocabulary present but total_words is 0.
      -- Could happen if upstream miscounts or with an empty buffer.
      local vocabulary = {
        total_words = 0,
        unique_words = 0,
        ttr = 0,
        most_frequent = {
          { word = "ghost", count = 1 },
          { word = "phantom", count = 2 },
        },
      }

      local lines = display.format_vocabulary_section(vocabulary)
      local rendered = table.concat(lines, "\n")

      assert.is_nil(rendered:lower():find("nan"),
        "rendered output should not contain 'nan'; got: " .. rendered)
      assert.is_nil(rendered:lower():find("inf"),
        "rendered output should not contain 'inf'; got: " .. rendered)
    end)
  end)
end)
