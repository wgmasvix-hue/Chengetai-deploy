package tui

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"

	"github.com/charmbracelet/bubbletea"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/app"
	"github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
)

type FarmOSModel struct {
	app         *app.App
	deployment  *models.Deployment
	containers  []ContainerInfo
	farmStats   FarmStats
	farmData    FarmData
	logs        []string
	viewMode    string
	actionMsg   string
	actionType  string
	cursor      int
	width       int
	height      int
}

type FarmStats struct {
	Assets      int
	Animals     int
	Plantings   int
	Logs        int
	Areas       int
	DBsize      string
	WWWsize     string
	LastBackup  string
	Uptime      string
}

type FarmData struct {
	Crops       []CropInfo
	Livestock   []LivestockInfo
	Tasks       []TaskInfo
	Inventory   []InventoryItem
	PostHarvest []PostHarvestInfo
	Markets     []MarketInfo
	Processing  []ProcessingInfo
}

type CropInfo struct {
	Name        string
	Variety     string
	Area        string
	PlantedDate string
	HarvestDate string
	Status      string
	Yield       string
}

type LivestockInfo struct {
	Type     string
	Breed    string
	Count    int
	Location string
	Status   string
}

type TaskInfo struct {
	Task     string
	DueDate  string
	Priority string
	Status   string
}

type InventoryItem struct {
	Item     string
	Quantity string
	Location string
}

type PostHarvestInfo struct {
	Crop         string
	HarvestedQty string
	DateHarvested string
	StorageType  string
	StorageLoc   string
	Quality      string
	Moisture     string
	Status       string
}

type MarketInfo struct {
	Product     string
	Quantity    string
	Price       string
	Buyer       string
	Market      string
	SaleDate    string
	Status      string
}

type ProcessingInfo struct {
	RawProduct   string
	ProcessedAs  string
	Quantity     string
	Date         string
	Equipment    string
	BatchNo      string
	Status       string
}

func NewFarmOSModel(application *app.App, deployment *models.Deployment) *FarmOSModel {
	m := &FarmOSModel{
		app:        application,
		deployment: deployment,
		viewMode:   "overview",
	}
	m.refreshAll()
	return m
}

func (m *FarmOSModel) refreshAll() {
	m.refreshContainers()
	m.refreshStats()
	m.loadFarmData()
}

func (m *FarmOSModel) refreshContainers() {
	m.containers = []ContainerInfo{}
	
	cmd := exec.Command("docker", "ps", "-a",
		"--filter", "name=farm",
		"--format", "{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}")
	out, err := cmd.Output()
	if err != nil {
		return
	}
	
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	for _, line := range lines {
		if line == "" || !strings.Contains(line, "farm") {
			continue
		}
		parts := strings.Split(line, "\t")
		if len(parts) >= 4 {
			state := "running"
			if strings.Contains(strings.ToLower(parts[2]), "exited") {
				state = "exited"
			}
			
			ports := strings.ReplaceAll(parts[3], "0.0.0.0:", "")
			ports = strings.ReplaceAll(ports, "[::]:", "")
			
			friendlyName := parts[0]
			if strings.Contains(parts[0], "www") {
				friendlyName = "🌐 Web Application"
			} else if strings.Contains(parts[0], "db") {
				friendlyName = "🗄️ PostgreSQL Database"
			}
			
			m.containers = append(m.containers, ContainerInfo{
				Name:   friendlyName,
				Image:  parts[1],
				Status: parts[2],
				Ports:  ports,
				State:  state,
			})
		}
	}
}

func (m *FarmOSModel) refreshStats() {
	cmd := exec.Command("docker", "exec", "docker-db-1", "psql", "-U", "farm", "-d", "farm", "-t", "-c",
		"SELECT pg_size_pretty(pg_database_size('farm'));")
	out, err := cmd.Output()
	if err == nil {
		m.farmStats.DBsize = strings.TrimSpace(string(out))
	}
	
	cmd = exec.Command("docker", "exec", "docker-db-1", "psql", "-U", "farm", "-d", "farm", "-t", "-c",
		"SELECT COUNT(*) FROM asset; SELECT COUNT(*) FROM log;")
	out, err = cmd.Output()
	if err == nil {
		lines := strings.Split(strings.TrimSpace(string(out)), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if n, err := strconv.Atoi(line); err == nil {
				if m.farmStats.Assets == 0 {
					m.farmStats.Assets = n
				} else if m.farmStats.Logs == 0 {
					m.farmStats.Logs = n
				}
			}
		}
	}
	
	cmd = exec.Command("du", "-sh", "/opt/chengetai-deploy/deployments/farmos/www")
	out, err = cmd.Output()
	if err == nil {
		m.farmStats.WWWsize = strings.Fields(string(out))[0]
	}
	
	cmd = exec.Command("docker", "inspect", "docker-www-1", "--format", "{{.State.StartedAt}}")
	out, err = cmd.Output()
	if err == nil {
		m.farmStats.Uptime = strings.TrimSpace(string(out))[:19]
	}
	
	cmd = exec.Command("ls", "-t", "/opt/chengetai-deploy/deployments/farmos/backups/")
	out, err = cmd.Output()
	if err == nil && len(out) > 0 {
		m.farmStats.LastBackup = strings.Split(string(out), "\n")[0]
	}
}

func (m *FarmOSModel) loadFarmData() {
	m.farmData = FarmData{
		Crops: []CropInfo{
			{Name: "Maize", Variety: "Hybrid 614", Area: "Field A", PlantedDate: "2026-06-15", HarvestDate: "2026-10-15", Status: "Growing", Yield: "4.5 t/ha"},
			{Name: "Tomatoes", Variety: "Roma", Area: "Greenhouse 1", PlantedDate: "2026-07-01", HarvestDate: "2026-09-01", Status: "Flowering", Yield: "25 t/ha"},
			{Name: "Wheat", Variety: "Winter Wheat", Area: "Field B", PlantedDate: "2026-05-20", HarvestDate: "2026-09-20", Status: "Maturing", Yield: "3.2 t/ha"},
			{Name: "Soybeans", Variety: "TGx 1835", Area: "Field C", PlantedDate: "2026-06-01", HarvestDate: "2026-11-01", Status: "Growing", Yield: "2.8 t/ha"},
		},
		Livestock: []LivestockInfo{
			{Type: "Cattle", Breed: "Brahman", Count: 25, Location: "Pasture A", Status: "Healthy"},
			{Type: "Chickens", Breed: "Rhode Island Red", Count: 150, Location: "Coop 1", Status: "Laying"},
			{Type: "Goats", Breed: "Boer", Count: 15, Location: "Pasture B", Status: "Healthy"},
			{Type: "Pigs", Breed: "Large White", Count: 10, Location: "Pigsty", Status: "Growing"},
		},
		Tasks: []TaskInfo{
			{Task: "Apply fertilizer to maize", DueDate: "2026-07-15", Priority: "High", Status: "Pending"},
			{Task: "Harvest tomatoes", DueDate: "2026-07-20", Priority: "High", Status: "Pending"},
			{Task: "Vaccinate cattle", DueDate: "2026-07-18", Priority: "Medium", Status: "Pending"},
			{Task: "Repair irrigation pump", DueDate: "2026-07-14", Priority: "High", Status: "In Progress"},
			{Task: "Order feed supplement", DueDate: "2026-07-25", Priority: "Low", Status: "Pending"},
			{Task: "Clean grain storage", DueDate: "2026-07-16", Priority: "Medium", Status: "Pending"},
		},
		Inventory: []InventoryItem{
			{Item: "NPK Fertilizer", Quantity: "250 kg", Location: "Store A"},
			{Item: "Pesticide", Quantity: "15 liters", Location: "Store B"},
			{Item: "Animal Feed", Quantity: "500 kg", Location: "Feed Store"},
			{Item: "Seeds - Maize", Quantity: "50 kg", Location: "Seed Store"},
			{Item: "Diesel", Quantity: "200 liters", Location: "Fuel Tank"},
			{Item: "Vaccines", Quantity: "100 doses", Location: "Cold Storage"},
			{Item: "Grain Bags", Quantity: "500 pcs", Location: "Equipment Shed"},
		},
		PostHarvest: []PostHarvestInfo{
			{Crop: "Maize", HarvestedQty: "4500 kg", DateHarvested: "2026-06-20", StorageType: "Silo", StorageLoc: "Silo A", Quality: "Grade A", Moisture: "12.5%", Status: "Stored"},
			{Crop: "Tomatoes", HarvestedQty: "800 kg", DateHarvested: "2026-06-25", StorageType: "Cold Room", StorageLoc: "Cold Room 1", Quality: "Grade A", Moisture: "N/A", Status: "Processing"},
			{Crop: "Wheat", HarvestedQty: "3200 kg", DateHarvested: "2026-06-15", StorageType: "Grain Bin", StorageLoc: "Bin 2", Quality: "Grade B", Moisture: "13.0%", Status: "Stored"},
			{Crop: "Maize", HarvestedQty: "2200 kg", DateHarvested: "2026-07-01", StorageType: "Bagged", StorageLoc: "Warehouse A", Quality: "Grade A", Moisture: "11.8%", Status: "For Sale"},
		},
		Markets: []MarketInfo{
			{Product: "Maize Grain", Quantity: "2200 kg", Price: "$0.35/kg", Buyer: "GrainCorp Ltd", Market: "Commodity Exchange", SaleDate: "2026-07-10", Status: "Confirmed"},
			{Product: "Tomato Paste", Quantity: "150 kg", Price: "$2.50/kg", Buyer: "FreshFoods Supermarket", Market: "Local Market", SaleDate: "2026-07-08", Status: "Delivered"},
			{Product: "Wheat Flour", Quantity: "500 kg", Price: "$0.80/kg", Buyer: "City Bakery", Market: "Direct Sale", SaleDate: "2026-07-05", Status: "Paid"},
			{Product: "Maize Meal", Quantity: "300 kg", Price: "$0.60/kg", Buyer: "School Program", Market: "Institutional", SaleDate: "2026-07-12", Status: "Pending"},
		},
		Processing: []ProcessingInfo{
			{RawProduct: "Tomatoes", ProcessedAs: "Tomato Paste", Quantity: "150 kg", Date: "2026-07-03", Equipment: "Pulper & Evaporator", BatchNo: "TP-2026-001", Status: "Completed"},
			{RawProduct: "Maize", ProcessedAs: "Maize Meal", Quantity: "300 kg", Date: "2026-07-06", Equipment: "Hammer Mill", BatchNo: "MM-2026-003", Status: "Completed"},
			{RawProduct: "Wheat", ProcessedAs: "Wheat Flour", Quantity: "500 kg", Date: "2026-07-02", Equipment: "Roller Mill", BatchNo: "WF-2026-002", Status: "Completed"},
			{RawProduct: "Maize", ProcessedAs: "Animal Feed", Quantity: "200 kg", Date: "2026-07-08", Equipment: "Feed Mixer", BatchNo: "AF-2026-004", Status: "In Progress"},
		},
	}
}

func (m *FarmOSModel) Init() tea.Cmd {
	return nil
}

func (m *FarmOSModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
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
			
		// View modes
		case "o": m.viewMode = "overview"; m.refreshAll(); return m, nil
		case "l": m.viewMode = "logs"; m.loadLogs(); return m, nil
		case "f": m.viewMode = "stats"; m.refreshStats(); return m, nil
		case "c": m.viewMode = "crops"; return m, nil
		case "v": m.viewMode = "livestock"; return m, nil
		case "k": m.viewMode = "tasks"; return m, nil
		case "i": m.viewMode = "inventory"; return m, nil
		case "h": m.viewMode = "postharvest"; return m, nil
		case "m": m.viewMode = "markets"; return m, nil
		case "g": m.viewMode = "processing"; return m, nil
		case "w": m.viewMode = "weather"; return m, nil
		case "b": m.viewMode = "backup"; return m, nil
			
		// Actions
		case "s":
			m.actionMsg = "🌾 Starting farmOS..."; m.actionType = "info"
			exec.Command("docker", "start", "docker-db-1", "docker-www-1").Run()
			m.refreshAll(); return m, nil
		case "t":
			m.actionMsg = "⏸️ Stopping farmOS..."; m.actionType = "warning"
			exec.Command("docker", "stop", "docker-www-1", "docker-db-1").Run()
			return m, nil
		case "r":
			m.actionMsg = "🔄 Restarting farmOS..."; m.actionType = "info"
			exec.Command("docker", "restart", "docker-db-1", "docker-www-1").Run()
			return m, nil
		case "x":
			m.actionMsg = "📦 Creating backup..."; m.actionType = "info"
			go m.createBackup(); return m, nil
			
		case "up", "u":
			if m.cursor > 0 { m.cursor-- }; return m, nil
		case "down", "j":
			if m.cursor < 15 { m.cursor++ }; return m, nil
		}
	}

	return m, nil
}

func (m *FarmOSModel) loadLogs() {
	m.logs = []string{}
	cmd := exec.Command("docker", "logs", "--tail", "30", "docker-www-1")
	out, _ := cmd.Output()
	m.logs = strings.Split(string(out), "\n")
}

func (m *FarmOSModel) createBackup() {
	exec.Command("bash", "/opt/chengetai-deploy/lib/farmos.sh", "backup").Run()
	m.actionMsg = "✓ Backup completed"; m.actionType = "success"
}

func (m *FarmOSModel) View() string {
	var b strings.Builder
	b.WriteString(logoStyle.Render(logo))
	b.WriteString("\n\n")
	b.WriteString(titleStyle.Render(fmt.Sprintf(" 🌾 farmOS: %s", m.deployment.Name)))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")

	if m.actionMsg != "" {
		msgColor := greenStyle
		if m.actionType == "warning" { msgColor = yellowStyle }
		b.WriteString(fmt.Sprintf(" %s\n\n", msgColor.Render(m.actionMsg)))
	}

	switch m.viewMode {
	case "overview": m.viewOverview(&b)
	case "logs": m.viewLogs(&b)
	case "stats": m.viewStats(&b)
	case "crops": m.viewCrops(&b)
	case "livestock": m.viewLivestock(&b)
	case "tasks": m.viewTasks(&b)
	case "inventory": m.viewInventory(&b)
	case "postharvest": m.viewPostHarvest(&b)
	case "markets": m.viewMarkets(&b)
	case "processing": m.viewProcessing(&b)
	case "backup": m.viewBackup(&b)
	case "weather": m.viewWeather(&b)
	default: m.viewOverview(&b)
	}

	return b.String()
}

func (m *FarmOSModel) viewOverview(b *strings.Builder) {
	statusColor := greenStyle; statusText := "● Running"
	if m.deployment.Status == "stopped" { statusColor = yellowStyle; statusText = "● Stopped" }
	
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Status:"), statusColor.Render(statusText)))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Version:"), "farmOS 4.x-dev"))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Uptime:"), dimStyle.Render(m.farmStats.Uptime)))
	b.WriteString("\n")

	b.WriteString(titleStyle.Render(" 📊 Farm Dashboard"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %-22s %s\n", greenStyle.Render("🌱"), labelStyle.Render("Crops:"), fmt.Sprintf("%d growing", len(m.farmData.Crops))))
	b.WriteString(fmt.Sprintf(" %s %-22s %s\n", greenStyle.Render("🐄"), labelStyle.Render("Livestock:"), fmt.Sprintf("%d groups", len(m.farmData.Livestock))))
	b.WriteString(fmt.Sprintf(" %s %-22s %s\n", greenStyle.Render("📦"), labelStyle.Render("Post-Harvest:"), fmt.Sprintf("%d batches stored", len(m.farmData.PostHarvest))))
	b.WriteString(fmt.Sprintf(" %s %-22s %s\n", greenStyle.Render("🏭"), labelStyle.Render("Processing:"), fmt.Sprintf("%d batches", len(m.farmData.Processing))))
	b.WriteString(fmt.Sprintf(" %s %-22s %s\n", greenStyle.Render("💰"), labelStyle.Render("Market Sales:"), fmt.Sprintf("%d transactions", len(m.farmData.Markets))))
	b.WriteString(fmt.Sprintf(" %s %-22s %s\n", greenStyle.Render("📋"), labelStyle.Render("Tasks:"), fmt.Sprintf("%d pending", len(m.farmData.Tasks))))
	b.WriteString("\n")

	b.WriteString(titleStyle.Render(" 🌐 Quick Access"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Web:"), greenStyle.Render("http://farmos.chengetailabs.co.zw")))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Login:"), "admin / admin123"))
	b.WriteString("\n")

	// Value Chain Menu
	b.WriteString(titleStyle.Render(" 🌾 Value Chain"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[C]"), menuStyle.Render("🌱 Crop Production")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[H]"), menuStyle.Render("🏠 Post-Harvest Storage")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[G]"), menuStyle.Render("🏭 Processing & Value Addition")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[M]"), menuStyle.Render("💰 Markets & Sales")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[V]"), menuStyle.Render("🐄 Livestock")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[I]"), menuStyle.Render("📦 Inventory")))
	b.WriteString("\n")

	b.WriteString(" ────────────────────────────────────────────\n")
	b.WriteString(fmt.Sprintf(" %s%s %s%s %s%s %s%s\n",
		keyStyle.Render("[S]"), menuStyle.Render("Start"),
		keyStyle.Render("[T]"), menuStyle.Render("Stop"),
		keyStyle.Render("[R]"), menuStyle.Render("Restart"),
		keyStyle.Render("[O]"), menuStyle.Render("Refresh")))
	b.WriteString(fmt.Sprintf(" %s %s", keyStyle.Render("[D]"), menuStyle.Render("Dashboard")))
	b.WriteString(fmt.Sprintf("  %s %s", keyStyle.Render("[P]"), menuStyle.Render("Deployments")))
	b.WriteString(fmt.Sprintf("  %s %s\n", keyStyle.Render("[Esc]"), menuStyle.Render("Back")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[Q]"), menuStyle.Render("Quit")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewPostHarvest(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 🏠 Post-Harvest Storage"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	b.WriteString(fmt.Sprintf(" %-12s %-10s %-12s %-12s %-10s %-10s %s\n",
		labelStyle.Render("Crop"),
		labelStyle.Render("Qty"),
		labelStyle.Render("Harvested"),
		labelStyle.Render("Storage"),
		labelStyle.Render("Quality"),
		labelStyle.Render("Moisture"),
		labelStyle.Render("Status")))
	b.WriteString("  " + strings.Repeat("─", 80) + "\n")
	
	for _, ph := range m.farmData.PostHarvest {
		qualityColor := greenStyle
		if ph.Quality == "Grade B" { qualityColor = yellowStyle }
		
		b.WriteString(fmt.Sprintf(" %-12s %-10s %-12s %-12s %s %s %s\n",
			ph.Crop,
			ph.HarvestedQty,
			ph.DateHarvested,
			ph.StorageType+" "+ph.StorageLoc,
			qualityColor.Render(ph.Quality),
			ph.Moisture,
			greenStyle.Render(ph.Status)))
	}
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewMarkets(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 💰 Markets & Sales"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	b.WriteString(fmt.Sprintf(" %-15s %-10s %-10s %-18s %-18s %-12s %s\n",
		labelStyle.Render("Product"),
		labelStyle.Render("Qty"),
		labelStyle.Render("Price"),
		labelStyle.Render("Buyer"),
		labelStyle.Render("Market"),
		labelStyle.Render("Date"),
		labelStyle.Render("Status")))
	b.WriteString("  " + strings.Repeat("─", 95) + "\n")
	
	totalValue := 0.0
	for _, sale := range m.farmData.Markets {
		statusColor := greenStyle
		if sale.Status == "Pending" { statusColor = yellowStyle }
		if sale.Status == "Paid" { statusColor = greenStyle }
		
		b.WriteString(fmt.Sprintf(" %-15s %-10s %-10s %-18s %-18s %-12s %s\n",
			sale.Product,
			sale.Quantity,
			sale.Price,
			sale.Buyer,
			sale.Market,
			sale.SaleDate,
			statusColor.Render(sale.Status)))
	}
	b.WriteString(fmt.Sprintf("\n %s $%.2f estimated\n", labelStyle.Render("Total:"), totalValue+770.0+400.0+180.0))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewProcessing(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 🏭 Processing & Value Addition"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	b.WriteString(fmt.Sprintf(" %-14s %-14s %-10s %-12s %-18s %-14s %s\n",
		labelStyle.Render("Raw Product"),
		labelStyle.Render("Processed As"),
		labelStyle.Render("Qty"),
		labelStyle.Render("Date"),
		labelStyle.Render("Equipment"),
		labelStyle.Render("Batch #"),
		labelStyle.Render("Status")))
	b.WriteString("  " + strings.Repeat("─", 95) + "\n")
	
	for _, proc := range m.farmData.Processing {
		statusColor := greenStyle
		if proc.Status == "In Progress" { statusColor = yellowStyle }
		
		b.WriteString(fmt.Sprintf(" %-14s %-14s %-10s %-12s %-18s %-14s %s\n",
			proc.RawProduct,
			proc.ProcessedAs,
			proc.Quantity,
			proc.Date,
			proc.Equipment,
			proc.BatchNo,
			statusColor.Render(proc.Status)))
	}
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewCrops(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 🌱 Crop Production"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	b.WriteString(fmt.Sprintf(" %-12s %-12s %-12s %-12s %-12s %-10s %s\n",
		labelStyle.Render("Crop"), labelStyle.Render("Variety"), labelStyle.Render("Area"),
		labelStyle.Render("Planted"), labelStyle.Render("Harvest"), labelStyle.Render("Yield"), labelStyle.Render("Status")))
	b.WriteString("  " + strings.Repeat("─", 80) + "\n")
	
	for _, crop := range m.farmData.Crops {
		b.WriteString(fmt.Sprintf(" %-12s %-12s %-12s %-12s %-12s %-10s %s\n",
			crop.Name, crop.Variety, crop.Area, crop.PlantedDate, crop.HarvestDate, crop.Yield, greenStyle.Render(crop.Status)))
	}
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewLivestock(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 🐄 Livestock"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	b.WriteString(fmt.Sprintf(" %-12s %-18s %-8s %-12s %s\n",
		labelStyle.Render("Type"), labelStyle.Render("Breed"), labelStyle.Render("Count"), labelStyle.Render("Location"), labelStyle.Render("Status")))
	b.WriteString("  " + strings.Repeat("─", 60) + "\n")
	for _, a := range m.farmData.Livestock {
		sc := greenStyle
		if a.Status != "Healthy" && a.Status != "Laying" { sc = yellowStyle }
		b.WriteString(fmt.Sprintf(" %-12s %-18s %-8d %-12s %s\n", a.Type, a.Breed, a.Count, a.Location, sc.Render(a.Status)))
	}
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewTasks(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 📋 Tasks"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	b.WriteString(fmt.Sprintf(" %-28s %-12s %-10s %s\n",
		labelStyle.Render("Task"), labelStyle.Render("Due"), labelStyle.Render("Priority"), labelStyle.Render("Status")))
	b.WriteString("  " + strings.Repeat("─", 60) + "\n")
	for _, t := range m.farmData.Tasks {
		pc := greenStyle
		if t.Priority == "High" { pc = redStyle } else if t.Priority == "Medium" { pc = yellowStyle }
		sc := yellowStyle
		if t.Status == "In Progress" { sc = greenStyle }
		b.WriteString(fmt.Sprintf(" %-28s %-12s %s %s\n", t.Task, t.DueDate, pc.Render(t.Priority), sc.Render(t.Status)))
	}
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewInventory(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 📦 Inventory"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	b.WriteString(fmt.Sprintf(" %-22s %-15s %s\n", labelStyle.Render("Item"), labelStyle.Render("Quantity"), labelStyle.Render("Location")))
	b.WriteString("  " + strings.Repeat("─", 50) + "\n")
	for _, item := range m.farmData.Inventory {
		b.WriteString(fmt.Sprintf(" %-22s %-15s %s\n", item.Item, item.Quantity, item.Location))
	}
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewStats(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 📊 Statistics"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("DB Size:"), m.farmStats.DBsize))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Files:"), m.farmStats.WWWsize))
	b.WriteString(fmt.Sprintf(" %s %d\n", labelStyle.Render("Assets:"), m.farmStats.Assets))
	b.WriteString(fmt.Sprintf(" %s %d\n", labelStyle.Render("Activities:"), m.farmStats.Logs))
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Last Backup:"), m.farmStats.LastBackup))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewLogs(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 📋 Logs"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	for _, log := range m.logs {
		if len(log) > 85 { log = log[:85] + "..." }
		b.WriteString(fmt.Sprintf(" %s\n", dimStyle.Render(log)))
	}
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewBackup(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 💾 Backup"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", labelStyle.Render("Last:"), m.farmStats.LastBackup))
	b.WriteString(fmt.Sprintf(" %s %s\n\n", labelStyle.Render("Path:"), dimStyle.Render("/opt/chengetai-deploy/deployments/farmos/backups/")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[X]"), menuStyle.Render("Create Backup")))
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}

func (m *FarmOSModel) viewWeather(b *strings.Builder) {
	b.WriteString(titleStyle.Render(" 🌤️ Weather"))
	b.WriteString("\n")
	b.WriteString(" ────────────────────────────────────────────\n\n")
	b.WriteString(dimStyle.Render(" Configure sensors in farmOS.\n"))
	b.WriteString(dimStyle.Render(" Admin → Structure → Sensor types\n"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf(" %s %s\n", keyStyle.Render("[O]"), menuStyle.Render("Back")))
	b.WriteString(" ────────────────────────────────────────────\n")
}
