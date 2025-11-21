# 🤖⛏️ Minecraft-Miner

A Minecraft bot written in Go that can connect to Minecraft 1.21.1 servers and respond to chat commands.

## Compatibility

- ✅ **Minecraft Version**: 1.21.1
- ✅ **Server Type**: Java Edition (offline-mode servers)
- ✅ **Protocol**: Compatible with Minecraft 1.21.1 protocol

## Features

- ✅ **Auto-connect**: Automatically connects to the specified Minecraft server
- 🏃 **Initial Mining**: Upon joining, the bot mines the cobblestone block directly in front of it
- ⛏️ **Mining Simulation**: Realistic mining with tick-based timing and durability tracking
- 💥 **Durability System**: Tracks tool durability and announces "IT BROKEEEEE" when it reaches 0
- 🛑 **Chat Commands**:
  - `!me` - Move to the player who issued the command and look at them
  - `!mine` - Start mining simulation with durability tracking
  - `!stop` - Gracefully disconnect from the server

## Configuration

The bot connects to the server with the following default settings (can be modified in `main.go`):
- **Server**: `100.94.216.120:25565`
- **Username**: `MINER`
- **Minecraft Version**: `1.21.1`

To change these settings, edit the constants at the top of `main.go`:

```go
const (
    serverAddr = "100.94.216.120:25565"  // Change to your server address
    username   = "MINER"                  // Change to your desired username
    version    = "1.21.1"                 // Minecraft version
)
```

## Prerequisites

- Go 1.24 or higher
- Access to a Minecraft 1.21.1 server (Java Edition)
- Server must be in **offline-mode** (online-mode authentication not yet supported)

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
4. Use chat commands in-game to control the bot

### Commands

| Command | Description | Example |
|---------|-------------|---------|
| `!me` | Bot acknowledges and responds to the player | Type `!me` in chat |
| `!mine` | Start mining simulation with durability tracking | Type `!mine` in chat |
| `!stop` | Gracefully disconnect the bot from the server | Type `!stop` in chat |

### Example Session

```
[Player] !mine
[MINER] Starting mining simulation!
[MINER] Mining... Durability: 95%
[MINER] Mining... Durability: 90%
...
[MINER] Mining... Durability: 5%
[MINER] IT BROKEEEEE

[Player] !stop
[MINER] Goodbye!
```

## Dependencies

This project uses:
- [github.com/Tnze/go-mc](https://github.com/Tnze/go-mc) - Go library for Minecraft protocol

Dependencies are managed via Go modules. Run `go mod tidy` to download them.

## Technical Details

### Architecture

The bot is structured with the following components:

- **Connection handling**: Manages server connection and authentication using the go-mc library
- **Event handlers**: Responds to game events (joining, teleporting, health changes, death)
- **Chat command parser**: Processes incoming chat messages for bot commands
- **Packet handlers**: Sends and receives Minecraft protocol packets for actions
- **Mining simulation**: Tick-based mining system with durability tracking

### Mining System

The mining simulation includes:
- **Tick-based timing**: Uses Minecraft's 50ms tick duration for realistic timing
- **Arm swing animation**: Swings arm every 10 ticks (500ms) for visual feedback
- **Durability tracking**: Reduces durability by 5% every 40 ticks (2 seconds)
- **Block mining**: Mines blocks in front of the bot position
- **Break notification**: Announces "IT BROKEEEEE" when durability reaches 0

### Protocol Implementation

- **Version**: 1.21.1
- **Chat packet format**: Updated for 1.21.1 protocol changes
  - Uses proper timestamp, salt, and signature fields
  - Sends messages with correct packet structure
- **Position encoding**: Uses Minecraft's packed position format (X/Z/Y encoding)
- **Player actions**: Implements digging, arm swinging, and teleport confirmation

## Important Notes

### Offline Mode vs Online Mode

- ✅ **Offline-mode servers**: The bot works out of the box
- ❌ **Online-mode servers**: Not currently supported (requires Mojang authentication)

If you're running your own server, set `online-mode=false` in `server.properties` to use this bot.

### Current Limitations

- The `!me` command framework is in place but requires player position tracking
- Item pickup and inventory management are not yet implemented
- Pathfinding and movement are not yet implemented
- Mining simulation uses fixed durability (not real item tracking)

## Roadmap

Future features planned:
- [ ] Player position tracking for `!me` command
- [ ] Item pickup and inventory management
- [ ] Real durability tracking from inventory packets
- [ ] Pathfinding and navigation
- [ ] Multiple mining patterns
- [ ] Online-mode authentication support
- [ ] Configuration file support

## Logging

The bot logs all activities to stdout, including:
- Connection status
- Game events
- Chat messages received
- Command execution
- Errors and warnings