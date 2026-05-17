-- Tests for writing-metrics init module
local helpers = require("tests.helpers")

describe("writing-metrics init", function()
  after_each(function()
    helpers.cleanup_buffers()
  end)

  describe("setup", function()
    it("resets _G.writing_metrics_reports so :Lazy reload doesn't preserve stale state", function()
      -- Simulate stale state from a previous module load.
      _G.writing_metrics_reports = { ["/some/stale/path.md"] = 9999 }

      -- Re-require and call setup() — what :Lazy reload effectively does.
      package.loaded["writing-metrics"] = nil
      local wm = require("writing-metrics")
      wm.setup({})

      assert.same({}, _G.writing_metrics_reports,
        "setup() should reset the reports table; got: "
        .. vim.inspect(_G.writing_metrics_reports))
    end)
  end)
end)
