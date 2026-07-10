package main

import (
	"github.com/spf13/cobra"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/engine"
)

var deployCmd = &cobra.Command{
	Use:   "deploy",
	Short: "Deploy applications",
}

var deployDSpaceCmd = &cobra.Command{
	Use:   "dspace",
	Short: "Deploy DSpace",
	RunE: func(cmd *cobra.Command, args []string) error {
		return engine.Run("deploy", "dspace")
	},
}

func init() {
	rootCmd.AddCommand(deployCmd)
	deployCmd.AddCommand(deployDSpaceCmd)
}

