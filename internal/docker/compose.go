package docker

import (
	"fmt"
	"os"
	"os/exec"
)

func ComposeUp(dir string) error {

	fmt.Println("Starting Docker containers...")

	cmd := exec.Command("docker", "compose", "up", "-d")
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	return cmd.Run()
}
