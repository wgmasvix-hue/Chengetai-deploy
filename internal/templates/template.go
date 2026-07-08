package templates

import (
	"os"
	"path/filepath"
	"text/template"

	"github.com/chengetai-labs/chengetai-deploy/internal/config"
)

func RenderTemplate(templatePath, outputPath string, deployment config.Deployment) error {

	tmpl, err := template.ParseFiles(templatePath)
	if err != nil {
		return err
	}

	if err := os.MkdirAll(filepath.Dir(outputPath), 0755); err != nil {
		return err
	}

	file, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer file.Close()

	return tmpl.Execute(file, deployment)
}
