package main

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/spf13/cobra"
)

var deployCmd = &cobra.Command{
	Use:   "deploy [platform] [name]",
	Short: "Deploy a new application",
	Long:  `Deploy a new application platform (dspace, koha, moodle, ojs, wordpress)`,
	Args:  cobra.RangeArgs(1, 2),
	RunE: func(cmd *cobra.Command, args []string) error {
		platform := args[0]
		name := ""
		if len(args) > 1 {
			name = args[1]
		}

		switch platform {
		case "dspace":
			return runEngine("deploy", "dspace", name)
		case "koha":
			return deployKohaDirect(name)
		default:
			return fmt.Errorf("unknown platform: %s", platform)
		}
	},
}

func runEngine(args ...string) error {
	cmdArgs := append([]string{"/opt/chengetai-deploy/chengetai-engine"}, args...)
	engineCmd := exec.Command("bash", cmdArgs...)
	engineCmd.Stdout = os.Stdout
	engineCmd.Stderr = os.Stderr
	engineCmd.Stdin = os.Stdin
	return engineCmd.Run()
}

func deployKohaDirect(name string) error {
	if name == "" {
		name = "library"
	}

	fmt.Println("╔════════════════════════════════════════════════╗")
	fmt.Println("║     ChengetAI Koha Deployment                 ║")
	fmt.Println("╚════════════════════════════════════════════════╝")
	fmt.Printf("\nDeploying Koha instance: %s\n\n", name)

	scriptPath := "/opt/chengetai-deploy/lib/koha-deploy.sh"
	
	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		return fmt.Errorf("Koha deployment script not found at %s", scriptPath)
	}

	cmd := exec.Command("bash", scriptPath, name)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("deployment failed: %w", err)
	}

	fmt.Println("\n✅ Run './chengetai' to see your new Koha instance!")
	return nil
}

func init() {
	rootCmd.AddCommand(deployCmd)
}
