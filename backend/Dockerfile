FROM m.daocloud.io/docker.io/library/python:3.12-slim

WORKDIR /app

COPY pyproject.toml ./
COPY app ./app

RUN pip install --disable-pip-version-check --no-cache-dir .

EXPOSE 8080

CMD ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080"]
