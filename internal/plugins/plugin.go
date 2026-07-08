package plugins

type Plugin interface {
	Name() string
	CheckPrerequisites() error
	Install() error
	Upgrade() error
	Backup() error
	Restore() error
	HealthCheck() error
}
