package config

type Deployment struct {
	ID               string
	Name             string

	Platform         string
	Version          string

	Domain           string
	Email            string

	InstallPath      string

	AdminEmail       string
	DatabasePassword string

	BackendImage     string
	SolrImage        string
	AngularImage     string
}
