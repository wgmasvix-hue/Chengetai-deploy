package dspace10

import (
	"path/filepath"

	"github.com/chengetai-labs/chengetai-deploy/internal/config"
	"github.com/chengetai-labs/chengetai-deploy/internal/templates"
)

func Generate(d config.Deployment) error {

	if err := templates.RenderTemplate(
		"templates/dspace/docker-compose.yml.tmpl",
		filepath.Join(d.InstallPath, "docker-compose.yml"),
		d,
	); err != nil {
		return err
	}

	if err := templates.RenderTemplate(
		"templates/dspace/.env.tmpl",
		filepath.Join(d.InstallPath, ".env"),
		d,
	); err != nil {
		return err
	}

	return nil
}
