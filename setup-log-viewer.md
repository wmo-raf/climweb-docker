# Setup the Admin Log Viewer (optional)

Normally, checking why something broke means logging into the server and running:

```bash
docker compose logs -f --tail 100 climweb
```

The log viewer puts the same output in the CMS admin under **Settings → Server logs**,
so an administrator who has no shell access can still see what the site is doing.

It does **not** open a new port or require a subdomain.

## How it works

The CMS container is never given access to `/var/run/docker.sock` — that would be
equivalent to giving it root on the host. Instead a small
[docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) sidecar mounts
the socket read-only and exposes a filtered HTTP API on the internal compose network:

```
  climweb  ──http──▶  climweb_docker_proxy  ──ro──▶  /var/run/docker.sock
             (internal network only)
```

Only two capabilities are enabled on the proxy:

- `CONTAINERS=1` — list containers and inspect them
- `LOGS=1` — read container logs

Everything else, including `POST`, `EXEC` and `ALLOW_RESTARTS`, is off. The proxy uses
`expose:` rather than `ports:`, so it is unreachable from outside the Docker network.

## Enable it

It is on by default, so there is nothing to add to `.env`:

1. Pull the latest `docker-compose.yml` — it contains the `climweb_docker_proxy`
   service and points the CMS at it.

2. Restart:

   ```bash
   make restart
   ```

3. Log into the CMS as a **superuser**. A **Server logs** item appears in the Settings
   menu. Non-superusers do not see it, and cannot reach the URL directly.

The flag alone does not switch anything on: the viewer only appears where
`CLIMWEB_DOCKER_HOST` points at a running proxy. An instance still on an older
`docker-compose.yml` has neither, so the menu item stays hidden rather than showing an
error — no action needed on those until they are upgraded.

## Turn it off

To disable it on an instance that does have the proxy, set:

```env
CLIMWEB_LOG_VIEWER_ENABLED=False
```

and `make restart`. The menu item disappears and the endpoints stop responding. To also
stop mounting the Docker socket, comment out the `climweb_docker_proxy` service.

## Using it

- Pick any container in the stack — `climweb`, `climweb_celery_worker`,
  `climweb_nginx`, `climweb_db` and so on. Unlike a Django-side log handler, this also
  shows startup failures and crashes, which is usually what you need.
- The view polls every few seconds; **Pause** stops it, and polling halts automatically
  while the browser tab is in the background.
- **Minimum level** and **Filter text** narrow what is displayed. Lines with no
  recognisable log level are always kept, so tracebacks are never hidden.
- **Download** saves a plain-text copy — handy for attaching to a support issue.

## Security notes

Read this before enabling it on a shared host.

- **Superusers only.** Logs contain request paths, email addresses, IPs and stack
  traces. Ordinary editors must not have access, and 2FA
  (`WAGTAIL_2FA_REQUIRED=True`) is strongly recommended.

- **Secrets are masked, but not perfectly.** Values of environment variables that look
  sensitive (anything whose name contains `secret`, `password`, `token`, `api_key`,
  `client_secret`, `database_url`, …) are replaced with `[redacted]` before the output
  reaches the browser, including the password component of connection strings. Add
  anything else that needs masking to `CLIMWEB_LOG_VIEWER_EXTRA_REDACTIONS`. This is a
  safety net, not a guarantee — a library that prints a novel credential format will
  not be caught.

- **`CONTAINERS=1` allows container inspect**, which exposes other containers'
  environment variables to anything that can reach the proxy. On a single-tenant
  ClimWeb host this is a small step from what the CMS container already knows. If the
  host runs unrelated workloads, set `CLIMWEB_LOG_VIEWER_CONTAINERS` to an explicit
  list so the viewer cannot read them:

  ```env
  CLIMWEB_LOG_VIEWER_CONTAINERS=climweb,climweb_celery_worker,climweb_celery_beat,climweb_nginx
  ```

  The allow-list is enforced server-side: a container name that is not on it is
  rejected before any Docker call is made.

- **Do not add capabilities to the proxy.** `EXEC=1` or `POST=1` would turn a log
  reader into remote code execution on the host.

- **Turn it off when you do not need it** — `CLIMWEB_LOG_VIEWER_ENABLED=False` hides the
  menu item and disables the endpoints, and the proxy can be commented out entirely.

## When to use something else

This is a debugging tool: it tails what Docker has retained, with no search across
time, no history beyond the container's log rotation, and no alerting. For ongoing
monitoring, ship logs out with the OpenTelemetry collector already in the stack — see
[setup-observability.md](setup-observability.md). That is outbound-only, so it also
needs no open port, and it is the better answer for "how is the site doing?" as opposed
to "what just broke?".
