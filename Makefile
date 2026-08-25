PYTHON_IMAGE := m.daocloud.io/docker.io/library/python:3.12-slim
COMPOSE_ENV_FILE ?= deploy/.env.example
COMPOSE_PROJECT_NAME ?= muyu-cloud
TEST_DATABASE_URL ?= postgresql+psycopg://muyu:muyu@localhost:5432/muyu_test
FLUTTER ?= $(shell command -v flutter 2>/dev/null || printf '%s/develop/flutter/bin/flutter' "$(HOME)")
DART ?= $(dir $(FLUTTER))dart
API_BASE_URL ?= http://localhost:8080
WEB_ORIGIN ?= http://localhost:8080

.PHONY: test verify backend-test backend-migrate backend-smoke client-test client-build client-build-web check-deployment legacy-check compose-up compose-down compose-clean smoke

test: backend-test client-test

verify: backend-migrate backend-test client-test check-deployment legacy-check

backend-test:
	docker run --rm --network host \
		-e TEST_DATABASE_URL=$(TEST_DATABASE_URL) \
		-v "$(CURDIR)/backend:/src" \
		-w /src \
		$(PYTHON_IMAGE) \
		sh -c 'pip install --disable-pip-version-check -e ".[dev]" && python -m pytest -q && python -m compileall -q app alembic'

backend-migrate:
	docker run --rm --network host \
		-e DATABASE_URL=$(TEST_DATABASE_URL) \
		-v "$(CURDIR)/backend:/src" \
		-w /src \
		$(PYTHON_IMAGE) \
		sh -c 'pip install --disable-pip-version-check -e . && alembic upgrade head'

backend-smoke:
	API_BASE_URL=$${API_BASE_URL:-http://localhost:$(API_PORT)} sh -c 'curl --fail --silent --show-error "$$API_BASE_URL/health/ready"'

client-test:
	cd client && $(FLUTTER) pub get && $(DART) format --output=none --set-exit-if-changed . && $(FLUTTER) analyze && $(FLUTTER) test

client-build:
	cd client && $(FLUTTER) pub get && $(FLUTTER) build apk --debug --dart-define=API_BASE_URL=$(API_BASE_URL)

client-build-web:
	cd client && $(FLUTTER) pub get && $(FLUTTER) build web --release --dart-define=API_BASE_URL=$(API_BASE_URL) --dart-define=WEB_ORIGIN=$(WEB_ORIGIN)

check-deployment:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) COMPOSE_ENV_FILE=$(COMPOSE_ENV_FILE) ./scripts/check-deployment.sh

legacy-check:
	./scripts/assert-no-legacy-runtime.sh

compose-up:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose --env-file $(COMPOSE_ENV_FILE) -f deploy/docker-compose.yml up --build -d

compose-down:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose --env-file $(COMPOSE_ENV_FILE) -f deploy/docker-compose.yml down --remove-orphans

compose-clean:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose --env-file $(COMPOSE_ENV_FILE) -f deploy/docker-compose.yml down --volumes --remove-orphans

smoke: backend-smoke
