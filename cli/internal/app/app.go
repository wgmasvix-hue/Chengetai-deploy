package app

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/engine"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/registry"
)

type App struct {
	Registry *registry.SQLiteRegistry
	Engine   *engine.BashEngine
}

func New(reg *registry.SQLiteRegistry, eng *engine.BashEngine) *App {
	app := &App{
		Registry: reg,
		Engine:   eng,
	}
	
	app.autoImportDeployments()
	
	return app
}

func (a *App) autoImportDeployments() {
	count, err := a.Registry.DeploymentCount()
	if err != nil || count > 0 {
		return
	}
	
	deployments := []models.Deployment{
		{
			ID:        "dare",
			Plugin:    "dspace",
			Name:      "Dare Repository",
			Status:    "running",
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		},
		{
			ID:        "main-library",
			Plugin:    "koha",
			Name:      "Main Library",
			Status:    "running",
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		},
		{
			ID:        "farmOs",
			Plugin:    "farmOs",
			Name:      "My Farm",
			Status:    "running",
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		},
	}
	
	for _, d := range deployments {
		a.Registry.CreateDeployment(&d)
	}
}

func (a *App) SystemStatus() (*models.SystemStatus, error) {
	status, err := a.Engine.SystemStatus()
	if err != nil {
		return nil, err
	}

	deployments, err := a.Registry.DeploymentCount()
	if err == nil {
		status.Deployments = deployments
	}

	tasks, err := a.Registry.TaskCount()
	if err == nil {
		status.Tasks = tasks
	}

	return status, nil
}

func (a *App) ListDeployments() ([]models.Deployment, error) {
	return a.Registry.ListDeployments()
}

func (a *App) GetDeployment(id string) (*models.Deployment, error) {
	return a.Registry.GetDeployment(id)
}

func (a *App) ListContainers() ([]string, error) {
	out, err := exec.Command("docker", "ps", "--format", "{{.Names}}").Output()
	if err != nil {
		return nil, fmt.Errorf("docker ps failed: %w", err)
	}

	containers := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(containers) == 1 && containers[0] == "" {
		return []string{}, nil
	}

	return containers, nil
}
