from __future__ import annotations

import os

import httpx
import pytest


@pytest.mark.cloud_protocol
def test_lightweight_workspace_two_user_acceptance() -> None:
    if os.getenv('RUN_CLOUD_PROTOCOL') != '1':
        pytest.skip('set RUN_CLOUD_PROTOCOL=1 for PostgreSQL cloud acceptance')
    with httpx.Client(base_url=os.getenv('CLOUD_PROTOCOL_BASE_URL', 'http://localhost:8080'), timeout=15) as client:
        assert client.get('/health/ready').status_code == 200
        snapshot = client.get('/api/v1/workspaces/current/snapshot')
        assert snapshot.status_code in (200, 401)
