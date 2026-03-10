# Default container name
CONTAINER=climweb

.PHONY: setup start stop restart logs shell createsuperuser build down

setup:
	bash setup.sh
	
build:
	docker compose build

pull:
	docker compose pull

start:
	docker compose pull && docker compose up -d 

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
