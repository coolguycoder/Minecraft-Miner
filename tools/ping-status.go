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

	// Print machine-readable output with proper shell escaping
	// Replace quotes and special chars to prevent command injection
	safeVersionName := strings.ReplaceAll(status.Version.Name, "\"", "\\\"")
	safeVersionName = strings.ReplaceAll(safeVersionName, "$", "\\$")
	safeVersionName = strings.ReplaceAll(safeVersionName, "`", "\\`")
	
	fmt.Printf("PROTOCOL=%d VERSION_NAME=\"%s\" MODDED=%s\n",
		status.Version.Protocol,
		safeVersionName,
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
	
	// Use iterative approach with a stack to avoid stack overflow
	// on deeply nested messages
	stack := []*chat.Message{&msg}
	depth := 0
	maxDepth := 100 // Reasonable limit to prevent infinite loops
	
	for len(stack) > 0 && depth < maxDepth {
		current := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		
		// Add the text content of this message
		if current.Text != "" {
			sb.WriteString(current.Text)
		}
		
		// Add nested messages to stack (in reverse order to maintain order)
		for i := len(current.Extra) - 1; i >= 0; i-- {
			stack = append(stack, &current.Extra[i])
		}
		
		depth++
	}
	
	return strings.TrimSpace(sb.String())
}

// detectModType detects if the server is running Fabric, Forge, or vanilla
func detectModType(versionName, motd string) string {
	versionLower := strings.ToLower(versionName)
	motdLower := strings.ToLower(motd)

	// Check for Fabric indicators - use word boundaries to avoid false positives
	// Look for "fabric" as a word (not part of "fabricated", etc.)
	if containsWord(versionLower, "fabric") || containsWord(motdLower, "fabric") {
		return "fabric"
	}

	// Check for Forge indicators
	if containsWord(versionLower, "forge") || containsWord(motdLower, "forge") ||
		containsWord(motdLower, "fml") {
		return "forge"
	}

	// Default to unknown/vanilla
	return "unknown"
}

// containsWord checks if a word exists in a string with word boundaries
func containsWord(text, word string) bool {
	// Simple word boundary check: word must be preceded/followed by non-letter or be at start/end
	text = " " + text + " "
	word = " " + word + " "
	return strings.Contains(text, word)
}
