package tui

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/charmbracelet/bubbletea"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/app"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
)

type KohaModel struct {
	app        *app.App
	deployment *models.Deployment
	containers []ContainerInfo
	logs       []string
	viewMode   string
	actionMsg  string
	actionType string
	cursor     int
	width      int
	height     int
}

func NewKohaModel(application *app.App, deployment *models.Deployment) *KohaModel {
	m := &KohaModel{
		app:        application,
		deployment: deployment,
		viewMode:   "overview",
	}
	m.refreshContainers()
	return m
}

func (m *KohaModel) refreshContainers() {
	m.containers = []ContainerInfo{}
	
	// Look for containers with the deployment ID as prefix
	prefix := m.deployment.ID
	
	cmd := exec.Command("docker", "ps", "-a",
		"--filter", fmt.Sprintf("name=%s", prefix),
		"--format", "{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}")
	out, err := cmd.Output()
	if err != nil {
		return
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
			}
			
			// Clean up ports display
			ports := parts[3]
			ports = strings.ReplaceAll(ports, "0.0.0.0:", "")
			ports = strings.ReplaceAll(ports, "[::]:", "")
			ports = strings.ReplaceAll(ports, ",", ", ")
			
			m.containers = append(m.containers, ContainerInfo{
				Name:   parts[0],
				Image:  parts[1],
				Status: parts[2],
				Ports:  ports,
				State:  state,
			})
		}
	}
}

func (m *KohaModel) Init() tea.Cmd {
	return nil
}

func (m *KohaModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
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
		case "s":
			m.actionMsg = "Starting Koha services..."
			m.actionType = "info"
			exec.Command("docker", "start",
				m.deployment.ID+"-db",
				m.deployment.ID+"-elasticsearch",
				m.deployment.ID+"-memcached",
				m.deployment.ID+"-app").Run()
			m.refreshContainers()
			return m, nil
		case "t":
			m.actionMsg = "Stopping Koha services..."
			m.actionType = "warning"
			exec.Command("docker", "stop",
				m.deployment.ID+"-app",
				m.deployment.ID+"-memcached",
				m.deployment.ID+"-elasticsearch",
				m.deployment.ID+"-db").Run()
			m.refreshContainers()
			return m, nil
		case "r":
			m.actionMsg = "Restarting Koha services..."
			m.actionType = "info"
			exec.Command("docker", "restart",
				m.deployment.ID+"-db",
				m.deployment.ID+"-elasticsearch",
				m.deployment.ID+"-memcached",
				m.deployment.ID+"-app").Run()
			m.refreshContainers()
			return m, nil
		case "l":
			m.viewMode = "logs"
			m.loadLogs()
			return m, nil
		case "o":
			m.viewMode = "overview"
			m.refreshContainers()
			return m, nil
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

func (m *KohaModel) loadLogs() {
	m.logs = []string{}
	cmd := exec.Command("docker", "logs", "--tail", "20", m.deployment.ID+"-app")
	out, err := cmd.Output()
	if err == nil {
		m.logs = strings.Split(string(out), "\n")
	}
}

func (m *KohaModel) View() string {
	var b strings.Builder

	b.WriteString(logoStyle.Render(logo))
	b.WriteString("\n\n")

	b.WriteString(titleStyle.Render(fmt.Sprintf(" Koha ILS: %s", m.deployment.Name)))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")

	// Action message
	if m.actionMsg != "" {
		msgColor := greenStyle
		if m.actionType == "warning" {
			msgColor = yellowStyle
		}
		b.WriteString(fmt.Sprintf(" %s\n\n", msgColor.Render(m.actionMsg)))
	}

	// Status
	statusColor := greenStyle
	statusText := "● Running"
	if m.deployment.Status == "stopped" {
		statusColor = yellowStyle
		statusText = "● Stopped"
	}
	
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Status:"), statusColor.Render(statusText)))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Platform:"), "Koha 24.05"))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Type:"), "Integrated Library System"))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("ID:"), dimStyle.Render(m.deployment.ID)))
	b.WriteString("\n")

	// Access URLs
	b.WriteString(titleStyle.Render(" Access URLs"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Staff:"), greenStyle.Render("http://144.91.125.128:8083")))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("OPAC:"), greenStyle.Render("http://144.91.125.128:8084")))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("MySQL:"), dimStyle.Render("localhost:3308")))
	b.WriteString("\n")

	// Containers
	b.WriteString(titleStyle.Render(" Containers"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	
	if len(m.containers) == 0 {
		b.WriteString(dimStyle.Render("  Loading containers...\n"))
	} else {
		for i, container := range m.containers {
			stateColor := greenStyle
			stateIcon := "● Up"
			if container.State == "exited" {
				stateColor = redStyle
				stateIcon = "● Down"
			}

			cursor := "  "
			if i == m.cursor {
				cursor = "▶ "
			}

			line := fmt.Sprintf(" %s%-25s %s %s\n",
				cursor,
				container.Name,
				stateColor.Render(stateIcon),
				dimStyle.Render(container.Ports))

			if i == m.cursor {
				b.WriteString(highlightStyle.Render(line))
			} else {
				b.WriteString(line)
			}
		}
	}
	b.WriteString("\n")

	// Actions
	b.WriteString(titleStyle.Render(" Quick Actions"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[S]"), menuStyle.Render("Start All")))
	b.WriteString(fmt.Sprintf("   %s %s\n", keyStyle.Render("[T]"), menuStyle.Render("Stop All")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[R]"), menuStyle.Render("Restart All")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[L]"), menuStyle.Render("View Logs")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[O]"), menuStyle.Render("Refresh")))
	b.WriteString("\n")

	// Navigation
	b.WriteString("\n ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[D]"), menuStyle.Render("Dashboard")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[P]"), menuStyle.Render("Deployments")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[↑↓]"), menuStyle.Render("Select")))
	b.WriteString(fmt.Sprintf("    %s %s\n", keyStyle.Render("[Esc]"), menuStyle.Render("Back")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[Q]"), menuStyle.Render("Quit")))
	b.WriteString(" ────────────────────────────────────────────\n")

	return b.String()
}
