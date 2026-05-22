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
sh webhook-config.sh
```

This will create a new file `webhook/hooks.yaml` with the correct paths in place, using the `webhook/hooks.yaml.sample` file

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
command=webhook -hooks /path_to_climweb_dir/webhook/hooks.yaml -verbose
autostart=true
autorestart=true
startretries=3
startsecs=0
```

Save the file.

After creating the configuration, tell `supervisord` to refresh its configuration and start the service:

```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl status
```

If everything is ok, `Webhook` is now set and ready to be used.


You can now set the  `CMS_UPGRADE_HOOK_URL` env variable to:

`http://host.docker.internal:9000/hooks/cms-upgrade`

Note this a special docker network url accessed only from inside the `cms_web` docker container.

Then rebubild and restart climweb with these commands

```bash

cd /path_to_climweb_dir/

make restart
```
---
