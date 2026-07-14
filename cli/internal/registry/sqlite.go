package registry

import (
    "database/sql"
    "fmt"
    "strings"
    "time"
    
    _ "github.com/mattn/go-sqlite3"
    "github.com/wgmasvix-hue/chengetai-deploy/cli/internal/models"
)

type SQLiteRegistry struct {
    db *sql.DB
}

func NewSQLiteRegistry(path string) (*SQLiteRegistry, error) {
    db, err := sql.Open("sqlite3", path)
    if err != nil {
        return nil, fmt.Errorf("open database: %w", err)
    }
    
    if err := db.Ping(); err != nil {
        return nil, fmt.Errorf("ping database: %w", err)
    }
    
    r := &SQLiteRegistry{db: db}
    if err := r.migrate(); err != nil {
        return nil, fmt.Errorf("migrate: %w", err)
    }
    
    return r, nil
}

func (r *SQLiteRegistry) migrate() error {
    queries := []string{
        `CREATE TABLE IF NOT EXISTS deployments (
            id TEXT PRIMARY KEY,
            plugin TEXT NOT NULL,
            name TEXT NOT NULL,
            status TEXT DEFAULT 'unknown',
            phase TEXT,
            host TEXT,
            domain TEXT,
            ports TEXT,
            config TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )`,
        `CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            resource TEXT,
            status TEXT DEFAULT 'pending',
            progress INTEGER DEFAULT 0,
            phase TEXT,
            error TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            started_at DATETIME,
            ended_at DATETIME
        )`,
        `CREATE TABLE IF NOT EXISTS backups (
            id TEXT PRIMARY KEY,
            deployment_id TEXT,
            type TEXT,
            size_bytes INTEGER DEFAULT 0,
            path TEXT,
            status TEXT DEFAULT 'completed',
            error TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (deployment_id) REFERENCES deployments(id)
        )`,
        `CREATE TABLE IF NOT EXISTS plugins (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            capabilities TEXT,
            status TEXT DEFAULT 'installed'
        )`,
        `CREATE TABLE IF NOT EXISTS servers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            host TEXT NOT NULL,
            port INTEGER DEFAULT 22,
            user TEXT DEFAULT 'root',
            status TEXT DEFAULT 'unknown'
        )`,
        `CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )`,
    }
    
    for _, q := range queries {
        if _, err := r.db.Exec(q); err != nil {
            return fmt.Errorf("migrate query: %w", err)
        }
    }
    
    return nil
}

func (r *SQLiteRegistry) Close() error {
    return r.db.Close()
}

// Deployments
func (r *SQLiteRegistry) CreateDeployment(d *models.Deployment) error {
    _, err := r.db.Exec(
        `INSERT INTO deployments (id, plugin, name, status, phase, host, domain, ports, config, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        d.ID, d.Plugin, d.Name, d.Status, d.Phase, d.Host, d.Domain, d.Ports, d.Config, d.CreatedAt, d.UpdatedAt,
    )
    return err
}

func (r *SQLiteRegistry) GetDeployment(id string) (*models.Deployment, error) {
    d := &models.Deployment{}
    var createdAt, updatedAt string
    err := r.db.QueryRow(
        `SELECT id, plugin, name, status, phase, host, domain, ports, config, created_at, updated_at
         FROM deployments WHERE id = ?`, id,
    ).Scan(&d.ID, &d.Plugin, &d.Name, &d.Status, &d.Phase, &d.Host, &d.Domain, &d.Ports, &d.Config, &createdAt, &updatedAt)
    if err != nil {
        return nil, err
    }
    d.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", createdAt)
    d.UpdatedAt, _ = time.Parse("2006-01-02 15:04:05", updatedAt)
    return d, nil
}

func (r *SQLiteRegistry) ListDeployments() ([]models.Deployment, error) {
    rows, err := r.db.Query(
        `SELECT id, plugin, name, status, phase, host, domain, ports, config, created_at, updated_at
         FROM deployments ORDER BY created_at DESC`,
    )
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    
    var deployments []models.Deployment
    for rows.Next() {
        var d models.Deployment
        var createdAt, updatedAt string
        if err := rows.Scan(&d.ID, &d.Plugin, &d.Name, &d.Status, &d.Phase, &d.Host, &d.Domain, &d.Ports, &d.Config, &createdAt, &updatedAt); err != nil {
            return nil, err
        }
        d.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", createdAt)
        d.UpdatedAt, _ = time.Parse("2006-01-02 15:04:05", updatedAt)
        deployments = append(deployments, d)
    }
    return deployments, nil
}

func (r *SQLiteRegistry) UpdateDeployment(id string, updates map[string]any) error {
    setClauses := []string{}
    args := []any{}
    for key, value := range updates {
        setClauses = append(setClauses, fmt.Sprintf("%s = ?", key))
        args = append(args, value)
    }
    
    query := fmt.Sprintf("UPDATE deployments SET %s, updated_at = ? WHERE id = ?", 
        strings.Join(setClauses, ", "))
    args = append(args, time.Now(), id)
    
    _, err := r.db.Exec(query, args...)
    return err
}

func (r *SQLiteRegistry) DeleteDeployment(id string) error {
    _, err := r.db.Exec("DELETE FROM deployments WHERE id = ?", id)
    return err
}

// Tasks
func (r *SQLiteRegistry) SaveTask(t *models.Task) error {
    _, err := r.db.Exec(
        `INSERT OR REPLACE INTO tasks (id, type, resource, status, progress, phase, error, created_at, started_at, ended_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        t.ID, t.Type, t.Resource, t.Status, t.Progress, t.Phase, t.Error, t.CreatedAt, t.StartedAt, t.EndedAt,
    )
    return err
}

func (r *SQLiteRegistry) GetTask(id string) (*models.Task, error) {
    t := &models.Task{}
    var createdAt, startedAt, endedAt string
    err := r.db.QueryRow(
        `SELECT id, type, resource, status, progress, phase, error, created_at, started_at, ended_at
         FROM tasks WHERE id = ?`, id,
    ).Scan(&t.ID, &t.Type, &t.Resource, &t.Status, &t.Progress, &t.Phase, &t.Error, &createdAt, &startedAt, &endedAt)
    if err != nil {
        return nil, err
    }
    t.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", createdAt)
    if startedAt != "" {
        st, _ := time.Parse("2006-01-02 15:04:05", startedAt)
        t.StartedAt = &st
    }
    if endedAt != "" {
        et, _ := time.Parse("2006-01-02 15:04:05", endedAt)
        t.EndedAt = &et
    }
    return t, nil
}

func (r *SQLiteRegistry) ListTasks() ([]models.Task, error) {
    rows, err := r.db.Query(
        `SELECT id, type, resource, status, progress, phase, error, created_at, started_at, ended_at
         FROM tasks ORDER BY created_at DESC LIMIT 50`,
    )
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    
    var tasks []models.Task
    for rows.Next() {
        var t models.Task
        var createdAt, startedAt, endedAt string
        if err := rows.Scan(&t.ID, &t.Type, &t.Resource, &t.Status, &t.Progress, &t.Phase, &t.Error, &createdAt, &startedAt, &endedAt); err != nil {
            return nil, err
        }
        t.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", createdAt)
        if startedAt != "" {
            st, _ := time.Parse("2006-01-02 15:04:05", startedAt)
            t.StartedAt = &st
        }
        if endedAt != "" {
            et, _ := time.Parse("2006-01-02 15:04:05", endedAt)
            t.EndedAt = &et
        }
        tasks = append(tasks, t)
    }
    return tasks, nil
}

// Settings
func (r *SQLiteRegistry) GetSetting(key string) (string, error) {
    var value string
    err := r.db.QueryRow("SELECT value FROM settings WHERE key = ?", key).Scan(&value)
    if err == sql.ErrNoRows {
        return "", nil
    }
    return value, err
}

func (r *SQLiteRegistry) SetSetting(key, value string) error {
    _, err := r.db.Exec("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", key, value)
    return err
}

// Counts for dashboard
func (r *SQLiteRegistry) DeploymentCount() (int, error) {
    var count int
    err := r.db.QueryRow("SELECT COUNT(*) FROM deployments WHERE status != 'removed'").Scan(&count)
    return count, err
}

func (r *SQLiteRegistry) RunningDeploymentCount() (int, error) {
    var count int
    err := r.db.QueryRow("SELECT COUNT(*) FROM deployments WHERE status = 'running'").Scan(&count)
    return count, err
}

func (r *SQLiteRegistry) TaskCount() (int, error) {
    var count int
    err := r.db.QueryRow("SELECT COUNT(*) FROM tasks WHERE status IN ('pending', 'running')").Scan(&count)
    return count, err
}
