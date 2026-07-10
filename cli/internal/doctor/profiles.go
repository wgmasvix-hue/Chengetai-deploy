package doctor

var Core = []Result{
	Check("Git", "git", "--version"),
	Check("Docker", "docker", "--version"),
	Check("Docker Compose", "docker", "compose", "version"),
	Check("Go", "go", "version"),
	Check("Curl", "curl", "--version"),
}

var DSpace = []Result{
	Check("Java", "java", "--version"),
	Check("Git", "git", "--version"),
	Check("Docker", "docker", "--version"),
	Check("Docker Compose", "docker", "compose", "version"),
	Check("PostgreSQL", "psql", "--version"),
}
