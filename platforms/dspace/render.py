#!/usr/bin/env python3
"""ChengetAi Deploy v3 — deployment.yml → generated config renderer.

Single source of truth: reads the master deployment.yml, builds a flat
context (adding derived values and secrets), and renders every *.tpl in the
templates directory to an output directory. Fails if any placeholder is left
unfilled, so a generated file can never contain a raw {{PLACEHOLDER}} — or a
hardcoded IP, since nothing but this config feeds the templates.

Usage: render.py <deployment.yml> <templates_dir> <out_dir>
Stdlib only (no PyYAML): the master config uses a small, controlled subset.
"""
import os
import re
import sys
import secrets
import string


def parse_yaml(path):
    """Minimal parser for our controlled 2-space-indented key: value subset."""
    data = {}
    stack = []  # (indent, key)
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            indent = len(line) - len(line.lstrip(" "))
            key, _, val = line.strip().partition(":")
            val = val.strip()
            # Strip an inline comment ("value   # note") — our values never
            # contain a whitespace-preceded '#'.
            val = re.split(r"\s+#", val, maxsplit=1)[0].strip()
            while stack and stack[-1][0] >= indent:
                stack.pop()
            keys = [k for _, k in stack] + [key]
            if val == "":
                stack.append((indent, key))
            else:
                if len(val) >= 2 and val[0] in "\"'" and val[-1] == val[0]:
                    val = val[1:-1]
                data[".".join(keys)] = val
    return data


def gen_secret(n=24):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(n))


def truthy(v):
    return str(v).strip().lower() in ("true", "yes", "1", "on")


def build_context(y):
    def g(k, default=""):
        return y.get(k, default)

    ssl = truthy(g("domain.ssl", "false"))
    domain = g("domain.public")
    if not domain:
        sys.exit("[ERROR] domain.public is required in deployment.yml")
    scheme = "https" if ssl else "http"
    public_url = f"{scheme}://{domain}"
    dns = g("domain.dns_provider", "manual") or "manual"

    return {
        "DEPLOY_ID": g("deployment.id") or "dspace",
        "PLATFORM": g("deployment.platform", "dspace"),
        "INSTITUTION": g("institution.name") or "DSpace Repository",
        "DOMAIN": domain,
        "HTTPS": "true" if ssl else "false",
        "SCHEME": scheme,
        "PUBLIC_URL": public_url,
        "SERVER_URL": f"{public_url}/server",
        "PUBLIC_PORT": "443" if ssl else "80",
        "UI_PORT": g("ports.ui", "4000"),
        "REST_PORT": g("ports.api", "8080"),
        "ADMIN_EMAIL": g("admin.email") or "admin@example.org",
        "ADMIN_PASSWORD": os.environ.get("ADMIN_PASSWORD") or gen_secret(16),
        "POSTGRES_PASSWORD": os.environ.get("POSTGRES_PASSWORD") or gen_secret(24),
        "DNS_PROVIDER": dns,
        "DB_ENGINE": g("database.engine", "postgres"),
        # Caddy site address: bare domain (auto-HTTPS) or http:// when ssl off.
        "CADDY_SITE": domain if ssl else f"http://{domain}",
    }


PLACEHOLDER = re.compile(r"\{\{\s*([A-Z0-9_]+)\s*\}\}")


def render(text, ctx):
    return PLACEHOLDER.sub(lambda m: ctx.get(m.group(1), m.group(0)), text)


def main():
    if len(sys.argv) != 4:
        sys.exit("Usage: render.py <deployment.yml> <templates_dir> <out_dir>")
    cfg_path, tpl_dir, out_dir = sys.argv[1:4]

    ctx = build_context(parse_yaml(cfg_path))
    os.makedirs(out_dir, exist_ok=True)

    rendered = []
    for name in sorted(os.listdir(tpl_dir)):
        if not name.endswith(".tpl"):
            continue
        with open(os.path.join(tpl_dir, name), encoding="utf-8") as fh:
            out = render(fh.read(), ctx)
        leftover = PLACEHOLDER.findall(out)
        if leftover:
            sys.exit(f"[ERROR] {name}: unfilled placeholder(s): {sorted(set(leftover))}")
        target = os.path.join(out_dir, name[:-4])  # strip .tpl
        with open(target, "w", encoding="utf-8") as fh:
            fh.write(out)
        # Secrets live only in .env; keep it private.
        os.chmod(target, 0o600 if name == ".env.tpl" else 0o644)
        rendered.append(os.path.basename(target))

    # Non-secret context summary for logging (secrets redacted).
    safe = {k: v for k, v in ctx.items() if "PASSWORD" not in k}
    print("RENDERED:", " ".join(rendered))
    for k in ("DEPLOY_ID", "DOMAIN", "PUBLIC_URL", "SERVER_URL", "HTTPS", "DNS_PROVIDER"):
        print(f"  {k}={safe[k]}")


if __name__ == "__main__":
    main()
