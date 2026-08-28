PYTHON_IMAGE := m.daocloud.io/docker.io/library/python:3.12-slim
PYPI_INDEX_URL ?= https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple
COMPOSE_ENV_FILE ?= deploy/.env.example
COMPOSE_PROJECT_NAME ?= muyu-cloud
TEST_DATABASE_URL ?= postgresql+psycopg://muyu:muyu@localhost:5432/muyu_test
FLUTTER ?= $(shell command -v flutter 2>/dev/null || printf '%s/develop/flutter/bin/flutter' "$(HOME)")
DART ?= $(dir $(FLUTTER))dart
API_BASE_URL ?= http://localhost:8080

.PHONY: test verify backend-test test-task-approval backend-migrate backend-smoke client-test client-build web-test web-build check-deployment legacy-check boundary-check compose-up compose-down compose-clean smoke smoke-task-approval smoke-lightweight-workspace

test: backend-test client-test web-test

verify: backend-migrate backend-test client-test web-test web-build check-deployment legacy-check boundary-check

backend-test:
	docker run --rm --network host \
		-e TEST_DATABASE_URL=$(TEST_DATABASE_URL) \
		-e PYPI_INDEX_URL=$(PYPI_INDEX_URL) \
		-v "$(CURDIR)/backend:/src" \
		-w /src \
		$(PYTHON_IMAGE) \
		sh -c 'pip install --disable-pip-version-check -i "$$PYPI_INDEX_URL" -e ".[dev]" && python -m pytest -q && python -m compileall -q app alembic'

test-task-approval:
	docker run --rm --network host \
		-e TEST_DATABASE_URL=$(TEST_DATABASE_URL) \
		-e PYPI_INDEX_URL=$(PYPI_INDEX_URL) \
		-v "$(CURDIR)/backend:/src" \
		-w /src \
		$(PYTHON_IMAGE) \
		sh -c 'pip install --disable-pip-version-check -i "$$PYPI_INDEX_URL" -e ".[dev]" && python -m pytest -q tests/tasks tests/httpapi/test_task_approval_routes.py tests/httpapi/test_task_approval_sync.py tests/e2e/test_two_person_task_approval.py'

backend-migrate:
	docker run --rm --network host \
		-e DATABASE_URL=$(TEST_DATABASE_URL) \
		-e PYPI_INDEX_URL=$(PYPI_INDEX_URL) \
		-v "$(CURDIR)/backend:/src" \
		-w /src \
		$(PYTHON_IMAGE) \
		sh -c 'pip install --disable-pip-version-check -i "$$PYPI_INDEX_URL" -e . && alembic upgrade head'

backend-smoke:
	API_BASE_URL=$${API_BASE_URL:-http://localhost:$(API_PORT)} sh -c 'curl --fail --silent --show-error "$$API_BASE_URL/health/ready"'

client-test:
	cd client && $(FLUTTER) pub get && $(DART) format --output=none --set-exit-if-changed . && $(FLUTTER) analyze && $(FLUTTER) test

client-build:
	cd client && $(FLUTTER) pub get && $(FLUTTER) build apk --debug --dart-define=API_BASE_URL=$(API_BASE_URL)

web-test:
	cd web && npm ci && npm run typecheck && npm test -- --run

web-build:
	cd web && npm ci && npm run build

check-deployment:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) COMPOSE_ENV_FILE=$(COMPOSE_ENV_FILE) ./scripts/check-deployment.sh

legacy-check:
	./scripts/assert-no-legacy-runtime.sh

boundary-check:
	./scripts/assert-client-boundary.sh

compose-up:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose --env-file $(COMPOSE_ENV_FILE) -f deploy/docker-compose.yml up --build -d

compose-down:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose --env-file $(COMPOSE_ENV_FILE) -f deploy/docker-compose.yml down --remove-orphans

compose-clean:
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) docker compose --env-file $(COMPOSE_ENV_FILE) -f deploy/docker-compose.yml down --volumes --remove-orphans

smoke: backend-smoke

smoke-task-approval:
	PYTHON_IMAGE=$(PYTHON_IMAGE) PYPI_INDEX_URL=$(PYPI_INDEX_URL) TEST_DATABASE_URL=$(TEST_DATABASE_URL) ./scripts/smoke-two-person-task-approval.sh

smoke-lightweight-workspace:
	API_BASE_URL=$(API_BASE_URL) ./scripts/smoke-lightweight-workspace.sh
