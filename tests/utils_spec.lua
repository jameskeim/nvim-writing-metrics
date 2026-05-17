-- Tests for writing-metrics.utils module
local helpers = require("tests.helpers")

describe("writing-metrics.utils", function()
  local utils

  before_each(function()
    package.loaded["writing-metrics.utils"] = nil
    utils = require("writing-metrics.utils")
  end)

  after_each(function()
    helpers.cleanup_buffers()
  end)

  describe("parse_full_output", function()
    it("parses JSON when a Pandoc warning containing { appears before it", function()
      -- Pandoc may emit warnings to the same stream as output. Warnings
      -- can legitimately contain '{', which would confuse a greedy
      -- find("{") strategy.
      local output = table.concat({
        "[WARNING] Some warning with { brace } in it",
        '{"basic": {"words": 5, "characters": 20, "sentences": 1, "paragraphs": 1, "lines": 1}, "readability": {"automated_readability": 0}}',
      }, "\n")

      local result, err = utils.parse_full_output(output)

      assert.is_nil(err, "should parse despite warning; got error: " .. tostring(err))
      assert.is_not_nil(result)
      assert.is_table(result.basic)
      assert.equals(5, result.basic.words)
      assert.equals(20, result.basic.characters)
    end)

    it("returns error for output without any JSON object", function()
      local result, err = utils.parse_full_output("just warnings, no JSON here")
      assert.is_nil(result)
      assert.is_string(err)
    end)

    it("returns error for empty output", function()
      local result, err = utils.parse_full_output("")
      assert.is_nil(result)
      assert.is_string(err)
    end)
  end)
end)
