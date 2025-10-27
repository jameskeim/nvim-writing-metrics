# Unified Pandoc Writing Metrics Filter

## Overview

Single Lua filter combining fast basic counts (wordcount.lua) and comprehensive analysis (textmetrics.lua) with dual-mode operation.

## Installation

Place `textmetrics.lua` in a directory accessible to Pandoc.

## Usage

### Basic Mode (Default)

Fast word count with space-separated output:

```bash
pandoc document.md --lua-filter=textmetrics.lua -M metrics=basic -t plain
# Output: "1247 7892 87 42 65"
# Fields: words chars lines paragraphs sentences
```

Or without metadata flag (defaults to basic):

```bash
pandoc document.md --lua-filter=textmetrics.lua -t plain
```

### Full Mode

Comprehensive JSON analysis:

```bash
pandoc document.md --lua-filter=textmetrics.lua -M metrics=full -t plain
```

Output includes:
- Basic counts (words, chars, sentences, paragraphs, lines)
- 6 readability formulas (Coleman-Liau, ARI, Flesch, Flesch-Kincaid, Gunning Fog, SMOG)
- Sentence variability (std dev, CV, distribution, monotony detection)
- Passive voice detection with examples
- Nominalization detection with frequency
- Vocabulary richness (TTR, top words)
- Sentence beginning variety analysis
- AI-style word detection
- Metadata (timestamp, mode, context)

### Context-Specific Analysis

Specify writing context for tailored thresholds:

```bash
pandoc document.md --lua-filter=textmetrics.lua -M metrics=full -M writing_context=grant -t plain
```

Contexts: `grant`, `creative`, `technical`, `default`

## Output Formats

### Basic Mode
```
1247 7892 87 42 65
```

### Full Mode
```json
{
  "basic": {
    "words": 1247,
    "characters": 7892,
    "sentences": 65,
    "paragraphs": 42,
    "lines": 87,
    "avg_words_per_sentence": 19.18,
    "avg_words_per_paragraph": 29.69,
    "avg_chars_per_word": 6.33
  },
  "readability": {
    "coleman_liau": 10.5,
    "automated_readability": 11.2,
    "flesch_reading_ease": 62.3,
    "flesch_kincaid_grade": 10.1,
    "gunning_fog": 12.4,
    "smog": 11.8
  },
  "variability": { ... },
  "passive_voice": { ... },
  "vocabulary": { ... },
  "ai_style": { ... }
}
```

## Performance

- **Basic mode**: O(n) single pass, minimal processing
- **Full mode**: O(n) with syllable counting, passive detection
- Both modes use same two-pass architecture (blocks → inlines)
- Basic mode skips expensive calculations for speed

## Edge Cases Handled

- Empty documents (returns zeros)
- Documents without sentences (readability = 0)
- Code blocks (counted, not analyzed)
- YAML frontmatter (ignored automatically)
- Poetry/line breaks (counted separately)
- Invalid mode parameter (defaults to basic)

## Testing

```bash
# Test basic mode
echo "This is a test. Another sentence." | pandoc --lua-filter=textmetrics.lua -M metrics=basic -t plain

# Test full mode with pipe to jq for formatting
pandoc document.md --lua-filter=textmetrics.lua -M metrics=full -t plain | jq '.'

# Extract specific metrics
pandoc document.md --lua-filter=textmetrics.lua -M metrics=full -t plain | jq '.readability'
```

## Backward Compatibility

Basic mode output format is 100% compatible with wordcount.lua:
- Same field order: words chars lines paragraphs sentences
- Same space-separated format
- Same counting methodology

## Integration Examples

### Shell Scripts
```bash
# Get just word count
WORDS=$(pandoc doc.md --lua-filter=textmetrics.lua -M metrics=basic -t plain | awk '{print $1}')

# Get readability score
FLESCH=$(pandoc doc.md --lua-filter=textmetrics.lua -M metrics=full -t plain | jq -r '.readability.flesch_reading_ease')
```

### Neovim (Lua)
```lua
local output = vim.fn.system({
  'pandoc',
  '--lua-filter=' .. filter_path,
  '-M', 'metrics=full',
  '-t', 'plain'
}, buffer_content)

local data = vim.fn.json_decode(output)
print("Words:", data.basic.words)
print("Readability:", data.readability.flesch_reading_ease)
```

## Author

Unified filter created from:
- textmetrics.lua (comprehensive analysis, 981 lines)
- wordcount.lua (basic counts, 128 lines)

Combined: 1109 lines with dual-mode operation
