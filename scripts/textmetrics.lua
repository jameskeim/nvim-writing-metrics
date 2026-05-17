-- ═══════════════════════════════════════════════════════════════
-- UNIFIED PANDOC WRITING METRICS FILTER
-- ═══════════════════════════════════════════════════════════════
-- Combines functionality of textmetrics.lua (comprehensive analysis)
-- and wordcount.lua (fast basic counts) into a single dual-mode filter.
--
-- USAGE:
--
-- Mode 1: Basic (fast, space-separated output)
--   pandoc document.md --lua-filter=textmetrics.lua -M metrics=basic -t plain
--   Output: "1247 7892 87 42 65"  (words chars lines paragraphs sentences)
--
-- Mode 2: Full (comprehensive JSON analysis)
--   pandoc document.md --lua-filter=textmetrics.lua -M metrics=full -t plain
--   Output: {"basic": {...}, "readability": {...}, ...}
--
-- Default mode if -M metrics not specified: basic
--
-- FEATURES BY MODE:
--
-- Basic Mode:
--   - Fast word, character, line, paragraph, sentence counts
--   - Space-separated output compatible with wordcount.lua
--   - Excludes markup, counts clean prose only
--
-- Full Mode:
--   - All basic counts plus detailed analysis
--   - 6 readability formulas (Coleman-Liau, ARI, Flesch, F-K, Gunning Fog, SMOG)
--   - Sentence variability analysis (std dev, CV, distribution)
--   - Passive voice detection with examples
--   - Nominalization detection with suggestions
--   - Vocabulary richness (TTR, frequency analysis)
--   - Sentence beginning variety analysis
--   - AI-style word detection
--   - JSON output with structured data
--
-- PERFORMANCE:
--   - Basic mode skips expensive calculations (syllable counting, etc.)
--   - Full mode performs comprehensive analysis
--   - Both modes use same two-pass architecture (blocks, then inlines)
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- GLOBAL COUNTERS
-- ═══════════════════════════════════════════════════════════════

-- Basic counters (used in both modes)
words = 0
chars = 0
lines = 0
paragraphs = 0
sentences = 0
questions = 0  -- Question sentences (ending with ?)

-- Enhanced tracking for full mode only (populated conditionally)
sentence_lengths = {}  -- Array of sentence lengths in words
current_sentence_words = 0  -- Running count for current sentence
current_sentence_text = {}  -- Array of words in current sentence (for passive detection)
is_sentence_start = true  -- Track if next word is sentence beginning

-- Syllable and complexity tracking (full mode only)
total_syllables = 0
complex_words = 0  -- 3+ syllables (for Gunning Fog)
total_word_chars = 0  -- Letters only (for Coleman-Liau)

-- AI-style detection (full mode only)
ai_word_counts = {}  -- Frequency of AI-associated words

-- Passive voice detection (full mode only)
passive_sentences = 0
passive_examples = {}  -- Store example sentences (up to 10)

-- Nominalization detection (full mode only)
total_nominalizations = 0
nominalization_examples = {}  -- Store unique examples with frequency

-- Vocabulary richness tracking (full mode only)
unique_words = {}  -- Hash table: word -> frequency count

-- Sentence beginning analysis (full mode only)
sentence_beginnings = {
  pronoun = 0,
  article = 0,
  conjunction = 0,
  preposition = 0,
  adverb = 0,
  other = 0
}

-- Mode flag (set during Pandoc function, determines processing)
analysis_mode = "basic"  -- "basic" or "full"

-- ═══════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

-- Stopwords for frequency analysis (common function words to exclude)
local stopwords_list = {
  "the", "of", "and", "to", "a", "in", "is", "that", "for", "with",
  "as", "on", "by", "this", "an", "be", "are", "from", "or", "at",
  "it", "was", "will", "can", "has", "have", "had", "but", "not",
  "they", "we", "you", "he", "she", "i", "me", "my", "your", "his",
  "her", "their", "our", "which", "who", "what", "when", "where",
  "how", "why", "if", "than", "then", "so", "do", "does", "did",
  "been", "being", "would", "should", "could", "may", "might",
  "must", "shall", "these", "those", "there", "here", "were",
  "am", "its", "into", "through", "during", "before", "after",
  "above", "below", "between", "under", "again", "further",
  "once", "all", "any", "both", "each", "few", "more", "most",
  "other", "some", "such", "no", "nor", "only", "own", "same",
  "too", "very", "just", "now"
}

-- Convert stopwords to set for fast lookup
local stopwords = {}
for _, word in ipairs(stopwords_list) do
  stopwords[word] = true
end

-- Normalize word for vocabulary tracking
local function normalize_word(word)
  -- Convert to lowercase
  word = word:lower()

  -- Remove all non-alphabetic characters (punctuation, numbers)
  word = word:gsub("[^a-z]", "")

  return word
end

-- Check if word is a stopword
local function is_stopword(word)
  return stopwords[word] == true
end

-- Classify sentence beginning words (full mode only)
local pronouns = {
  "i", "we", "you", "he", "she", "it", "they",
  "this", "these", "that", "those", "my", "our",
  "your", "his", "her", "its", "their"
}

local articles = {
  "a", "an", "the"
}

local conjunctions = {
  "and", "but", "or", "nor", "for", "yet", "so",
  "although", "because", "since", "if", "when",
  "while", "unless", "until", "whether", "though"
}

local prepositions = {
  "in", "on", "at", "to", "from", "with", "by",
  "about", "for", "through", "during", "before",
  "after", "above", "below", "between", "under",
  "over", "of", "into", "onto", "upon", "within"
}

local adverbs = {
  "however", "therefore", "thus", "moreover",
  "furthermore", "additionally", "finally",
  "consequently", "nevertheless", "nonetheless",
  "meanwhile", "instead", "otherwise", "similarly",
  "conversely", "indeed", "certainly", "perhaps"
}

-- Convert word lists to sets for fast lookup
local pronoun_set = {}
for _, word in ipairs(pronouns) do
  pronoun_set[word] = true
end

local article_set = {}
for _, word in ipairs(articles) do
  article_set[word] = true
end

local conjunction_set = {}
for _, word in ipairs(conjunctions) do
  conjunction_set[word] = true
end

local preposition_set = {}
for _, word in ipairs(prepositions) do
  preposition_set[word] = true
end

local adverb_set = {}
for _, word in ipairs(adverbs) do
  adverb_set[word] = true
end

-- Classify sentence beginning based on first word (full mode only)
local function classify_beginning(first_word)
  -- Normalize: lowercase and remove punctuation
  first_word = first_word:lower():gsub("[^a-z]", "")

  if #first_word == 0 then
    return "other"
  end

  if pronoun_set[first_word] then
    return "pronoun"
  elseif article_set[first_word] then
    return "article"
  elseif conjunction_set[first_word] then
    return "conjunction"
  elseif preposition_set[first_word] then
    return "preposition"
  elseif adverb_set[first_word] then
    return "adverb"
  else
    return "other"
  end
end

-- Syllable counting using vowel-group heuristic (~85% accuracy)
-- Only used in full mode
local function count_syllables(word)
  word = word:lower()

  -- Remove non-letters
  word = word:gsub("[^a-z]", "")

  if #word == 0 then return 0 end
  if #word <= 3 then return 1 end

  -- Count vowel groups
  local count = 0
  local previous_was_vowel = false

  for i = 1, #word do
    local char = word:sub(i, i)
    local is_vowel = char:match("[aeiouy]")

    if is_vowel and not previous_was_vowel then
      count = count + 1
    end

    previous_was_vowel = is_vowel
  end

  -- Adjust for silent 'e'
  if word:sub(-1) == "e" then
    count = count - 1
  end

  -- Minimum 1 syllable
  return math.max(count, 1)
end

-- Detect complex words (3+ syllables, for Gunning Fog)
-- Only used in full mode
-- is_sent_start: true when the word opens a sentence (capitalized for syntactic reasons,
-- not because it is a proper noun).
local function is_complex(word, syllables, is_sent_start)
  -- 3+ syllables = complex
  if syllables < 3 then return false end

  -- Exclude proper nouns (capitalized), but NOT sentence-initial words.
  -- Sentence-initial words are capitalized by convention; they are not necessarily names.
  if word:match("^%u") and not is_sent_start then return false end

  -- Exclude common suffixes that add syllables but not complexity
  if word:match("ed$") or word:match("es$") or word:match("ing$") then
    -- Recount without suffix
    local base = word:gsub("ed$", ""):gsub("es$", ""):gsub("ing$", "")
    if count_syllables(base) < 3 then return false end
  end

  return true
end

-- AI-associated words (Tier 1 - most notorious)
-- Only used in full mode
local ai_words = {
  "delve", "delves", "delving",
  "tapestry",
  "landscape", "landscapes",
  "realm", "realms",
  "navigate", "navigates", "navigating",
  "leverage", "leverages", "leveraging",
  "elevate", "elevates", "elevating",
  "foster", "fosters", "fostering",
  "showcase", "showcases", "showcasing",
  "embark", "embarks", "embarking",
  "unleash", "unleashes", "unleashing",
  "vibrant",
  "pivotal",
  "meticulous",
  "multifaceted",
  "intriguing",
}

-- Check if word is AI-associated (full mode only)
local function is_ai_word(word)
  word = word:lower():gsub("[^a-z]", "")
  for _, ai_word in ipairs(ai_words) do
    if word == ai_word then
      return ai_word
    end
  end
  return nil
end

-- Check if word is a nominalization (full mode only)
-- Nominalizations are abstract nouns formed from verbs (e.g., "investigation" from "investigate")
-- Common suffixes: -tion, -sion, -ment, -ance, -ence, -ness, -ity, etc.
local nominalization_suffixes = {
  "tion", "sion", "ment", "ance", "ence", "ancy", "ency",
  "ness", "ity", "ship", "dom", "hood", "age", "al", "ure"
}

-- Words that look like nominalizations but aren't (or are acceptable)
local nominalization_whitelist = {
  -- Common words ending in -al
  "trial", "final", "signal", "material", "general", "personal", "national",
  "local", "global", "clinical", "medical", "social", "mental", "physical",
  "initial", "total", "visual", "oral", "moral", "rural", "vital",
  "actual", "equal", "legal", "normal", "real", "special", "typical",
  "central", "federal", "natural", "neutral", "virtual", "essential",
  "traditional", "individual", "professional", "potential", "original",

  -- Common words ending in -tion/-sion
  "question", "version", "session", "mission", "fashion", "passion",

  -- Common words ending in -ment
  "moment", "segment", "element", "comment", "implement", "compliment",
  "supplement", "instrument", "document", "monument", "regiment", "fragment",

  -- Common words ending in -age
  "image", "message", "language", "damage", "usage", "package", "passage",
  "storage", "village", "average", "engage", "courage",

  -- Information/communication words (often acceptable)
  "information", "communication", "education", "publication",

  -- Other acceptable terms
  "position", "condition", "situation", "organization", "population",
  "relation", "function", "section", "direction", "action", "reaction",
  "attention", "intention", "dimension", "tension", "mention",
}

-- Convert whitelist to set for fast lookup
local whitelist_set = {}
for _, word in ipairs(nominalization_whitelist) do
  whitelist_set[word] = true
end

local function is_nominalization(word)
  word = word:lower():gsub("[^a-z]", "")

  -- Minimum length: 5 characters (avoid false positives like "it", "al")
  if #word < 5 then return false end

  -- Check whitelist first
  if whitelist_set[word] then return false end

  -- Check for nominalization suffixes
  for _, suffix in ipairs(nominalization_suffixes) do
    if word:sub(-#suffix) == suffix then
      return true, word  -- Return cleaned word for tracking
    end
  end

  return false
end

-- ═══════════════════════════════════════════════════════════════
-- PASSIVE VOICE DETECTION (Full Mode Only)
-- ═══════════════════════════════════════════════════════════════

-- Check if word is a "to be" verb
local function is_to_be(word)
  word = word:lower():gsub("[^a-z]", "")
  local to_be_verbs = {
    "is", "are", "was", "were", "been", "be", "being", "am"
  }
  for _, verb in ipairs(to_be_verbs) do
    if word == verb then
      return true
    end
  end
  return false
end

-- Check if word is a past participle
-- Uses simple heuristics: -ed, -en endings, or common irregular forms
local function is_past_participle(word)
  word = word:lower():gsub("[^a-z]", "")

  -- Too short to be a participle
  if #word < 3 then return false end

  -- Regular past participles (-ed)
  if word:match("ed$") then return true end

  -- Past participles ending in -en
  if word:match("en$") then return true end

  -- Common irregular past participles
  local irregular_participles = {
    "made", "done", "gone", "seen", "given", "taken", "written", "known",
    "shown", "drawn", "driven", "thrown", "broken", "spoken", "chosen",
    "frozen", "stolen", "hidden", "bitten", "forgotten", "proven",
    "brought", "bought", "taught", "caught", "thought", "fought",
    "told", "sold", "held", "built", "sent", "spent", "lent", "meant",
    "kept", "slept", "swept", "felt", "left", "lost", "found", "bound",
    "understood", "heard", "said", "paid", "laid", "read", "led", "fed",
    "met", "let", "set", "bet", "cut", "put", "hurt", "shut", "spread",
    "become", "come", "run", "begun", "sung", "rung", "drunk", "sunk",
    "shrunk", "swum", "hung"
  }

  for _, participle in ipairs(irregular_participles) do
    if word == participle then
      return true
    end
  end

  return false
end

-- Detect passive voice in a sentence (word array)
-- Returns true if "to be" + past participle pattern is found
local function detect_passive_voice(sentence_words)
  -- Need at least 2 words for passive construction
  if #sentence_words < 2 then return false end

  -- Look for "to be" verb followed by past participle (within 2 words)
  for i = 1, #sentence_words - 1 do
    if is_to_be(sentence_words[i]) then
      -- Check next word
      if is_past_participle(sentence_words[i + 1]) then
        return true
      end
      -- Check word after next (for constructions like "is being done")
      if i < #sentence_words - 1 and is_past_participle(sentence_words[i + 2]) then
        return true
      end
    end
  end

  return false
end

-- ═══════════════════════════════════════════════════════════════
-- READABILITY CALCULATION FUNCTIONS (Full Mode Only)
-- ═══════════════════════════════════════════════════════════════

local function calculate_coleman_liau(words, sentences, total_word_chars)
  if words == 0 or sentences == 0 then return 0 end
  local L = (total_word_chars / words) * 100  -- avg letters per 100 words
  local S = (sentences / words) * 100  -- avg sentences per 100 words
  return 0.0588 * L - 0.296 * S - 15.8
end

local function calculate_ari(chars, words, sentences)
  if words == 0 or sentences == 0 then return 0 end
  return 4.71 * (chars / words) + 0.5 * (words / sentences) - 21.43
end

local function calculate_flesch_reading_ease(words, sentences, syllables)
  if words == 0 or sentences == 0 then return 0 end
  return 206.835 - 1.015 * (words / sentences) - 84.6 * (syllables / words)
end

local function calculate_flesch_kincaid(words, sentences, syllables)
  if words == 0 or sentences == 0 then return 0 end
  return 0.39 * (words / sentences) + 11.8 * (syllables / words) - 15.59
end

local function calculate_gunning_fog(words, sentences, complex_words)
  if words == 0 or sentences == 0 then return 0 end
  return 0.4 * ((words / sentences) + 100 * (complex_words / words))
end

local function calculate_smog(complex_words, sentences)
  if sentences == 0 then return 0 end
  return 1.0430 * math.sqrt(complex_words * (30 / sentences)) + 3.1291
end

-- ═══════════════════════════════════════════════════════════════
-- SENTENCE LENGTH THRESHOLD ANALYSIS (Full Mode Only)
-- ═══════════════════════════════════════════════════════════════

-- Context-specific thresholds for sentence length
local thresholds = {
  grant = {
    short = 8,  -- Grant writing: avoid choppy sentences < 8 words
    long = 25   -- Grant writing: avoid run-on sentences > 25 words
  },
  creative = {
    short = 5,  -- Creative writing: more flexibility for impact
    long = 35   -- Creative writing: allow longer flowing sentences
  },
  technical = {
    short = 10, -- Technical writing: avoid oversimplification
    long = 30   -- Technical writing: balance clarity with detail
  },
  default = {
    short = 8,
    long = 25
  }
}

local function analyze_sentence_lengths(sentence_lengths, context)
  context = context or "default"
  local threshold = thresholds[context] or thresholds.default

  if #sentence_lengths == 0 then
    return {
      short_count = 0,
      short_pct = 0,
      long_count = 0,
      long_pct = 0,
      threshold = threshold
    }
  end

  -- Count sentences outside thresholds
  local short_count = 0
  local long_count = 0

  for _, len in ipairs(sentence_lengths) do
    if len < threshold.short then
      short_count = short_count + 1
    elseif len > threshold.long then
      long_count = long_count + 1
    end
  end

  -- Calculate percentages
  local total = #sentence_lengths
  local short_pct = (short_count / total) * 100
  local long_pct = (long_count / total) * 100

  return {
    short_count = short_count,
    short_pct = short_pct,
    long_count = long_count,
    long_pct = long_pct,
    threshold = threshold
  }
end

-- ═══════════════════════════════════════════════════════════════
-- VARIABILITY ANALYSIS (Full Mode Only)
-- ═══════════════════════════════════════════════════════════════

local function calculate_variability(sentence_lengths)
  if #sentence_lengths == 0 then
    return {
      mean = 0,
      std_dev = 0,
      cv = 0,
      min = 0,
      max = 0,
      range = 0,
      distribution = {
        ["1-5"] = 0,
        ["6-10"] = 0,
        ["11-20"] = 0,
        ["21-30"] = 0,
        ["31+"] = 0
      },
      patterns = {}
    }
  end

  -- Calculate mean
  local sum = 0
  for _, len in ipairs(sentence_lengths) do
    sum = sum + len
  end
  local mean = sum / #sentence_lengths

  -- Calculate standard deviation
  local sum_squared = 0
  for _, len in ipairs(sentence_lengths) do
    sum_squared = sum_squared + (len - mean) ^ 2
  end
  local variance = sum_squared / #sentence_lengths
  local std_dev = math.sqrt(variance)

  -- Calculate coefficient of variation
  local cv = mean > 0 and (std_dev / mean) * 100 or 0

  -- Calculate min/max/range
  local min = sentence_lengths[1]
  local max = sentence_lengths[1]
  for _, len in ipairs(sentence_lengths) do
    if len < min then min = len end
    if len > max then max = len end
  end
  local range = max - min

  -- Calculate distribution
  local distribution = {
    ["1-5"] = 0,
    ["6-10"] = 0,
    ["11-20"] = 0,
    ["21-30"] = 0,
    ["31+"] = 0
  }
  for _, len in ipairs(sentence_lengths) do
    if len <= 5 then
      distribution["1-5"] = distribution["1-5"] + 1
    elseif len <= 10 then
      distribution["6-10"] = distribution["6-10"] + 1
    elseif len <= 20 then
      distribution["11-20"] = distribution["11-20"] + 1
    elseif len <= 30 then
      distribution["21-30"] = distribution["21-30"] + 1
    else
      distribution["31+"] = distribution["31+"] + 1
    end
  end

  -- Detect monotonous patterns (4+ consecutive sentences within ±3 words)
  local patterns = {}
  local pattern_start = nil
  local pattern_count = 0
  local pattern_min = nil
  local pattern_max = nil

  for i = 2, #sentence_lengths do
    local diff = math.abs(sentence_lengths[i] - sentence_lengths[i-1])
    if diff <= 3 then
      if pattern_start == nil then
        pattern_start = i - 1
        pattern_min = math.min(sentence_lengths[i-1], sentence_lengths[i])
        pattern_max = math.max(sentence_lengths[i-1], sentence_lengths[i])
      end
      pattern_count = pattern_count + 1
      pattern_min = math.min(pattern_min, sentence_lengths[i])
      pattern_max = math.max(pattern_max, sentence_lengths[i])
    else
      if pattern_count >= 3 then  -- 4+ sentences
        table.insert(patterns, {
          start_sentence = pattern_start,
          end_sentence = pattern_start + pattern_count,
          count = pattern_count + 1,
          min_length = pattern_min,
          max_length = pattern_max,
          avg_length = (pattern_min + pattern_max) / 2
        })
      end
      pattern_start = nil
      pattern_count = 0
    end
  end

  -- Check if last pattern should be recorded
  if pattern_count >= 3 then
    table.insert(patterns, {
      start_sentence = pattern_start,
      end_sentence = pattern_start + pattern_count,
      count = pattern_count + 1,
      min_length = pattern_min,
      max_length = pattern_max,
      avg_length = (pattern_min + pattern_max) / 2
    })
  end

  return {
    mean = mean,
    std_dev = std_dev,
    cv = cv,
    min = min,
    max = max,
    range = range,
    distribution = distribution,
    patterns = patterns
  }
end

-- ═══════════════════════════════════════════════════════════════
-- ABBREVIATION / DECIMAL HELPERS
-- ═══════════════════════════════════════════════════════════════

-- Common English abbreviations that contain '.' but do not end sentences.
-- Compared case-insensitively against the token text with trailing punctuation stripped.
local ABBREVIATIONS = {
  ["dr"] = true, ["mr"] = true, ["mrs"] = true, ["ms"] = true, ["jr"] = true, ["sr"] = true,
  ["e.g"] = true, ["i.e"] = true, ["etc"] = true, ["vs"] = true, ["cf"] = true,
  ["st"] = true, ["mt"] = true, ["fig"] = true, ["no"] = true, ["vol"] = true,
  ["ed"] = true, ["eds"] = true, ["op"] = true, ["pp"] = true, ["ch"] = true,
  ["u.s"] = true, ["u.s.a"] = true, ["u.k"] = true, ["a.m"] = true, ["p.m"] = true,
  ["ph.d"] = true, ["m.d"] = true, ["b.a"] = true, ["m.a"] = true,
}

-- Returns true if the token text (with optional surrounding punctuation) appears to be
-- a known abbreviation, not a true sentence terminator.
local function is_abbreviation(text)
  -- Strip trailing punctuation/whitespace; lowercase for case-insensitive match.
  local cleaned = text:gsub("[%s%.,;:!%?]+$", ""):lower()
  return ABBREVIATIONS[cleaned] == true
end

-- Returns true if the token is a decimal-bearing number like "3.14" or "$3.14"
-- where the trailing '.' is the decimal point itself, not a sentence boundary.
-- Tokens like "$4.20." end with a real sentence-period after the decimal, so they
-- should NOT be suppressed — return false in that case.
local function is_decimal_number(text)
  -- Must contain a decimal pattern (digit.digit)
  if not text:match("%d+%.%d+") then
    return false
  end
  -- If the token ends with digit(s), the trailing '.' in the match IS the decimal.
  -- e.g. "3.14" or "$3.14" → true (no extra trailing period).
  -- If the token ends in '.' after digits, that could be a sentence terminator.
  -- e.g. "$4.20." → the final '.' is a sentence-end period, not the decimal dot.
  -- Distinguish: after stripping the last '.', check if the result still has digit.digit.
  local stripped = text:gsub("%.$", "")  -- remove one trailing period if present
  if stripped == text then
    -- No trailing period was present; the match is purely a decimal number.
    return true
  else
    -- There WAS a trailing period. If the stripped form still ends in digits
    -- that are part of a decimal (e.g. "4.20" in "$4.20"), this '.' is a
    -- sentence terminator following a decimal number — do NOT suppress.
    return false
  end
end

-- ═══════════════════════════════════════════════════════════════
-- ELEMENT HANDLERS (INLINE)
-- ═══════════════════════════════════════════════════════════════

wordcount = {
  Str = function(el)
    -- Count words that aren't purely punctuation (both modes)
    if el.text:match("%P") then
      words = words + 1

      -- Full mode: additional tracking
      if analysis_mode == "full" then
        current_sentence_words = current_sentence_words + 1

        -- Capture sentence-start flag BEFORE clearing it so is_complex can use it.
        -- is_sentence_start is true for the first content token of each sentence;
        -- those tokens are capitalised for syntactic (not proper-noun) reasons.
        local word_is_sentence_start = is_sentence_start

        -- Track sentence beginning
        if is_sentence_start then
          local category = classify_beginning(el.text)
          sentence_beginnings[category] = sentence_beginnings[category] + 1
          is_sentence_start = false
        end

        -- Collect word for passive voice detection
        -- Remove trailing punctuation for word analysis
        local clean_word = el.text:gsub("[.!?,;:]$", "")
        table.insert(current_sentence_text, clean_word)

        -- Enhanced tracking for readability
        local syllables = count_syllables(el.text)
        total_syllables = total_syllables + syllables

        if is_complex(el.text, syllables, word_is_sentence_start) then
          complex_words = complex_words + 1
        end

        -- Count letters only (for Coleman-Liau)
        local letters = el.text:gsub("[^%a]", "")
        total_word_chars = total_word_chars + #letters

        -- Check for AI-associated words
        local ai_word = is_ai_word(el.text)
        if ai_word then
          ai_word_counts[ai_word] = (ai_word_counts[ai_word] or 0) + 1
        end

        -- Check for nominalizations
        local is_nom, clean_word = is_nominalization(el.text)
        if is_nom then
          total_nominalizations = total_nominalizations + 1

          -- Track unique examples with frequency (store up to 15)
          if nominalization_examples[clean_word] then
            nominalization_examples[clean_word] = nominalization_examples[clean_word] + 1
          else
            -- Count how many unique examples we have
            local unique_count = 0
            for _ in pairs(nominalization_examples) do
              unique_count = unique_count + 1
            end

            -- Only add if we have room
            if unique_count < 15 then
              nominalization_examples[clean_word] = 1
            end
          end
        end

        -- Track vocabulary richness
        local normalized = normalize_word(el.text)
        if #normalized > 0 then  -- Only count actual words
          unique_words[normalized] = (unique_words[normalized] or 0) + 1
        end
      end
    end

    -- Count all characters in text nodes (both modes)
    chars = chars + #el.text

    -- Count sentences: look for sentence-ending punctuation at end of string (both modes).
    -- Guard against abbreviations (Dr., Mr., e.g.) and decimal numbers (3.14, $4.20)
    -- which would otherwise falsely increment the sentence counter.
    if el.text:match("[.!?]%s*$")
       and not is_abbreviation(el.text)
       and not is_decimal_number(el.text) then
      sentences = sentences + 1

      -- Detect questions (sentences ending with ?)
      if el.text:match("%?%s*$") then
        questions = questions + 1
      end

      -- Full mode: passive voice and sentence length tracking
      if analysis_mode == "full" then
        -- Check for passive voice in this sentence
        if #current_sentence_text > 0 and detect_passive_voice(current_sentence_text) then
          passive_sentences = passive_sentences + 1

          -- Store example sentence (up to 10)
          if #passive_examples < 10 then
            local sentence_text = table.concat(current_sentence_text, " ")
            table.insert(passive_examples, sentence_text)
          end
        end

        -- Record sentence length for variability analysis
        if current_sentence_words > 0 then
          table.insert(sentence_lengths, current_sentence_words)
        end
        current_sentence_words = 0
        current_sentence_text = {}  -- Reset for next sentence
        is_sentence_start = true  -- Next word will be sentence beginning
      end
    end
  end,

  Space = function(el)
    -- Count spaces between words (both modes)
    chars = chars + 1
  end,

  Code = function(el)
    -- Inline code is markup, not prose. Skip word/char/syllable counting.
    return el
  end,

  CodeBlock = function(el)
    -- Code blocks are not prose; exclude from readability denominators.
    return el
  end,

  SoftBreak = function(el)
    -- Soft line breaks (poetry lines, wrapped text) (both modes)
    chars = chars + 1
    lines = lines + 1
  end,

  LineBreak = function(el)
    -- Hard line breaks (both modes)
    chars = chars + 1
    lines = lines + 1
  end,
}

-- ═══════════════════════════════════════════════════════════════
-- ELEMENT HANDLERS (BLOCK)
-- ═══════════════════════════════════════════════════════════════

blockcounter = {
  Para = function(el)
    -- Regular paragraphs (both modes)
    paragraphs = paragraphs + 1
    lines = lines + 1  -- Each paragraph is at least one line
    return el  -- Continue walking child elements
  end,

  Header = function(el)
    -- Headings count as structural paragraph units (both modes)
    paragraphs = paragraphs + 1
    lines = lines + 1
    return el
  end,

  BlockQuote = function(el)
    -- Block quotes contain paragraphs, don't double-count (both modes)
    return el  -- Walk will count Para inside
  end,

  BulletList = function(el)
    -- Each list item is like a mini-paragraph (both modes)
    for i,item in ipairs(el.content) do
      paragraphs = paragraphs + 1
      lines = lines + 1
    end
    return el
  end,

  OrderedList = function(el)
    -- Same as bullet list (both modes)
    for i,item in ipairs(el.content) do
      paragraphs = paragraphs + 1
      lines = lines + 1
    end
    return el
  end,

  HorizontalRule = function(el)
    -- Horizontal rules create a visual line (both modes)
    lines = lines + 1
    return el
  end,
}

-- ═══════════════════════════════════════════════════════════════
-- MAIN PANDOC FUNCTION
-- ═══════════════════════════════════════════════════════════════

function Pandoc(el)
  -- Determine processing mode from metadata
  analysis_mode = "basic"  -- Default
  if el.meta and (el.meta.metrics_mode or el.meta.metrics) then
    analysis_mode = pandoc.utils.stringify(el.meta.metrics_mode or el.meta.metrics)
  end

  -- Validate mode (if invalid, default to basic)
  if analysis_mode ~= "basic" and analysis_mode ~= "full" then
    analysis_mode = "basic"
  end

  -- First pass: count block-level elements
  el.blocks:walk(blockcounter)

  -- Second pass: count inline elements (words, chars, sentences)
  -- Processing is mode-aware inside wordcount.Str handler
  el.blocks:walk(wordcount)

  -- ═══════════════════════════════════════════════════════════════
  -- OUTPUT GENERATION
  -- ═══════════════════════════════════════════════════════════════

  if analysis_mode == "basic" then
    -- Basic mode: space-separated output
    -- Format: "words chars sentences paragraphs avg_sentence_len avg_word_len"
    -- Example: "1247 7892 65 42 19.18 6.33"
    local avg_sentence_len = sentences > 0 and (words / sentences) or 0
    local avg_word_len = words > 0 and (chars / words) or 0
    print(words .. " " .. chars .. " " .. sentences .. " " .. paragraphs .. " " .. avg_sentence_len .. " " .. avg_word_len)

  elseif analysis_mode == "full" then
    -- Full mode: comprehensive JSON output

    -- Calculate readability formulas
    local readability = {
      coleman_liau = calculate_coleman_liau(words, sentences, total_word_chars),
      automated_readability = calculate_ari(chars, words, sentences),
      flesch_reading_ease = calculate_flesch_reading_ease(words, sentences, total_syllables),
      flesch_kincaid_grade = calculate_flesch_kincaid(words, sentences, total_syllables),
      gunning_fog = calculate_gunning_fog(words, sentences, complex_words),
      smog = calculate_smog(complex_words, sentences),
      complex_words = complex_words
    }

    -- Calculate sentence variability
    local variability = calculate_variability(sentence_lengths)

    -- Detect context from metadata (default to "default")
    local context = "default"
    if el.meta and el.meta.writing_context then
      context = pandoc.utils.stringify(el.meta.writing_context)
    end

    local length_analysis = analyze_sentence_lengths(sentence_lengths, context)

    -- Calculate vocabulary richness metrics
    local unique_count = 0
    for _ in pairs(unique_words) do
      unique_count = unique_count + 1
    end

    local ttr = words > 0 and (unique_count / words * 100) or 0

    -- Build frequency list (exclude stopwords, sort by frequency)
    local frequency_list = {}
    for word, count in pairs(unique_words) do
      if not is_stopword(word) and #word > 2 then  -- Exclude stopwords and very short words
        table.insert(frequency_list, { word = word, count = count })
      end
    end

    -- Sort by frequency (descending)
    table.sort(frequency_list, function(a, b)
      return a.count > b.count
    end)

    -- Keep only top 15
    local top_frequent = {}
    for i = 1, math.min(15, #frequency_list) do
      table.insert(top_frequent, frequency_list[i])
    end

    -- Calculate sentence beginning percentages
    local total_beginnings = 0
    for _, count in pairs(sentence_beginnings) do
      total_beginnings = total_beginnings + count
    end

    local beginning_analysis = {
      pronoun = {
        count = sentence_beginnings.pronoun,
        percentage = total_beginnings > 0 and (sentence_beginnings.pronoun / total_beginnings * 100) or 0
      },
      article = {
        count = sentence_beginnings.article,
        percentage = total_beginnings > 0 and (sentence_beginnings.article / total_beginnings * 100) or 0
      },
      conjunction = {
        count = sentence_beginnings.conjunction,
        percentage = total_beginnings > 0 and (sentence_beginnings.conjunction / total_beginnings * 100) or 0
      },
      preposition = {
        count = sentence_beginnings.preposition,
        percentage = total_beginnings > 0 and (sentence_beginnings.preposition / total_beginnings * 100) or 0
      },
      adverb = {
        count = sentence_beginnings.adverb,
        percentage = total_beginnings > 0 and (sentence_beginnings.adverb / total_beginnings * 100) or 0
      },
      other = {
        count = sentence_beginnings.other,
        percentage = total_beginnings > 0 and (sentence_beginnings.other / total_beginnings * 100) or 0
      }
    }

    -- Build JSON output
    local json = require("pandoc.json")
    local output = {
      basic = {
        words = words,
        characters = chars,
        sentences = sentences,
        paragraphs = paragraphs,
        lines = lines,
        avg_words_per_sentence = sentences > 0 and (words / sentences) or 0,
        avg_words_per_paragraph = paragraphs > 0 and (words / paragraphs) or 0,
        avg_chars_per_word = words > 0 and (chars / words) or 0
      },
      readability = readability,
      variability = variability,
      sentence_length_analysis = length_analysis,
      sentence_variety = {
        beginnings = beginning_analysis
      },
      sentence_types = {
        questions = questions,
        question_percentage = sentences > 0 and (questions / sentences * 100) or 0
      },
      passive_voice = {
        count = passive_sentences,
        percentage = sentences > 0 and (passive_sentences / sentences * 100) or 0,
        examples = passive_examples
      },
      nominalizations = {
        count = total_nominalizations,
        percentage = words > 0 and (total_nominalizations / words * 100) or 0,
        examples = nominalization_examples
      },
      vocabulary = {
        total_words = words,
        unique_words = unique_count,
        ttr = ttr,
        most_frequent = top_frequent
      },
      ai_style = {
        word_counts = ai_word_counts
      },
      metadata = {
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        mode = "full",
        context = context
      }
    }

    print(json.encode(output))
  end

  os.exit(0)
end

-- ═══════════════════════════════════════════════════════════════
-- EXAMPLE OUTPUTS
-- ═══════════════════════════════════════════════════════════════
--
-- BASIC MODE (metrics=basic):
-- $ pandoc document.md --lua-filter=textmetrics.lua -M metrics=basic -t plain
-- Output: "1247 7892 87 42 65"
-- Fields: words chars lines paragraphs sentences
--
-- FULL MODE (metrics=full):
-- $ pandoc document.md --lua-filter=textmetrics.lua -M metrics=full -t plain
-- Output: {
--   "basic": {
--     "words": 1247,
--     "characters": 7892,
--     "sentences": 65,
--     "paragraphs": 42,
--     "lines": 87,
--     "avg_words_per_sentence": 19.18,
--     "avg_words_per_paragraph": 29.69,
--     "avg_chars_per_word": 6.33
--   },
--   "readability": {
--     "coleman_liau": 10.5,
--     "automated_readability": 11.2,
--     "flesch_reading_ease": 62.3,
--     "flesch_kincaid_grade": 10.1,
--     "gunning_fog": 12.4,
--     "smog": 11.8
--   },
--   "variability": {
--     "mean": 19.18,
--     "std_dev": 7.42,
--     "cv": 38.7,
--     "min": 5,
--     "max": 38,
--     "range": 33,
--     "distribution": {
--       "1-5": 3,
--       "6-10": 8,
--       "11-20": 35,
--       "21-30": 15,
--       "31+": 4
--     },
--     "patterns": [
--       {
--         "start_sentence": 12,
--         "end_sentence": 17,
--         "count": 6,
--         "min_length": 18,
--         "max_length": 21,
--         "avg_length": 19.5
--       }
--     ]
--   },
--   "passive_voice": {
--     "count": 8,
--     "percentage": 12.3,
--     "examples": [
--       "The study was conducted by researchers",
--       "Data were collected from participants"
--     ]
--   },
--   "vocabulary": {
--     "total_words": 1247,
--     "unique_words": 487,
--     "ttr": 39.1,
--     "most_frequent": [
--       {"word": "research", "count": 23},
--       {"word": "analysis", "count": 18}
--     ]
--   },
--   "ai_style": {
--     "word_counts": {
--       "delve": 2,
--       "leverage": 3
--     }
--   },
--   "metadata": {
--     "timestamp": "2025-10-25T12:34:56Z",
--     "mode": "full",
--     "context": "grant"
--   }
-- }
--
-- EDGE CASES HANDLED:
-- - Empty documents (all counters return 0)
-- - Documents without sentences (readability formulas return 0)
-- - Code blocks (counted but not analyzed for readability)
-- - YAML frontmatter (ignored by Pandoc's AST parser)
-- - Poetry/line breaks (counted but don't affect sentence counts)
-- - Invalid mode parameter (defaults to basic)
-- - Documents without metadata (defaults to basic mode)
-- ═══════════════════════════════════════════════════════════════
