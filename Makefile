# Default container name
CONTAINER=climweb

.PHONY: setup start stop restart logs shell createsuperuser build down backup restore

setup:
	bash setup.sh
	
build:
	docker compose build

pull:
	docker compose pull

permit:
	sudo chown -R 1001:1001 climweb/backup
	sudo chown -R 1001:1001 climweb/static
	sudo chown -R 1001:1001 climweb/plugins
	sudo chown -R 1001:1001 climweb/media


# A failed refresh must not stop the stack from starting: images already on
# the server are used, and any that are missing are pulled by `up`.
start:
	docker compose pull --ignore-pull-failures
	docker compose up -d

stop:
	docker compose stop

restart:
	docker compose down
	docker compose up -d

down:
	docker compose down --remove-orphans

logs:
	docker compose logs -f --tail=100

shell:
	docker exec -it $(CONTAINER) /bin/bash

createsuperuser:
	docker exec -it $(CONTAINER) /bin/bash -c "climweb createsuperuser"

generate_forecast:
	docker exec -it $(CONTAINER) /bin/bash -c "climweb generate_forecast"

status:
	docker compose ps

backup:
	bash scripts/backup.sh --clean

restore:
	bash scripts/restore.sh
