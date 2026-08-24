import asyncio
from types import SimpleNamespace

from app.main import create_app


def test_lifespan_initializes_database_before_ready(monkeypatch) -> None:
    calls: list[str] = []
    settings = SimpleNamespace(
        database_url="postgresql+psycopg://db",
    )

    class FakeEngine:
        def dispose(self) -> None:
            calls.append("dispose")

    class FakeConnection:
        def execute(self, _statement) -> None:
            pass

        def __enter__(self):
            calls.append("connection-open")
            return self

        def __exit__(self, *_args) -> None:
            calls.append("connection-close")

    monkeypatch.setattr("app.main.get_settings", lambda: settings)
    monkeypatch.setattr("app.main.create_database_engine", lambda url: (calls.append(f"engine:{url}"), FakeEngine())[1])
    monkeypatch.setattr("app.main.run_migrations", lambda url: calls.append(f"migrations:{url}"))
    FakeEngine.connect = lambda _self: FakeConnection()

    app = create_app()

    async def exercise_lifespan() -> None:
        async with app.router.lifespan_context(app):
            assert app.state.ready is True

    asyncio.run(exercise_lifespan())

    assert calls == [
        "engine:postgresql+psycopg://db",
        "migrations:postgresql+psycopg://db",
        "connection-open",
        "connection-close",
        "dispose",
    ]
