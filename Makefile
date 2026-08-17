PYTHON_IMAGE := m.daocloud.io/docker.io/library/python:3.12-slim
COMPOSE_ENV_FILE ?= deploy/.env.example
COMPOSE_PROJECT_NAME ?= muyu
API_PORT ?= 8080
TEST_DATABASE_URL ?= sqlite:////tmp/muyu-test.db
FLUTTER ?= $(shell command -v flutter 2>/dev/null || printf '%s/develop/flutter/bin/flutter' "$(HOME)")
DART ?= $(dir $(FLUTTER))dart

.PHONY: test backend-test client-test compose-up compose-down compose-clean smoke smoke-tasks

test: backend-test client-test

backend-test:
	docker run --rm \
		-e TEST_DATABASE_URL=$(TEST_DATABASE_URL) \
		-v "$(CURDIR)/backend:/src" \
		-w /src \
		$(PYTHON_IMAGE) \
		sh -c 'pip install --disable-pip-version-check -e ".[dev]" && python -m pytest -q && python -m compileall -q app alembic'

client-test:
	cd client && $(FLUTTER) pub get && $(DART) format --output=none --set-exit-if-changed . && $(FLUTTER) analyze && $(FLUTTER) test

compose-up:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) API_PORT=$(API_PORT) docker compose --env-file $(COMPOSE_ENV_FILE) -f deploy/docker-compose.yml up --build -d

compose-down:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) API_PORT=$(API_PORT) docker compose --env-file $(COMPOSE_ENV_FILE) -f deploy/docker-compose.yml down --remove-orphans

compose-clean:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) API_PORT=$(API_PORT) docker compose --env-file $(COMPOSE_ENV_FILE) -f deploy/docker-compose.yml down --volumes --remove-orphans

smoke:
	API_BASE_URL=$${API_BASE_URL:-http://localhost:$(API_PORT)} AUTH_PASSWORD="$${AUTH_PASSWORD:?set AUTH_PASSWORD}" ./scripts/smoke-auth.sh

smoke-tasks:
	API_BASE_URL=$${API_BASE_URL:-http://localhost:$(API_PORT)} AUTH_PASSWORD="$${AUTH_PASSWORD:?set AUTH_PASSWORD}" ./scripts/smoke-tasks.sh
