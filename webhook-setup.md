# Manage Climweb Upgrades

This guide will walk you trhough how to setup upgrade functionality on the CMS Admin interface.

## 1. Set up Webhook

[Webhook](https://github.com/adnanh/webhook) helps to automate some tasks that otherwise need to be done manually. For example upgrading the CMS to a newer version.

The [Webhook](https://github.com/adnanh/webhook) package needs to be installed on your server (`NOT` in a docker container)

Install the [Webhook](https://github.com/adnanh/webhook) package for your OS as described [here](https://github.com/adnanh/webhook/tree/master#using-package-manager)

If on Ubuntu or Debian, you can run:

```
sudo apt-get install webhook
```

From the root project directory (where you cloned this project) run:

```bash
bash webhook-config.sh
```

Run it with `bash`, not `sh` — on Debian/Ubuntu `sh` is `dash`, which does not support the
parameter expansion the script uses and will fail with `Bad substitution`.

This will create a new file `webhook/hooks.yaml` with the correct paths in place, using the `webhook/hooks.yaml.sample` file

Re-run this script any time `SECRET_KEY` changes in `.env`, then restart webhook —
otherwise the CMS will sign upgrade requests with a secret the hook no longer expects
and every request will be rejected with `Hook rules were not satisfied`.

We will use this file to run [Webhook](https://github.com/adnanh/webhook)

---

## 2. Running Webhook server with Supervisor

Install supervisor to keep the webhook server running in the background.

```bash
sudo apt install supervisor
```

Create a `webhook.conf` file in `/etc/supervisor/conf.d/`

```bash
cd /etc/supervisor/conf.d
sudo nano webhook.conf
```

Add the following inside the `webhook.conf` file

```conf
[program:webhook]
command=webhook -hooks /path_to_climweb_dir/webhook/hooks.yaml -hotreload -verbose
autostart=true
autorestart=true
startretries=3
startsecs=0
```

`-hotreload` matters more than it looks. Without it, `webhook` reads the hook list
once at startup, so every new server-side action the ClimWeb team ships would need
someone to SSH in and restart the service. With it, `webhook` notices a changed
`hooks.yaml` on its own, and the `self-update` task can install new actions from the
CMS Admin with no terminal access. If your `webhook.conf` predates this flag, add it
and run `sudo supervisorctl reread && sudo supervisorctl update` — or just press
**self-update** in the admin, which repairs the config for you.

Save the file.

After creating the configuration, tell `supervisord` to refresh its configuration and start the service:

```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl status
```

If everything is ok, `Webhook` is now set and ready to be used.


Set `CMS_TASK_HOOK_URL` as well:

`http://host.docker.internal:9000/hooks/cms-task`

That is the maintenance-task hook — the one that lets the CMS Admin run named jobs
from `webhook/tasks/`, including `self-update`, which is how this server picks up
future capabilities without anyone logging in. See `webhook/webhook.md`.

You can now set the  `CMS_UPGRADE_HOOK_URL` env variable to:

`http://host.docker.internal:9000/hooks/cms-upgrade`

Note this a special docker network url accessed only from inside the `cms_web` docker container.

Then rebubild and restart climweb with these commands

```bash

cd /path_to_climweb_dir/

make restart
```
---
