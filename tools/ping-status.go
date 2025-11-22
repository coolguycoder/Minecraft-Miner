package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/Tnze/go-mc/bot"
	"github.com/Tnze/go-mc/chat"
)

// ServerStatus represents the parsed Minecraft server status response
type ServerStatus struct {
	Description chat.Message `json:"description"`
	Players     struct {
		Max    int `json:"max"`
		Online int `json:"online"`
		Sample []struct {
			Name string `json:"name"`
			ID   string `json:"id"`
		} `json:"sample"`
	} `json:"players"`
	Version struct {
		Name     string `json:"name"`
		Protocol int    `json:"protocol"`
	} `json:"version"`
	Favicon string `json:"favicon,omitempty"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <server-address:port>\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "Example: %s 100.94.216.120:25565\n", os.Args[0])
		os.Exit(1)
	}

	addr := os.Args[1]

	// Ping the server
	resp, delay, err := bot.PingAndList(addr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: Failed to ping server: %v\n", err)
		os.Exit(1)
	}

	// Parse the JSON response
	var status ServerStatus
	err = json.Unmarshal(resp, &status)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: Failed to parse server response: %v\n", err)
		os.Exit(1)
	}

	// Flatten MOTD text (remove JSON formatting)
	motdText := flattenMessage(status.Description)

	// Detect modded server type based on heuristics
	moddedType := detectModType(status.Version.Name, motdText)

	// Print machine-readable output
	fmt.Printf("PROTOCOL=%d VERSION_NAME=\"%s\" MODDED=%s\n",
		status.Version.Protocol,
		status.Version.Name,
		moddedType)

	// Print human-readable details to stderr for debugging
	fmt.Fprintf(os.Stderr, "Server Status:\n")
	fmt.Fprintf(os.Stderr, "  Version: %s (Protocol %d)\n", status.Version.Name, status.Version.Protocol)
	fmt.Fprintf(os.Stderr, "  MOTD: %s\n", motdText)
	fmt.Fprintf(os.Stderr, "  Players: %d/%d\n", status.Players.Online, status.Players.Max)
	fmt.Fprintf(os.Stderr, "  Delay: %v\n", delay)
	fmt.Fprintf(os.Stderr, "  Detected Type: %s\n", moddedType)

	if len(status.Players.Sample) > 0 {
		fmt.Fprintf(os.Stderr, "  Sample Players:\n")
		for _, player := range status.Players.Sample {
			fmt.Fprintf(os.Stderr, "    - %s (%s)\n", player.Name, player.ID)
		}
	}
}

// flattenMessage extracts plain text from a chat.Message
func flattenMessage(msg chat.Message) string {
	var sb strings.Builder
	flattenMessageRecursive(&msg, &sb)
	return strings.TrimSpace(sb.String())
}

// flattenMessageRecursive recursively extracts text from chat messages
func flattenMessageRecursive(msg *chat.Message, sb *strings.Builder) {
	// Add the text content of this message
	if msg.Text != "" {
		sb.WriteString(msg.Text)
	}

	// Process extra messages (nested components)
	for i := range msg.Extra {
		flattenMessageRecursive(&msg.Extra[i], sb)
	}
}

// detectModType detects if the server is running Fabric, Forge, or vanilla
func detectModType(versionName, motd string) string {
	versionLower := strings.ToLower(versionName)
	motdLower := strings.ToLower(motd)

	// Check for Fabric indicators
	if strings.Contains(versionLower, "fabric") || strings.Contains(motdLower, "fabric") {
		return "fabric"
	}

	// Check for Forge indicators
	if strings.Contains(versionLower, "forge") || strings.Contains(motdLower, "forge") ||
		strings.Contains(motdLower, "fml") {
		return "forge"
	}

	// Default to unknown/vanilla
	return "unknown"
}
