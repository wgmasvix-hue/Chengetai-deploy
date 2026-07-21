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

## What is NOT yet covered (Phase 1b)

Colours, the footer, the login screen and error pages are **compiled into the
DSpace Angular frontend image**, so changing them needs a *themed source build*
of `dspace-angular` (a custom `src/themes/<institution>/` with `_theme.scss` and
component overrides), not just an asset swap. That's the next branding phase.
Until then, `chengetai brand` covers the institution's **name, identity, logo,
favicon and browser title** — enough that the repository already reads as the
institution's, not DSpace's.

## Roadmap

- **Phase 1a (done):** name, short name, publisher, preview brand, browser
  title, logo, favicon — driven from a per-deployment brand profile.
- **Phase 1b:** institution colour palette, custom footer, branded login and
  error pages via a themed Angular build.
