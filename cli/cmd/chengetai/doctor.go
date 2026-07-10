package main

import (
	"github.com/spf13/cobra"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/engine"
)

var doctorCmd = &cobra.Command{
	Use:   "doctor",
	Short: "Check system health",
	RunE: func(cmd *cobra.Command, args []string) error {
		return engine.Run("doctor")
	},
}

func init() {
	rootCmd.AddCommand(doctorCmd)
}
