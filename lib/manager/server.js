// ChengetAi Manager — a tiny, zero-dependency local web UI for ONE
// deployment. Launched by `chengetai manager <name>`; it shells out to the
// same `chengetai` CLI an engineer would run, so there is one code path for
// every operation. Local by default (127.0.0.1) and gated by a per-session
// token printed at startup.
const http = require('http');
const { execFile } = require('child_process');
const { URL } = require('url');

const CFG = {
  name: process.env.MGR_DEPLOYMENT || 'deployment',
  platform: process.env.MGR_PLATFORM || 'unknown',
  cli: process.env.MGR_CLI, // path to the chengetai entry point
  token: process.env.MGR_TOKEN || '',
  port: Number(process.env.MGR_PORT || 9000),
  bind: process.env.MGR_BIND || '127.0.0.1',
  institution: process.env.MGR_INSTITUTION || '',
  uiUrl: process.env.MGR_UI_URL || '',
  restUrl: process.env.MGR_REST_URL || '',
};

// Actions the UI may trigger, mapped to CLI invocations. `logs` is captured
// as a bounded snapshot so a follow never hangs the request.
const ACTIONS = {
  status: (n) => [CFG.cli, 'status', n],
  start: (n) => [CFG.cli, 'start', n],
  stop: (n) => [CFG.cli, 'stop', n],
  restart: (n) => [CFG.cli, 'restart', n],
  backup: (n) => [CFG.cli, 'backup', n],
};

function runArgs(args, cb) {
  execFile('bash', args, { timeout: 15 * 60 * 1000, maxBuffer: 16 * 1024 * 1024 }, (err, out, errout) => {
    cb(`${out || ''}${errout || ''}`.trim() || '(no output)');
  });
}

function runLogsSnapshot(cb) {
  // timeout bounds `logs -f`; tail keeps the payload small.
  const cmd = `timeout 6 bash ${JSON.stringify(CFG.cli)} logs ${JSON.stringify(CFG.name)} 2>&1 | tail -200`;
  execFile('bash', ['-c', cmd], { timeout: 20000, maxBuffer: 8 * 1024 * 1024 }, (err, out) => {
    cb((out || '').trim() || '(no recent log output)');
  });
}

function authed(u) {
  return CFG.token && u.searchParams.get('t') === CFG.token;
}

function json(res, code, obj) {
  res.writeHead(code, { 'content-type': 'application/json' });
  res.end(JSON.stringify(obj));
}

const server = http.createServer((req, res) => {
  const u = new URL(req.url, `http://${req.headers.host}`);

  if (!authed(u)) {
    res.writeHead(403, { 'content-type': 'text/plain' });
    return res.end('Forbidden — missing or wrong access token.');
  }

  if (req.method === 'GET' && u.pathname === '/') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    return res.end(PAGE());
  }

  if (req.method === 'GET' && u.pathname === '/api/info') {
    return json(res, 200, {
      name: CFG.name,
      platform: CFG.platform,
      institution: CFG.institution,
      uiUrl: CFG.uiUrl,
      restUrl: CFG.restUrl,
    });
  }

  if (req.method === 'POST' && u.pathname === '/api/action') {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      let action = '';
      try {
        action = JSON.parse(body || '{}').action;
      } catch {
        return json(res, 400, { error: 'bad JSON' });
      }
      if (action === 'logs') return runLogsSnapshot((out) => json(res, 200, { output: out }));
      const build = ACTIONS[action];
      if (!build) return json(res, 400, { error: `unknown action '${action}'` });
      runArgs(build(CFG.name), (out) => json(res, 200, { output: out }));
    });
    return;
  }

  if (req.method === 'POST' && u.pathname === '/api/admin') {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      let p = {};
      try {
        p = JSON.parse(body || '{}');
      } catch {
        return json(res, 400, { error: 'bad JSON' });
      }
      const args = [CFG.cli, 'admin', CFG.name];
      if (p.email) args.push('--email', String(p.email));
      if (p.password) args.push('--password', String(p.password));
      if (p.generate) args.push('--generate');
      runArgs(args, (out) => json(res, 200, { output: out }));
    });
    return;
  }

  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('Not found');
});

server.listen(CFG.port, CFG.bind, () => {
  // manager.sh prints the friendly URL; this confirms the bind.
  console.log(`[manager] ${CFG.name} on http://${CFG.bind}:${CFG.port}`);
});

function PAGE() {
  const t = CFG.token;
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ChengetAi Manager — ${esc(CFG.name)}</title>
<style>
  :root{--bg:#0f1220;--card:#191d31;--line:#2a3050;--fg:#e8eaf5;--muted:#9aa3c7;--accent:#6c7bff;--ok:#38c172;--warn:#f0a000;--danger:#e3506a}
  *{box-sizing:border-box}
  body{margin:0;font:15px/1.5 system-ui,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--fg)}
  header{padding:20px 24px;border-bottom:1px solid var(--line);display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}
  header h1{font-size:18px;margin:0}
  header .tag{color:var(--muted);font-size:13px}
  main{max-width:900px;margin:0 auto;padding:24px}
  .card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:18px;margin-bottom:18px}
  .row{display:flex;gap:10px;flex-wrap:wrap}
  button{background:var(--accent);color:#fff;border:0;border-radius:8px;padding:10px 14px;font-weight:600;cursor:pointer}
  button.ghost{background:#232842}
  button.warn{background:var(--warn)}
  button.danger{background:var(--danger)}
  button:disabled{opacity:.5;cursor:progress}
  a.link{color:var(--accent);text-decoration:none}
  input{background:#0f1326;border:1px solid var(--line);color:var(--fg);border-radius:8px;padding:9px 11px;min-width:180px}
  label{display:block;color:var(--muted);font-size:12px;margin:8px 0 4px}
  pre{background:#0b0e1c;border:1px solid var(--line);border-radius:8px;padding:14px;overflow:auto;max-height:340px;white-space:pre-wrap;word-break:break-word}
  .muted{color:var(--muted)}
  h2{font-size:14px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);margin:0 0 12px}
</style></head>
<body>
<header>
  <h1>ChengetAi Manager</h1>
  <span class="tag">${esc(CFG.name)} · ${esc(CFG.platform)}${CFG.institution ? ' · ' + esc(CFG.institution) : ''}</span>
</header>
<main>
  <div class="card">
    <h2>Links</h2>
    <div class="row">
      ${CFG.uiUrl ? `<a class="link" href="${esc(CFG.uiUrl)}" target="_blank">Open UI ↗</a>` : '<span class="muted">UI URL unknown</span>'}
      ${CFG.restUrl ? `<a class="link" href="${esc(CFG.restUrl)}" target="_blank">Open REST ↗</a>` : ''}
    </div>
  </div>

  <div class="card">
    <h2>Lifecycle</h2>
    <div class="row">
      <button onclick="act('status')">Refresh status</button>
      <button class="ghost" onclick="act('start')">Start</button>
      <button class="warn" onclick="act('restart')">Restart</button>
      <button class="danger" onclick="act('stop')">Stop</button>
      <button class="ghost" onclick="act('backup')">Backup</button>
      <button class="ghost" onclick="act('logs')">Recent logs</button>
    </div>
  </div>

  <div class="card">
    <h2>Administrator</h2>
    <label>Email</label><input id="adm-email" placeholder="admin@example.org">
    <label>Password <span class="muted">(leave blank + tick Generate)</span></label>
    <input id="adm-pass" type="password" placeholder="••••••••">
    <label><input type="checkbox" id="adm-gen"> Generate a random password</label>
    <div class="row" style="margin-top:12px"><button onclick="admin()">Create / reset admin</button></div>
  </div>

  <div class="card">
    <h2>Output</h2>
    <pre id="out" class="muted">Ready. Pick an action above.</pre>
  </div>
</main>
<script>
  const T=${JSON.stringify(t)};
  const out=document.getElementById('out');
  function show(x){out.textContent=x;out.classList.remove('muted')}
  function busy(b){document.querySelectorAll('button').forEach(x=>x.disabled=b)}
  // Relative paths so the page works whether served directly or through the
  // dashboard's reverse proxy (which mounts it under a longer prefix).
  async function act(action){
    busy(true);show('Running '+action+' …');
    try{const r=await fetch('api/action?t='+encodeURIComponent(T),{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({action})});
      const j=await r.json();show(j.output||j.error||'(done)');}
    catch(e){show('Request failed: '+e)} finally{busy(false)}
  }
  async function admin(){
    busy(true);show('Updating administrator …');
    const body={email:document.getElementById('adm-email').value,password:document.getElementById('adm-pass').value,generate:document.getElementById('adm-gen').checked};
    try{const r=await fetch('api/admin?t='+encodeURIComponent(T),{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
      const j=await r.json();show(j.output||j.error||'(done)');}
    catch(e){show('Request failed: '+e)} finally{busy(false)}
  }
  act('status');
</script>
</body></html>`;
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
