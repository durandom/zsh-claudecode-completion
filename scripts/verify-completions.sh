#!/bin/bash
#
# Verification script for zsh completion script
#
# Tests that the _claude completion script can be loaded and executed
# without errors. Uses expect to simulate tab completion in an interactive
# zsh session, which catches _arguments parsing errors that static checks miss.
#
# Exit codes:
#   0 - Verification passed
#   1 - Verification failed (completion errors detected)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPLETION_FILE="$REPO_ROOT/_claude"

# Check dependencies
if ! command -v expect &> /dev/null; then
    echo "Error: 'expect' is required but not installed"
    echo "Install with: brew install expect (macOS) or apt-get install expect (Linux)"
    exit 1
fi

if ! command -v zsh &> /dev/null; then
    echo "Error: 'zsh' is required but not installed"
    exit 1
fi

if [[ ! -f "$COMPLETION_FILE" ]]; then
    echo "Error: Completion file not found: $COMPLETION_FILE"
    exit 1
fi

echo "Verifying completion script: $COMPLETION_FILE"

# Test 1: Static syntax check
echo "  [1/2] Running static syntax check..."
SYNTAX_OUTPUT=$(zsh -n "$COMPLETION_FILE" 2>&1) || {
    echo ""
    echo "VERIFICATION FAILED"
    echo "==================="
    echo "Static syntax check failed:"
    echo "$SYNTAX_OUTPUT"
    exit 1
}

# Test 2: Interactive completion test using expect
echo "  [2/2] Testing interactive completion..."

# Create a temporary directory for our test zsh configuration
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Create a minimal .zshrc that loads our completion
cat > "$TMPDIR/.zshrc" << ZSHRC
fpath=($REPO_ROOT \$fpath)
autoload -Uz compinit && compinit -u -d /dev/null
autoload -Uz _claude && compdef _claude claude
PS1='TEST> '
ZSHRC

# Run expect to test completion
OUTPUT_FILE="$TMPDIR/output.txt"
ZSHRC_FILE="$TMPDIR/.zshrc"

# Temporarily disable exit on error for expect
set +e
expect << EXPECT_SCRIPT > "$OUTPUT_FILE" 2>&1
set timeout 10
set env(HOME) "$TMPDIR"

# Use zsh -f to skip ALL rc files (avoids system compinit prompts on Ubuntu)
# Then manually source our test configuration
spawn zsh -f

# Wait for basic prompt
expect {
    -re {%|>|\$} {}
    timeout { puts "TIMEOUT: waiting for initial prompt"; exit 1 }
    eof { puts "EOF: zsh exited unexpectedly"; exit 1 }
}

# Source our test configuration
send "source $ZSHRC_FILE\r"

# Wait for our custom prompt
expect {
    "TEST>" {}
    -re "insecure directories" {
        # Handle compinit security prompt if it appears
        send "y\r"
        exp_continue
    }
    timeout { puts "TIMEOUT: waiting for TEST> prompt"; exit 1 }
    eof { puts "EOF: zsh exited unexpectedly"; exit 1 }
}

# Test: Trigger completion for 'claude --'
send "claude --\t"
sleep 0.5

expect {
    -re "invalid option definition" {
        puts "ERROR: invalid option definition detected"
        exit 1
    }
    -re "_arguments:.*:.*:" {
        puts "ERROR: _arguments error detected"
        exit 1
    }
    "TEST>" {}
    timeout {}
}

send "exit\r"
expect eof

puts "COMPLETION_TEST_PASSED"
exit 0
EXPECT_SCRIPT

EXPECT_EXIT=$?
set -e

# Check results
if [[ $EXPECT_EXIT -ne 0 ]]; then
    echo ""
    echo "VERIFICATION FAILED"
    echo "==================="
    echo "Interactive completion test failed"
    echo ""
    echo "Output:"
    cat "$OUTPUT_FILE"
    exit 1
fi

if grep -q "invalid option definition" "$OUTPUT_FILE"; then
    echo ""
    echo "VERIFICATION FAILED"
    echo "==================="
    echo "Invalid option definition error detected:"
    echo ""
    cat "$OUTPUT_FILE"
    exit 1
fi

if grep -q "ERROR:" "$OUTPUT_FILE"; then
    echo ""
    echo "VERIFICATION FAILED"
    echo "==================="
    echo "Completion errors detected:"
    echo ""
    cat "$OUTPUT_FILE"
    exit 1
fi

if ! grep -q "COMPLETION_TEST_PASSED" "$OUTPUT_FILE"; then
    echo ""
    echo "VERIFICATION FAILED"
    echo "==================="
    echo "Completion test did not complete successfully"
    echo ""
    echo "Output:"
    cat "$OUTPUT_FILE"
    exit 1
fi

echo ""
echo "VERIFICATION PASSED"
echo "==================="
echo "Completion script validated successfully"
exit 0
