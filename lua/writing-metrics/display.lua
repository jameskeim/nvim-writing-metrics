--- Report formatting and display module for nvim-writing-metrics
--- Creates beautiful, readable reports with interpretation guidance
--- @module writing-metrics.display
local M = {}

--- Find existing report buffer for a source buffer
--- @param source_bufnr number Source buffer number
--- @return number|nil Report buffer number if exists and valid
function M.find_existing_report(source_bufnr)
  -- Use filepath as key, not buffer number (buffers can be reused for different files)
  local source_filepath = vim.api.nvim_buf_get_name(source_bufnr)
  if source_filepath == "" then
    return nil  -- Unnamed buffers don't get tracked
  end

  local report_bufnr = _G.writing_metrics_reports[source_filepath]

  if report_bufnr and vim.api.nvim_buf_is_valid(report_bufnr) then
    return report_bufnr
  end

  -- Clean up stale reference
  if report_bufnr then
    _G.writing_metrics_reports[source_filepath] = nil
  end

  return nil
end

--- Generate unique buffer name for report
--- @param source_bufnr number Source buffer number
--- @return string Buffer name like "Report: filename.md"
function M.generate_report_name(source_bufnr)
  local source_name = vim.api.nvim_buf_get_name(source_bufnr)

  if source_name == "" then
    return "Report: [No Name]"
  end

  -- Get just the filename (tail)
  local filename = vim.fn.fnamemodify(source_name, ":t")

  -- If filename is empty or very common, include parent directory
  if filename == "" or filename == "README.md" or filename == "draft.md" then
    filename = vim.fn.fnamemodify(source_name, ":~:.")
  end

  return "Report: " .. filename
end

--- Update existing report buffer with new content
--- @param report_bufnr number Report buffer to update
--- @param lines table New content lines
function M.update_report_buffer(report_bufnr, lines)
  -- Make buffer temporarily modifiable
  vim.api.nvim_buf_set_option(report_bufnr, "modifiable", true)

  -- Replace all content
  vim.api.nvim_buf_set_lines(report_bufnr, 0, -1, false, lines)

  -- Restore unmodifiable state
  vim.api.nvim_buf_set_option(report_bufnr, "modifiable", false)
end

--- Format the complete comprehensive report
--- @param data table Full metrics data from Pandoc filter
--- @return table Lines for display
function M.format_report(data)
  local lines = {}

  -- Header
  table.insert(lines, "# Writing Metrics Report")
  table.insert(lines, "")
  table.insert(lines, string.format("**Generated:** %s", os.date("%Y-%m-%d %H:%M:%S")))
  table.insert(lines, "**Buffer:** " .. vim.api.nvim_buf_get_name(0))
  table.insert(lines, "")
  table.insert(lines, "---")

  -- Section 1: Basic Statistics
  if data.basic then
    local section = M.format_basic_section(data.basic)
    vim.list_extend(lines, section)
  end

  -- Section 2: Readability Scores
  if data.readability then
    local section = M.format_readability_section(data.readability, data.basic)
    vim.list_extend(lines, section)
  end

  -- Section 3: Sentence Variety
  if data.variability or data.sentence_variety then
    local variability = data.variability or data.sentence_variety
    local section = M.format_sentence_variety_section(variability)
    vim.list_extend(lines, section)
  end

  -- Section 4: Sentence Beginning Variety
  if data.sentence_variety and data.sentence_variety.beginnings then
    local section = M.format_sentence_beginnings_section(data.sentence_variety.beginnings, data.basic)
    vim.list_extend(lines, section)
  end

  -- Section 5: Passive Voice
  if data.passive_voice then
    local section = M.format_passive_voice_section(data.passive_voice)
    vim.list_extend(lines, section)
  end

  -- Section 6: Nominalizations
  if data.nominalizations then
    local section = M.format_nominalization_section(data.nominalizations)
    vim.list_extend(lines, section)
  end

  -- Section 7: Vocabulary Richness
  if data.vocabulary then
    local section = M.format_vocabulary_section(data.vocabulary)
    vim.list_extend(lines, section)
  end

  -- Section 8: AI-Style Detection
  if data.ai_style or data.ai_words then
    local ai_data = data.ai_style or data.ai_words
    local section = M.format_ai_style_section(ai_data, data.basic)
    vim.list_extend(lines, section)
  end

  -- Footer with cache info
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")
  table.insert(lines, "**Navigation:** Press `q` to close | `<leader>mr` from document to regenerate | `1`-`8` to jump to sections")
  table.insert(lines, "")

  return lines
end

--- Format basic statistics section
--- @param basic table Basic metrics data
--- @return table Lines for this section
function M.format_basic_section(basic)
  local lines = {}
  local utils = require("writing-metrics.utils")

  table.insert(lines, "")
  table.insert(lines, "## 📊 Basic Statistics")
  table.insert(lines, "")
  table.insert(lines, string.format("| Metric | Value |"))
  table.insert(lines, string.format("|--------|-------|"))
  table.insert(lines, string.format("| Words | **%s** |", utils.format_number(basic.words)))
  table.insert(lines, string.format("| Characters | **%s** |", utils.format_number(basic.characters or basic.chars)))
  table.insert(lines, string.format("| Sentences | **%s** |", utils.format_number(basic.sentences)))
  table.insert(lines, string.format("| Paragraphs | **%s** |", utils.format_number(basic.paragraphs)))
  table.insert(lines, string.format("| Lines | **%s** |", utils.format_number(basic.lines)))
  table.insert(lines, "")
  table.insert(lines, "**Averages:**")
  table.insert(lines, "")
  table.insert(
    lines,
    string.format("- %.1f words per sentence", basic.avg_words_per_sentence or basic.avg_sentence_len or 0)
  )
  table.insert(lines, string.format("- %.1f characters per word", basic.avg_chars_per_word or basic.avg_word_len or 0))
  table.insert(
    lines,
    string.format("- %.1f sentences per paragraph", basic.avg_sentences_per_paragraph or 0)
  )

  return lines
end

--- Format readability scores section
--- @param readability table Readability data
--- @param basic table Basic metrics for interpretation
--- @return table Lines for this section
function M.format_readability_section(readability, basic)
  local lines = {}

  table.insert(lines, "")
  table.insert(lines, "## 📖 Readability Scores")
  table.insert(lines, "")

  -- Table header
  table.insert(lines, "| Formula | Score | Interpretation |")
  table.insert(lines, "|---------|-------|----------------|")

  -- Tier 1: Fast formulas (no syllable counting)
  if readability.coleman_liau then
    local grade = readability.coleman_liau
    local interp = M.interpret_grade_level(grade)
    table.insert(lines, string.format("| Coleman-Liau Index | **%.1f** | %s |", grade, interp))
  end

  if readability.automated_readability or readability.ari then
    local grade = readability.automated_readability or readability.ari
    local interp = M.interpret_grade_level(grade)
    table.insert(lines, string.format("| Automated Readability (ARI) | **%.1f** | %s |", grade, interp))
  end

  -- Tier 2: Comprehensive formulas (with syllables)
  if readability.flesch_reading_ease then
    local score = readability.flesch_reading_ease
    local interp = M.interpret_flesch_reading_ease(score)
    table.insert(lines, string.format("| Flesch Reading Ease | **%.1f** | %s |", score, interp))
  end

  if readability.flesch_kincaid_grade or readability.flesch_kincaid then
    local grade = readability.flesch_kincaid_grade or readability.flesch_kincaid
    local interp = M.interpret_grade_level(grade)
    table.insert(lines, string.format("| Flesch-Kincaid Grade | **%.1f** | %s |", grade, interp))
  end

  if readability.gunning_fog then
    local grade = readability.gunning_fog
    local interp = M.interpret_grade_level(grade)
    table.insert(lines, string.format("| Gunning Fog Index | **%.1f** | %s |", grade, interp))
  end

  if readability.smog then
    local grade = readability.smog
    local interp = M.interpret_grade_level(grade)
    table.insert(lines, string.format("| SMOG Index | **%.1f** | %s |", grade, interp))
  end

  table.insert(lines, "")

  -- Overall assessment
  local avg_grade = M.calculate_average_grade(readability)
  if avg_grade then
    table.insert(lines, "**Overall Assessment:**")
    table.insert(lines, "")
    table.insert(lines, string.format("- Average grade level: **%.1f** (%s)", avg_grade, M.interpret_grade_level(avg_grade)))
    table.insert(lines, "")

    -- Context-specific guidance
    if avg_grade >= 12 then
      table.insert(lines, "✓ Suitable for **grant proposals** and **academic writing**")
    elseif avg_grade >= 9 then
      table.insert(lines, "✓ Suitable for **general audiences** and **technical writing**")
    elseif avg_grade >= 7 then
      table.insert(lines, "✓ Suitable for **creative writing** and **broad audiences**")
    else
      table.insert(lines, "ℹ Very accessible - suitable for **young adult** or **general public**")
    end
  end

  return lines
end

--- Format sentence variety section
--- @param variability table Variability data
--- @return table Lines for this section
function M.format_sentence_variety_section(variability)
  local lines = {}
  local utils = require("writing-metrics.utils")

  table.insert(lines, "")
  table.insert(lines, "## 📝 Sentence Length Variety")
  table.insert(lines, "")

  table.insert(lines, "| Metric | Value |")
  table.insert(lines, "|--------|-------|")
  table.insert(lines, string.format("| Mean length | **%.1f words** |", variability.mean or 0))
  table.insert(lines, string.format("| Standard deviation | **%.1f words** |", variability.std_dev or 0))
  table.insert(lines, string.format("| Coefficient of variation | **%.1f%%** |", variability.cv or 0))
  table.insert(lines, string.format("| Range | **%d - %d words** |", variability.min or 0, variability.max or 0))
  table.insert(lines, "")

  -- Interpretation
  local cv = variability.cv or 0
  local interp = M.interpret_sentence_variety(cv)
  table.insert(lines, "**Interpretation:** " .. interp)
  table.insert(lines, "")

  -- Distribution
  if variability.distribution then
    local dist = variability.distribution
    local total = (dist["1-5"] or 0)
      + (dist["6-10"] or 0)
      + (dist["11-20"] or 0)
      + (dist["21-30"] or 0)
      + (dist["31+"] or 0)

    if total > 0 then
      table.insert(lines, "**Distribution:**")
      table.insert(lines, "")

      local function format_bar(count, max_count)
        local bar_length = 20
        local filled = math.floor((count / max_count) * bar_length)
        local bar = string.rep("█", filled) .. string.rep("░", bar_length - filled)
        return bar
      end

      local max_count = math.max(dist["1-5"] or 0, dist["6-10"] or 0, dist["11-20"] or 0, dist["21-30"] or 0, dist["31+"] or 0)

      table.insert(
        lines,
        string.format(
          "- 1-5 words:   %s  **%3d** (%5.1f%%)",
          format_bar(dist["1-5"] or 0, max_count),
          dist["1-5"] or 0,
          (dist["1-5"] or 0) / total * 100
        )
      )
      table.insert(
        lines,
        string.format(
          "- 6-10 words:  %s  **%3d** (%5.1f%%)",
          format_bar(dist["6-10"] or 0, max_count),
          dist["6-10"] or 0,
          (dist["6-10"] or 0) / total * 100
        )
      )
      table.insert(
        lines,
        string.format(
          "- 11-20 words: %s  **%3d** (%5.1f%%)",
          format_bar(dist["11-20"] or 0, max_count),
          dist["11-20"] or 0,
          (dist["11-20"] or 0) / total * 100
        )
      )
      table.insert(
        lines,
        string.format(
          "- 21-30 words: %s  **%3d** (%5.1f%%)",
          format_bar(dist["21-30"] or 0, max_count),
          dist["21-30"] or 0,
          (dist["21-30"] or 0) / total * 100
        )
      )
      table.insert(
        lines,
        string.format(
          "- 31+ words:   %s  **%3d** (%5.1f%%)",
          format_bar(dist["31+"] or 0, max_count),
          dist["31+"] or 0,
          (dist["31+"] or 0) / total * 100
        )
      )
    end
  end

  -- Monotonous patterns
  if variability.patterns and #variability.patterns > 0 then
    table.insert(lines, "")
    table.insert(lines, "⚠ **Monotonous patterns detected:**")
    table.insert(lines, "")
    for _, pattern in ipairs(variability.patterns) do
      table.insert(
        lines,
        string.format(
          "- Sentences %d-%d: %d similar-length sentences (%.0f-%.0f words)",
          pattern.start_sentence,
          pattern.end_sentence,
          pattern.count,
          pattern.min_length,
          pattern.max_length
        )
      )
    end
    table.insert(lines, "")
    table.insert(lines, "> **Recommendation:** Vary sentence structure in these sections for better rhythm.")
  else
    table.insert(lines, "")
    table.insert(lines, "✓ No monotonous patterns detected.")
  end

  return lines
end

--- Format sentence beginnings variety section
--- @param beginnings table Sentence beginnings data
--- @param basic table Basic metrics for percentages
--- @return table Lines for this section
function M.format_sentence_beginnings_section(beginnings, basic)
  local lines = {}

  table.insert(lines, "")
  table.insert(lines, "## 🎯 Sentence Beginning Variety")
  table.insert(lines, "")

  table.insert(lines, "Distribution of how sentences start:")
  table.insert(lines, "")

  table.insert(lines, "| Category | Count | Percentage | Examples |")
  table.insert(lines, "|----------|-------|------------|----------|")

  -- Helper to generate bar
  local function format_mini_bar(pct)
    local filled = math.floor(pct / 5) -- Scale to 20 chars max
    return string.rep("█", filled) .. string.rep("░", 20 - filled)
  end

  -- Sort by percentage
  local categories = {
    { name = "Pronouns", data = beginnings.pronoun, examples = "I, we, you, they, this" },
    { name = "Articles", data = beginnings.article, examples = "a, an, the" },
    { name = "Conjunctions", data = beginnings.conjunction, examples = "and, but, or, because" },
    { name = "Prepositions", data = beginnings.preposition, examples = "in, on, at, with" },
    { name = "Adverbs", data = beginnings.adverb, examples = "however, therefore, etc." },
    { name = "Other", data = beginnings.other, examples = "nouns, verbs, adjectives" },
  }

  for _, cat in ipairs(categories) do
    local count = cat.data.count or 0
    local pct = cat.data.percentage or 0
    table.insert(
      lines,
      string.format("| %s | **%d** | %.1f%% %s | %s |", cat.name, count, pct, format_mini_bar(pct), cat.examples)
    )
  end

  table.insert(lines, "")

  -- Check for monotonous patterns (>40% of any category)
  local warnings = {}
  for _, cat in ipairs(categories) do
    local pct = cat.data.percentage or 0
    if pct > 40 then
      table.insert(warnings, string.format("%s (%.1f%%)", cat.name, pct))
    end
  end

  if #warnings > 0 then
    table.insert(lines, "⚠ **MONOTONOUS BEGINNING PATTERN DETECTED:**")
    table.insert(lines, "")
    for _, warning in ipairs(warnings) do
      table.insert(lines, "- Over-reliance on " .. warning)
    end
    table.insert(lines, "")
    table.insert(lines, "> **Recommendation:** Vary sentence beginnings for better rhythm and engagement.")
    table.insert(lines, "> No single category should exceed 35% of total sentences.")
  else
    local max_pct = 0
    for _, cat in ipairs(categories) do
      max_pct = math.max(max_pct, cat.data.percentage or 0)
    end

    if max_pct <= 35 then
      table.insert(lines, "✓ **Excellent variety** in sentence beginnings")
      table.insert(lines, "")
      table.insert(lines, "> Well-balanced distribution creates good rhythm.")
    else
      table.insert(lines, "ℹ Acceptable variety in sentence beginnings")
      table.insert(lines, "")
      table.insert(lines, string.format("> Highest category: %.1f%% (approaching 35%% threshold)", max_pct))
    end
  end

  return lines
end

--- Format passive voice section
--- @param passive_voice table Passive voice data
--- @return table Lines for this section
function M.format_passive_voice_section(passive_voice)
  local lines = {}
  local utils = require("writing-metrics.utils")

  table.insert(lines, "")
  table.insert(lines, "## 🔍 Passive Voice Analysis")
  table.insert(lines, "")

  local count = passive_voice.count or 0
  local pct = passive_voice.percentage or 0

  table.insert(lines, string.format("**Instances:** %d (%s)", count, utils.format_percentage(pct)))
  table.insert(lines, "")

  -- Interpretation
  local interp = M.interpret_passive_voice(pct, "grant")
  table.insert(lines, interp)
  table.insert(lines, "")

  -- Examples
  if passive_voice.examples and #passive_voice.examples > 0 then
    table.insert(lines, "**Examples:**")
    table.insert(lines, "")
    local max_examples = math.min(10, #passive_voice.examples)
    for i = 1, max_examples do
      table.insert(lines, string.format("%d. %s", i, passive_voice.examples[i]))
    end
    table.insert(lines, "")
    table.insert(lines, "> **Tip:** Convert to active voice: *\"We conducted the study\"* instead of *\"The study was conducted\"*")
  end

  return lines
end

--- Format nominalization section
--- @param nominalizations table Nominalization data
--- @return table Lines for this section
function M.format_nominalization_section(nominalizations)
  local lines = {}
  local utils = require("writing-metrics.utils")

  table.insert(lines, "")
  table.insert(lines, "## 📐 Nominalization Analysis")
  table.insert(lines, "")

  local count = nominalizations.count or 0
  local pct = nominalizations.percentage or 0

  table.insert(lines, string.format("**Instances:** %d (%s)", count, utils.format_percentage(pct)))
  table.insert(lines, "")

  -- Interpretation
  local interp = M.interpret_nominalizations(pct)
  table.insert(lines, interp)
  table.insert(lines, "")

  -- Examples with verb suggestions
  if nominalizations.examples and next(nominalizations.examples) then
    -- Sort by frequency
    local sorted = {}
    for word, word_count in pairs(nominalizations.examples) do
      table.insert(sorted, { word = word, count = word_count })
    end
    table.sort(sorted, function(a, b)
      return a.count > b.count
    end)

    table.insert(lines, "**Top nominalizations:**")
    table.insert(lines, "")
    table.insert(lines, "| Nominalization | Count | → Suggested Verb |")
    table.insert(lines, "|----------------|-------|------------------|")

    local verb_suggestions = M.get_nominalization_suggestions()
    local max_display = math.min(15, #sorted)

    for i = 1, max_display do
      local item = sorted[i]
      local suggestion = verb_suggestions[item.word] or "—"
      table.insert(lines, string.format("| %s | %d | **%s** |", item.word, item.count, suggestion))
    end

    table.insert(lines, "")
    table.insert(
      lines,
      "> **Tip:** Convert nominalizations to verb forms: *\"investigate\"* instead of *\"conduct an investigation\"*"
    )
  end

  return lines
end

--- Format vocabulary richness section
--- @param vocabulary table Vocabulary data
--- @return table Lines for this section
function M.format_vocabulary_section(vocabulary)
  local lines = {}
  local utils = require("writing-metrics.utils")

  table.insert(lines, "")
  table.insert(lines, "## 📚 Vocabulary Richness")
  table.insert(lines, "")

  local total = vocabulary.total_words or 0
  local unique = vocabulary.unique_words or 0
  local ttr = vocabulary.ttr or vocabulary.type_token_ratio or 0

  table.insert(lines, "| Metric | Value |")
  table.insert(lines, "|--------|-------|")
  table.insert(lines, string.format("| Total words | **%s** |", utils.format_number(total)))
  table.insert(lines, string.format("| Unique words | **%s** |", utils.format_number(unique)))
  table.insert(lines, string.format("| Type-Token Ratio (TTR) | **%.1f%%** |", ttr))
  table.insert(lines, "")

  -- Interpretation
  local interp = M.interpret_vocabulary_richness(ttr)
  table.insert(lines, interp)
  table.insert(lines, "")

  -- Most frequent words
  if vocabulary.most_frequent and #vocabulary.most_frequent > 0 then
    table.insert(lines, "**Most frequent content words:**")
    table.insert(lines, "")
    local max_words = math.min(10, #vocabulary.most_frequent)
    for i = 1, max_words do
      local item = vocabulary.most_frequent[i]
      local word = item.word or item[1]
      local word_count = item.count or item[2]
      local word_pct = (word_count / total) * 100
      table.insert(lines, string.format("%2d. **%s** - %d times (%.2f%%)", i, word, word_count, word_pct))
    end

    table.insert(lines, "")

    -- Check for overused words (> 1%)
    local overused = {}
    for _, item in ipairs(vocabulary.most_frequent) do
      local word = item.word or item[1]
      local word_count = item.count or item[2]
      local word_pct = (word_count / total) * 100
      if word_pct > 1.0 then
        table.insert(overused, { word = word, count = word_count, pct = word_pct })
      end
    end

    if #overused > 0 then
      table.insert(lines, "⚠ **Potentially overused words (>1% of text):**")
      table.insert(lines, "")
      for _, item in ipairs(overused) do
        table.insert(lines, string.format("- **%s**: %d times (%.1f%%)", item.word, item.count, item.pct))
      end
      table.insert(lines, "")
      table.insert(lines, "> **Recommendation:** Consider using synonyms to increase vocabulary richness.")
    else
      table.insert(lines, "✓ No words appear more than 1% of the time - good balance!")
    end
  end

  return lines
end

--- Format AI-style detection section
--- @param ai_style table AI-style data
--- @param basic table Basic metrics for percentages
--- @return table Lines for this section
function M.format_ai_style_section(ai_style, basic)
  local lines = {}

  table.insert(lines, "")
  table.insert(lines, "## 🤖 AI-Style Detection")
  table.insert(lines, "")

  local word_counts = ai_style.word_counts or {}
  local total_ai_words = 0

  -- Calculate total
  for _, count in pairs(word_counts) do
    total_ai_words = total_ai_words + count
  end

  local total_words = basic and basic.words or 1
  local ai_pct = (total_ai_words / total_words) * 100

  table.insert(lines, string.format("**Total AI-associated words:** %d (%.2f%% of text)", total_ai_words, ai_pct))
  table.insert(lines, "")

  if total_ai_words == 0 then
    table.insert(lines, "✓ **No AI-associated words detected**")
    table.insert(lines, "")
    table.insert(lines, "> Your writing has a natural, human voice.")
  else
    -- Sort by frequency
    local sorted = {}
    for word, count in pairs(word_counts) do
      table.insert(sorted, { word = word, count = count })
    end
    table.sort(sorted, function(a, b)
      return a.count > b.count
    end)

    table.insert(lines, "**Detected AI-associated words:**")
    table.insert(lines, "")

    local max_display = math.min(20, #sorted)
    for i = 1, max_display do
      local item = sorted[i]
      table.insert(lines, string.format("- **%s**: %d times", item.word, item.count))
    end

    table.insert(lines, "")

    -- Interpretation based on frequency
    if ai_pct < 0.5 then
      table.insert(lines, "✓ **Low AI-style presence** - writing sounds authentic")
      table.insert(lines, "")
      table.insert(lines, "> Consider replacing the few AI-associated words with more specific alternatives.")
    elseif ai_pct < 1.0 then
      table.insert(lines, "⚠ **Moderate AI-style presence** - review for authenticity")
      table.insert(lines, "")
      table.insert(
        lines,
        "> **Recommendation:** Replace AI-associated words with concrete, specific alternatives:"
      )
      table.insert(lines, "> - \"optimize\" → \"improve\"")
      table.insert(lines, "> - \"leverage\" → \"use\"")
      table.insert(lines, "> - \"delve\" → \"examine\" or \"explore\"")
    else
      table.insert(lines, "⚠ **High AI-style presence** - significant revision recommended")
      table.insert(lines, "")
      table.insert(lines, "> Your writing contains many AI-associated words and phrases.")
      table.insert(lines, "> Focus on:")
      table.insert(lines, "> - Using concrete, specific language")
      table.insert(lines, "> - Avoiding business jargon and buzzwords")
      table.insert(lines, "> - Choosing simple verbs over elaborate constructions")
    end

    table.insert(lines, "")
    table.insert(lines, "> **Tools:** Use `<leader>la` to toggle AI-word highlighting (vim-wordy integration)")
  end

  return lines
end

--- Create report buffer and display it
--- @param lines table Lines to display
--- @param opts table Options (window_type, source_bufnr)
function M.create_report_buffer(lines, opts)
  opts = opts or {}
  local window_type = opts.window_type or "tab"
  local source_bufnr = opts.source_bufnr

  -- Open new window
  if window_type == "tab" then
    vim.cmd("tabnew")
  elseif window_type == "split" then
    vim.cmd("split")
  elseif window_type == "vsplit" then
    vim.cmd("vsplit")
  end

  local bufnr = vim.api.nvim_get_current_buf()

  -- Set content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

  -- Set unique buffer name based on source
  if source_bufnr then
    local buffer_name = M.generate_report_name(source_bufnr)
    vim.api.nvim_buf_set_name(bufnr, buffer_name)

    -- Store mapping in global tracking table (use filepath as key)
    local source_filepath = vim.api.nvim_buf_get_name(source_bufnr)
    if source_filepath ~= "" then
      _G.writing_metrics_reports[source_filepath] = bufnr
    end
  end

  -- Set buffer-local keymaps
  M.setup_report_keymaps(bufnr)
end

--- Setup keymaps for navigating the report
--- @param bufnr number Buffer number
function M.setup_report_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true, nowait = true }

  -- Close report
  vim.keymap.set("n", "q", "<cmd>close<cr>", opts)
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", opts)

  -- Jump to sections
  vim.keymap.set("n", "1", "/^## 📊<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "2", "/^## 📖<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "3", "/^## 📝<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "4", "/^## 🎯<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "5", "/^## 🔍<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "6", "/^## 📐<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "7", "/^## 📚<CR>:nohlsearch<CR>", opts)
  vim.keymap.set("n", "8", "/^## 🤖<CR>:nohlsearch<CR>", opts)
end

--- ============================================================================
--- INTERPRETATION HELPERS
--- ============================================================================

--- Interpret grade level readability score
--- @param grade number Grade level (1-20)
--- @return string Interpretation
function M.interpret_grade_level(grade)
  if grade <= 5 then
    return "Elementary (grades 1-5)"
  elseif grade <= 8 then
    return "Middle school (grades 6-8)"
  elseif grade <= 12 then
    return "High school (grades 9-12)"
  elseif grade <= 16 then
    return "College level (undergraduate)"
  else
    return "Graduate level (advanced)"
  end
end

--- Interpret Flesch Reading Ease score
--- @param score number Flesch Reading Ease (0-100)
--- @return string Interpretation
function M.interpret_flesch_reading_ease(score)
  if score >= 90 then
    return "Very easy (5th grade)"
  elseif score >= 80 then
    return "Easy (6th grade)"
  elseif score >= 70 then
    return "Fairly easy (7th grade)"
  elseif score >= 60 then
    return "Standard (8-9th grade)"
  elseif score >= 50 then
    return "Fairly difficult (10-12th grade)"
  elseif score >= 30 then
    return "Difficult (college)"
  else
    return "Very difficult (graduate)"
  end
end

--- Calculate average grade level from all available formulas
--- @param readability table Readability data
--- @return number|nil Average grade level
function M.calculate_average_grade(readability)
  local grades = {}

  if readability.coleman_liau then
    table.insert(grades, readability.coleman_liau)
  end
  if readability.automated_readability or readability.ari then
    table.insert(grades, readability.automated_readability or readability.ari)
  end
  if readability.flesch_kincaid_grade or readability.flesch_kincaid then
    table.insert(grades, readability.flesch_kincaid_grade or readability.flesch_kincaid)
  end
  if readability.gunning_fog then
    table.insert(grades, readability.gunning_fog)
  end
  if readability.smog then
    table.insert(grades, readability.smog)
  end

  if #grades == 0 then
    return nil
  end

  local sum = 0
  for _, grade in ipairs(grades) do
    sum = sum + grade
  end

  return sum / #grades
end

--- Interpret sentence variety coefficient of variation
--- @param cv number Coefficient of variation percentage
--- @return string Interpretation
function M.interpret_sentence_variety(cv)
  if cv < 30 then
    return "**Low variety** - sentences very similar in length. Consider varying sentence structure for better rhythm."
  elseif cv < 50 then
    return "**Moderate variety** - good sentence rhythm with balanced variation."
  else
    return "**High variety** - strong rhythmic variation with mix of short and long sentences."
  end
end

--- Interpret passive voice percentage
--- @param pct number Percentage of passive voice sentences
--- @param context string Writing context ("grant", "creative", "academic")
--- @return string Interpretation
function M.interpret_passive_voice(pct, context)
  context = context or "grant"

  if pct == 0 then
    return "✓ **No passive voice detected** - strong, direct writing"
  elseif pct < 5 then
    return "✓ **Very low passive voice** - excellent for most writing contexts"
  elseif pct < 10 then
    return "✓ **Low passive voice** - acceptable for grants and technical writing (target: <10%)"
  elseif pct < 20 then
    if context == "grant" then
      return "⚠ **Moderate passive voice** - consider revising for grants (target: <10%)"
    else
      return "ℹ **Moderate passive voice** - acceptable for academic writing"
    end
  else
    return "⚠ **High passive voice** - reduces clarity and impact. Convert to active voice for stronger writing."
  end
end

--- Interpret nominalization percentage
--- @param pct number Percentage of nominalizations
--- @return string Interpretation
function M.interpret_nominalizations(pct)
  if pct == 0 then
    return "✓ **No nominalizations detected** - direct, action-oriented writing"
  elseif pct < 3 then
    return "✓ **Very low nominalization usage** - excellent for grant writing"
  elseif pct < 5 then
    return "✓ **Low nominalization usage** - good for direct prose (target: <5%)"
  elseif pct < 8 then
    return "⚠ **Moderate nominalizations** - consider using direct verb forms (target: <5%)"
  else
    return "⚠ **High nominalizations** - makes writing wordy and abstract. Replace with direct verb forms."
  end
end

--- Interpret vocabulary richness (TTR)
--- @param ttr number Type-Token Ratio percentage
--- @return string Interpretation
function M.interpret_vocabulary_richness(ttr)
  if ttr < 40 then
    return "**Low vocabulary richness** - high word repetition. May indicate technical writing or need for more variety. (Target: Creative 60-80%, Grant 40-60%)"
  elseif ttr < 60 then
    return "**Medium vocabulary richness** - balanced repetition. Good for grant writing and technical documents."
  elseif ttr < 80 then
    return "**High vocabulary richness** - varied word choice. Excellent for creative writing."
  else
    return "**Very high vocabulary richness** - minimal repetition. May lack thematic coherence or be overly varied."
  end
end

--- Get nominalization to verb conversion suggestions
--- @return table Mapping of nominalizations to suggested verbs
function M.get_nominalization_suggestions()
  return {
    ["investigation"] = "investigate",
    ["implementation"] = "implement",
    ["utilization"] = "use",
    ["consideration"] = "consider",
    ["determination"] = "determine",
    ["exploration"] = "explore",
    ["application"] = "apply",
    ["examination"] = "examine",
    ["evaluation"] = "evaluate",
    ["observation"] = "observe",
    ["experimentation"] = "experiment",
    ["demonstration"] = "demonstrate",
    ["explanation"] = "explain",
    ["discussion"] = "discuss",
    ["conclusion"] = "conclude",
    ["recommendation"] = "recommend",
    ["development"] = "develop",
    ["improvement"] = "improve",
    ["establishment"] = "establish",
    ["assessment"] = "assess",
    ["achievement"] = "achieve",
    ["arrangement"] = "arrange",
    ["adjustment"] = "adjust",
    ["measurement"] = "measure",
    ["treatment"] = "treat",
    ["requirement"] = "require",
    ["management"] = "manage",
    ["movement"] = "move",
    ["placement"] = "place",
    ["replacement"] = "replace",
  }
end

-- Manual testing:
-- :lua local data = {basic = {words = 1000, chars = 5000}}; print(vim.inspect(require("writing-metrics.display").format_basic_section(data)))
-- :lua require("writing-metrics.display").create_report_buffer({"# Test", "", "This is a test report"}, {window_type = "tab"})

return M
