package runtime

import (
	"os"
	"path/filepath"

	"github.com/chengetai-labs/chengetai-deploy/internal/config"
)

func Prepare(d config.Deployment) error {

	dirs := []string{
		d.InstallPath,
		filepath.Join(d.InstallPath, "assetstore"),
		filepath.Join(d.InstallPath, "config"),
		filepath.Join(d.InstallPath, "logs"),
		filepath.Join(d.InstallPath, "postgres"),
		filepath.Join(d.InstallPath, "solr"),
	}

	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return err
		}
	}

	return nil
}
