#!/bin/bash
# Test runner script for nvim-writing-metrics
# Usage: ./run-tests.sh [options]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
VERBOSE=0
SPECIFIC_TEST=""
MINIMAL_INIT="tests/minimal_init.lua"

# Help message
show_help() {
    cat << EOF
Usage: ./run-tests.sh [options]

Options:
    -h, --help              Show this help message
    -v, --verbose           Show verbose output
    -t, --test FILE         Run specific test file
    -a, --all               Run all tests (default)

Examples:
    ./run-tests.sh                          # Run all tests
    ./run-tests.sh -v                       # Run with verbose output
    ./run-tests.sh -t tests/cache_spec.lua  # Run specific test file

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -t|--test)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        -a|--all)
            SPECIFIC_TEST=""
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Check dependencies
echo -e "${BLUE}Checking dependencies...${NC}"

if ! command -v nvim &> /dev/null; then
    echo -e "${RED}Error: Neovim is not installed${NC}"
    exit 1
fi

if ! command -v pandoc &> /dev/null; then
    echo -e "${YELLOW}Warning: Pandoc is not installed. Some tests will be skipped.${NC}"
fi

echo -e "${GREEN}Neovim version:${NC}"
nvim --version | head -n 1

if command -v pandoc &> /dev/null; then
    echo -e "${GREEN}Pandoc version:${NC}"
    pandoc --version | head -n 1
fi

# Check if plenary.nvim is installed
PLENARY_PATH="/tmp/nvim-writing-metrics-test/site/pack/vendor/start/plenary.nvim"
if [ ! -d "$PLENARY_PATH" ]; then
    echo -e "${YELLOW}Installing plenary.nvim for testing...${NC}"
    mkdir -p "$(dirname "$PLENARY_PATH")"
    git clone --depth=1 https://github.com/nvim-lua/plenary.nvim "$PLENARY_PATH"
fi

echo ""
echo -e "${BLUE}Running tests...${NC}"
echo ""

# Run tests
if [ -n "$SPECIFIC_TEST" ]; then
    echo -e "${BLUE}Running specific test: $SPECIFIC_TEST${NC}"
    if [ ! -f "$SPECIFIC_TEST" ]; then
        echo -e "${RED}Error: Test file not found: $SPECIFIC_TEST${NC}"
        exit 1
    fi

    if [ $VERBOSE -eq 1 ]; then
        nvim --headless -u "$MINIMAL_INIT" \
            -c "lua require('plenary.test_harness').test_file('$SPECIFIC_TEST')" \
            -c "quit"
    else
        nvim --headless -u "$MINIMAL_INIT" \
            -c "PlenaryBustedFile $SPECIFIC_TEST" \
            -c "quit"
    fi
else
    echo -e "${BLUE}Running all tests in tests/ directory${NC}"

    if [ $VERBOSE -eq 1 ]; then
        nvim --headless -u "$MINIMAL_INIT" \
            -c "lua require('plenary.test_harness').test_directory('tests/', { minimal_init = './$MINIMAL_INIT' })" \
            -c "quit"
    else
        nvim --headless -u "$MINIMAL_INIT" \
            -c "PlenaryBustedDirectory tests/ { minimal_init = './$MINIMAL_INIT' }" \
            -c "quit"
    fi
fi

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo -e "${RED}Some tests failed (exit code: $EXIT_CODE)${NC}"
fi

exit $EXIT_CODE
