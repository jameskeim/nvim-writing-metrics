-- Luacheck configuration for nvim-writing-metrics

-- Global vim API
globals = {
  "vim",
}

-- Standard library
std = "luajit"

-- Ignore warnings about line length
max_line_length = false

-- Ignore warnings about unused self
self = false

-- Read globals for testing (plenary.nvim)
files["tests/"] = {
  globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "assert",
    "pending",
  },
}

-- Pandoc filter has its own runtime environment with injected globals.
-- pandoc is the Pandoc filter API entry point; Pandoc (capitalised) is the
-- document-level filter function Pandoc calls back into. The rest are
-- accumulator variables populated by walker functions in the filter.
-- utf8 is a Lua 5.3+ standard library available in the Pandoc runtime.
-- blockcounter / wordcount are filter-dispatch tables set as globals.
-- W411 (shadow) for clean_word is suppressed here because it is an
-- intentional multi-return local redeclared inside the walker loop.
files["scripts/textmetrics.lua"] = {
  globals = {
    "pandoc",
    "Pandoc",
    "words",
    "chars",
    "sentences",
    "paragraphs",
    "lines",
    "questions",
    "passive_sentences",
    "passive_examples",
    "total_nominalizations",
    "nominalization_examples",
    "ai_word_counts",
    "sentence_beginnings",
    "sentence_lengths",
    "current_sentence_words",
    "current_sentence_text",
    "is_sentence_start",
    "total_syllables",
    "complex_words",
    "total_word_chars",
    "unique_words",
    "analysis_mode",
    "wordcount",
    "blockcounter",
    "utf8",
  },
  ignore = { "411" },
}

-- Exclude external dependencies and generated files
exclude_files = {
  ".luarocks/",
  ".git/",
  "vendor/",
}

-- Warnings to ignore
ignore = {
  "212", -- Unused argument (common in callbacks)
  "631", -- Line too long (handled by formatter)
}
