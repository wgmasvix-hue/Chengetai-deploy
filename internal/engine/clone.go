package engine

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/chengetai-labs/chengetai-deploy/internal/config"
)

const OfficialDSpaceDocker = "https://github.com/DSpace/dspace-docker.git"

func CloneOfficialRepo(d config.Deployment) error {

	target := filepath.Join(d.InstallPath, "dspace-docker")

	if _, err := os.Stat(target); err == nil {
		fmt.Println("Official DSpace Docker repository already exists.")
		return nil
	}

	fmt.Println("Cloning official DSpace Docker repository...")

	cmd := exec.Command(
		"git",
		"clone",
		OfficialDSpaceDocker,
		target,
	)

	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	return cmd.Run()
}
