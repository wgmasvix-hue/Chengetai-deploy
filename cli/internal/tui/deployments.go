package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbletea"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/app"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
)

type DeploymentsModel struct {
	app         *app.App
	deployments []models.Deployment
	cursor      int
	width       int
	height      int
}

func NewDeploymentsModel(application *app.App) *DeploymentsModel {
	return &DeploymentsModel{
		app:    application,
		cursor: 0,
	}
}

func (m *DeploymentsModel) Init() tea.Cmd {
	return m.fetchDeployments
}

func (m *DeploymentsModel) fetchDeployments() tea.Msg {
	deployments, err := m.app.ListDeployments()
	if err != nil {
		return deploymentsErrMsg{err}
	}
	return deploymentsMsg{deployments}
}

func (m *DeploymentsModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
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
		case "d":
			dashboard := NewDashboardModel(m.app)
			return dashboard, dashboard.Init()
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
			return m, nil
		case "down", "j":
			if m.cursor < len(m.deployments)-1 {
				m.cursor++
			}
			return m, nil
		case "enter":
			if len(m.deployments) > 0 && m.cursor < len(m.deployments) {
				d := m.deployments[m.cursor]
				
				switch d.Plugin {
				case "dspace":
					dsModel := NewDSpaceModel(m.app, &d)
					return dsModel, dsModel.Init()
				case "koha":
					kohaModel := NewKohaModel(m.app, &d)
					return kohaModel, kohaModel.Init()
				case "farmOs":
					farmModel := NewFarmOSModel(m.app, &d)
					return farmModel, farmModel.Init()
				default:
					details := NewDetailsModel(m.app, d.ID)
					details.deployment = &d
					return details, details.Init()
				}
			}
			return m, nil
		}
	}

	return m, nil
}

func (m *DeploymentsModel) View() string {
	var b strings.Builder

	b.WriteString(logoStyle.Render(logo))
	b.WriteString("\n\n")

	b.WriteString(titleStyle.Render(" Deployments"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")

	if len(m.deployments) == 0 {
		b.WriteString(dimStyle.Render("  No managed deployments found.\n\n"))
	} else {
		b.WriteString(fmt.Sprintf("  %-3s %-20s %-15s %-12s %s\n",
			"",
			labelStyle.Render("Name"),
			labelStyle.Render("Platform"),
			labelStyle.Render("Status"),
			labelStyle.Render("ID")))
		b.WriteString("  ───────────────────────────────────────────────────────────\n")

		for i, d := range m.deployments {
			cursor := "  "
			if i == m.cursor {
				cursor = "▶ "
			}

			statusColor := greenStyle
			statusIcon := "● Running"
			if d.Status == "stopped" {
				statusColor = yellowStyle
				statusIcon = "● Stopped"
			} else if d.Status == "failed" {
				statusColor = redStyle
				statusIcon = "● Failed"
			}

			platformIcon := "📦"
			switch d.Plugin {
			case "dspace":
				platformIcon = "🗄️"
			case "koha":
				platformIcon = "📚"
			case "moodle":
				platformIcon = "🎓"
			case "ojs":
				platformIcon = "📄"
			case "wordpress":
				platformIcon = "🌐"
			case "farmOs":
				platformIcon = "🌾"
			}

			line := fmt.Sprintf(" %s%-3s %-20s %-15s %s %s\n",
				cursor,
				platformIcon,
				d.Name,
				d.Plugin,
				statusColor.Render(statusIcon),
				dimStyle.Render(d.ID))

			if i == m.cursor {
				b.WriteString(highlightStyle.Render(line))
			} else {
				b.WriteString(line)
			}
		}
	}

	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[D]"), menuStyle.Render("Dashboard")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[↑↓]"), menuStyle.Render("Navigate")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[Enter]"), menuStyle.Render("Manage")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[Q]"), menuStyle.Render("Quit")))
	b.WriteString(" ────────────────────────────────────────────\n")

	return b.String()
}
