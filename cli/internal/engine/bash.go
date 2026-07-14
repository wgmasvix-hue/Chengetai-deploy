package engine

import (
    "bufio"
    "context"
    "fmt"
    "os/exec"
    "strings"
    
    "github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
)

type BashEngine struct {
    EnginePath string
}

func NewBashEngine(enginePath string) *BashEngine {
    return &BashEngine{EnginePath: enginePath}
}

func (e *BashEngine) SystemStatus() (*models.SystemStatus, error) {
    status := &models.SystemStatus{}
    
    if out, err := exec.Command("hostname").Output(); err == nil {
        status.Hostname = strings.TrimSpace(string(out))
    }
    
    if out, err := exec.Command("lsb_release", "-ds").Output(); err == nil {
        status.OS = strings.TrimSpace(string(out))
    }
    
    if out, err := exec.Command("docker", "version", "--format", "{{.Server.Version}}").Output(); err == nil {
        status.DockerVersion = strings.TrimSpace(string(out))
    }
    
    if out, err := exec.Command("sh", "-c", "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1").Output(); err == nil {
        var cpu float64
        fmt.Sscanf(strings.TrimSpace(string(out)), "%f", &cpu)
        status.CPUPercent = cpu
    }
    
    if out, err := exec.Command("free", "-b").Output(); err == nil {
        lines := strings.Split(string(out), "\n")
        if len(lines) > 1 {
            fields := strings.Fields(lines[1])
            if len(fields) >= 3 {
                fmt.Sscanf(fields[1], "%d", &status.MemoryTotal)
                fmt.Sscanf(fields[2], "%d", &status.MemoryUsed)
            }
        }
    }
    
    if out, err := exec.Command("df", "-B1", "/").Output(); err == nil {
        lines := strings.Split(string(out), "\n")
        if len(lines) > 1 {
            fields := strings.Fields(lines[1])
            if len(fields) >= 4 {
                fmt.Sscanf(fields[1], "%d", &status.DiskTotal)
                fmt.Sscanf(fields[2], "%d", &status.DiskUsed)
            }
        }
    }
    
    if out, err := exec.Command("docker", "ps", "-q").Output(); err == nil {
        containers := strings.Split(strings.TrimSpace(string(out)), "\n")
        status.Containers = len(containers)
        if len(containers) == 1 && containers[0] == "" {
            status.Containers = 0
        }
    }
    
    return status, nil
}

func (e *BashEngine) Run(ctx context.Context, task *models.Task) error {
    return fmt.Errorf("not implemented")
}

func (e *BashEngine) Cancel(taskID string) error {
    return exec.Command("pkill", "-f", taskID).Run()
}

func (e *BashEngine) Status(taskID string) (string, error) {
    cmd := exec.Command("pgrep", "-f", taskID)
    if err := cmd.Run(); err != nil {
        return "completed", nil
    }
    return "running", nil
}

func (e *BashEngine) Logs(taskID string) (<-chan string, error) {
    ch := make(chan string, 100)
    go func() {
        defer close(ch)
        cmd := exec.Command("tail", "-f", fmt.Sprintf("/tmp/chengetai-%s.log", taskID))
        stdout, _ := cmd.StdoutPipe()
        cmd.Start()
        scanner := bufio.NewScanner(stdout)
        for scanner.Scan() {
            ch <- scanner.Text()
        }
    }()
    return ch, nil
}
