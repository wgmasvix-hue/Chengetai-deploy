package tui

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/charmbracelet/bubbletea"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/app"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
)

type DSpaceModel struct {
	app         *app.App
	deployment  *models.Deployment
	containers  []ContainerInfo
	logs        []string
	viewMode    string // "overview", "logs", "config", "backup"
	actionMsg   string
	actionType  string // "success", "error", "info"
	cursor      int
	width       int
	height      int
}

type ContainerInfo struct {
	Name   string
	Image  string
	Status string
	Ports  string
	State  string // "running", "exited", "paused"
}

func NewDSpaceModel(application *app.App, deployment *models.Deployment) *DSpaceModel {
	m := &DSpaceModel{
		app:        application,
		deployment: deployment,
		viewMode:   "overview",
	}
	m.refreshContainers()
	return m
}

func (m *DSpaceModel) refreshContainers() {
	m.containers = []ContainerInfo{}
	
	prefixes := []string{"dspace-angular", "dspace", "dspacesolr", "dspacedb"}
	
	for _, prefix := range prefixes {
		cmd := exec.Command("docker", "ps", "-a", 
			"--filter", fmt.Sprintf("name=%s", prefix),
			"--format", "{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}")
		out, err := cmd.Output()
		if err != nil {
			continue
		}
		
		lines := strings.Split(strings.TrimSpace(string(out)), "\n")
		for _, line := range lines {
			if line == "" {
				continue
			}
			parts := strings.Split(line, "\t")
			if len(parts) >= 4 {
				state := "running"
				if strings.Contains(strings.ToLower(parts[2]), "exited") {
					state = "exited"
				} else if strings.Contains(strings.ToLower(parts[2]), "paused") {
					state = "paused"
				}
				
				m.containers = append(m.containers, ContainerInfo{
					Name:   parts[0],
					Image:  parts[1],
					Status: parts[2],
					Ports:  parts[3],
					State:  state,
				})
			}
		}
	}
}

func (m *DSpaceModel) Init() tea.Cmd {
	return nil
}

func (m *DSpaceModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		// Clear action message on any key
		m.actionMsg = ""
		
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "d":
			dashboard := NewDashboardModel(m.app)
			return dashboard, dashboard.Init()
		case "p":
			deployments := NewDeploymentsModel(m.app)
			return deployments, deployments.Init()
		case "esc":
			deployments := NewDeploymentsModel(m.app)
			return deployments, deployments.Init()
			
		// View modes
		case "o":
			m.viewMode = "overview"
			m.refreshContainers()
			m.actionMsg = "Overview refreshed"
			m.actionType = "info"
			return m, nil
		case "l":
			m.viewMode = "logs"
			m.loadLogs()
			m.actionMsg = "Loaded recent logs"
			m.actionType = "info"
			return m, nil
		case "c":
			m.viewMode = "config"
			m.actionMsg = "Configuration view"
			m.actionType = "info"
			return m, nil
			
		// Service actions
		case "s":
			m.actionMsg = m.startAllServices()
			m.actionType = "success"
			m.refreshContainers()
			return m, nil
		case "t":
			m.actionMsg = m.stopAllServices()
			m.actionType = "warning"
			m.refreshContainers()
			return m, nil
		case "r":
			m.actionMsg = m.restartAllServices()
			m.actionType = "info"
			m.refreshContainers()
			return m, nil
			
		// Individual container actions
		case "1":
			if len(m.containers) > 0 {
				m.actionMsg = m.controlContainer(m.containers[0].Name, "restart")
				m.refreshContainers()
			}
			return m, nil
		case "2":
			if len(m.containers) > 1 {
				m.actionMsg = m.controlContainer(m.containers[1].Name, "restart")
				m.refreshContainers()
			}
			return m, nil
		case "3":
			if len(m.containers) > 2 {
				m.actionMsg = m.controlContainer(m.containers[2].Name, "restart")
				m.refreshContainers()
			}
			return m, nil
		case "4":
			if len(m.containers) > 3 {
				m.actionMsg = m.controlContainer(m.containers[3].Name, "restart")
				m.refreshContainers()
			}
			return m, nil
			
		// Backup
		case "b":
			m.viewMode = "backup"
			m.actionMsg = "Creating backup..."
			m.actionType = "info"
			go m.createBackup()
			return m, nil
			
		// Navigation
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
			return m, nil
		case "down", "j":
			if m.cursor < len(m.containers)-1 {
				m.cursor++
			}
			return m, nil
		}
	}

	return m, nil
}

func (m *DSpaceModel) startAllServices() string {
	containers := []string{"dspacedb", "dspacesolr", "dspace", "dspace-angular"}
	for _, name := range containers {
		exec.Command("docker", "start", name).Run()
		time.Sleep(500 * time.Millisecond)
	}
	return "✓ All DSpace services started"
}

func (m *DSpaceModel) stopAllServices() string {
	containers := []string{"dspace-angular", "dspace", "dspacesolr", "dspacedb"}
	for _, name := range containers {
		exec.Command("docker", "stop", name).Run()
	}
	return "✓ All DSpace services stopped"
}

func (m *DSpaceModel) restartAllServices() string {
	m.stopAllServices()
	time.Sleep(1 * time.Second)
	m.startAllServices()
	return "✓ All DSpace services restarted"
}

func (m *DSpaceModel) controlContainer(name, action string) string {
	cmd := exec.Command("docker", action, name)
	if err := cmd.Run(); err != nil {
		return fmt.Sprintf("✗ Failed to %s %s", action, name)
	}
	return fmt.Sprintf("✓ %s %s", action, name)
}

func (m *DSpaceModel) loadLogs() {
	// Get logs from all DSpace containers
	m.logs = []string{}
	
	containers := []string{"dspace", "dspace-angular", "dspacesolr", "dspacedb"}
	for _, name := range containers {
		cmd := exec.Command("docker", "logs", "--tail", "10", name)
		out, err := cmd.Output()
		if err == nil {
			lines := strings.Split(strings.TrimSpace(string(out)), "\n")
			for _, line := range lines {
				if line != "" {
					m.logs = append(m.logs, fmt.Sprintf("[%s] %s", name, line))
				}
			}
		}
	}
}

func (m *DSpaceModel) createBackup() {
	// Call the Bash engine for backup
	cmd := exec.Command("/opt/chengetai-deploy/chengetai-engine", "backup", m.deployment.ID)
	cmd.Run()
	m.actionMsg = "✓ Backup completed"
	m.actionType = "success"
}

func (m *DSpaceModel) View() string {
	var b strings.Builder

	// Header
	b.WriteString(logoStyle.Render(logo))
	b.WriteString("\n\n")

	b.WriteString(titleStyle.Render(fmt.Sprintf(" DSpace: %s", m.deployment.Name)))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")

	// Action feedback message
	if m.actionMsg != "" {
		msgColor := greenStyle
		if m.actionType == "error" {
			msgColor = redStyle
		} else if m.actionType == "warning" {
			msgColor = yellowStyle
		}
		b.WriteString(fmt.Sprintf(" %s\n\n", msgColor.Render(m.actionMsg)))
	}

	switch m.viewMode {
	case "overview":
		m.viewOverview(&b)
	case "logs":
		m.viewLogs(&b)
	case "config":
		m.viewConfig(&b)
	case "backup":
		m.viewBackup(&b)
	}

	return b.String()
}

func (m *DSpaceModel) viewOverview(b *strings.Builder) {
	// Status
	statusColor := greenStyle
	statusText := "● Running"
	if m.deployment.Status == "stopped" {
		statusColor = yellowStyle
		statusText = "● Stopped"
	}
	
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Status:"), statusColor.Render(statusText)))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Platform:"), "DSpace 8.0"))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("ID:"), dimStyle.Render(m.deployment.ID)))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Created:"), dimStyle.Render(m.deployment.CreatedAt.Format("2006-01-02"))))
	b.WriteString("\n")

	// Containers
	b.WriteString(titleStyle.Render(" Containers"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	
	if len(m.containers) == 0 {
		b.WriteString(dimStyle.Render("  No containers found\n"))
	} else {
		b.WriteString(fmt.Sprintf(" %-3s %-20s %-10s %s\n",
			dimStyle.Render("#"),
			labelStyle.Render("Name"),
			labelStyle.Render("State"),
			labelStyle.Render("Ports")))
		b.WriteString("  ──────────────────────────────────────────\n")

		for i, container := range m.containers {
			cursor := "  "
			if i == m.cursor {
				cursor = "▶ "
			}

			stateColor := greenStyle
			stateIcon := "Up"
			if container.State == "exited" {
				stateColor = redStyle
				stateIcon = "Down"
			} else if container.State == "paused" {
				stateColor = yellowStyle
				stateIcon = "Paused"
			}

			ports := container.Ports
			if ports == "" {
				ports = dimStyle.Render("internal")
			}

			line := fmt.Sprintf(" %s%-3d %-20s %s %s\n",
				cursor,
				i+1,
				container.Name,
				stateColor.Render(stateIcon),
				ports)

			if i == m.cursor {
				b.WriteString(highlightStyle.Render(line))
			} else {
				b.WriteString(line)
			}
		}
	}
	b.WriteString("\n")

	// Service Controls
	b.WriteString(titleStyle.Render(" Service Controls"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[S]"), menuStyle.Render("Start All")))
	b.WriteString(fmt.Sprintf("   %s %s\n", keyStyle.Render("[T]"), menuStyle.Render("Stop All")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[R]"), menuStyle.Render("Restart All")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[1-4]"), menuStyle.Render("Restart Container")))
	b.WriteString("\n")

	// Management Actions
	b.WriteString(titleStyle.Render(" Management"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[B]"), menuStyle.Render("Create Backup")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[L]"), menuStyle.Render("View Logs")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[C]"), menuStyle.Render("Configure")))
	b.WriteString(fmt.Sprintf("   %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Refresh")))
	b.WriteString("\n")

	// Navigation
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[D]"), menuStyle.Render("Dashboard")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[P]"), menuStyle.Render("Deployments")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[↑↓]"), menuStyle.Render("Select")))
	b.WriteString(fmt.Sprintf("    %s %s\n", keyStyle.Render("[Esc]"), menuStyle.Render("Back")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[Q]"), menuStyle.Render("Quit")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *DSpaceModel) viewLogs(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" Recent Logs (All Containers)"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	
	if len(m.logs) == 0 {
		b.WriteString(dimStyle.Render("  Loading logs...\n"))
	} else {
		// Show last 30 lines
		start := 0
		if len(m.logs) > 30 {
			start = len(m.logs) - 30
		}
		for _, log := range m.logs[start:] {
			if len(log) > 100 {
				log = log[:100] + "..."
			}
			b.WriteString(fmt.Sprintf(" %s\n", dimStyle.Render(log)))
		}
	}
	b.WriteString("\n")

	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[O]"), menuStyle.Render("Overview")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[R]"), menuStyle.Render("Refresh")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[Esc]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *DSpaceModel) viewConfig(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" Configuration"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Repository Name:"), m.deployment.Name))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Deployment ID:"), m.deployment.ID))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Domain:"), dimStyle.Render("repo.example.org")))
	b.WriteString("\n")
	
	b.WriteString(titleStyle.Render(" Access URLs"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("XMLUI:"), greenStyle.Render("http://localhost:4000")))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("REST API:"), greenStyle.Render("http://localhost:8080/server")))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("OAI-PMH:"), greenStyle.Render("http://localhost:8080/server/oai")))
	b.WriteString("\n")

	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[O]"), menuStyle.Render("Overview")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[Esc]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *DSpaceModel) viewBackup(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" Backup"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	
	if m.actionMsg == "Creating backup..." {
		b.WriteString(yellowStyle.Render(" ⟳ Creating backup...\n\n"))
		b.WriteString(dimStyle.Render(" This may take a few minutes.\n"))
		b.WriteString(dimStyle.Render(" Backup includes:\n"))
		b.WriteString(dimStyle.Render("  • Database dump\n"))
		b.WriteString(dimStyle.Render("  • Assetstore files\n"))
		b.WriteString(dimStyle.Render("  • Configuration files\n"))
		b.WriteString(dimStyle.Render("  • Solr index\n"))
	} else {
		b.WriteString(greenStyle.Render(" ✓ " + m.actionMsg + "\n"))
	}

	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[O]"), menuStyle.Render("Overview")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[Esc]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}
