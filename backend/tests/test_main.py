import asyncio
from types import SimpleNamespace

from app.main import create_app


def test_healthz_reports_ready_after_application_startup(monkeypatch) -> None:
    class FakeEngine:
        def dispose(self) -> None:
            pass

    class FakeSession:
        def __enter__(self):
            return object()

        def __exit__(self, *_args) -> None:
            pass

    monkeypatch.setattr(
        "app.main.get_settings",
        lambda: SimpleNamespace(database_url="postgresql+psycopg://db", auth_password="password"),
    )
    monkeypatch.setattr("app.main.create_database_engine", lambda _url: FakeEngine())
    monkeypatch.setattr("app.main.run_migrations", lambda _url: None)
    monkeypatch.setattr("app.main.Session", lambda _engine: FakeSession())
    monkeypatch.setattr("app.main.seed_fixed_users", lambda _session, _password: None)

    app = create_app()

    async def exercise_lifespan() -> dict[str, str]:
        async with app.router.lifespan_context(app):
            route = next(route for route in app.routes if route.path == "/healthz")
            return route.endpoint()

    assert asyncio.run(exercise_lifespan()) == {"status": "ok"}
