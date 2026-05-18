# Changelog

All notable changes to nvim-writing-metrics will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `config.get()` — public accessor on the config module returning the live
  merged configuration table. Internal modules now route reads through this
  accessor instead of reading `config.config` directly.
- Reading time estimation derived from the cached word count, with two
  configurable profiles (silent, default 200 wpm; spoken, default 150 wpm).
  Surfaces in three places:
  - statusline suffix appended to the existing word/char display
    (`⏱`/`🎤`, profile-selectable via `reading_time.statusline_profile`)
  - `:ReadingTime` toast showing both profiles at once
  - Two rows in the Basic Statistics section of `:ReadabilityReport`
- `reading_time` config block (5 keys: `enabled`, `wpm_silent`, `wpm_spoken`,
  `statusline`, `statusline_profile`)
- `basic.get_reading_time(bufnr)` public API for callers that want the
  pre-formatted reading-time table
- Initial plugin implementation
- Basic metrics calculation (word, character, sentence, paragraph counts)
- Six readability formulas:
  - Coleman-Liau Index
  - Automated Readability Index (ARI)
  - Flesch Reading Ease
  - Flesch-Kincaid Grade Level
  - Gunning Fog Index
  - SMOG Index
- Advanced analysis features:
  - Passive voice detection
  - Nominalization detection
  - Vocabulary richness analysis
  - Sentence variety analysis with monotonous pattern detection
  - AI-style detection (80+ AI-associated words)
- Intelligent two-tier caching system:
  - 500ms cache for statusline updates
  - 30-second cache for full reports
- Async execution to prevent UI blocking
- Pandoc Lua filter integration for accurate text analysis
- Statusline integration with lualine/heirline examples
- User commands:
  - `:WordCount` - Show basic metrics in floating window
  - `:ReadabilityReport` - Comprehensive analysis in new tab
  - `:WritingMetricsToggle` - Toggle fast/accurate mode
  - `:WritingMetricsCache` - Cache management
- Configuration system with sensible defaults
- Target threshold support for different writing contexts:
  - Grant writing
  - Creative writing
  - Academic writing
- File type support: markdown, text, tex, org, asciidoc
- Comprehensive documentation:
  - README with installation, usage, and configuration
  - CONTRIBUTING guidelines
  - Vim help documentation (doc/writing-metrics.txt)
- Test suite with plenary.nvim

### Changed
- `filter.custom_path` config key renamed to `filter.path`. The previous name
  was undocumented and only appeared inside `config.lua`; users who set
  `filter.custom_path` via `setup({ filter = { custom_path = ... } })` will
  silently lose their override after this release and should rename it to
  `filter.path`. No deprecation shim is provided.
- `filter.auto_detect = false` now has real semantics. Previously a no-op,
  it now means "trust `filter.path` even if the file is not readable; do not
  fall back to the search chain." Combined with `filter.path = nil`, an
  explicit `auto_detect = false` returns an error from dependency validation
  (the user opted out of auto-detect but provided no path).

### Removed
- `cache.basic_ttl` config option and `cache.is_valid()` function — both
  obsoleted by the changedtick-based cache validation introduced earlier.
  The `cache = {}` block can be removed from user setup() calls. Passing
  it is harmless (deep-merge ignores unknown keys), but the value has no
  effect since validation no longer uses TTL.

### Dependencies
- Neovim >= 0.10
- Pandoc >= 2.19
- snacks.nvim >= 2.0

## [1.0.0] - TBD

First stable release.

### Added
- Feature-complete writing metrics and readability analysis
- Comprehensive test coverage
- Full documentation
- CI/CD pipeline for automated testing

### Changed
- Performance optimizations based on user feedback
- Improved error handling and user messaging

### Fixed
- Various bug fixes discovered during beta testing

## [0.1.0] - TBD

Initial alpha release for testing and feedback.

### Added
- Core functionality for metrics calculation
- Basic caching system
- Simple UI commands

### Known Issues
- Performance may degrade on very large files (>50,000 words)
- Some edge cases in sentence detection may be inaccurate
- Limited error messages when Pandoc is misconfigured

---

## Version History Notes

### Unreleased
Changes in the main branch that haven't been released yet.

### 1.0.0 (Planned)
First stable release with:
- Complete feature set
- Comprehensive testing
- Production-ready performance
- Full documentation

### 0.1.0 (Planned)
Alpha release for early testing and feedback collection.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting bugs, suggesting features, and submitting pull requests.

## Links

- [Repository](https://github.com/jameskeim/nvim-writing-metrics)
- [Issues](https://github.com/jameskeim/nvim-writing-metrics/issues)
- [Discussions](https://github.com/jameskeim/nvim-writing-metrics/discussions)
