#!/usr/bin/env bash

# Minecraft 1.21.10 Protocol Fix Script
# This script automatically finds and applies the correct protocol version
# for connecting to Minecraft 1.21.10 servers

set -euo pipefail

# Configuration
GOMC_DIR="./go-mc-local"
GOMC_REPO="https://github.com/Tnze/go-mc.git"
SERVER_ADDR="100.94.216.120:25565"
PROTOCOL_FILE=".protocol-version"
GOMOD_BACKUP="go.mod.backup"
MCBOT_FILE="$GOMC_DIR/bot/mcbot.go"
BUILD_TIMEOUT=60
CONNECT_TIMEOUT=6
TEST_LOG="protocol-test.log"

# Protocol versions to test (in order of likelihood for 1.21.10)
PROTOCOL_VERSIONS=(768 769 770 771 766)

# Colors and emojis for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse command line arguments
FORCE_MODE=false
CLEAN_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --clean)
            CLEAN_MODE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force    Redo tests even if .protocol-version exists"
            echo "  --clean    Remove go-mc-local, .protocol-version, and restore go.mod.backup"
            echo "  --help     Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Logging helper functions
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

step() {
    echo -e "${CYAN}📦 $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Display header
echo "🔧 Minecraft 1.21.10 Protocol Fix Script"
echo "========================================"
echo ""

# Handle --clean mode
if [ "$CLEAN_MODE" = true ]; then
    step "Cleaning up protocol fix files..."
    
    # Remove go-mc-local directory
    if [ -d "$GOMC_DIR" ]; then
        rm -rf "$GOMC_DIR"
        success "Removed $GOMC_DIR"
    fi
    
    # Remove .protocol-version file
    if [ -f "$PROTOCOL_FILE" ]; then
        rm -f "$PROTOCOL_FILE"
        success "Removed $PROTOCOL_FILE"
    fi
    
    # Restore go.mod.backup if it exists
    if [ -f "$GOMOD_BACKUP" ]; then
        cp "$GOMOD_BACKUP" go.mod
        success "Restored go.mod from backup"
    fi
    
    # Remove test log
    if [ -f "$TEST_LOG" ]; then
        rm -f "$TEST_LOG"
        success "Removed $TEST_LOG"
    fi
    
    # Remove minecraft-bot binary
    if [ -f "minecraft-bot" ]; then
        rm -f "minecraft-bot"
        success "Removed minecraft-bot binary"
    fi
    
    echo ""
    success "Cleanup complete!"
    exit 0
fi

# Sanity checks
step "Running sanity checks..."

# Check if go is installed
if ! command -v go &> /dev/null; then
    error "Go is not installed. Please install Go first."
    exit 1
fi
success "Go is installed: $(go version)"

# Check if main.go exists in repository root
if [ ! -f "main.go" ]; then
    error "main.go not found in repository root"
    exit 1
fi
success "main.go found in repository root"

echo ""

# Check if already fixed (skip if --force)
if [ -f "$PROTOCOL_FILE" ] && [ "$FORCE_MODE" = false ]; then
    SAVED_PROTOCOL=$(cat "$PROTOCOL_FILE")
    info "Protocol version $SAVED_PROTOCOL was previously discovered"
    echo ""
    success "Already fixed! Use --force to redo tests or --clean to reset"
    echo ""
    echo "To run your bot with protocol version $SAVED_PROTOCOL:"
    echo "  ./minecraft-bot"
    echo ""
    exit 0
fi

if [ "$FORCE_MODE" = true ]; then
    warn "Force mode enabled - redoing protocol tests"
    echo ""
fi

# Step 1: Clone or update go-mc library
step "Checking go-mc library..."

if [ -d "$GOMC_DIR" ]; then
    info "go-mc library already exists at $GOMC_DIR"
    info "Using existing clone"
else
    info "Cloning go-mc library locally..."
    if git clone "$GOMC_REPO" "$GOMC_DIR" > /dev/null 2>&1; then
        success "Cloned successfully"
    else
        error "Failed to clone go-mc library"
        exit 1
    fi
fi

# Verify mcbot.go exists
if [ ! -f "$MCBOT_FILE" ]; then
    error "Cannot find $MCBOT_FILE"
    exit 1
fi
success "Found $MCBOT_FILE"

echo ""

# Step 2: Backup go.mod (only if backup doesn't exist)
if [ ! -f "$GOMOD_BACKUP" ]; then
    step "Backing up go.mod..."
    cp go.mod "$GOMOD_BACKUP"
    success "Backup created at $GOMOD_BACKUP"
    echo ""
else
    info "go.mod backup already exists, skipping"
    echo ""
fi

# Step 3: Add replace directive to go.mod if not already present (idempotent)
step "Configuring go.mod..."
if ! grep -q "replace github.com/Tnze/go-mc" go.mod; then
    echo "" >> go.mod
    echo "replace github.com/Tnze/go-mc => ./go-mc-local" >> go.mod
    success "Added replace directive to go.mod"
else
    info "Replace directive already exists in go.mod"
fi

echo ""

# Step 4: Test each protocol version
step "Testing protocol versions..."
echo ""
info "Will test protocols in order: ${PROTOCOL_VERSIONS[*]}"
echo ""

# Initialize test log
echo "Protocol Version Test Log - $(date)" > "$TEST_LOG"
echo "======================================" >> "$TEST_LOG"
echo "" >> "$TEST_LOG"

WORKING_PROTOCOL=""

for PROTOCOL in "${PROTOCOL_VERSIONS[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔍 Testing protocol version $PROTOCOL..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Log protocol test header
    echo "Testing Protocol $PROTOCOL" >> "$TEST_LOG"
    echo "------------------------" >> "$TEST_LOG"
    
    # Create a backup of original mcbot.go first time
    if [ ! -f "$MCBOT_FILE.original" ]; then
        cp "$MCBOT_FILE" "$MCBOT_FILE.original"
    fi
    
    # Restore from original before each modification
    cp "$MCBOT_FILE.original" "$MCBOT_FILE"
    
    # Modify mcbot.go to set the protocol version
    info "Patching ProtocolVersion to $PROTOCOL..."
    
    # Find and replace the ProtocolVersion line using sed
    # Capture original line for validation
    ORIGINAL_LINE=$(grep -E '^\s*ProtocolVersion\s*=\s*[0-9]+' "$MCBOT_FILE" || echo "")
    
    if [ -n "$ORIGINAL_LINE" ]; then
        # Replace existing ProtocolVersion (only the numeric value)
        sed -i "s/\(ProtocolVersion[[:space:]]*=[[:space:]]*\)[0-9]\+/\1$PROTOCOL/" "$MCBOT_FILE"
        success "Patched: ProtocolVersion = $PROTOCOL"
    else
        error "ProtocolVersion constant not found in $MCBOT_FILE"
        echo "Failed: ProtocolVersion constant not found" >> "$TEST_LOG"
        echo "" >> "$TEST_LOG"
        continue
    fi
    
    # Run go mod tidy
    info "Running go mod tidy..."
    if ! go mod tidy 2>&1 | tee -a "$TEST_LOG"; then
        error "go mod tidy failed"
        echo "" >> "$TEST_LOG"
        continue
    fi
    success "go mod tidy completed"
    
    # Build the bot
    info "Building bot binary..."
    BUILD_OUTPUT=$(go build -o minecraft-bot main.go 2>&1)
    BUILD_EXIT_CODE=$?
    
    echo "$BUILD_OUTPUT" >> "$TEST_LOG"
    
    if [ $BUILD_EXIT_CODE -ne 0 ]; then
        error "Build failed with protocol $PROTOCOL"
        echo "Build failed with exit code $BUILD_EXIT_CODE" >> "$TEST_LOG"
        echo "" >> "$TEST_LOG"
        continue
    fi
    
    if [ ! -f "minecraft-bot" ]; then
        error "Build failed - binary not created"
        echo "Binary not created" >> "$TEST_LOG"
        echo "" >> "$TEST_LOG"
        continue
    fi
    
    success "Build successful"
    
    # Test connection
    info "Testing connection to server (${CONNECT_TIMEOUT}s timeout)..."
    
    # Run bot with timeout and capture output
    TEMP_BOT_LOG=$(mktemp)
    
    # Use timeout command with the bot
    timeout $CONNECT_TIMEOUT ./minecraft-bot > "$TEMP_BOT_LOG" 2>&1 || true
    
    # Append bot output to test log
    cat "$TEMP_BOT_LOG" >> "$TEST_LOG"
    
    # Check the output for success indicators
    if grep -q "Successfully connected to server\|Game started" "$TEMP_BOT_LOG"; then
        success "SUCCESS! Connected with protocol $PROTOCOL"
        WORKING_PROTOCOL=$PROTOCOL
        echo "SUCCESS with protocol $PROTOCOL" >> "$TEST_LOG"
        rm -f "$TEMP_BOT_LOG"
        break
    elif grep -q "Incompatible client" "$TEMP_BOT_LOG"; then
        error "Failed: Incompatible client"
        echo "Failed: Incompatible client" >> "$TEST_LOG"
    elif grep -q "Failed to join server" "$TEMP_BOT_LOG"; then
        error "Failed: Connection error"
        echo "Failed: Connection error" >> "$TEST_LOG"
    else
        warn "Unknown result - check logs"
        echo "Unknown result" >> "$TEST_LOG"
    fi
    
    rm -f "$TEMP_BOT_LOG"
    echo "" >> "$TEST_LOG"
    echo ""
done

# Clean up temporary files
info "Cleaning up temporary files..."
rm -f "$MCBOT_FILE.original"

# Step 5: Report results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -n "$WORKING_PROTOCOL" ]; then
    success "Fixed! Your bot now works with Minecraft 1.21.10"
    echo ""
    echo "📋 Working Protocol Version: $WORKING_PROTOCOL"
    echo ""
    
    # Save the working protocol version
    echo "$WORKING_PROTOCOL" > "$PROTOCOL_FILE"
    success "Saved to $PROTOCOL_FILE"
    
    echo ""
    echo "📝 To run your bot:"
    echo "   ./minecraft-bot"
    echo ""
    echo "📝 To view the discovered protocol version:"
    echo "   cat $PROTOCOL_FILE"
    echo ""
    info "The go-mc library has been patched locally in $GOMC_DIR"
    info "Your go.mod now uses this local version via replace directive"
    info "Full test log saved to $TEST_LOG"
    echo ""
    success "Done! ✅"
    exit 0
else
    error "Could not find a working protocol version"
    echo ""
    info "Tried protocol versions: ${PROTOCOL_VERSIONS[*]}"
    info "Full test log saved to $TEST_LOG"
    echo ""
    
    warn "Restoring original state..."
    
    # Restore original mcbot.go
    if [ -f "$MCBOT_FILE.original" ]; then
        mv "$MCBOT_FILE.original" "$MCBOT_FILE"
        info "Restored original mcbot.go"
    fi
    
    # Note: We don't restore go.mod.backup automatically here
    # because the user might want to keep the replace directive
    # for manual protocol testing
    
    echo ""
    error "Troubleshooting suggestions:"
    echo "   1. Check if the server is running at $SERVER_ADDR"
    echo "   2. Verify you can connect to the server with the official client"
    echo "   3. Check the test log for details: cat $TEST_LOG"
    echo "   4. Try manual protocol version adjustment in $MCBOT_FILE"
    echo "   5. Use --clean to reset and start over"
    echo ""
    exit 1
fi
