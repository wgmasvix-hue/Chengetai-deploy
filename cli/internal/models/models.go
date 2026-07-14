package models

import "time"

type Deployment struct {
    ID        string    `json:"id"`
    Plugin    string    `json:"plugin"`
    Name      string    `json:"name"`
    Status    string    `json:"status"`
    Phase     string    `json:"phase,omitempty"`
    Host      string    `json:"host,omitempty"`
    Domain    string    `json:"domain,omitempty"`
    Ports     string    `json:"ports,omitempty"`
    Config    string    `json:"config,omitempty"`
    CreatedAt time.Time `json:"created_at"`
    UpdatedAt time.Time `json:"updated_at"`
}

type Task struct {
    ID        string     `json:"id"`
    Type      string     `json:"type"`
    Resource  string     `json:"resource"`
    Status    string     `json:"status"`
    Progress  int        `json:"progress"`
    Phase     string     `json:"phase,omitempty"`
    Error     string     `json:"error,omitempty"`
    CreatedAt time.Time  `json:"created_at"`
    StartedAt *time.Time `json:"started_at,omitempty"`
    EndedAt   *time.Time `json:"ended_at,omitempty"`
}

type Backup struct {
    ID           string    `json:"id"`
    DeploymentID string    `json:"deployment_id"`
    Type         string    `json:"type"`
    SizeBytes    int64     `json:"size_bytes"`
    Path         string    `json:"path"`
    Status       string    `json:"status"`
    Error        string    `json:"error,omitempty"`
    CreatedAt    time.Time `json:"created_at"`
}

type Server struct {
    ID     string `json:"id"`
    Name   string `json:"name"`
    Host   string `json:"host"`
    Port   int    `json:"port"`
    User   string `json:"user"`
    Status string `json:"status"`
}

type Plugin struct {
    ID           string `json:"id"`
    Name         string `json:"name"`
    Version      string `json:"version"`
    Capabilities string `json:"capabilities"`
    Status       string `json:"status"`
}

type SystemStatus struct {
    Hostname      string  `json:"hostname"`
    OS            string  `json:"os"`
    DockerVersion string  `json:"docker_version"`
    CPUPercent    float64 `json:"cpu_percent"`
    MemoryUsed    uint64  `json:"memory_used"`
    MemoryTotal   uint64  `json:"memory_total"`
    DiskUsed      uint64  `json:"disk_used"`
    DiskTotal     uint64  `json:"disk_total"`
    Deployments   int     `json:"deployments"`
    Containers    int     `json:"containers"`
    Tasks         int     `json:"tasks"`
}
