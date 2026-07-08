package engine

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/chengetai-labs/chengetai-deploy/internal/config"
)

func Install(d config.Deployment) error {

	project := filepath.Join(d.InstallPath, "dspace-docker")

	fmt.Println("Starting official DSpace Docker deployment...")

	cmd := exec.Command(
		"docker",
		"compose",
		"up",
		"-d",
	)

	cmd.Dir = project
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	return cmd.Run()
}
