# Second Wind website

The static marketing site for [Second Wind](https://github.com/IanHanna12/secondWind).
It has no build step and no runtime dependencies.

## Preview locally

From the repository root:

```bash
python3 -m http.server 8000 --directory website
```

Open <http://127.0.0.1:8000>.

## Structure

```text
website/
├── index.html                     # Page structure and product copy
├── guides/                        # Search-focused storage guides
├── css/styles.css                 # Design tokens, layout, and responsive styles
├── js/main.js                     # Navigation, tabs, copy buttons, and motion
├── assets/screenshots/            # Screenshots used by the page
├── assets/social-card.png         # 1200 × 630 Open Graph image
├── assets/social-card-source.html # Reproducible source for the social card
└── validate.mjs                   # Metadata, link, sitemap, and asset checks
```

Run the same validation used by GitHub Pages before publishing:

```bash
node website/validate.mjs
```

## Content boundaries

This site must describe the current product accurately:

- Second Wind is local-first and requires no account or remote service.
- It has no remote telemetry, analytics, cloud sync, remote rule downloads, or
  automatic update checks.
- The optional Prometheus/Grafana companion is deliberately enabled, runs
  locally, is loopback-only and read-only, and exposes redacted aggregates.
- Cleanup remains reviewed, explicitly confirmed, and recoverable where
  supported; it is not risk-free. Users should keep current backups.

Use the repository README and `Docs/` as the source of truth before changing
product, privacy, release, or installation copy.

## Publishing

The site can be deployed on any static host. The repository includes a GitHub
Pages workflow that publishes this directory after a change to `website/` lands
on `main`.

Enable it once in GitHub:

1. Open **IanHanna12/secondWind → Settings → Pages**.
2. Under **Build and deployment**, choose **GitHub Actions**.
3. Push the website and workflow. GitHub deploys it to
   `https://ianhanna12.github.io/secondWind/`.

Anyone can then open that URL; no account, clone, or local app installation is
required. GitHub Pages is public static hosting, so GitHub may process visitor
IP addresses for security. The site itself makes no third-party font request.

After the first deployment, create a free Google Search Console URL-prefix
property for `https://ianhanna12.github.io/secondWind/`. Verify it with the
HTML file method, then submit `https://ianhanna12.github.io/secondWind/sitemap.xml`.
This provides search-index visibility without adding a visitor analytics script.

Before publishing, verify:

1. Every screenshot referenced by `index.html` exists below
   `assets/screenshots/`.
2. External links point to the current GitHub repository and release.
3. Version, macOS requirement, safety, and observability copy match the main
   repository documentation.
4. `node website/validate.mjs` succeeds.
