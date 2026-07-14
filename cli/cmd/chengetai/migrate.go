package main

import (
	"fmt"
	"time"

	"github.com/spf13/cobra"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/registry"
)

var migrateCmd = &cobra.Command{
	Use:   "migrate",
	Short: "Import existing deployments into the registry",
	RunE: func(cmd *cobra.Command, args []string) error {
		reg, err := registry.NewSQLiteRegistry("/opt/chengetai-deploy/registry.db")
		if err != nil {
			return fmt.Errorf("failed to open registry: %w", err)
		}
		defer reg.Close()

		fmt.Println("Scanning for existing deployments...")

		// Manual import of known deployments
		deployments := []models.Deployment{
			{
				ID:        "dare",
				Plugin:    "dspace",
				Name:      "Dare Repository",
				Status:    "running",
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			},
			{
				ID:        "open-webui",
				Plugin:    "open-webui",
				Name:      "Open WebUI",
				Status:    "running",
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			},
			{
				ID:        "farmOs",
				Plugin:    "farmOs",
				Name:      "farmOS",
				Status:    "running",
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			},
		}

		imported := 0
		for _, d := range deployments {
			if err := reg.CreateDeployment(&d); err != nil {
				fmt.Printf("  Skipped %s: %v\n", d.Name, err)
				continue
			}
			fmt.Printf("  ✓ Imported %s (%s)\n", d.Name, d.Plugin)
			imported++
		}

		fmt.Printf("\nSuccessfully imported %d deployment(s).\n", imported)
		fmt.Println("Run 'chengetai' to see them in the dashboard.")

		return nil
	},
}

func init() {
	rootCmd.AddCommand(migrateCmd)
}
