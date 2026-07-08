package dspace10

import (
	"fmt"

	"github.com/chengetai-labs/chengetai-deploy/internal/docker"
)

type Plugin struct{}

func New() *Plugin {
	return &Plugin{}
}

func (p *Plugin) Name() string {
	return "DSpace 10"
}

func (p *Plugin) CheckPrerequisites() error {

	if err := docker.CheckDocker(); err != nil {
		return err
	}

	if err := docker.CheckCompose(); err != nil {
		return err
	}

	return nil
}

func (p *Plugin) Install() error {
	fmt.Println("Installing DSpace 10...")
	return nil
}

func (p *Plugin) Upgrade() error {
	fmt.Println("Upgrading DSpace 10...")
	return nil
}

func (p *Plugin) Backup() error {
	fmt.Println("Backing up DSpace 10...")
	return nil
}

func (p *Plugin) Restore() error {
	fmt.Println("Restoring DSpace 10...")
	return nil
}

func (p *Plugin) HealthCheck() error {
	fmt.Println("Checking DSpace health...")
	return nil
}
