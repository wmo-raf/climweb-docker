# CMS webhooks

[Webhook](https://github.com/adnanh/webhook) lets the CMS Admin ask the server to do
things that have to happen outside the containers. The hook definitions live in
`hooks.yaml.sample`; `webhook-config.sh` turns that into `hooks.yaml` with this
installation's paths and secret. The scripts they run are in `scripts/`.

Every hook is authenticated with the Django `SECRET_KEY`, sent by the CMS as the
`X-Webhook-Secret` header.

## The hooks

| Hook | Triggered from | Runs |
|---|---|---|
| `cms-upgrade` | Admin → upgrade page | `scripts/cms-upgrade.sh <version>` |
| `plugin-remove` | Admin → Plugins page | `scripts/plugin-remove.sh <plugin_name>` |
| `cms-task` | Admin → maintenance actions | `scripts/cms-task.sh <task_name>` |

## Maintenance tasks (`cms-task`)

The first two hooks each do one fixed job. `cms-task` is the general one: the CMS
posts `{"task_name": "self-update"}` and the server runs `tasks/self-update.sh`.

The name only ever selects a file from `tasks/` **in this repository**. A payload
can never supply a command, a path or a URL, and the dispatcher rejects anything
that is not `[a-z0-9-]`, so there is nothing to escape out of. Adding a server
capability is a commit here, reviewed like any other code — not a remote fetch.

Why it exists: before this, giving instances a new server-side action meant SSH-ing
into each one to edit `hooks.yaml` and restart webhook. Now the ClimWeb team commits
the task, the focal point presses **self-update**, and the new action appears on
that server. Two things make that work:

* `webhook` is started with `-hotreload`, so it notices a changed `hooks.yaml`
  without being restarted.
* `tasks/self-update.sh` fast-forwards this repo and regenerates `hooks.yaml`
  (and repairs a supervisor config that predates `-hotreload`).

### Adding a task

1. Write `tasks/<name>.sh`. Source `scripts/task-lib.sh`, call `task_init "<name>"`,
   report progress with `task_step`, abort with `task_fail`. Exit non-zero to fail —
   the runner writes the final status from the exit code.
2. Commit it. No change to `hooks.yaml.sample` is needed; the one `cms-task` hook
   serves every task.
3. Instances get it when someone presses **self-update**.

Keep tasks idempotent and safe to run twice. Anything destructive belongs behind
its own confirmation in the CMS, not behind a task name.

### Reporting back

Tasks write `<BACKUP_VOLUME>/task-status.json`, which is mounted into the CMS
container, so the admin page can poll it:

```json
{ "task": "self-update", "status": "running", "step": "Fetching the latest main…",
  "detail": "", "started_at": "…", "updated_at": "…", "log": "…/logs/climweb-tasks.log" }
```

`status` is `running`, `success`, `failed` or `rejected`. Full output goes to
`logs/climweb-tasks.log`.

### Running one by hand

Identical to pressing the button:

```bash
cd /path_to_climweb_dir
sudo bash webhook/scripts/cms-task.sh self-update
```

## Available tasks

| Task | What it does |
|---|---|
| `self-update` | Fast-forwards this repo on its current branch and refreshes the hook list. Refuses if tracked files were edited locally or history diverged. Does not touch `.env`, compose, nginx, containers or data, and does not change the ClimWeb version. |
