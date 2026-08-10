# Institutional branding

Make a deployed repository present as **the institution's own** — not "DSpace".
ChengetAi Deploy is the internal tool; the branded repository is the product a
university administrator should look at and say *"this is our Institutional
Repository."*

## What `chengetai brand` sets

```bash
chengetai brand dare \
  --name "DARE Digital Repository" \
  --logo /path/to/dare-logo.svg
```

| What | Where it applies | Rebuild? |
|---|---|---|
| Repository name (`--name`) | site name — **browser-tab title** + header, via `DSPACE_NAME` in the engine's `.env` | No — the engine recreates the backend container for you |
| Navbar logo (`--logo`, SVG) | bind-mounted into the frontend at `assets/images/dspace-logo.svg` | No — the container reads the file straight off disk |

`chengetai brand` forwards straight to the DSpace 10 engine's own `bin/chengetai
brand`, which writes `DSPACE_NAME` into `deployments/<name>/engine/.env` and,
if you passed `--logo`, copies it to `deployments/<name>/engine/branding/logo.svg`
— then runs `docker compose up -d` itself so the change is live immediately.

```bash
chengetai brand dare --name "DARE Digital Repository"
chengetai brand dare --logo dare-logo.svg
chengetai brand dare --status     # show the current branding profile
```

- **Logo**: SVG. Any size works — it's rendered inline, not baked into a
  fixed-dimension raster.

## What is NOT yet covered

Short name, publisher, preview-brand abbreviation, favicon, institution
colours and themed footer/login/error pages were supported against an earlier
reference engine that built a custom frontend image per deployment. The
DSpace 10 engine (`ChengetAi-DSPACE-Engine`) runs the **unmodified, prebuilt**
`dspace-angular` image and only exposes two runtime hooks — the site name and
the header logo — so `chengetai brand` is scoped to match. `--shortname`,
`--publisher`, `--tagline`, `--favicon`, `--primary` and `--accent` are
accepted but ignored (with a warning); passing them is a no-op until the
engine grows the equivalent hook.

If you need one of those sooner, the underlying DSpace setting can usually be
written directly into `deployments/<name>/engine/config/local.cfg` (e.g.
`dspace.shortname = ...`) followed by `chengetai restart <name>` — see
`docs/CUSTOMIZATION.md` in the engine repository.
