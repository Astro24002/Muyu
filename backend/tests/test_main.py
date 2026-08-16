import asyncio

from app.main import create_app


def test_healthz_reports_ready_after_application_startup() -> None:
    app = create_app()

    async def exercise_lifespan() -> dict[str, str]:
        async with app.router.lifespan_context(app):
            route = next(route for route in app.routes if route.path == "/healthz")
            return route.endpoint()

    assert asyncio.run(exercise_lifespan()) == {"status": "ok"}
