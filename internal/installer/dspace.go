package installer

import (
	"fmt"
	"os/exec"

	"github.com/chengetai-labs/chengetai-deploy/internal/config"
)

func InstallDSpace(d config.Deployment) error {

	fmt.Println("Initializing DSpace database...")

	cmd := exec.Command(
		"docker",
		"exec",
		d.ID+"-dspace",
		"/dspace/bin/dspace",
		"database",
		"migrate",
	)

	cmd.Stdout = nil
	cmd.Stderr = nil

	if err := cmd.Run(); err != nil {
		return err
	}

	fmt.Println("Database migration completed.")

	return nil
}
