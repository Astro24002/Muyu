from app.core.logging import redact_sensitive_data


def test_redaction_removes_credentials_from_nested_request_data() -> None:
    payload = {
        "authorization": "Bearer secret-token",
        "cookie": "session=secret-cookie",
        "body": {
            "otp": "123456",
            "phone": "+8613800138000",
            "qr_nonce": "browser-login-nonce",
            "qr_proof": "approval-proof",
            "title": "visible task title",
        },
    }

    assert redact_sensitive_data(payload) == {
        "authorization": "[REDACTED]",
        "cookie": "[REDACTED]",
        "body": {
            "otp": "[REDACTED]",
            "phone": "[REDACTED]",
            "qr_nonce": "[REDACTED]",
            "qr_proof": "[REDACTED]",
            "title": "visible task title",
        },
    }
