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

## Prerequisites

- Go 1.24 or higher
- Access to a Minecraft server (Java Edition 1.21.10 or compatible)
- Git (for cloning the go-mc library locally if protocol fix is needed)

## Protocol Version Fix

If you encounter the error "Incompatible client! Please use 1.21.10", you need to fix the protocol version mismatch:

```bash
./fix-protocol.sh
```

This script will:
- Clone the go-mc library locally to `./go-mc-local`
- Test multiple protocol versions (768, 769, 770, 771, 766) automatically
- Find the correct protocol version for Minecraft 1.21.10
- Update your configuration to use the working protocol version
- Save the result to `.protocol-version` for future reference

The script is idempotent and can be run multiple times safely.

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
- The bot uses the go-mc library which implements the Minecraft protocol
- Graceful shutdown is handled via `!stop` command or SIGINT/SIGTERM signals

## Logging

The bot logs all activities to stdout, including:
- Connection status
- Game events
- Chat messages received
- Command execution
- Errors and warnings