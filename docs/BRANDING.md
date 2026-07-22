# Institutional branding

Make a deployed repository present as **the institution's own** — not "DSpace".
ChengetAi Deploy is the internal tool; the branded repository is the product a
university administrator should look at and say *"this is our Institutional
Repository."*

## What `chengetai brand` sets

```bash
chengetai brand dare \
  --name "DARE Digital Repository" \
  --institution "DARE" \
  --shortname DARE \
  --publisher "DARE" \
  --logo /path/to/dare-logo.png \
  --favicon /path/to/dare-favicon.png \
  --apply
```

| What | Where it applies | Rebuild? |
|---|---|---|
| Repository name (`--name`) | `dspace.name` → site name **and browser-tab title** | No — restart only |
| Short name (`--shortname`) | `dspace.shortname`, preview-brand abbrev | No |
| Institution (`--institution`) | preview brand | No |
| Publisher (`--publisher`) | DataCite publisher (citation/export metadata) | No |
| Navbar logo (`--logo`, PNG) | baked into the frontend image | Yes (frontend) |
| Favicon (`--favicon`, PNG) | baked into the frontend image | Yes (frontend) |

Values are stored in `deployments/<name>/branding/brand.env` and merged on
re-run (flags win), so you can adjust one thing at a time. If you omit
`--shortname`, it's derived from the institution's initials (e.g. *Digital
Archive Research Exchange* → *DARE*).

The name/publisher settings are written **in place** into the deployment's
`local.cfg` (never as duplicate keys — DSpace combines duplicates into a list,
so a second `dspace.name` would break the title). They take effect on a backend
restart.

## Apply

```bash
# Names/title only (fast — restarts the backend):
chengetai brand dare --name "DARE Digital Repository" --institution DARE
chengetai restart dare

# Everything including logo/favicon (rebuilds the frontend image, a few minutes):
chengetai brand dare --logo dare-logo.png --favicon dare-favicon.png --apply

chengetai brand dare --status     # show the current branding profile
```

- **Logo**: PNG, ~320×80 works well for the navbar.
- **Favicon**: PNG (DSpace serves the bytes at `/favicon.ico`).

## Institution colours

```bash
chengetai brand dare --primary '#0E5C4A' --accent '#C8A24B' --apply
```

`--primary` (required for theming) and `--accent` generate a palette stylesheet
into `deployments/<name>/branding/theme.css`. The engine **injects it into the
UI after the compiled styles and bind-mounts it at runtime**, so it re-colours
the header, navbar, footer, buttons, links, badges and focus states — with
derived shades computed by CSS `color-mix()` (no colour math in shell). A
frontend restart applies colour-only changes; `--apply` also rebuilds the image
so the theme ships inside it.

A ready-made identity for DARE (emerald `#0E5C4A` + gold `#C8A24B`, serif-D
monogram logo + favicon) lives in `examples/branding/dare/`.

## What is NOT yet covered (Phase 1c)

Custom footer *content*, the login-page layout and error-page copy are
**compiled into the DSpace Angular frontend**, so changing their structure
needs a *themed source build* of `dspace-angular` (a custom
`src/themes/<institution>/`), not just an asset/CSS overlay. The colour theme
above already re-skins them; only their content/layout remains build-bound.

## Roadmap

- **Phase 1a (done):** name, short name, publisher, preview brand, browser
  title, logo, favicon — driven from a per-deployment brand profile.
- **Phase 1b (done):** institution colour palette via an injected + runtime-
  mounted theme stylesheet (`--primary` / `--accent`).
- **Phase 1c:** custom footer content, login and error-page layout via a themed
  Angular source build.
