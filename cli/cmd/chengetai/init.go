package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"golang.org/x/crypto/bcrypt"
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize ChengetAI Deploy",
	RunE: func(cmd *cobra.Command, args []string) error {

		reader := bufio.NewReader(os.Stdin)

		fmt.Println()
		fmt.Println("===================================")
		fmt.Println(" ChengetAI Deploy Initialization")
		fmt.Println("===================================")

		fmt.Print("Administrator Name: ")
		name, _ := reader.ReadString('\n')

		fmt.Print("Username: ")
		username, _ := reader.ReadString('\n')

		fmt.Print("Email: ")
		email, _ := reader.ReadString('\n')

		fmt.Print("Password: ")
		password, _ := reader.ReadString('\n')

		hash, err := bcrypt.GenerateFromPassword(
			[]byte(strings.TrimSpace(password)),
			bcrypt.DefaultCost,
		)

		if err != nil {
			return err
		}

		configDir := "/etc/chengetai"

		if err := os.MkdirAll(configDir, 0755); err != nil {
			return err
		}

		viper.Set("admin.name", strings.TrimSpace(name))
		viper.Set("admin.username", strings.TrimSpace(username))
		viper.Set("admin.email", strings.TrimSpace(email))
		viper.Set("admin.password_hash", string(hash))

		viper.SetConfigType("yaml")
		viper.SetConfigFile(filepath.Join(configDir, "config.yaml"))

		if err := viper.WriteConfigAs(filepath.Join(configDir, "config.yaml")); err != nil {
			return err
		}

		fmt.Println()
		fmt.Println("✓ ChengetAI initialized")
		fmt.Println("✓ Configuration written to /etc/chengetai/config.yaml")

		return nil
	},
}

func init() {
	rootCmd.AddCommand(initCmd)
}
