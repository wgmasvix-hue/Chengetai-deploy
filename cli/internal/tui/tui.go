package tui

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
)

type model struct {
	cursor int
	items  []string
}

func New() model {
	return model{
		items: []string{
			"Dashboard",
			"Deployments",
			"Doctor",
			"Create Deployment",
			"Logs",
			"Backup",
			"Restore",
			"Plugins",
			"AI Assistant",
			"Settings",
			"Exit",
		},
	}
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {

	case tea.KeyMsg:

		switch msg.String() {

		case "ctrl+c", "q":
			return m, tea.Quit

		case "up":
			if m.cursor > 0 {
				m.cursor--
			}

		case "down":
			if m.cursor < len(m.items)-1 {
				m.cursor++
			}

		case "enter":
			if m.items[m.cursor] == "Exit" {
				return m, tea.Quit
			}

			fmt.Println("Selected:", m.items[m.cursor])
		}

	}

	return m, nil
}

func (m model) View() string {

	s := "\nChengetAI Deploy\n\n"

	for i, item := range m.items {

		cursor := " "

		if m.cursor == i {
			cursor = ">"
		}

		s += fmt.Sprintf("%s %s\n", cursor, item)
	}

	s += "\n↑↓ Move   Enter Select   q Quit\n"

	return s
}

func Run() error {
	p := tea.NewProgram(New())
	_, err := p.Run()
	return err
}

func Start() {
	if err := Run(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
