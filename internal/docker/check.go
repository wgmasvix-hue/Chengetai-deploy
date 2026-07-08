package docker

import (
	"fmt"
	"os/exec"
)

func CheckDocker() error {
	cmd := exec.Command("docker", "--version")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf(
			"docker check failed\nCommand: docker --version\nOutput:\n%s\nError: %w",
			string(output),
			err,
		)
	}

	fmt.Printf("✓ %s", output)
	return nil
}

func CheckCompose() error {
	cmd := exec.Command("docker", "compose", "version")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf(
			"docker compose check failed\nCommand: docker compose version\nOutput:\n%s\nError: %w",
			string(output),
			err,
		)
	}

	fmt.Printf("✓ %s", output)
	return nil
}

func CheckDockerDaemon() error {
	cmd := exec.Command("docker", "info")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf(
			"docker daemon is not running\nCommand: docker info\nOutput:\n%s\nError: %w",
			string(output),
			err,
		)
	}

	fmt.Println("✓ Docker daemon is running")
	return nil
}

func Doctor() error {

	fmt.Println("Running Docker diagnostics...")
	fmt.Println()

	if err := CheckDocker(); err != nil {
		return err
	}

	if err := CheckCompose(); err != nil {
		return err
	}

	if err := CheckDockerDaemon(); err != nil {
		return err
	}

	fmt.Println()
	fmt.Println("✓ Docker environment is healthy")

	return nil
}
