# office-deployment

One common deployment toolkit for all 4 office apps (ticket_tracker,
IRR-Log-Analyser, BatchHealthAnalyzer, HealthCheckPlatform). Each app's
own folder no longer has its own setup script -- everything that used to
be a per-project "run this once" script now lives here, driven by
`config.yaml`.

## First-time deploy on a new environment (Dev / UAT / Prod)

1. For each app, point its own database connection at that environment's
   SQL Server (edit that app's `.env` -- `DATABASE_URL` for the 3
   Flask-SQLAlchemy apps, `HEALTHCHECK_DB_DSN` for HealthCheckPlatform).
2. Fill in `config.yaml`: each project's `path` (where its code lives on
   this server), and under `iis:` the `site_name`, `port`, `app_pool`,
   `service_account`, and `venv_path` for that environment.
3. Create the database schema + all tables for every app:
   ```
   python setup_database.py
   ```
   Or just one app: `python setup_database.py ticket_tracker`
4. Set up IIS (site, app pool, FastCGI handler) for every app, from an
   elevated PowerShell prompt:
   ```
   .\setup_iis.ps1
   ```
   Or just one app: `.\setup_iis.ps1 -ProjectName ticket_tracker`

Both scripts are safe to re-run -- they only create what's missing, never
reset or overwrite something that's already there.

## What this does NOT do

- Does not write each app's own `web.config` (FastCGI route mapping for
  that specific app) -- that still needs placing by hand in the app's
  folder on first deploy.
- Does not set the app pool identity's password -- IIS requires that to
  be entered interactively (IIS Manager or `appcmd`) for security reasons.
- Does not copy application code to the server -- `path` in config.yaml
  must already point at code that's present.
