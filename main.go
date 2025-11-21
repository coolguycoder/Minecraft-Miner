package main

import (
	"fmt"
	"log"
	"math"
	"os"
	"os/signal"
	"strings"
	"sync"
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
	version    = "1.21.1"

	// Timing constants
	worldLoadDelay  = 2 * time.Second         // Wait time for world to load after joining
	basicMiningTime = 1 * time.Second         // Time to mine a block with bare hands
	itemMiningTime  = 500 * time.Millisecond  // Time to mine a block with a tool
	tickDuration    = 50 * time.Millisecond   // Duration of one Minecraft tick

	// Mining simulation constants
	armSwingInterval           = 10 // Ticks between arm swings
	durabilityReductionInterval = 40 // Ticks between durability reductions (2 seconds)
	durabilityReductionAmount   = 5  // Amount to reduce durability each interval

	// Minecraft protocol position encoding constants
	// Position is encoded as: X (26 bits) << 38 | Z (26 bits) << 12 | Y (12 bits)
	positionXZMask = 0x3FFFFFF // 26-bit mask for X and Z coordinates
	positionYMask  = 0xFFF     // 12-bit mask for Y coordinate
)

var (
	client        *bot.Client
	player        *basic.Player
	shouldStop    bool
	shouldStopMutex sync.RWMutex // Protects shouldStop variable
	minedFirst    bool
	miningItem    int32 = -1  // Current slot holding mining item
	itemDurability int  = 100 // Current item durability (0-100)
	miningTicks    int  = 0   // Counter for mining ticks
	playerX       float64
	playerY       float64
	playerZ       float64
	playerYaw     float32
	playerPitch   float32
	miningMutex   sync.Mutex // Protects mining-related variables
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
		shouldStopMutex.Lock()
		shouldStop = true
		shouldStopMutex.Unlock()
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

	log.Printf("Successfully connected to server! (Minecraft %s)", version)

	// Keep the bot running in a goroutine to prevent blocking
	go func() {
		err = client.HandleGame()
		if err != nil {
			if !shouldStop {
				log.Printf("Game ended with error: %v", err)
			}
		}
	}()

	// Wait for shutdown signal (blocks indefinitely until interrupted)
	select {}
}

// onGameStart is called when the player joins the game
func onGameStart() error {
	log.Println("Game started! Bot is now in the game.")

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

	// Parse chat commands by checking for exact command words
	msgLower := strings.ToLower(msgText)
	words := strings.Fields(msgLower)
	
	for _, word := range words {
		switch word {
		case "!stop":
			log.Println("Received !stop command")
			go handleStopCommand()
			return nil
		case "!mine":
			log.Println("Received !mine command")
			go handleMineCommand()
			return nil
		case "!me":
			log.Println("Received !me command")
			go handleMeCommand(msgText)
			return nil
		}
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
	time.Sleep(basicMiningTime)

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
	position := int64(x&positionXZMask)<<38 | int64(z&positionXZMask)<<12 | int64(y&positionYMask)

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

	sendChatMessage("Starting mining simulation!")

	// Reset mining state with thread-safe access
	miningMutex.Lock()
	itemDurability = 100
	miningTicks = 0
	miningMutex.Unlock()

	// Start simulated mining
	go simulateMining()
}

// handleStopCommand gracefully stops the bot
func handleStopCommand() {
	log.Println("Executing !stop command...")

	sendChatMessage("Goodbye!")

	time.Sleep(1 * time.Second)

	shouldStopMutex.Lock()
	shouldStop = true
	shouldStopMutex.Unlock()
	
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

	// For Minecraft 1.21.1 chat packet format
	timestamp := time.Now().UnixMilli()
	err := client.Conn.WritePacket(pk.Marshal(
		packetid.ServerboundChat,
		pk.String(message),
		pk.Long(timestamp),
		pk.Long(0),          // Salt
		pk.ByteArray(nil),   // Signature (empty array)
		pk.Boolean(false),   // Has signature (false)
	))
	if err != nil {
		log.Printf("Failed to send chat message: %v", err)
	} else {
		log.Printf("Sent chat message: %s", message)
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
	time.Sleep(itemMiningTime)

	// Finish digging
	err = sendDigging(2, x, y, z, 1)
	if err != nil {
		log.Printf("Error finishing dig: %v", err)
		return
	}

	log.Println("Mining action completed")
}

// simulateMining simulates realistic mining with durability tracking
func simulateMining() {
	log.Println("Starting mining simulation with durability tracking...")

	// Calculate block position in front
	blockX := int(math.Floor(playerX))
	blockY := int(math.Floor(playerY))
	blockZ := int(math.Floor(playerZ + 1))

	for {
		// Check stop condition with thread-safe access
		shouldStopMutex.RLock()
		stopping := shouldStop
		shouldStopMutex.RUnlock()
		
		if stopping {
			break
		}

		miningMutex.Lock()
		currentDurability := itemDurability
		currentTicks := miningTicks
		miningTicks++
		miningMutex.Unlock()

		if currentDurability <= 0 {
			break
		}

		// Swing arm at regular intervals for visual feedback
		if currentTicks%armSwingInterval == 0 {
			err := sendSwingArm()
			if err != nil {
				log.Printf("Error swinging arm: %v", err)
			}
		}

		// Reduce durability at regular intervals
		if currentTicks%durabilityReductionInterval == 0 {
			miningMutex.Lock()
			itemDurability -= durabilityReductionAmount
			newDurability := itemDurability
			miningMutex.Unlock()

			log.Printf("Mining... Durability: %d%%", newDurability)

			if newDurability <= 0 {
				log.Println("Tool broke!")
				sendChatMessage("IT BROKEEEEE")
				break
			}

			// Mine a block
			mineWithItem(blockX, blockY, blockZ)
		}

		time.Sleep(tickDuration)
	}

	log.Println("Mining simulation ended")
}

// sendSwingArm sends an arm swing animation packet
func sendSwingArm() error {
	return client.Conn.WritePacket(pk.Marshal(
		packetid.ServerboundSwing,
		pk.VarInt(0), // Hand (0 = main hand)
	))
}
