#!/bin/bash

# Minecraft 1.21.10 Protocol Fix Script
# This script automatically finds and applies the correct protocol version
# for connecting to Minecraft 1.21.10 servers
#
# Usage: ./fix-protocol.sh [--help]

set -e  # Exit on error

# Show help if requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Minecraft 1.21.10 Protocol Fix Script"
    echo ""
    echo "This script automatically finds and applies the correct protocol version"
    echo "for connecting to Minecraft 1.21.10 servers."
    echo ""
    echo "Usage: ./fix-protocol.sh"
    echo ""
    echo "The script will:"
    echo "  1. Clone the go-mc library locally to ./go-mc-local"
    echo "  2. Test multiple protocol versions (768, 769, 770, 771, 766)"
    echo "  3. Find the working protocol version"
    echo "  4. Update go.mod with a replace directive"
    echo "  5. Save the result to .protocol-version"
    echo ""
    echo "Options:"
    echo "  --help, -h    Show this help message"
    echo ""
    exit 0
fi

# Configuration
GOMC_DIR="./go-mc-local"
GOMC_REPO="https://github.com/Tnze/go-mc.git"
SERVER_ADDR="100.94.216.120:25565"
PROTOCOL_FILE=".protocol-version"
GOMOD_BACKUP="go.mod.backup"
MCBOT_FILE="$GOMC_DIR/bot/mcbot.go"
BUILD_TIMEOUT=60
CONNECT_TIMEOUT=5

# Protocol versions to test (in order of likelihood for 1.21.10)
PROTOCOL_VERSIONS=(768 769 770 771 766)

# Colors and emojis for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔧 Minecraft 1.21.10 Protocol Fix Script"
echo "========================================"
echo ""

# Check for required tools
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install git and try again."
    exit 1
fi

if ! command -v go &> /dev/null; then
    print_error "Go is not installed. Please install Go and try again."
    exit 1
fi

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to cleanup on failure
cleanup_on_failure() {
    print_error "Script failed. Cleaning up..."
    
    # Restore go.mod if backup exists
    if [ -f "$GOMOD_BACKUP" ]; then
        mv "$GOMOD_BACKUP" go.mod
        print_info "Restored go.mod from backup"
    fi
    
    # Remove go-mc-local if it was created in this run
    if [ "$GOMC_CLONED_THIS_RUN" = "true" ]; then
        rm -rf "$GOMC_DIR"
        print_info "Removed go-mc-local directory"
    fi
    
    exit 1
}

# Set up trap for cleanup
trap cleanup_on_failure ERR

# Check if already fixed
if [ -f "$PROTOCOL_FILE" ]; then
    SAVED_PROTOCOL=$(cat "$PROTOCOL_FILE")
    print_info "Protocol version $SAVED_PROTOCOL was previously saved"
    read -p "Do you want to re-test? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Exiting. Use the saved protocol version: $SAVED_PROTOCOL"
        exit 0
    fi
fi

# Step 1: Clone or update go-mc library
echo ""
echo "📦 Checking go-mc library..."
GOMC_CLONED_THIS_RUN=false

if [ -d "$GOMC_DIR" ]; then
    print_info "go-mc library already exists at $GOMC_DIR"
    print_info "Using existing clone"
else
    echo "   Cloning go-mc library locally..."
    git clone "$GOMC_REPO" "$GOMC_DIR" > /dev/null 2>&1
    GOMC_CLONED_THIS_RUN=true
    print_success "Cloned successfully"
fi

# Verify mcbot.go exists
if [ ! -f "$MCBOT_FILE" ]; then
    print_error "Cannot find $MCBOT_FILE"
    exit 1
fi

# Step 2: Backup go.mod
echo ""
echo "💾 Backing up go.mod..."
cp go.mod "$GOMOD_BACKUP"
print_success "Backup created"

# Step 3: Add replace directive to go.mod if not already present
if ! grep -q "replace github.com/Tnze/go-mc" go.mod; then
    echo "" >> go.mod
    echo "replace github.com/Tnze/go-mc => ./go-mc-local" >> go.mod
    print_success "Added replace directive to go.mod"
else
    print_info "Replace directive already exists in go.mod"
fi

# Step 4: Test each protocol version
echo ""
echo "🔍 Testing protocol versions..."
WORKING_PROTOCOL=""

for PROTOCOL in "${PROTOCOL_VERSIONS[@]}"; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔍 Testing protocol version $PROTOCOL..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Modify mcbot.go to set the protocol version
    print_info "Modifying mcbot.go to use protocol $PROTOCOL..."
    
    # Create a backup of original mcbot.go first time
    if [ ! -f "$MCBOT_FILE.original" ]; then
        cp "$MCBOT_FILE" "$MCBOT_FILE.original"
    fi
    
    # Restore from original before each modification
    cp "$MCBOT_FILE.original" "$MCBOT_FILE"
    
    # Find and replace the ProtocolVersion line
    # The go-mc library has ProtocolVersion defined in bot/mcbot.go
    if grep -q "ProtocolVersion.*=" "$MCBOT_FILE"; then
        # Replace existing ProtocolVersion
        sed -i "s/ProtocolVersion[[:space:]]*=[[:space:]]*[0-9]*/ProtocolVersion = $PROTOCOL/" "$MCBOT_FILE"
    else
        # If ProtocolVersion not found, try to add it after package declaration
        print_warning "ProtocolVersion not found, attempting to add it"
        sed -i "/^package bot/a \\nconst ProtocolVersion = $PROTOCOL" "$MCBOT_FILE"
    fi
    
    print_success "Modified mcbot.go"
    
    # Build the bot
    echo "   🔨 Building bot..."
    
    # Clean any previous build
    rm -f minecraft-bot
    
    # Build with timeout
    BUILD_OUTPUT=$(timeout $BUILD_TIMEOUT go build -o minecraft-bot main.go 2>&1)
    BUILD_EXIT=$?
    
    if [ $BUILD_EXIT -ne 0 ]; then
        print_error "Build failed with protocol $PROTOCOL"
        echo "$BUILD_OUTPUT" | head -5 | sed 's/^/   /'
        continue
    fi
    
    if [ ! -f "minecraft-bot" ]; then
        print_error "Build failed - binary not created"
        continue
    fi
    
    print_success "Build successful"
    
    # Test connection
    echo "   🌐 Testing connection to server..."
    
    # Run bot with timeout and capture output
    # The bot will fail if protocol is wrong
    timeout $CONNECT_TIMEOUT ./minecraft-bot > /tmp/bot_test_${PROTOCOL}.log 2>&1 &
    BOT_PID=$!
    
    # Wait for the timeout or process to finish
    sleep $CONNECT_TIMEOUT
    
    # Check the output
    if grep -q "Successfully connected to server" /tmp/bot_test_${PROTOCOL}.log; then
        print_success "SUCCESS! Connected with protocol $PROTOCOL"
        WORKING_PROTOCOL=$PROTOCOL
        
        # Kill the bot gracefully
        kill -SIGTERM $BOT_PID 2>/dev/null || true
        sleep 1
        kill -9 $BOT_PID 2>/dev/null || true
        wait $BOT_PID 2>/dev/null || true
        
        break
    elif grep -q "Incompatible client" /tmp/bot_test_${PROTOCOL}.log; then
        print_error "Failed with protocol $PROTOCOL (Incompatible client)"
        kill -9 $BOT_PID 2>/dev/null || true
        wait $BOT_PID 2>/dev/null || true
    elif grep -q "Failed to join server" /tmp/bot_test_${PROTOCOL}.log; then
        print_error "Failed with protocol $PROTOCOL (Connection error)"
        # Show the actual error
        grep "Failed to join server" /tmp/bot_test_${PROTOCOL}.log | head -1
        kill -9 $BOT_PID 2>/dev/null || true
        wait $BOT_PID 2>/dev/null || true
    else
        print_warning "Unknown result with protocol $PROTOCOL"
        # Show last few lines for debugging
        echo "   Last output:"
        tail -3 /tmp/bot_test_${PROTOCOL}.log | sed 's/^/   /'
        kill -9 $BOT_PID 2>/dev/null || true
        wait $BOT_PID 2>/dev/null || true
    fi
done

# Clean up test logs
rm -f /tmp/bot_test_*.log

# Step 5: Report results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$WORKING_PROTOCOL" ]; then
    echo ""
    print_success "Fixed! Your bot now works with Minecraft 1.21.10"
    echo ""
    echo "Protocol version: $WORKING_PROTOCOL"
    echo ""
    
    # Save the working protocol version
    echo "$WORKING_PROTOCOL" > "$PROTOCOL_FILE"
    print_success "Saved to $PROTOCOL_FILE"
    
    # Keep the modified version
    rm -f "$MCBOT_FILE.original"
    rm -f "$GOMOD_BACKUP"
    
    echo ""
    echo "📝 To run your bot:"
    echo "   ./minecraft-bot"
    echo ""
    echo "📝 The go-mc library has been modified locally in $GOMC_DIR"
    echo "📝 Your go.mod now uses this local version"
    echo ""
else
    print_error "Could not find a working protocol version"
    echo ""
    print_info "Tried protocol versions: ${PROTOCOL_VERSIONS[*]}"
    echo ""
    print_info "Restoring original files..."
    
    # Restore original files
    if [ -f "$MCBOT_FILE.original" ]; then
        mv "$MCBOT_FILE.original" "$MCBOT_FILE"
    fi
    
    if [ -f "$GOMOD_BACKUP" ]; then
        mv "$GOMOD_BACKUP" go.mod
    fi
    
    print_warning "Original files restored"
    echo ""
    print_info "You may need to:"
    echo "   1. Check if the server is running"
    echo "   2. Verify the server address: $SERVER_ADDR"
    echo "   3. Try different protocol versions manually"
    echo ""
    exit 1
fi

echo "✅ Done!"
