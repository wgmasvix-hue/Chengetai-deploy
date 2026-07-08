package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"github.com/chengetai-labs/chengetai-deploy/plugins/dspace10"
)

var deployCmd = &cobra.Command{
	Use:   "deploy",
	Short: "Deploy services",
}

var deployDSpaceCmd = &cobra.Command{
	Use:   "dspace",
	Short: "Deploy DSpace 10",
	RunE: func(cmd *cobra.Command, args []string) error {

		plugin := dspace10.New()

		fmt.Printf("Deploying %s\n\n", plugin.Name())

		if err := plugin.CheckPrerequisites(); err != nil {
			return err
		}

		if err := plugin.Install(); err != nil {
			return err
		}

		return plugin.HealthCheck()
	},
}

func init() {
	rootCmd.AddCommand(deployCmd)
	deployCmd.AddCommand(deployDSpaceCmd)
}
