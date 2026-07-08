package dspace10

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/chengetai-labs/chengetai-deploy/internal/config"
	"github.com/chengetai-labs/chengetai-deploy/internal/docker"
	"github.com/chengetai-labs/chengetai-deploy/internal/installer"
	"github.com/chengetai-labs/chengetai-deploy/internal/runtime"
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

	deployment := config.Deployment{
		ID:               "demo",
		Name:             "ChengetAI Demo",
		Platform:         "dspace10",
		Version:          "10.0",
		Domain:           "repo.local",
		Email:            "admin@repo.local",
		AdminEmail:       "admin@repo.local",
		DatabasePassword: "dspace",
		InstallPath: filepath.Join(
			os.Getenv("HOME"),
			"chengetai",
			"deployments",
			"demo",
		),
	}

	images, err := GetImages(deployment.Version)
	if err != nil {
		return err
	}

	deployment.BackendImage = images.Backend
	deployment.SolrImage = images.Solr
	deployment.AngularImage = images.Angular

	fmt.Println("Preparing deployment...")

	if err := runtime.Prepare(deployment); err != nil {
		return err
	}

	if err := Generate(deployment); err != nil {
		return err
	}

	if err := docker.ComposeUp(deployment.InstallPath); err != nil {
		return err
	}

	if err := installer.InstallDSpace(deployment); err != nil {
		return err
	}

	fmt.Println()
	fmt.Println("Deployment generated successfully")
	fmt.Println(deployment.InstallPath)

	return nil
}

func (p *Plugin) Upgrade() error {
	return nil
}

func (p *Plugin) Backup() error {
	return nil
}

func (p *Plugin) Restore() error {
	return nil
}

func (p *Plugin) HealthCheck() error {
	fmt.Println("Checking DSpace health...")
	return nil
}
