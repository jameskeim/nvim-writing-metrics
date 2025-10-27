-- examples/lazy-nvim-config.lua
-- Configuration examples for lazy.nvim plugin manager

-- ============================================================================
-- MINIMAL CONFIGURATION
-- ============================================================================

-- Simplest setup - uses all defaults
{
  "username/nvim-writing-metrics",
  cmd = { "WordCount", "ReadabilityReport" },
  ft = { "markdown", "text", "tex", "fountain", "org" },
  keys = {
    { "<leader>mc", "<cmd>WordCount<cr>", desc = "Word count" },
    { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability report" },
    { "<leader>mt", "<cmd>WritingMetricsToggle<cr>", desc = "Toggle fast/accurate mode" },
  },
}

-- ============================================================================
-- RECOMMENDED CONFIGURATION
-- ============================================================================

-- Includes Snacks.nvim for better notifications (optional but recommended)
{
  "username/nvim-writing-metrics",
  dependencies = {
    "folke/snacks.nvim",  -- For pretty notifications
  },
  cmd = {
    "WordCount",
    "ReadabilityReport",
    "WritingMetrics",
    "WritingMetricsToggle",
    "WritingMetricsCache",
    "WritingMetricsClear",
  },
  ft = { "markdown", "text", "tex", "fountain", "org", "asciidoc", "rst" },
  keys = {
    -- Word count (works in visual mode)
    { "<leader>mc", "<cmd>WordCount<cr>", mode = { "n", "v" }, desc = "Word count" },

    -- Readability report
    { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability report" },

    -- Toggle mode
    { "<leader>mt", "<cmd>WritingMetricsToggle<cr>", desc = "Toggle word count mode" },

    -- Plugin info
    { "<leader>mi", "<cmd>WritingMetrics<cr>", desc = "Writing metrics info" },
  },
  opts = {
    -- Use defaults for everything
  },
}

-- ============================================================================
-- FULL CONFIGURATION (All Options)
-- ============================================================================

{
  "username/nvim-writing-metrics",
  dependencies = {
    "folke/snacks.nvim",
  },
  cmd = {
    "WordCount",
    "ReadabilityReport",
    "WritingMetrics",
    "WritingMetricsToggle",
    "WritingMetricsCache",
    "WritingMetricsClear",
    -- Backward compatibility
    "AccurateWordCount",
    "ToggleWordCountMode",
  },
  ft = { "markdown", "text", "tex", "fountain", "org", "asciidoc", "rst" },
  keys = {
    { "<leader>mc", "<cmd>WordCount<cr>", mode = { "n", "v" }, desc = "Word count" },
    { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability report" },
    { "<leader>mt", "<cmd>WritingMetricsToggle<cr>", desc = "Toggle mode" },
    { "<leader>mi", "<cmd>WritingMetrics<cr>", desc = "Plugin info" },
    { "<leader>mC", "<cmd>WritingMetricsCache<cr>", desc = "Cache status" },
  },
  opts = {
    -- Cache configuration
    cache = {
      basic_ttl = 500,     -- 500ms cache for statusline (fast updates)
      full_ttl = 30000,    -- 30s cache for full reports (expensive computation)
    },

    -- Feature toggles (enable/disable specific analyses)
    features = {
      basic = true,                -- Word/char/sentence counts
      readability = true,          -- 6 readability formulas
      passive_voice = true,        -- Passive voice detection
      nominalizations = true,      -- Nominalization detection
      vocabulary = true,           -- Vocabulary richness analysis
      sentence_variety = true,     -- Sentence length variability
    },

    -- Display configuration
    display = {
      float_border = "rounded",    -- Border style: "none", "single", "double", "rounded"
      report_window = "tab",       -- Report display: "tab", "split", "vsplit"
    },

    -- Target ranges for different writing contexts
    targets = {
      grant = {
        flesch_kincaid = { min = 11, max = 14 },    -- College level, clear
        passive_voice = { max = 10 },                -- < 10% passive voice
        nominalizations = { max = 5 },               -- < 5% nominalizations
        sentence_variability = { min = 6 },          -- Some variety
      },
      creative = {
        flesch_kincaid = { min = 7, max = 9 },      -- 7-9th grade (accessible)
        sentence_variability = { min = 8 },          -- High variety
        passive_voice = { max = 15 },                -- More flexible
      },
      academic = {
        flesch_kincaid = { min = 12, max = 16 },    -- College/grad level
        nominalizations = { max = 8 },               -- More acceptable
        passive_voice = { max = 20 },                -- Scientific style
      },
      blog = {
        flesch_kincaid = { min = 6, max = 8 },      -- Easy to read
        sentence_variability = { min = 7 },          -- Varied rhythm
      },
    },

    -- Statusline configuration
    statusline = {
      mode = "accurate",           -- Default mode: "fast" or "accurate"
      format = "words_chars",      -- Format: "words_chars", "words_only", "detailed"
      show_reading_time = true,    -- Show estimated reading time
      reading_speed_wpm = 200,     -- Words per minute for reading time
    },
  },
}

-- ============================================================================
-- GRANT WRITING CONFIGURATION
-- ============================================================================

-- Optimized for grant proposals with strict quality requirements
{
  "username/nvim-writing-metrics",
  dependencies = { "folke/snacks.nvim" },
  cmd = { "WordCount", "ReadabilityReport", "WritingMetricsToggle" },
  ft = { "markdown", "text" },
  keys = {
    { "<leader>mc", "<cmd>WordCount<cr>", mode = { "n", "v" }, desc = "Word count" },
    { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability report" },
  },
  opts = {
    cache = {
      full_ttl = 60000,  -- 60s cache (grants change less frequently)
    },
    features = {
      basic = true,
      readability = true,
      passive_voice = true,
      nominalizations = true,
      vocabulary = true,
      sentence_variety = true,
    },
    display = {
      float_border = "rounded",
      report_window = "tab",  -- Full tab for comprehensive review
    },
    targets = {
      grant = {
        flesch_kincaid = { min = 11, max = 14 },
        passive_voice = { max = 10 },
        nominalizations = { max = 5 },
        sentence_variability = { min = 6 },
      },
    },
    statusline = {
      mode = "accurate",
      format = "words_chars",
      show_reading_time = true,
      reading_speed_wpm = 200,
    },
  },
}

-- ============================================================================
-- CREATIVE WRITING CONFIGURATION
-- ============================================================================

-- Optimized for fiction/creative nonfiction
{
  "username/nvim-writing-metrics",
  dependencies = { "folke/snacks.nvim" },
  cmd = { "WordCount", "ReadabilityReport" },
  ft = { "markdown", "text", "fountain" },
  keys = {
    { "<leader>mc", "<cmd>WordCount<cr>", mode = { "n", "v" }, desc = "Word count" },
    { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability report" },
  },
  opts = {
    features = {
      basic = true,
      readability = true,
      passive_voice = false,       -- Don't flag passive voice in creative
      nominalizations = false,     -- Don't flag nominalizations
      vocabulary = true,
      sentence_variety = true,     -- Important for creative writing
    },
    targets = {
      creative = {
        flesch_kincaid = { min = 7, max = 9 },
        sentence_variability = { min = 8 },  -- High variety for rhythm
      },
    },
  },
}

-- ============================================================================
-- MINIMAL OVERHEAD CONFIGURATION
-- ============================================================================

-- For users who want metrics on demand, no statusline integration
{
  "username/nvim-writing-metrics",
  cmd = { "WordCount", "ReadabilityReport" },
  ft = { "markdown" },
  keys = {
    { "<leader>wc", "<cmd>WordCount<cr>", desc = "Word count" },
    { "<leader>wr", "<cmd>ReadabilityReport<cr>", desc = "Readability" },
  },
  opts = {
    cache = {
      basic_ttl = 0,     -- Disable statusline caching
      full_ttl = 30000,
    },
    features = {
      basic = true,
      readability = true,
      passive_voice = false,
      nominalizations = false,
      vocabulary = false,
      sentence_variety = false,
    },
    statusline = {
      mode = "fast",
    },
  },
}

-- ============================================================================
-- PERFORMANCE-OPTIMIZED CONFIGURATION
-- ============================================================================

-- For very large documents (books, dissertations)
{
  "username/nvim-writing-metrics",
  dependencies = { "folke/snacks.nvim" },
  cmd = { "WordCount", "ReadabilityReport" },
  ft = { "markdown", "text" },
  keys = {
    { "<leader>mc", "<cmd>WordCount<cr>", mode = { "n", "v" }, desc = "Word count" },
    { "<leader>mr", "<cmd>ReadabilityReport<cr>", desc = "Readability report" },
  },
  opts = {
    cache = {
      basic_ttl = 1000,    -- 1s cache (slower updates, less overhead)
      full_ttl = 120000,   -- 2min cache (very expensive for large docs)
    },
    features = {
      basic = true,
      readability = true,
      passive_voice = false,       -- Disable expensive features
      nominalizations = false,
      vocabulary = false,
      sentence_variety = true,
    },
    statusline = {
      mode = "fast",  -- Use fast counting for statusline
    },
  },
}
