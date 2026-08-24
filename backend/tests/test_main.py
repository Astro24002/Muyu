import asyncio
from types import SimpleNamespace

from app.main import create_app


def test_health_endpoints_report_ready_after_application_startup(monkeypatch) -> None:
    class FakeEngine:
        def dispose(self) -> None:
            pass

    class FakeConnection:
        def execute(self, _statement) -> None:
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_args) -> None:
            pass

    FakeEngine.connect = lambda _self: FakeConnection()

    monkeypatch.setattr(
        "app.main.get_settings",
        lambda: SimpleNamespace(
            database_url="postgresql+psycopg://db",
        ),
    )
    monkeypatch.setattr("app.main.create_database_engine", lambda _url: FakeEngine())
    monkeypatch.setattr("app.main.run_migrations", lambda _url: None)

    app = create_app()

    async def exercise_lifespan() -> dict[str, str]:
        async with app.router.lifespan_context(app):
            route = next(route for route in app.routes if getattr(route, "path", None) == "/health/ready")
            return route.endpoint(SimpleNamespace(app=app))

    assert asyncio.run(exercise_lifespan()) == {"status": "ready"}
