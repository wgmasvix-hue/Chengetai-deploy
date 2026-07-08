package engine

import (
	"fmt"

	"github.com/chengetai-labs/chengetai-deploy/internal/config"
)

func HealthCheck(d config.Deployment) error {

	fmt.Println("Running health checks...")

	return nil
}
