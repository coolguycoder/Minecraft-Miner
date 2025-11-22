#!/usr/bin/env bash

# Minecraft 1.21.10 Protocol Fix Script with Modded Server Support
# This script automatically finds and applies the correct protocol version
# for connecting to Minecraft 1.21.10 servers (Fabric, Forge, and Vanilla)

set -euo pipefail

# Configuration
GOMC_DIR="./go-mc-local"
GOMC_REPO="https://github.com/Tnze/go-mc.git"
SERVER_ADDR="100.94.216.120:25565"
PROTOCOL_FILE=".protocol-version"
PROTOCOL_ATTEMPTS=".protocol-attempts"
GOMOD_BACKUP="go.mod.backup"
MCBOT_FILE="$GOMC_DIR/bot/mcbot.go"
BUILD_TIMEOUT=60
CONNECT_TIMEOUT=6
TEST_LOG="protocol-test.log"
PING_TOOL="tools/ping-status.go"

# Default protocol versions to test (fallback if ping fails)
DEFAULT_PROTOCOL_VERSIONS=(768 769 770 771 766)

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
VERBOSE_MODE=false
FABRIC_MODE=false
FORGE_MODE=false
RANGE_START=""
RANGE_END=""
REPORTED_PROTOCOL=""
MODDED_TYPE="unknown"

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
        --verbose)
            VERBOSE_MODE=true
            shift
            ;;
        --fabric)
            FABRIC_MODE=true
            shift
            ;;
        --forge)
            FORGE_MODE=true
            shift
            ;;
        --range)
            if [[ $# -lt 2 ]]; then
                echo "Error: --range requires START-END argument (e.g., --range 760-800)"
                exit 1
            fi
            shift
            IFS='-' read -r RANGE_START RANGE_END <<< "$1"
            if [[ ! "$RANGE_START" =~ ^[0-9]+$ ]] || [[ ! "$RANGE_END" =~ ^[0-9]+$ ]]; then
                echo "Error: --range requires numeric START-END values (e.g., --range 760-800)"
                exit 1
            fi
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force           Redo tests even if .protocol-version exists"
            echo "  --clean           Remove go-mc-local, .protocol-version, and restore go.mod.backup"
            echo "  --verbose         Show detailed output during testing"
            echo "  --fabric          Force Fabric mode (no Forge handshake)"
            echo "  --forge           Force Forge mode (experimental - FML handshake not implemented)"
            echo "  --range START-END Override protocol candidate range (e.g., --range 760-800)"
            echo "  --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                      # Auto-detect protocol and test"
            echo "  $0 --verbose            # Show detailed output"
            echo "  $0 --range 760-800      # Test specific protocol range"
            echo "  $0 --fabric             # Force Fabric mode"
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

# Cleanup function for temporary files
cleanup() {
    if [ -f "$MCBOT_FILE.original" ]; then
        rm -f "$MCBOT_FILE.original"
    fi
}

# Set up trap to cleanup on exit
trap cleanup EXIT INT TERM

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

verbose() {
    if [ "$VERBOSE_MODE" = true ]; then
        echo -e "${NC}🔍 $1${NC}"
    fi
}

# Display header
echo "🔧 Minecraft Protocol Fix Script with Modded Server Support"
echo "============================================================="
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
    
    # Remove .protocol-attempts file
    if [ -f "$PROTOCOL_ATTEMPTS" ]; then
        rm -f "$PROTOCOL_ATTEMPTS"
        success "Removed $PROTOCOL_ATTEMPTS"
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

# Step 0: Ping server to discover protocol version
step "Pinging server to discover protocol version..."
echo ""

if [ -f "$PING_TOOL" ]; then
    info "Running ping tool on $SERVER_ADDR..."
    
    # Run the ping tool and capture output
    PING_OUTPUT=$(go run "$PING_TOOL" "$SERVER_ADDR" 2>&1 || true)
    
    verbose "Ping output: $PING_OUTPUT"
    
    # Parse the machine-readable output line
    if echo "$PING_OUTPUT" | grep -q "^PROTOCOL="; then
        PING_LINE=$(echo "$PING_OUTPUT" | grep "^PROTOCOL=" | head -1)
        
        # Extract protocol, version name, and modded type
        REPORTED_PROTOCOL=$(echo "$PING_LINE" | sed -n 's/.*PROTOCOL=\([0-9]*\).*/\1/p')
        VERSION_NAME=$(echo "$PING_LINE" | sed -n 's/.*VERSION_NAME="\([^"]*\)".*/\1/p')
        MODDED_TYPE=$(echo "$PING_LINE" | sed -n 's/.*MODDED=\([^ ]*\).*/\1/p')
        
        success "Server responded!"
        info "Protocol Version: $REPORTED_PROTOCOL"
        info "Version Name: $VERSION_NAME"
        info "Server Type: $MODDED_TYPE"
        
        # Update mode flags if not explicitly set
        if [ "$MODDED_TYPE" = "fabric" ] && [ "$FORGE_MODE" = false ]; then
            info "Fabric server detected - using vanilla protocol handshake"
            FABRIC_MODE=true
        elif [ "$MODDED_TYPE" = "forge" ] && [ "$FABRIC_MODE" = false ]; then
            warn "Forge server detected!"
            warn "Full FML handshake is NOT yet implemented."
            warn "Connection may fail or have limited functionality."
            FORGE_MODE=true
        fi
    else
        warn "Could not parse server ping response"
        verbose "Full output: $PING_OUTPUT"
        info "Will use fallback protocol candidates"
    fi
else
    warn "Ping tool not found at $PING_TOOL"
    info "Will use fallback protocol candidates"
fi

echo ""

# Generate protocol candidate list
step "Generating protocol candidate list..."

PROTOCOL_VERSIONS=()

# If user specified a range, use that
if [ -n "$RANGE_START" ] && [ -n "$RANGE_END" ]; then
    info "Using user-specified range: $RANGE_START-$RANGE_END"
    for ((p=$RANGE_START; p<=$RANGE_END; p++)); do
        PROTOCOL_VERSIONS+=("$p")
    done
elif [ -n "$REPORTED_PROTOCOL" ]; then
    # Build candidate window around reported protocol
    # P, P-1, P+1, P-2, P+2
    info "Building candidate window around reported protocol $REPORTED_PROTOCOL"
    
    # Add the reported protocol first
    PROTOCOL_VERSIONS+=("$REPORTED_PROTOCOL")
    
    # Add nearby protocols
    for offset in 1 2; do
        # Add P-offset (if > 0)
        if [ $((REPORTED_PROTOCOL - offset)) -gt 0 ]; then
            PROTOCOL_VERSIONS+=("$((REPORTED_PROTOCOL - offset))")
        fi
        # Add P+offset
        PROTOCOL_VERSIONS+=("$((REPORTED_PROTOCOL + offset))")
    done
    
    # Merge with fallback candidates (unique values only)
    for proto in "${DEFAULT_PROTOCOL_VERSIONS[@]}"; do
        # Check if proto is not already in PROTOCOL_VERSIONS
        if [[ ! " ${PROTOCOL_VERSIONS[@]} " =~ " ${proto} " ]]; then
            PROTOCOL_VERSIONS+=("$proto")
        fi
    done
else
    # Use default fallback candidates
    info "Using default fallback candidates"
    PROTOCOL_VERSIONS=("${DEFAULT_PROTOCOL_VERSIONS[@]}")
fi

success "Will test ${#PROTOCOL_VERSIONS[@]} protocol versions: ${PROTOCOL_VERSIONS[*]}"
echo ""

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

# Function to patch protocol version in mcbot.go
patch_protocol_version() {
    local protocol=$1
    local file=$2
    
    verbose "Patching ProtocolVersion to $protocol in $file"
    
    # Find and replace the ProtocolVersion line using sed
    # Handles various formatting: spaces, tabs, etc.
    if grep -qE '^\s*ProtocolVersion\s*=\s*[0-9]+' "$file"; then
        sed -i "s/\(ProtocolVersion[[:space:]]*=[[:space:]]*\)[0-9]\+/\1$protocol/" "$file"
        return 0
    else
        error "ProtocolVersion constant not found in $file"
        return 1
    fi
}

# Step 4: Test each protocol version
step "Testing protocol versions..."
echo ""
info "Will test protocols in order: ${PROTOCOL_VERSIONS[*]}"
echo ""

# Initialize test log
echo "Protocol Version Test Log - $(date)" > "$TEST_LOG"
echo "======================================" >> "$TEST_LOG"
if [ -n "$REPORTED_PROTOCOL" ]; then
    echo "Reported Protocol: $REPORTED_PROTOCOL" >> "$TEST_LOG"
    echo "Version Name: $VERSION_NAME" >> "$TEST_LOG"
    echo "Server Type: $MODDED_TYPE" >> "$TEST_LOG"
fi
echo "" >> "$TEST_LOG"

# Initialize or load protocol attempts tracking
if [ -f "$PROTOCOL_ATTEMPTS" ] && [ "$FORCE_MODE" = false ]; then
    info "Resuming from previous attempts (use --force to start fresh)"
fi

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
    
    # Check if already attempted and failed
    if [ -f "$PROTOCOL_ATTEMPTS" ] && grep -q "^$PROTOCOL:FAILED$" "$PROTOCOL_ATTEMPTS"; then
        verbose "Protocol $PROTOCOL was already attempted and failed, skipping"
        continue
    fi
    
    # Restore from original before each modification
    cp "$MCBOT_FILE.original" "$MCBOT_FILE"
    
    # Modify mcbot.go to set the protocol version using our patching function
    info "Patching ProtocolVersion to $PROTOCOL..."
    
    if ! patch_protocol_version "$PROTOCOL" "$MCBOT_FILE"; then
        echo "Failed: ProtocolVersion patching error" >> "$TEST_LOG"
        echo "$PROTOCOL:FAILED" >> "$PROTOCOL_ATTEMPTS"
        echo "" >> "$TEST_LOG"
        continue
    fi
    success "Patched: ProtocolVersion = $PROTOCOL"
    
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
    
    # Show verbose output if requested
    if [ "$VERBOSE_MODE" = true ]; then
        verbose "Connection test output:"
        cat "$TEMP_BOT_LOG"
    fi
    
    # Append bot output to test log
    cat "$TEMP_BOT_LOG" >> "$TEST_LOG"
    
    # Improved success heuristics:
    # 1. Check for explicit success messages
    # 2. Check for game state indicators (Login success, Game started, JoinGame)
    # 3. Check that "Incompatible client" is NOT present
    # 4. Check for connection stability (no immediate disconnect)
    
    CONNECTION_SUCCESS=false
    
    if grep -qE "Successfully connected to server|Game started|Login success|JoinGame" "$TEMP_BOT_LOG"; then
        CONNECTION_SUCCESS=true
    elif ! grep -q "Incompatible client" "$TEMP_BOT_LOG" && \
         grep -q "Connecting to server" "$TEMP_BOT_LOG" && \
         [ $(wc -l < "$TEMP_BOT_LOG") -gt 3 ]; then
        # If we connected, didn't get "Incompatible client", and have substantial output
        verbose "Connection appears stable (no incompatible client error)"
        CONNECTION_SUCCESS=true
    fi
    
    if [ "$CONNECTION_SUCCESS" = true ]; then
        success "SUCCESS! Connected with protocol $PROTOCOL"
        WORKING_PROTOCOL=$PROTOCOL
        echo "SUCCESS with protocol $PROTOCOL" >> "$TEST_LOG"
        echo "$PROTOCOL:SUCCESS" >> "$PROTOCOL_ATTEMPTS"
        rm -f "$TEMP_BOT_LOG"
        break
    elif grep -q "Incompatible client" "$TEMP_BOT_LOG"; then
        error "Failed: Incompatible client"
        echo "Failed: Incompatible client" >> "$TEST_LOG"
        echo "$PROTOCOL:FAILED" >> "$PROTOCOL_ATTEMPTS"
    elif grep -q "Failed to join server" "$TEMP_BOT_LOG"; then
        error "Failed: Connection error"
        echo "Failed: Connection error" >> "$TEST_LOG"
        echo "$PROTOCOL:FAILED" >> "$PROTOCOL_ATTEMPTS"
    else
        warn "Unknown result - check logs"
        echo "Unknown result" >> "$TEST_LOG"
        echo "$PROTOCOL:UNKNOWN" >> "$PROTOCOL_ATTEMPTS"
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
    success "Fixed! Your bot now works with the server"
    echo ""
    echo "📋 Working Protocol Version: $WORKING_PROTOCOL"
    if [ -n "$VERSION_NAME" ]; then
        echo "📋 Server Version: $VERSION_NAME"
    fi
    if [ "$MODDED_TYPE" != "unknown" ]; then
        echo "📋 Server Type: $MODDED_TYPE"
    fi
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
    
    # Provide specific guidance if we have a reported protocol but it didn't work
    if [ -n "$REPORTED_PROTOCOL" ]; then
        warn "Server reported protocol version $REPORTED_PROTOCOL, but connection failed."
        echo ""
        echo "📝 Manual fix instructions:"
        echo "   1. The server expects protocol $REPORTED_PROTOCOL"
        echo "   2. Manually patch $MCBOT_FILE:"
        echo "      Change: ProtocolVersion = <old_value>"
        echo "      To:     ProtocolVersion = $REPORTED_PROTOCOL"
        echo "   3. Run: go mod tidy"
        echo "   4. Run: go build -o minecraft-bot main.go"
        echo "   5. Run: ./minecraft-bot"
        echo ""
        echo "   Or try a different protocol range:"
        echo "   ./fix-protocol.sh --range $((REPORTED_PROTOCOL - 5))-$((REPORTED_PROTOCOL + 5))"
        echo ""
    fi
    
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
    echo "   4. Run the ping tool directly: go run $PING_TOOL $SERVER_ADDR"
    echo "   5. Try a wider protocol range: --range 760-800"
    echo "   6. Use --verbose for detailed output"
    echo "   7. Use --clean to reset and start over"
    echo ""
    exit 1
fi
