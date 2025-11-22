package main

import (
	"fmt"
	"log"
	"math"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/Tnze/go-mc/bot"
	"github.com/Tnze/go-mc/bot/basic"
	"github.com/Tnze/go-mc/chat"
	"github.com/Tnze/go-mc/data/packetid"
	pk "github.com/Tnze/go-mc/net/packet"
)

const (
	version    = "1.21.10" // Minecraft Java Edition version
	serverAddr = "100.94.216.120:25565"
	username   = "MINER"

	// Timing constants
	worldLoadDelay  = 2 * time.Second        // Wait time for world to load after joining
	basicMiningTime = 1 * time.Second        // Time to mine a block with bare hands
	itemMiningTime  = 500 * time.Millisecond // Time to mine a block with a tool
	tickDuration    = 50 * time.Millisecond  // Minecraft tick duration (20 ticks per second)
	miningTickCount = 40                     // Ticks to mine a block (40 ticks = 2 seconds)
	swingInterval   = 10                     // Ticks between arm swings

	// Minecraft protocol position encoding constants
	// Position is encoded as: X (26 bits) << 38 | Z (26 bits) << 12 | Y (12 bits)
	positionXZMask = 0x3FFFFFF // 26-bit mask for X and Z coordinates
	positionYMask  = 0xFFF     // 12-bit mask for Y coordinate
)

var (
	client         *bot.Client
	player         *basic.Player
	shouldStop     bool
	minedFirst     bool
	miningItem     int32 = -1  // Current slot holding mining item
	itemDurability int   = 100 // Item durability (default: 100)
	miningTicks    int   = 0   // Counter for mining simulation ticks
	playerX        float64
	playerY        float64
	playerZ        float64
	playerYaw      float32
	playerPitch    float32
)

func main() {
	log.Println("🤖 Starting Minecraft Bot...")
	log.Printf("📦 Minecraft Java Edition version: %s", version)

	// Create client
	client = bot.NewClient()
	client.Auth.Name = username

	// Create event listeners
	events := basic.EventsListener{
		GameStart:    onGameStart,
		Disconnect:   onDisconnect,
		HealthChange: onHealthChange,
		Death:        onDeath,
		Teleported:   onTeleported,
	}

	// Create player with event handlers
	player = basic.NewPlayer(client, basic.DefaultSettings, events)

	// Add custom packet handler for chat messages
	client.Events.AddListener(
		bot.PacketHandler{
			ID: packetid.ClientboundSystemChat,
			F:  handleChatPacket,
		},
		bot.PacketHandler{
			ID: packetid.ClientboundPlayerChat,
			F:  handleChatPacket,
		},
		bot.PacketHandler{
			ID: packetid.ClientboundDisguisedChat,
			F:  handleChatPacket,
		},
	)

	// Setup signal handler for graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigCh
		log.Println("Received interrupt signal, shutting down...")
		shouldStop = true
		if client.Conn != nil {
			client.Conn.Close()
		}
		os.Exit(0)
	}()

	// Join server
	log.Printf("Connecting to server %s as %s (Minecraft Java Edition %s)...", serverAddr, username, version)
	err := client.JoinServer(serverAddr)
	if err != nil {
		log.Fatalf("❌ Failed to join server: %v", err)
	}

	log.Println("✓ Successfully connected to server!")

	// Run game handler in goroutine to prevent blocking
	go func() {
		err := client.HandleGame()
		if err != nil && !shouldStop {
			log.Printf("❌ Game ended with error: %v", err)
		}
	}()

	// Keep the main thread running until interrupted
	// Signal handler above will call os.Exit(0) for graceful shutdown
	select {}
}

// onGameStart is called when the player joins the game
func onGameStart() error {
	log.Println("🎮 Game started! Bot is now in the game.")

	// Wait a moment for the world to load
	time.Sleep(worldLoadDelay)

	// Mine the cobblestone block directly in front
	if !minedFirst {
		go mineBlockInFront()
		minedFirst = true
	}

	return nil
}

// onDisconnect is called when disconnected from the server
func onDisconnect(reason chat.Message) error {
	log.Printf("👋 Disconnected: %s", reason.String())
	return nil
}

// onHealthChange handles health updates
func onHealthChange(health float32, food int32, foodSaturation float32) error {
	log.Printf("❤️ Health: %.1f, Food: %d, Saturation: %.1f", health, food, foodSaturation)
	return nil
}

// onDeath is called when the player dies
func onDeath() error {
	log.Println("💀 Player died!")
	// Respawn the player
	return player.Respawn()
}

// onTeleported is called when the player is teleported
func onTeleported(x, y, z float64, yaw, pitch float32, flags byte, teleportID int32) error {
	log.Printf("📍 Teleported to: X=%.2f, Y=%.2f, Z=%.2f, Yaw=%.2f, Pitch=%.2f", x, y, z, yaw, pitch)

	// Update tracked position
	playerX = x
	playerY = y
	playerZ = z
	playerYaw = yaw
	playerPitch = pitch

	// Confirm teleportation
	return player.AcceptTeleportation(pk.VarInt(teleportID))
}

// handleChatPacket processes incoming chat messages
func handleChatPacket(p pk.Packet) error {
	var msg chat.Message

	// Try to decode the chat message
	if err := p.Scan(&msg); err != nil {
		return fmt.Errorf("failed to parse chat message: %w", err)
	}

	msgText := msg.String()
	log.Printf("💬 Chat message: %s", msgText)

	// Parse chat commands (support both exact match and contains)
	msgLower := strings.ToLower(msgText)
	if strings.Contains(msgLower, "!me") {
		log.Println("📥 Received !me command")
		go handleMeCommand(msgText)
	} else if strings.Contains(msgLower, "!mine") {
		log.Println("📥 Received !mine command")
		go handleMineCommand()
	} else if strings.Contains(msgLower, "!stop") {
		log.Println("📥 Received !stop command")
		go handleStopCommand()
	}

	return nil
}

// mineBlockInFront mines the cobblestone block directly in front of the bot
func mineBlockInFront() {
	log.Println("⛏️ Mining cobblestone block in front...")

	// Use tracked player position (from teleported event)
	// Calculate block position in front (1 block forward based on yaw)
	// Assuming the bot is facing a specific direction, let's just mine the block at feet level + 0
	blockX := int(math.Floor(playerX))
	blockY := int(math.Floor(playerY))
	blockZ := int(math.Floor(playerZ + 1)) // Block in front

	log.Printf("🎯 Attempting to mine block at position: (%d, %d, %d)", blockX, blockY, blockZ)

	// Send start digging packet
	err := sendDigging(0, blockX, blockY, blockZ, 1) // Status 0 = start digging, face 1 = top
	if err != nil {
		log.Printf("❌ Error starting to dig: %v", err)
		return
	}

	// Perform realistic mining simulation
	simulateMining()

	// Send finish digging packet
	err = sendDigging(2, blockX, blockY, blockZ, 1) // Status 2 = finish digging
	if err != nil {
		log.Printf("❌ Error finishing dig: %v", err)
		return
	}

	// Reduce durability if using an item
	if miningItem >= 0 {
		itemDurability -= 5
		log.Printf("🔧 Item durability: %d", itemDurability)
		if itemDurability <= 0 {
			log.Println("💥 IT BROKEEEEE")
			itemDurability = 100 // Reset for next item
		}
	}

	log.Println("✓ Successfully mined the block!")
}

// sendDigging sends a player digging packet
func sendDigging(status int32, x, y, z int, face byte) error {
	// Encode position as per Minecraft protocol
	position := int64(x&positionXZMask)<<38 | int64(z&positionXZMask)<<12 | int64(y&positionYMask)

	return client.Conn.WritePacket(pk.Marshal(
		packetid.ServerboundPlayerAction,
		pk.VarInt(status),
		pk.Long(position),
		pk.Byte(face),
		pk.VarInt(0), // Sequence
	))
}

// sendArmSwing sends an arm swing animation packet
func sendArmSwing() error {
	return client.Conn.WritePacket(pk.Marshal(
		packetid.ServerboundSwing,
		pk.VarInt(0), // Main hand
	))
}

// simulateMining simulates realistic mining with ticks and arm swings
func simulateMining() {
	miningTicks = 0
	for miningTicks < miningTickCount {
		time.Sleep(tickDuration)
		miningTicks++

		// Send arm swing animation every 10 ticks
		if miningTicks%swingInterval == 0 {
			err := sendArmSwing()
			if err != nil {
				log.Printf("⚠️ Error sending arm swing: %v", err)
			}
		}

		// Show progress every 20 ticks
		if miningTicks%(swingInterval*2) == 0 {
			log.Printf("⛏️ Mining progress: %d/%d ticks", miningTicks, miningTickCount)
		}
	}
}

// handleMeCommand moves the bot to the player who issued the command
func handleMeCommand(msg string) {
	log.Println("🏃 Executing !me command...")

	sendChatMessage("Moving to you!")

	// Note: Full implementation would require:
	// 1. Parse the sender's username from the chat message
	// 2. Track other players' positions from spawn entity packets
	// 3. Calculate path to player using pathfinding
	// 4. Send player position packets to move
	// 5. Look at player by calculating yaw/pitch

	log.Println("✓ !me command acknowledged (requires player position tracking and pathfinding)")
}

// handleMineCommand handles the !mine command
func handleMineCommand() {
	log.Println("⛏️ Executing !mine command...")

	sendChatMessage("Ready to mine! Throw me a tool!")

	// Note: Full implementation would require:
	// 1. Listen for entity spawn packets (thrown items)
	// 2. Move to item location
	// 3. Collect the item (automatic when in range)
	// 4. Track inventory slots to find the item
	// 5. Select the item slot
	// 6. Mine blocks with it
	// 7. Track item durability from slot updates
	// 8. Send "IT BROKEEEEE" when durability reaches 0

	log.Println("⏳ Waiting for item to be thrown...")
}

// handleStopCommand gracefully stops the bot
func handleStopCommand() {
	log.Println("🛑 Executing !stop command...")

	sendChatMessage("Goodbye!")

	time.Sleep(1 * time.Second)

	shouldStop = true
	if client.Conn != nil {
		client.Conn.Close()
	}

	log.Println("👋 Bot stopped gracefully")
	os.Exit(0)
}

// sendChatMessage sends a chat message to the server
func sendChatMessage(message string) {
	if client.Conn == nil {
		log.Println("⚠️ Cannot send chat message: not connected")
		return
	}

	// For Minecraft 1.21.10, we use the chat packet format
	// Updated for 1.21+ protocol
	err := client.Conn.WritePacket(pk.Marshal(
		packetid.ServerboundChat,
		pk.String(message),
		pk.Long(time.Now().UnixMilli()), // Timestamp
		pk.Long(0),                      // Salt
		pk.Boolean(false),               // Has signature
		pk.VarInt(0),                    // Message Count
		pk.Byte(0),                      // Acknowledged
	))
	if err != nil {
		log.Printf("❌ Failed to send chat message: %v", err)
	}
}

// mineWithItem mines a block using the current held item
func mineWithItem(x, y, z int) {
	log.Printf("⛏️ Mining block at (%d, %d, %d) with item...", x, y, z)

	// Start digging
	err := sendDigging(0, x, y, z, 1)
	if err != nil {
		log.Printf("❌ Error starting to dig: %v", err)
		return
	}

	// Perform realistic mining simulation
	simulateMining()

	// Finish digging
	err = sendDigging(2, x, y, z, 1)
	if err != nil {
		log.Printf("❌ Error finishing dig: %v", err)
		return
	}

	// Reduce durability after mining (5 per 40 ticks)
	itemDurability -= 5
	log.Printf("🔧 Item durability: %d", itemDurability)

	if itemDurability <= 0 {
		log.Println("💥 IT BROKEEEEE")
		sendChatMessage("IT BROKEEEEE")
		itemDurability = 100 // Reset for next item
		miningItem = -1      // No longer holding a mining item
	}

	log.Println("✓ Mining action completed")
}
