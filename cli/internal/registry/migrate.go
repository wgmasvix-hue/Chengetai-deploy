package registry

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
	"gopkg.in/yaml.v3"
)

// DeploymentManifest represents the .chengetai/deployment.yaml marker file
type DeploymentManifest struct {
	ID      string `yaml:"id"`
	Plugin  string `yaml:"plugin"`
	Version string `yaml:"version"`
	Created string `yaml:"created"`
}

// DiscoverExistingDeployments scans for existing deployments
func (r *SQLiteRegistry) DiscoverExistingDeployments(basePath string) ([]models.Deployment, error) {
	var deployments []models.Deployment

	// Look for .chengetai marker files
	err := filepath.Walk(basePath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // Skip errors
		}

		if info.Name() == "deployment.yaml" && filepath.Base(filepath.Dir(path)) == ".chengetai" {
			// Read the manifest
			data, err := os.ReadFile(path)
			if err != nil {
				return nil
			}

			var manifest DeploymentManifest
			if err := yaml.Unmarshal(data, &manifest); err != nil {
				return nil
			}

			// Check if already in registry
			existing, _ := r.GetDeployment(manifest.ID)
			if existing != nil {
				return nil // Already registered
			}

			// Create deployment record
			createdAt, _ := time.Parse("2006-01-02", manifest.Created)
			deployment := models.Deployment{
				ID:        manifest.ID,
				Plugin:    manifest.Plugin,
				Name:      manifest.ID,
				Status:    "running", // Assume running if found
				CreatedAt: createdAt,
				UpdatedAt: time.Now(),
			}

			deployments = append(deployments, deployment)
		}

		return nil
	})

	return deployments, err
}

// ImportDeployment registers a discovered deployment
func (r *SQLiteRegistry) ImportDeployment(d *models.Deployment) error {
	return r.CreateDeployment(d)
}

// ScanAndImport discovers and imports all existing deployments
func (r *SQLiteRegistry) ScanAndImport(basePaths ...string) (int, error) {
	imported := 0

	for _, basePath := range basePaths {
		deployments, err := r.DiscoverExistingDeployments(basePath)
		if err != nil {
			continue
		}

		for _, d := range deployments {
			if err := r.ImportDeployment(&d); err != nil {
				fmt.Printf("Failed to import %s: %v\n", d.ID, err)
				continue
			}
			imported++
		}
	}

	return imported, nil
}
