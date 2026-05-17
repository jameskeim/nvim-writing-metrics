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

  describe("section navigation data", function()
    it("M.SECTIONS has 8 entries with unique keys, icons, and names", function()
      assert.is_table(display.SECTIONS)
      assert.equals(8, #display.SECTIONS)

      local keys, icons, names = {}, {}, {}
      for _, s in ipairs(display.SECTIONS) do
        assert.is_string(s.key, "section needs string key")
        assert.is_string(s.icon, "section needs string icon")
        assert.is_string(s.name, "section needs string name")
        assert.is_string(s.title, "section needs string title")
        assert.is_nil(keys[s.key], "duplicate key: " .. s.key)
        assert.is_nil(icons[s.icon], "duplicate icon: " .. s.icon)
        assert.is_nil(names[s.name], "duplicate name: " .. s.name)
        keys[s.key], icons[s.icon], names[s.name] = true, true, true
      end
    end)

    it("section_heading returns '## <icon> <title>' that matches the keymap pattern", function()
      for _, s in ipairs(display.SECTIONS) do
        local heading = display.section_heading(s.name)
        assert.equals("## " .. s.icon .. " " .. s.title, heading,
          "section_heading(" .. s.name .. ") should produce expected line")
        -- The keymap is /^## <icon><CR>. Verify the heading line matches.
        assert.is_truthy(heading:find("^## " .. s.icon, 1, false),
          "heading should match navigation pattern for key " .. s.key)
      end
    end)

    it("section_heading errors on unknown name", function()
      assert.has.errors(function()
        display.section_heading("nonexistent_section")
      end)
    end)
  end)
end)
