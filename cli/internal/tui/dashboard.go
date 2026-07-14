package tui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/app"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
)

var (
	logoStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#7c3aed")).
			Bold(true)

	headerStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#7c3aed")).
			Align(lipgloss.Center)

	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#ffffff"))

	labelStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#a78bfa"))

	greenStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#22c55e"))

	yellowStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#eab308"))

	redStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#ef4444"))

	dimStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#6b7280"))

	menuStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#9ca3af"))

	keyStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#7c3aed"))

	highlightStyle = lipgloss.NewStyle().
			Background(lipgloss.Color("#7c3aed")).
			Foreground(lipgloss.Color("#ffffff")).
			Padding(0, 2)
)

const logo = `
 ██████╗██╗  ██╗███████╗███╗   ██╗ ██████╗ ███████╗████████╗ █████╗ ██╗
██╔════╝██║  ██║██╔════╝████╗  ██║██╔════╝ ██╔════╝╚══██╔══╝██╔══██╗██║
██║     ███████║█████╗  ██╔██╗ ██║██║  ███╗█████╗     ██║   ███████║██║
██║     ██╔══██║██╔══╝  ██║╚██╗██║██║   ██║██╔══╝     ██║   ██╔══██║██║
╚██████╗██║  ██║███████╗██║ ╚████║╚██████╔╝███████╗   ██║   ██║  ██║██║
 ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝
`

type DashboardModel struct {
	app         *app.App
	status      *models.SystemStatus
	containers  []string
	deployments []models.Deployment
	width       int
	height      int
}

func NewDashboardModel(application *app.App) *DashboardModel {
	return &DashboardModel{app: application}
}

func (m *DashboardModel) Init() tea.Cmd {
	return tea.Batch(m.fetchStatus, m.fetchContainers, m.fetchDeployments)
}

func (m *DashboardModel) fetchStatus() tea.Msg {
	status, err := m.app.SystemStatus()
	if err != nil {
		return statusErrMsg{err}
	}
	return statusMsg{status}
}

func (m *DashboardModel) fetchContainers() tea.Msg {
	containers, err := m.app.ListContainers()
	if err != nil {
		return containersErrMsg{err}
	}
	return containersMsg{containers}
}

func (m *DashboardModel) fetchDeployments() tea.Msg {
	deployments, err := m.app.ListDeployments()
	if err != nil {
		return deploymentsErrMsg{err}
	}
	return deploymentsMsg{deployments}
}

type statusMsg struct {
	status *models.SystemStatus
}

type statusErrMsg struct {
	err error
}

type containersMsg struct {
	containers []string
}

type containersErrMsg struct {
	err error
}

type deploymentsMsg struct {
	deployments []models.Deployment
}

type deploymentsErrMsg struct {
	err error
}

func (m *DashboardModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case statusMsg:
		m.status = msg.status
		return m, tea.Tick(3*time.Second, func(t time.Time) tea.Msg {
			return m.fetchStatus()
		})

	case statusErrMsg:
		return m, tea.Tick(5*time.Second, func(t time.Time) tea.Msg {
			return m.fetchStatus()
		})

	case containersMsg:
		m.containers = msg.containers
		return m, tea.Tick(10*time.Second, func(t time.Time) tea.Msg {
			return m.fetchContainers()
		})

	case containersErrMsg:
		return m, nil

	case deploymentsMsg:
		m.deployments = msg.deployments
		return m, nil

	case deploymentsErrMsg:
		return m, nil

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "p":
			// Switch to deployments page
			deployModel := NewDeploymentsModel(m.app)
			return deployModel, deployModel.Init()
		case "d":
			return m, nil
		}
	}

	return m, nil
}

func (m *DashboardModel) View() string {
	if m.status == nil {
		return "Loading dashboard...\n"
	}

	s := m.status

	var b strings.Builder

	b.WriteString(logoStyle.Render(logo))
	b.WriteString("\n")
	b.WriteString(headerStyle.Render("══════════════════════════════════════════════════════════"))
	b.WriteString("\n\n")

	// System Health
	b.WriteString(titleStyle.Render(" System Health") + "\n")
	b.WriteString(" ────────────────────────────────────────────\n")

	healthColor := greenStyle
	healthStatus := "Healthy"
	if s.CPUPercent > 80 {
		healthColor = redStyle
		healthStatus = "Critical"
	} else if s.CPUPercent > 60 {
		healthColor = yellowStyle
		healthStatus = "Warning"
	}
	b.WriteString(fmt.Sprintf(" %s %s  %s\n\n",
		healthColor.Render("● "+healthStatus),
		labelStyle.Render(s.Hostname),
		dimStyle.Render(s.OS)))

	// Resource bars
	cpuBar := progressBar(s.CPUPercent, 100, 20)
	memPercent := float64(s.MemoryUsed) / float64(s.MemoryTotal) * 100
	memBar := progressBar(memPercent, 100, 20)
	diskUsedPercent := float64(s.DiskUsed) / float64(s.DiskTotal) * 100
	diskBar := progressBar(diskUsedPercent, 100, 20)

	memUsed := float64(s.MemoryUsed) / 1024 / 1024 / 1024
	memTotal := float64(s.MemoryTotal) / 1024 / 1024 / 1024
	diskFree := float64(s.DiskTotal-s.DiskUsed) / 1024 / 1024 / 1024

	b.WriteString(fmt.Sprintf(" CPU    %s %5.0f%%\n", cpuBar, s.CPUPercent))
	b.WriteString(fmt.Sprintf(" Memory %s %.1f/%.0f GB\n", memBar, memUsed, memTotal))
	b.WriteString(fmt.Sprintf(" Disk   %s %.0f GB Free\n", diskBar, diskFree))

	if s.DockerVersion != "" {
		b.WriteString(fmt.Sprintf(" Docker %s %s\n\n", greenStyle.Render("●"), s.DockerVersion))
	}

	// Managed Deployments
	b.WriteString(titleStyle.Render(" Managed Deployments") + "\n")
	b.WriteString(" ────────────────────────────────────────────\n")

	if len(m.deployments) == 0 {
		b.WriteString(dimStyle.Render(" No managed deployments") + "\n")
	} else {
		for _, d := range m.deployments {
			statusColor := greenStyle
			statusIcon := "●"
			if d.Status == "stopped" {
				statusColor = yellowStyle
			} else if d.Status == "failed" {
				statusColor = redStyle
			}
			b.WriteString(fmt.Sprintf(" %s %-20s %s\n",
				statusColor.Render(statusIcon),
				d.Name,
				dimStyle.Render(d.Plugin+" "+d.Status)))
		}
	}
	b.WriteString("\n")

	// Running Containers
	b.WriteString(titleStyle.Render(" Running Containers") + "\n")
	b.WriteString(" ────────────────────────────────────────────\n")

	if len(m.containers) == 0 {
		b.WriteString(dimStyle.Render(" No running containers\n"))
	} else {
		limit := 5
		if len(m.containers) < limit {
			limit = len(m.containers)
		}
		for i := 0; i < limit; i++ {
			b.WriteString(fmt.Sprintf(" %s %s\n", greenStyle.Render("●"), m.containers[i]))
		}
		if len(m.containers) > 5 {
			b.WriteString(dimStyle.Render(fmt.Sprintf(" ... and %d more\n", len(m.containers)-5)))
		}
	}
	b.WriteString("\n")

	// Active Tasks
	if s.Tasks > 0 {
		b.WriteString(titleStyle.Render(" Active Tasks") + "\n")
		b.WriteString(" ────────────────────────────────────────────\n")
		b.WriteString(fmt.Sprintf(" %s %d task(s) in progress\n\n", yellowStyle.Render("●"), s.Tasks))
	}

	// Menu
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[D]"), menuStyle.Render("Dashboard")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[P]"), menuStyle.Render("Deployments")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[C]"), menuStyle.Render("Create")))
	b.WriteString(fmt.Sprintf("    %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Doctor")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[L]"), menuStyle.Render("Logs")))
	b.WriteString(fmt.Sprintf("      %s %s\n", keyStyle.Render("[A]"), menuStyle.Render("AI")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[S]"), menuStyle.Render("Settings")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[Q]"), menuStyle.Render("Quit")))
	b.WriteString(" ────────────────────────────────────────────\n")

	return b.String()
}

func progressBar(current, total, width float64) string {
	if total == 0 {
		return dimStyle.Render("[" + strings.Repeat(" ", int(width)) + "]")
	}

	filled := int((current / total) * width)
	if filled > int(width) {
		filled = int(width)
	}

	bar := ""
	for i := 0; i < filled; i++ {
		bar += "█"
	}
	for i := filled; i < int(width); i++ {
		bar += "░"
	}

	if current/total > 0.8 {
		return redStyle.Render("[" + bar + "]")
	} else if current/total > 0.6 {
		return yellowStyle.Render("[" + bar + "]")
	}
	return greenStyle.Render("[" + bar + "]")
}
