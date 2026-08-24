from types import SimpleNamespace

from fastapi import HTTPException

from app.main import create_app


def _endpoint(app, path: str):
    return next(route.endpoint for route in app.routes if getattr(route, "path", None) == path)


def test_health_reports_database_readiness() -> None:
    class Connection:
        def execute(self, statement) -> None:
            assert str(statement) == "SELECT 1"

        def __enter__(self):
            return self

        def __exit__(self, *_args) -> None:
            pass

    class Engine:
        def connect(self) -> Connection:
            return Connection()

    app = create_app()
    app.state.ready = True
    app.state.engine = Engine()

    assert _endpoint(app, "/health/ready")(SimpleNamespace(app=app)) == {"status": "ready"}


def test_health_reports_not_ready_before_database_initialization() -> None:
    app = create_app()

    try:
        _endpoint(app, "/health/ready")(SimpleNamespace(app=app))
    except HTTPException as error:
        assert error.status_code == 503
    else:
        raise AssertionError("readiness must fail before database initialization")


def test_live_health_does_not_depend_on_database_readiness() -> None:
    app = create_app()

    assert _endpoint(app, "/health/live")() == {"status": "live"}
