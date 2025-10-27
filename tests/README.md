# nvim-writing-metrics Test Suite

Comprehensive test suite for the nvim-writing-metrics plugin using plenary.nvim's test harness.

## Test Structure

```
tests/
├── README.md                 # This file
├── minimal_init.lua          # Minimal Neovim config for testing
├── helpers.lua               # Shared test utilities and fixtures
├── config_spec.lua           # Configuration and validation tests
├── cache_spec.lua            # Cache behavior tests
├── basic_spec.lua            # Basic metrics tests
├── full_spec.lua             # Full report tests
├── integration_spec.lua      # End-to-end integration tests
└── compatibility_spec.lua    # Backward compatibility tests
```

## Running Tests

### Local Testing

**Run all tests:**
```bash
./run-tests.sh
```

**Run with verbose output:**
```bash
./run-tests.sh -v
```

**Run specific test file:**
```bash
./run-tests.sh -t tests/cache_spec.lua
```

### From Neovim

**Run all tests:**
```vim
:PlenaryBustedDirectory tests/
```

**Run specific test file:**
```vim
:PlenaryBustedFile tests/cache_spec.lua
```

**Run current test file:**
```vim
:PlenaryBustedFile %
```

## Test Coverage

### config_spec.lua
- Module loading
- Default configuration
- User configuration merging
- Dependency validation (Pandoc)
- Filter path detection

### cache_spec.lua
- Basic metrics caching
- Full metrics caching
- TTL expiration
- Cache invalidation
- Cache statistics
- Edge cases (invalid buffers, nil data)

### basic_spec.lua
- Fast word count
- Accurate word count (with Pandoc)
- Statusline integration
- Mode toggling (fast/accurate)
- Lualine component
- Markdown syntax stripping
- Cache behavior
- Edge cases (empty buffer, whitespace-only)

### full_spec.lua
- JSON parsing
- Full metrics generation
- Readability metrics (all 6 formulas)
- Sentence variability
- AI style detection
- Report display
- Cache behavior
- Error handling

### integration_spec.lua
- Plugin setup
- Full workflow: buffer → metrics → cache → display
- Basic metrics end-to-end
- Full metrics end-to-end
- Cache persistence
- Command registration
- Error handling
- Performance tests

### compatibility_spec.lua
- Global function exports (`_G.accurate_wordcount`, `_G.text_metrics`)
- Legacy command registration
- Lualine component compatibility
- API stability
- Configuration compatibility
- Display function compatibility

## Test Helpers

The `helpers.lua` file provides:

### Functions
- `create_test_buffer(content)` - Creates test buffer with markdown filetype
- `wait_for_async(condition_fn, timeout_ms)` - Waits for async operations
- `wait(ms)` - Simple delay
- `assert_metrics_structure(metrics, mode)` - Validates metrics structure
- `skip_without_pandoc()` - Skips test if Pandoc not installed
- `cleanup_buffers()` - Cleans up test buffers

### Test Documents
- `simple` - Simple two-sentence text
- `complex` - Multi-paragraph document with sections
- `minimal` - Single word
- `empty` - Empty string
- `with_markdown` - Text with markdown formatting

### Mock Data
- `mock_pandoc_basic` - Sample basic metrics output
- `mock_pandoc_full` - Sample full metrics JSON

## CI/CD

Tests run automatically via GitHub Actions on:
- Push to `main` or `develop` branches
- Pull requests to `main`
- Manual workflow dispatch

### Test Matrix
- **OS**: Ubuntu, macOS
- **Neovim**: stable, nightly

### Additional CI Jobs
- **Lint**: Runs luacheck on Lua code
- **Documentation**: Validates README and filter file existence

## Dependencies

### Required
- **Neovim** (0.9.0+)
- **plenary.nvim** - Test framework
- **Pandoc** - For accurate metrics (tests skip if not available)

### Optional
- **luacheck** - For linting (CI only)

## Writing New Tests

### Test Structure
```lua
describe("module name", function()
  local module

  before_each(function()
    -- Setup before each test
    module = require("writing-metrics.module")
  end)

  after_each(function()
    -- Cleanup after each test
    helpers.cleanup_buffers()
  end)

  describe("feature group", function()
    it("does something specific", function()
      -- Test code
      assert.equals(expected, actual)
    end)
  end)
end)
```

### Common Assertions
```lua
assert.equals(expected, actual)        -- Value equality
assert.is_true(condition)              -- Boolean true
assert.is_false(condition)             -- Boolean false
assert.is_not_nil(value)               -- Not nil
assert.is_nil(value)                   -- Is nil
assert.is_function(func)               -- Is function
assert.is_table(tbl)                   -- Is table
assert.is_number(num)                  -- Is number
assert.is_string(str)                  -- Is string
assert.truthy(value)                   -- Truthy value
assert.are_not.equals(val1, val2)      -- Not equal
```

### Async Testing
```lua
it("handles async operation", function()
  local done = false
  local result = nil

  module.async_function(function(data)
    done = true
    result = data
  end)

  -- Wait for callback
  local success = helpers.wait_for_async(function()
    return done
  end, 3000)

  assert.is_true(success, "Callback should be called")
  assert.is_not_nil(result)
end)
```

### Skipping Tests
```lua
it("requires Pandoc", function()
  helpers.skip_without_pandoc()

  -- Test code that requires Pandoc
end)
```

## Performance Expectations

- **Fast word count**: < 10ms
- **Cached retrieval**: < 50ms
- **Full metrics**: < 5 seconds (with Pandoc)
- **Total test suite**: < 30 seconds

## Troubleshooting

### Tests fail with "Pandoc not found"
Install Pandoc:
```bash
# Ubuntu
sudo apt-get install pandoc

# macOS
brew install pandoc

# Arch
sudo pacman -S pandoc
```

### Tests hang or timeout
- Increase timeout in `helpers.wait_for_async()`
- Check for infinite loops in callbacks
- Verify Pandoc is responding

### Plenary.nvim not found
Install manually:
```bash
git clone https://github.com/nvim-lua/plenary.nvim \
  ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim
```

### Buffer cleanup issues
- Ensure `after_each()` calls `helpers.cleanup_buffers()`
- Check for buffers with modified state

## Test Philosophy

1. **Fast**: Tests should run quickly (< 30 seconds total)
2. **Isolated**: Each test is independent
3. **Focused**: Test one thing per `it()` block
4. **Clear**: Test names describe what they verify
5. **Maintainable**: Easy to update when code changes
6. **Comprehensive**: Cover happy path, edge cases, and errors

## Contributing Tests

When adding new features:
1. Write tests first (TDD)
2. Test happy path
3. Test edge cases
4. Test error handling
5. Update this README if needed

## Test Metrics

Current coverage (approximate):
- **6 test files**
- **100+ test cases**
- **Core modules**: 100% covered
- **Edge cases**: Comprehensive
- **Async operations**: Full coverage
- **Backward compatibility**: Complete
