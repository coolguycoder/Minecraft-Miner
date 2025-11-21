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
	serverAddr = "100.94.216.120:25565"
	username   = "MINER"
)

var (
	client      *bot.Client
	player      *basic.Player
	shouldStop  bool
	minedFirst  bool
	miningItem  int32 = -1 // Current slot holding mining item
	playerX     float64
	playerY     float64
	playerZ     float64
	playerYaw   float32
	playerPitch float32
)

func main() {
	log.Println("Starting Minecraft Bot...")

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
	log.Printf("Connecting to server %s as %s...", serverAddr, username)
	err := client.JoinServer(serverAddr)
	if err != nil {
		log.Fatalf("Failed to join server: %v", err)
	}

	log.Println("Successfully connected to server!")

	// Keep the bot running
	err = client.HandleGame()
	if err != nil {
		if !shouldStop {
			log.Printf("Game ended with error: %v", err)
		}
	}
}

// onGameStart is called when the player joins the game
func onGameStart() error {
	log.Println("Game started! Bot is now in the game.")

	// Wait a moment for the world to load
	time.Sleep(2 * time.Second)

	// Mine the cobblestone block directly in front
	if !minedFirst {
		go mineBlockInFront()
		minedFirst = true
	}

	return nil
}

// onDisconnect is called when disconnected from the server
func onDisconnect(reason chat.Message) error {
	log.Printf("Disconnected: %s", reason.String())
	return nil
}

// onHealthChange handles health updates
func onHealthChange(health float32, food int32, foodSaturation float32) error {
	log.Printf("Health: %.1f, Food: %d, Saturation: %.1f", health, food, foodSaturation)
	return nil
}

// onDeath is called when the player dies
func onDeath() error {
	log.Println("Player died!")
	// Respawn the player
	return player.Respawn()
}

// onTeleported is called when the player is teleported
func onTeleported(x, y, z float64, yaw, pitch float32, flags byte, teleportID int32) error {
	log.Printf("Teleported to: X=%.2f, Y=%.2f, Z=%.2f, Yaw=%.2f, Pitch=%.2f", x, y, z, yaw, pitch)

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
	log.Printf("Chat message: %s", msgText)

	// Parse chat commands
	if strings.Contains(msgText, "!me") {
		log.Println("Received !me command")
		go handleMeCommand(msgText)
	} else if strings.Contains(msgText, "!mine") {
		log.Println("Received !mine command")
		go handleMineCommand()
	} else if strings.Contains(msgText, "!stop") {
		log.Println("Received !stop command")
		go handleStopCommand()
	}

	return nil
}

// mineBlockInFront mines the cobblestone block directly in front of the bot
func mineBlockInFront() {
	log.Println("Mining cobblestone block in front...")

	// Use tracked player position (from teleported event)
	// Calculate block position in front (1 block forward based on yaw)
	// Assuming the bot is facing a specific direction, let's just mine the block at feet level + 0
	blockX := int(math.Floor(playerX))
	blockY := int(math.Floor(playerY))
	blockZ := int(math.Floor(playerZ + 1)) // Block in front

	log.Printf("Attempting to mine block at position: (%d, %d, %d)", blockX, blockY, blockZ)

	// Send start digging packet
	err := sendDigging(0, blockX, blockY, blockZ, 1) // Status 0 = start digging, face 1 = top
	if err != nil {
		log.Printf("Error starting to dig: %v", err)
		return
	}

	// Wait for mining time
	time.Sleep(1 * time.Second)

	// Send finish digging packet
	err = sendDigging(2, blockX, blockY, blockZ, 1) // Status 2 = finish digging
	if err != nil {
		log.Printf("Error finishing dig: %v", err)
		return
	}

	log.Println("Successfully sent mining packets!")
}

// sendDigging sends a player digging packet
func sendDigging(status int32, x, y, z int, face byte) error {
	// Encode position as per Minecraft protocol
	position := int64(x&0x3FFFFFF)<<38 | int64(z&0x3FFFFFF)<<12 | int64(y&0xFFF)

	return client.Conn.WritePacket(pk.Marshal(
		packetid.ServerboundPlayerAction,
		pk.VarInt(status),
		pk.Long(position),
		pk.Byte(face),
		pk.VarInt(0), // Sequence
	))
}

// handleMeCommand moves the bot to the player who issued the command
func handleMeCommand(msg string) {
	log.Println("Executing !me command...")

	sendChatMessage("Moving to you!")

	// Note: Full implementation would require:
	// 1. Parse the sender's username from the chat message
	// 2. Track other players' positions from spawn entity packets
	// 3. Calculate path to player using pathfinding
	// 4. Send player position packets to move
	// 5. Look at player by calculating yaw/pitch

	log.Println("!me command acknowledged (requires player position tracking and pathfinding)")
}

// handleMineCommand handles the !mine command
func handleMineCommand() {
	log.Println("Executing !mine command...")

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

	log.Println("Waiting for item to be thrown...")
}

// handleStopCommand gracefully stops the bot
func handleStopCommand() {
	log.Println("Executing !stop command...")

	sendChatMessage("Goodbye!")

	time.Sleep(1 * time.Second)

	shouldStop = true
	if client.Conn != nil {
		client.Conn.Close()
	}

	log.Println("Bot stopped gracefully")
	os.Exit(0)
}

// sendChatMessage sends a chat message to the server
func sendChatMessage(message string) {
	if client.Conn == nil {
		log.Println("Cannot send chat message: not connected")
		return
	}

	// For modern Minecraft, we need to send a chat command or message
	// Try chat message packet
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
		log.Printf("Failed to send chat message: %v", err)
	}
}

// mineWithItem mines a block using the current held item
func mineWithItem(x, y, z int) {
	log.Printf("Mining block at (%d, %d, %d) with item...", x, y, z)

	// Start digging
	err := sendDigging(0, x, y, z, 1)
	if err != nil {
		log.Printf("Error starting to dig: %v", err)
		return
	}

	// Wait for mining
	time.Sleep(500 * time.Millisecond)

	// Finish digging
	err = sendDigging(2, x, y, z, 1)
	if err != nil {
		log.Printf("Error finishing dig: %v", err)
		return
	}

	log.Println("Mining action completed")
}
