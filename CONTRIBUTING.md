# Contributing to nvim-writing-metrics

Thank you for your interest in contributing to nvim-writing-metrics! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [How to Contribute](#how-to-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Submitting Pull Requests](#submitting-pull-requests)
- [Development Workflow](#development-workflow)
- [Code Style Guidelines](#code-style-guidelines)
- [Testing Guidelines](#testing-guidelines)
- [Commit Message Conventions](#commit-message-conventions)
- [Documentation](#documentation)

## Code of Conduct

This project follows a simple code of conduct:

- Be respectful and inclusive
- Provide constructive feedback
- Focus on what is best for the community
- Show empathy towards other community members

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/your-username/nvim-writing-metrics.git
   cd nvim-writing-metrics
   ```
3. **Add upstream remote**:
   ```bash
   git remote add upstream https://github.com/jkeim/nvim-writing-metrics.git
   ```

## Development Setup

### Prerequisites

- Neovim >= 0.10
- Pandoc >= 2.19
- Git
- Basic understanding of Lua and Neovim plugin development

### Local Installation

For development, install the plugin locally using your plugin manager:

**Using lazy.nvim:**

```lua
{
  "nvim-writing-metrics",
  dir = "~/projects/nvim-writing-metrics",  -- Path to your local clone
  dependencies = { "folke/snacks.nvim" },
  opts = {},
}
```

**Manual setup:**

```bash
# Link plugin to Neovim's package path
mkdir -p ~/.local/share/nvim/site/pack/dev/start
ln -s ~/projects/nvim-writing-metrics ~/.local/share/nvim/site/pack/dev/start/
```

### Running Tests

```bash
# Run all tests
nvim --headless -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }" -c "quit"

# Run specific test file
nvim --headless -c "PlenaryBustedFile tests/metrics_spec.lua { minimal_init = 'tests/minimal_init.lua' }" -c "quit"
```

Or use the test runner script:

```bash
./run-tests.sh
```

## How to Contribute

### Reporting Bugs

Before submitting a bug report:

1. **Check existing issues** to avoid duplicates
2. **Update to the latest version** to see if the bug still exists
3. **Test with minimal configuration** to rule out conflicts

When creating a bug report, include:

- **Clear title** describing the issue
- **Steps to reproduce** the bug
- **Expected behavior** vs. actual behavior
- **Environment information**:
  - Neovim version (`:version`)
  - Plugin version/commit
  - OS and version
  - Pandoc version (`pandoc --version`)
- **Minimal configuration** to reproduce the issue
- **Error messages** or relevant log output
- **Screenshots or recordings** if applicable

**Example bug report:**

```markdown
## Bug: Word count shows 0 for LaTeX files

### Steps to Reproduce
1. Open a `.tex` file with content
2. Run `:WordCount`
3. Shows 0 words

### Expected Behavior
Should display accurate word count for LaTeX content

### Environment
- Neovim: 0.10.0
- Plugin: commit abc123
- OS: Arch Linux 6.17.4
- Pandoc: 3.1.2

### Minimal Config
[Attach minimal init.lua]
```

### Suggesting Features

Before suggesting a feature:

1. **Check existing issues** and discussions
2. **Consider if it fits the plugin's scope** (writing metrics and analysis)
3. **Think about implementation complexity** and maintenance burden

When suggesting a feature, include:

- **Clear use case** - Why is this feature needed?
- **Proposed behavior** - How should it work?
- **Alternative approaches** - Other ways to achieve the goal
- **Examples** - Code snippets or mockups if applicable

**Example feature request:**

```markdown
## Feature: Reading time estimation

### Use Case
Writers want to estimate how long it will take readers to consume their content.

### Proposed Behavior
- Calculate reading time based on word count (avg 200-250 wpm)
- Display in statusline or word count report
- Make reading speed configurable

### Configuration Example
```lua
opts = {
  reading_speed = 225,  -- words per minute
  show_reading_time = true,
}
```

### Alternatives
- Could use external script/tool
- Could be a separate plugin

### Additional Context
Common in content management systems (Medium, Substack, etc.)
```

### Submitting Pull Requests

1. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/my-feature
   # or
   git checkout -b fix/my-bugfix
   ```

2. **Make your changes** following the [code style guidelines](#code-style-guidelines)

3. **Write tests** for new functionality

4. **Update documentation** if needed (README, help docs, code comments)

5. **Test your changes**:
   ```bash
   ./run-tests.sh
   # Also test manually in Neovim
   ```

6. **Commit with clear messages** following [commit conventions](#commit-message-conventions)

7. **Push to your fork**:
   ```bash
   git push origin feature/my-feature
   ```

8. **Create a Pull Request** on GitHub with:
   - Clear title describing the change
   - Detailed description of what changed and why
   - Reference to related issues (if any)
   - Screenshots or demos for UI changes

## Development Workflow

### Branch Strategy

- `main` - Stable release branch
- `feature/*` - New features
- `fix/*` - Bug fixes
- `docs/*` - Documentation updates
- `refactor/*` - Code refactoring

### Making Changes

1. **Keep changes focused** - One feature/fix per PR
2. **Write clear code** - Readable > clever
3. **Add comments** for complex logic
4. **Test thoroughly** - Unit tests + manual testing
5. **Update docs** - Keep README and help docs in sync

### Updating Your Fork

Keep your fork up to date with upstream:

```bash
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

Rebase feature branches:

```bash
git checkout feature/my-feature
git rebase main
```

## Code Style Guidelines

### Lua Style

Follow the Neovim Lua style guide:

- **Indentation:** 2 spaces (no tabs)
- **Line length:** 100 characters max
- **Quotes:** Double quotes for strings
- **Naming:**
  - `snake_case` for variables and functions
  - `PascalCase` for modules/classes
  - `UPPER_CASE` for constants

**Example:**

```lua
-- Good
local function calculate_word_count(text)
  local words = vim.split(text, "%s+")
  return #words
end

-- Bad
local function CalculateWordCount(text)
    local Words = vim.split(text, "%s+")
    return #Words
end
```

### Code Organization

- **Separate concerns** - Each module has a clear responsibility
- **Avoid globals** - Use local variables and return tables
- **Error handling** - Use `pcall` for operations that might fail
- **Documentation** - Add comments for public functions

**Module structure:**

```lua
-- Module: lua/writing-metrics/calculator.lua

local M = {}

--- Calculate basic metrics for text
-- @param text string The text to analyze
-- @return table Metrics data { words = number, chars = number, ... }
function M.calculate(text)
  -- Implementation
end

return M
```

### Configuration Patterns

Use consistent patterns for user configuration:

```lua
local defaults = {
  cache_ttl_statusline = 500,
  enable_statusline = true,
}

local config = vim.tbl_deep_extend("force", defaults, opts or {})
```

## Testing Guidelines

### Test Structure

Tests use plenary.nvim's testing framework:

```lua
local eq = assert.are.same

describe("calculator", function()
  local calculator = require("writing-metrics.calculator")

  before_each(function()
    -- Setup
  end)

  after_each(function()
    -- Cleanup
  end)

  it("should count words correctly", function()
    local result = calculator.calculate("Hello world")
    eq(2, result.words)
  end)
end)
```

### What to Test

- **Core functionality** - Metrics calculation, caching, etc.
- **Edge cases** - Empty text, special characters, large files
- **Configuration** - Different options produce expected behavior
- **Error handling** - Graceful failures when Pandoc missing, etc.

### Test File Organization

```
tests/
   minimal_init.lua           # Minimal config for testing
   calculator_spec.lua        # Calculator module tests
   cache_spec.lua             # Cache system tests
   integration_spec.lua       # Integration tests
   fixtures/                  # Test data files
       sample.md
       large_file.txt
```

### Running Specific Tests

```bash
# All tests
./run-tests.sh

# Specific test file
nvim --headless -c "PlenaryBustedFile tests/calculator_spec.lua" -c "quit"

# Specific test suite
nvim --headless -c "lua require('plenary.test_harness').test_directory('tests/', { minimal_init = 'tests/minimal_init.lua' })" -c "quit"
```

## Commit Message Conventions

Follow conventional commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `style` - Code style changes (formatting, no logic change)
- `refactor` - Code refactoring (no feature change)
- `test` - Adding or updating tests
- `chore` - Maintenance tasks (dependencies, tooling)
- `perf` - Performance improvements

### Examples

```
feat(calculator): add passive voice detection

Implement passive voice detection using Pandoc filter.
Adds new 'passive_voice_count' and 'passive_voice_percent' fields to metrics.

Closes #42
```

```
fix(cache): prevent cache collision between buffers

Use buffer number in cache key to prevent different buffers
from sharing cached metrics.

Fixes #67
```

```
docs(readme): add troubleshooting section

Add common issues and solutions for Pandoc not found errors.
```

### Commit Best Practices

- **Write clear, descriptive messages** - Explain *what* and *why*
- **Keep commits focused** - One logical change per commit
- **Reference issues** - Use `Fixes #123` or `Closes #123`
- **Use present tense** - "Add feature" not "Added feature"

## Documentation

### What to Document

1. **Public API** - All public functions and modules
2. **Configuration options** - All user-facing settings
3. **Commands** - User-facing Vim commands
4. **Examples** - Common use cases and workflows
5. **Troubleshooting** - Known issues and solutions

### Documentation Files

- **README.md** - Overview, installation, usage, configuration
- **doc/writing-metrics.txt** - Vim help documentation
- **Code comments** - Inline documentation for developers
- **CHANGELOG.md** - Version history and changes

### Vim Help Documentation

Use proper Vim help tags:

```
*writing-metrics-config*

CONFIGURATION                                    *writing-metrics.config*

The plugin can be configured via the setup function:
>
    require("writing-metrics").setup({
      cache_ttl_statusline = 500,
    })
<
```

### Updating Documentation

When adding features:

1. Update README.md with usage examples
2. Add entry to doc/writing-metrics.txt
3. Add inline code comments
4. Update CHANGELOG.md

## Questions or Need Help?

- **Discussions:** Use GitHub Discussions for questions
- **Issues:** Use Issues for bug reports and feature requests
- **Email:** Contact maintainer at [email]

## Recognition

Contributors will be acknowledged in:

- CHANGELOG.md for significant contributions
- README.md acknowledgments section
- Git commit history (always preserved)

Thank you for contributing to nvim-writing-metrics!
