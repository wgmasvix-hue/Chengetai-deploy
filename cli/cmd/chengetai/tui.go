package main

import (
	"github.com/spf13/cobra"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/tui"
)

var tuiCmd = &cobra.Command{
	Use:   "tui",
	Short: "Launch the ChengetAI terminal interface",
	Run: func(cmd *cobra.Command, args []string) {
		tui.Start()
	},
}

func init() {
	rootCmd.AddCommand(tuiCmd)
}
