# Changelog

All notable changes to nvim-writing-metrics will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
