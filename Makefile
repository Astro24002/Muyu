PYTHON_IMAGE := m.daocloud.io/docker.io/library/python:3.12-slim

.PHONY: test backend-test compose-up compose-down

test: backend-test

backend-test:
	docker run --rm -v "$(CURDIR)/backend:/src" -w /src $(PYTHON_IMAGE) sh -c 'pip install --disable-pip-version-check -e ".[dev]" && python -m pytest'

compose-up:
	docker compose --env-file deploy/.env -f deploy/docker-compose.yml up --build -d

compose-down:
	docker compose --env-file deploy/.env -f deploy/docker-compose.yml down --volumes --remove-orphans
