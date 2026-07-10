package doctor

import (
	"bytes"
	"os/exec"
	"strings"
)

type Result struct {
	Name      string
	Version   string
	Installed bool
}

func Check(name string, command string, args ...string) Result {
	cmd := exec.Command(command, args...)

	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out

	err := cmd.Run()

	if err != nil {
		return Result{
			Name:      name,
			Installed: false,
			Version:   "Not Installed",
		}
	}

	return Result{
		Name:      name,
		Installed: true,
		Version:   strings.TrimSpace(out.String()),
	}
}
