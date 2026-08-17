from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy.orm import Session

from app.auth.routes import UserResponse
from app.httpapi.dependencies import get_db, require_access_token
from app.httpapi.errors import ApiError
from app.user.repository import UserRepository


class ProfilePatchRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    nickname: str | None = Field(default=None, min_length=1, max_length=100)
    role: str | None = Field(default=None, min_length=1, max_length=100)

    @model_validator(mode="after")
    def require_mutable_field(self) -> "ProfilePatchRequest":
        if self.nickname is None and self.role is None:
            raise ValueError("at least one profile field is required")
        return self


router = APIRouter(tags=["user"])


@router.get("/api/me", response_model=UserResponse)
def me(user_id: UUID = Depends(require_access_token), session: Session = Depends(get_db)) -> UserResponse:
    user = UserRepository(session).find_by_id(user_id)
    if user is None:
        raise ApiError(401, "UNAUTHORIZED", "authentication required")
    return UserResponse.model_validate(user)


@router.patch("/api/me", response_model=UserResponse)
def update_me(
    payload: ProfilePatchRequest,
    user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> UserResponse:
    repository = UserRepository(session)
    user = repository.find_by_id(user_id)
    if user is None:
        raise ApiError(401, "UNAUTHORIZED", "authentication required")
    if payload.nickname is not None:
        user.nickname = payload.nickname
    if payload.role is not None:
        user.role = payload.role
    session.commit()
    return UserResponse.model_validate(user)


@router.get("/api/users", response_model=list[UserResponse])
def list_users(
    _user_id: UUID = Depends(require_access_token),
    session: Session = Depends(get_db),
) -> list[UserResponse]:
    return [UserResponse.model_validate(user) for user in UserRepository(session).list_users()]
