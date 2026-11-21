# VPS API update for 3106

## App endpoint
The iOS app now sends license verification requests to:

`https://api.panelreseller.shop/v1/verify`

The app sends JSON containing `license_key` and `device_id`. It does **not**
contain the internal API secret. Do not embed `INTERNAL_API_SECRET` in an IPA.

## VPS API file
`api.py` in this folder is the public mobile verification endpoint intended
to replace the current FastAPI `api.py` module. It uses the existing `.db`
functions and existing database; it does not create a new database or change
the database schema.

Before replacing anything:
1. Back up the current VPS `api.py`.
2. Confirm the service's working directory/module path.
3. Copy this file over the existing API module only. Do not replace `db.py`,
   `.env`, the SQLite/database file, or the systemd service file.
4. Restart `vip-license-api`, then check `systemctl status vip-license-api`
   and `curl https://api.panelreseller.shop/health`.

The existing Nginx reverse proxy must overwrite `X-Real-IP` with `$remote_addr`.
The in-memory throttle is a basic safeguard; for a multi-worker deployment,
use a shared rate-limit store or Nginx rate limiting.

## Important
This source ZIP does not include the VPS backend or its database. The API
patch must be installed on the VPS separately before app login can succeed.
The GitHub workflow builds an **unsigned** IPA; it still needs your usual
signing/resigning process before installation on an iPhone.
