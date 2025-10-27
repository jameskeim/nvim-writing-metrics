# Testing Quick Reference - nvim-writing-metrics

## Run Tests

```bash
# All tests
./run-tests.sh

# Verbose output
./run-tests.sh -v

# Specific test file
./run-tests.sh -t tests/cache_spec.lua
```

## From Neovim

```vim
:PlenaryBustedDirectory tests/
:PlenaryBustedFile tests/cache_spec.lua
:PlenaryBustedFile %
```

## Test Files

| File                    | Purpose                    | Tests |
|-------------------------|----------------------------|-------|
| config_spec.lua         | Configuration & validation | 14    |
| cache_spec.lua          | Cache behavior & TTL       | 19    |
| basic_spec.lua          | Basic metrics              | 21    |
| full_spec.lua           | Full reports               | 17    |
| integration_spec.lua    | End-to-end workflows       | 16    |
| compatibility_spec.lua  | Backward compatibility     | 19    |

## Test Coverage

- **106 test cases** across 6 test files
- **45 test suites** (describe blocks)
- **1,749 lines** of test code (including helpers)
- **100% module coverage**

## Common Assertions

```lua
assert.equals(expected, actual)
assert.is_true(condition)
assert.is_not_nil(value)
assert.is_function(func)
assert.is_table(tbl)
```

## Helper Functions

```lua
helpers.create_test_buffer(content)
helpers.wait_for_async(fn, timeout_ms)
helpers.assert_metrics_structure(metrics, mode)
helpers.skip_without_pandoc()
helpers.cleanup_buffers()
```

## Test Documents

```lua
helpers.test_documents.simple        -- Two sentences
helpers.test_documents.complex       -- Multi-paragraph
helpers.test_documents.minimal       -- Single word
helpers.test_documents.empty         -- Empty string
helpers.test_documents.with_markdown -- Markdown formatting
```

## Performance Targets

| Operation        | Target  | Status |
|------------------|---------|--------|
| Fast word count  | < 10ms  | ✅     |
| Cached retrieval | < 50ms  | ✅     |
| Full metrics     | < 5 sec | ✅     |
| Total test suite | < 30s   | ✅     |

## CI/CD

- **Triggers:** Push to main/develop, PRs, manual
- **Matrix:** Ubuntu + macOS × stable + nightly = 4 runs
- **Jobs:** test, lint, documentation
- **Badge:** [![Tests](https://github.com/jameskeim/nvim-writing-metrics/workflows/Tests/badge.svg)](https://github.com/jameskeim/nvim-writing-metrics/actions)

## Documentation

- `tests/README.md` - Complete test guide
- `TEST_SUMMARY.md` - Detailed summary
- `TESTING_QUICK_REFERENCE.md` - This file

## Dependencies

- **Neovim** 0.9.0+
- **plenary.nvim** (auto-installed)
- **Pandoc** (optional, tests skip without it)
- **luacheck** (CI only)

## Troubleshooting

**Tests fail with "Pandoc not found":**
```bash
# Ubuntu
sudo apt-get install pandoc

# macOS
brew install pandoc
```

**Tests hang or timeout:**
- Increase timeout in `helpers.wait_for_async()`
- Check Pandoc installation

**Plenary not found:**
```bash
git clone https://github.com/nvim-lua/plenary.nvim \
  ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim
```

## Writing New Tests

```lua
describe("feature name", function()
  local module

  before_each(function()
    module = require("writing-metrics.module")
  end)

  after_each(function()
    helpers.cleanup_buffers()
  end)

  it("does something", function()
    assert.equals(expected, actual)
  end)
end)
```

## Test Philosophy

1. **Fast** - < 30 seconds total
2. **Isolated** - Independent tests
3. **Focused** - One thing per test
4. **Clear** - Descriptive names
5. **Maintainable** - Easy updates

---

**Full Documentation:** See `tests/README.md` and `TEST_SUMMARY.md`
