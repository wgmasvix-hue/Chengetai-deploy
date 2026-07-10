package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/ui"
)

var rootCmd = &cobra.Command{
	Use:   "chengetai",
	Short: "ChengetAI Deploy",
	Long:  "ChengetAI Deploy - Enterprise AI Deployment Platform",
	Run: func(cmd *cobra.Command, args []string) {
		ui.PrintBanner()
		fmt.Println("Welcome to ChengetAI Deploy")
		fmt.Println()
		fmt.Println("Type 'chengetai --help' to get started.")
	},
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
