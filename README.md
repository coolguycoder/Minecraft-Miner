# Minecraft-Miner

A Minecraft bot written in Go that can connect to a Minecraft Java Edition 1.21.10 server and respond to chat commands.

## Features

- **Auto-connect**: Automatically connects to the specified Minecraft Java Edition 1.21.10 server
- **Initial Mining**: Upon joining, the bot mines the cobblestone block directly in front of it with realistic mining simulation
  - 40 ticks (2 seconds) mining time
  - Arm swing animations every 10 ticks
  - Mining progress logging
- **Enhanced Logging**: Emoji-enhanced status messages for better readability (🎮, ⛏️, 👋, ❤️, etc.)
- **Chat Commands** (case-insensitive):
  - `!me` - Move to the player who issued the command and look at them
  - `!mine` - Pick up thrown items and use them to mine blocks (sends "IT BROKEEEEE" when tool breaks)
  - `!stop` - Gracefully disconnect from the server
- **Durability Tracking**: Items lose 5 durability every 40 ticks of mining

## Configuration

The bot connects to the server with the following default settings (can be modified in `main.go`):
- **Server**: `100.94.216.120:25565`
- **Username**: `MINER`
- **Version**: Minecraft Java Edition 1.21.10
- **Protocol Version**: 768 (compatible with Minecraft 1.21.2-1.21.4)

## Prerequisites

- Go 1.24 or higher
- Access to a Minecraft server (Java Edition 1.21.10 or compatible)
- Git (for cloning the go-mc library locally if protocol fix is needed)

## Protocol Version Fix (Minecraft 1.21.10)

If you encounter the error "Incompatible client! Please use 1.21.10", you need to fix the protocol version mismatch. This happens because the upstream `go-mc` library hardcodes a protocol version that may not match your server's expected version.

### Why This Script Is Needed

The upstream go-mc library is not yet updated to support Minecraft 1.21.10's specific protocol version. Until upstream support lands, we use this script to automatically detect and patch the correct protocol version locally.

### Usage

**Initial run** (automatically detects the correct protocol version):
```bash
./fix-protocol.sh
```

**Force re-run** (redo tests even if a protocol version was previously found):
```bash
./fix-protocol.sh --force
```

**Clean reset** (remove all local modifications and start fresh):
```bash
./fix-protocol.sh --clean
```

**Show discovered protocol version:**
```bash
cat .protocol-version
```

### What The Script Does

1. Performs sanity checks (verifies Go is installed and main.go exists)
2. Clones the go-mc library locally to `./go-mc-local` (if not already present)
3. Tests multiple protocol versions (768, 769, 770, 771, 766) automatically
4. For each version:
   - Patches the `ProtocolVersion` constant in `go-mc-local/bot/mcbot.go`
   - Updates `go.mod` with a replace directive (idempotent)
   - Runs `go mod tidy`
   - Builds the bot binary
   - Tests connection to the server
5. Saves the working protocol version to `.protocol-version`
6. Creates a backup of your original `go.mod` at `go.mod.backup`

The script is idempotent and safe to run multiple times.

### Future TODO

When the upstream go-mc library officially supports Minecraft 1.21.10, this script and the local modifications can be removed. Monitor the [go-mc repository](https://github.com/Tnze/go-mc) for updates.

## Version Compatibility

This bot uses **protocol version 768** to connect to Minecraft servers. This protocol version is compatible with:
- Minecraft 1.21.2
- Minecraft 1.21.3
- Minecraft 1.21.4
- Minecraft 1.21.10 (tested)

If you need to connect to a different Minecraft version, you may need to update the protocol version in `go-mc-local/bot/mcbot.go`.

## Building

To build the bot:

```bash
go build -o minecraft-bot main.go
```

Or use:

```bash
go build
```

## Running

To run the bot:

```bash
./minecraft-bot
```

Or directly with:

```bash
go run main.go
```

## Usage

1. Start the bot with `./minecraft-bot`
2. The bot will connect to the configured Minecraft server
3. Once connected, it will automatically mine the cobblestone block in front of it
4. Use chat commands in-game to control the bot:
   - Type `!me` to make the bot move to you
   - Type `!mine` to make the bot ready to pick up tools and mine with them
   - Type `!stop` to gracefully shut down the bot

## Dependencies

This project uses:
- [github.com/Tnze/go-mc](https://github.com/Tnze/go-mc) - Go library for Minecraft protocol

Dependencies are managed via Go modules. Run `go mod tidy` to download them.

## Development

The bot is structured as follows:
- **Connection handling**: Manages server connection and authentication
- **Event handlers**: Responds to game events (joining, teleporting, health changes, etc.)
- **Chat command parser**: Processes incoming chat messages for commands
- **Packet handlers**: Sends and receives Minecraft protocol packets for actions

## Notes

- The `!me` command requires tracking other players' positions (partially implemented)
- The `!mine` command requires item pickup tracking and durability monitoring (framework in place)
- The bot uses a modified version of the go-mc library (vendored in `go-mc-local/`)
- Graceful shutdown is handled via `!stop` command or SIGINT/SIGTERM signals

## Troubleshooting

### "Incompatible client" Error

If you see an error like:
```
❌ Failed to join server: bot: login error: [disconnect] disconnect because: Incompatible client! Please use X.XX.XX
```

This means the server is running a different Minecraft version that requires a different protocol version. To fix:

1. Determine the correct protocol version for your Minecraft version (check [wiki.vg/Protocol_version_numbers](https://wiki.vg/Protocol_version_numbers))
2. Update the protocol version in `go-mc-local/bot/mcbot.go`:
   ```go
   const (
       ProtocolVersion = XXX // Update this number
       DefaultPort     = mcnet.DefaultPort
   )
   ```
3. Update the `protocolVersion` constant in `main.go` to match
4. Rebuild: `go build`

### Connection Issues

- Ensure the server IP and port are correct in `main.go`
- Verify the server is running and accessible
- Check that the server allows offline mode connections (or configure authentication)

## Logging

The bot logs all activities to stdout, including:
- Connection status (with protocol version information)
- Game events
- Chat messages received
- Command execution
- Errors and warnings