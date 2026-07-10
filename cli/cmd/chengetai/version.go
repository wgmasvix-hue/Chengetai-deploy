package main

import (
	"fmt"

	"github.com/spf13/cobra"
)

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Show ChengetAI version",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("ChengetAI Deploy")
		fmt.Println("Version : 2.0.0-alpha")
		fmt.Println("Build   : 2026.07")
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
