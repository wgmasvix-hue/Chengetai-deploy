// Real host metrics — replaces the hardcoded demo numbers.
const os = require('os');
const fs = require('fs');
const { execFile } = require('child_process');

function exec(cmd, args) {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout: 4000 }, (err, stdout) => {
      resolve(err ? null : stdout);
    });
  });
}

// CPU utilisation over a short sampling window, from /proc/stat.
function readCpuTimes() {
  const line = fs.readFileSync('/proc/stat', 'utf8').split('\n')[0];
  const parts = line.trim().split(/\s+/).slice(1).map(Number);
  const idle = parts[3] + (parts[4] || 0);
  const total = parts.reduce((a, b) => a + b, 0);
  return { idle, total };
}

async function cpuPercent() {
  try {
    const a = readCpuTimes();
    await new Promise((r) => setTimeout(r, 250));
    const b = readCpuTimes();
    const total = b.total - a.total;
    const idle = b.idle - a.idle;
    if (total <= 0) return 0;
    return Math.round(((total - idle) / total) * 100);
  } catch {
    // Fallback: 1-minute load average scaled by core count.
    return Math.min(100, Math.round((os.loadavg()[0] / os.cpus().length) * 100));
  }
}

function memoryPercent() {
  try {
    const info = fs.readFileSync('/proc/meminfo', 'utf8');
    const get = (k) => Number((info.match(new RegExp(`^${k}:\\s+(\\d+)`, 'm')) || [])[1] || 0);
    const total = get('MemTotal');
    const available = get('MemAvailable');
    if (total > 0) return Math.round(((total - available) / total) * 100);
  } catch {
    /* fall through */
  }
  return Math.round(((os.totalmem() - os.freemem()) / os.totalmem()) * 100);
}

async function diskPercent() {
  const out = await exec('df', ['-k', '/']);
  if (!out) return 0;
  const fields = out.trim().split('\n')[1].split(/\s+/);
  return parseInt(fields[4], 10) || 0;
}

async function containerCount() {
  const out = await exec('docker', ['ps', '-q']);
  if (!out) return 0;
  return out.split('\n').filter(Boolean).length;
}

function formatUptime() {
  const s = os.uptime();
  const days = Math.floor(s / 86400);
  const hours = Math.floor((s % 86400) / 3600);
  if (days > 0) return `${days} day${days === 1 ? '' : 's'}, ${hours}h`;
  const minutes = Math.floor((s % 3600) / 60);
  return `${hours}h ${minutes}m`;
}

async function stats(deploymentCount) {
  const [cpu, disk, containers] = await Promise.all([
    cpuPercent(),
    diskPercent(),
    containerCount(),
  ]);
  const memory = memoryPercent();
  return {
    repositories: deploymentCount,
    containers,
    cpu,
    memory,
    disk,
    uptime: formatUptime(),
    server: cpu < 90 && memory < 90 && disk < 90 ? 'Healthy' : 'Under pressure',
    hostname: os.hostname(),
  };
}

module.exports = { stats };
