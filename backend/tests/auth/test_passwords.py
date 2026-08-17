from app.auth.passwords import hash_password, verify_password


def test_hash_password_does_not_store_plaintext_and_verifies_correct_value() -> None:
    password_hash = hash_password("shared-password")

    assert password_hash != "shared-password"
    assert verify_password("shared-password", password_hash) is True


def test_verify_password_rejects_wrong_value() -> None:
    password_hash = hash_password("shared-password")

    assert verify_password("wrong-password", password_hash) is False
