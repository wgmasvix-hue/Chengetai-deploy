package main

import (
    "fmt"
    "github.com/wgmasvix-hue/chengetai-deploy/cli/internal/app"
    "github.com/wgmasvix-hue/chengetai-deploy/cli/internal/engine"
    "github.com/wgmasvix-hue/chengetai-deploy/cli/internal/registry"
)

func main() {
    reg, _ := registry.NewSQLiteRegistry("/opt/chengetai-deploy/registry.db")
    eng := engine.NewBashEngine("/opt/chengetai-deploy")
    application := app.New(reg, eng)
    
    deployments, err := application.ListDeployments()
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        return
    }
    
    fmt.Printf("Found %d deployments:\n", len(deployments))
    for _, d := range deployments {
        fmt.Printf("  - %s (%s) [%s]\n", d.Name, d.Plugin, d.Status)
    }
}
