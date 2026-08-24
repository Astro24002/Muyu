from sqlalchemy import inspect, text


def test_database_fixture_uses_a_disposable_schema(db_engine) -> None:
    with db_engine.connect() as connection:
        schema = connection.scalar(text("SELECT current_schema()"))

    assert schema.startswith("test_")
    assert "users" in inspect(db_engine).get_table_names(schema=schema)
