package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbletea"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/app"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
)

type DetailsModel struct {
	app        *app.App
	deployment *models.Deployment
	containers []string
	width      int
	height     int
}

func NewDetailsModel(application *app.App, deploymentID string) *DetailsModel {
	return &DetailsModel{
		app: application,
	}
}

func (m *DetailsModel) Init() tea.Cmd {
	return nil
}

func (m *DetailsModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
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
		}
	}

	return m, nil
}

func (m *DetailsModel) View() string {
	var b strings.Builder

	b.WriteString(logoStyle.Render(logo))
	b.WriteString("\n\n")

	b.WriteString(titleStyle.Render(" Deployment Details"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")

	if m.deployment != nil {
		d := m.deployment
		b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Name:"), d.Name))
		b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("ID:"), d.ID))
		b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Platform:"), d.Plugin))
		
		statusColor := greenStyle
		if d.Status == "stopped" {
			statusColor = yellowStyle
		} else if d.Status == "failed" {
			statusColor = redStyle
		}
		b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Status:"), statusColor.Render("● "+d.Status)))
		b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Created:"), dimStyle.Render(d.CreatedAt.Format("2006-01-02"))))
		
		if d.Domain != "" {
			b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Domain:"), d.Domain))
		}
		b.WriteString("\n")

		// Actions
		b.WriteString(titleStyle.Render(" Actions"))
		b.WriteString("\n")
		b.WriteString(" ────────────────────────────────────────────\n")
		b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[S]"), menuStyle.Render("Start")))
		b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[T]"), menuStyle.Render("Stop")))
		b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[R]"), menuStyle.Render("Restart")))
		b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[B]"), menuStyle.Render("Backup")))
		b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[L]"), menuStyle.Render("Logs")))
		b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[X]"), menuStyle.Render("Remove")))
		b.WriteString("\n")
	}

	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[D]"), menuStyle.Render("Dashboard")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[P]"), menuStyle.Render("Deployments")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[Esc]"), menuStyle.Render("Back")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[Q]"), menuStyle.Render("Quit")))
	b.WriteString(" ────────────────────────────────────────────\n")

	return b.String()
}
