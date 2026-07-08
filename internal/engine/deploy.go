package engine

import (
	"fmt"

	"github.com/chengetai-labs/chengetai-deploy/internal/config"
)

func Deploy(d config.Deployment) error {

	fmt.Println("ChengetAI Deploy Engine")
	fmt.Println()

	if err := CloneOfficialRepo(d); err != nil {
		return err
	}

	if err := Configure(d); err != nil {
		return err
	}

	if err := Install(d); err != nil {
		return err
	}

	return HealthCheck(d)
}
