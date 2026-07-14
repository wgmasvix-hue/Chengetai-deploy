package main

import (
	"fmt"
	"os"

	"github.com/charmbracelet/bubbletea"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/app"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/engine"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/registry"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/tui"
)

func main() {
	// Initialize registry
	reg, err := registry.NewSQLiteRegistry("/opt/chengetai-deploy/registry.db")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to initialize registry: %v\n", err)
		os.Exit(1)
	}
	defer reg.Close()

	// Initialize engine
	eng := engine.NewBashEngine("/opt/chengetai-deploy")

	// Create app
	application := app.New(reg, eng)

	// Launch TUI with dashboard
	dashboard := tui.NewDashboardModel(application)

	p := tea.NewProgram(dashboard, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
