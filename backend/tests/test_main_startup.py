import asyncio
from types import SimpleNamespace

from app.main import create_app


def test_lifespan_initializes_database_before_ready(monkeypatch) -> None:
    calls: list[str] = []
    settings = SimpleNamespace(database_url="postgresql+psycopg://db", auth_password="password")

    class FakeEngine:
        def dispose(self) -> None:
            calls.append("dispose")

    class FakeSession:
        def __enter__(self):
            calls.append("session-open")
            return object()

        def __exit__(self, *_args) -> None:
            calls.append("session-close")

    monkeypatch.setattr("app.main.get_settings", lambda: settings)
    monkeypatch.setattr("app.main.create_database_engine", lambda url: (calls.append(f"engine:{url}"), FakeEngine())[1])
    monkeypatch.setattr("app.main.run_migrations", lambda url: calls.append(f"migrations:{url}"))
    monkeypatch.setattr("app.main.Session", lambda engine: FakeSession())
    monkeypatch.setattr("app.main.seed_fixed_users", lambda session, password: calls.append(f"seed:{password}"))

    app = create_app()

    async def exercise_lifespan() -> None:
        async with app.router.lifespan_context(app):
            assert app.state.ready is True

    asyncio.run(exercise_lifespan())

    assert calls == [
        "engine:postgresql+psycopg://db",
        "migrations:postgresql+psycopg://db",
        "session-open",
        "seed:password",
        "session-close",
        "dispose",
    ]
