package engine

import (
	"os"
	"os/exec"
)

const EnginePath = "/opt/chengetai-deploy/chengetai-engine"

func Run(args ...string) error {
	cmd := exec.Command(EnginePath, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}
