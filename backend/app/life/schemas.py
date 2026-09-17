from __future__ import annotations

from datetime import date
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.db.enums import AnniversaryKind, HabitFrequency, LedgerEntryType


class LedgerCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    type: LedgerEntryType
    amount: str | None = None
    amount_minor: int | None = Field(default=None, gt=0)
    title: str = Field(min_length=1, max_length=200)
    category: str = Field(min_length=1, max_length=80)
    payer_or_payee_id: UUID
    date: date
    note: str | None = Field(default=None, max_length=5000)

    @model_validator(mode="after")
    def require_amount(self) -> "LedgerCreateRequest":
        if self.amount is None and self.amount_minor is None:
            raise ValueError("amount or amount_minor is required")
        if self.amount is not None and self.amount_minor is not None:
            raise ValueError("amount and amount_minor cannot both be provided")
        return self


class LedgerPatchRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    expected_version: int = Field(ge=1)
    changes: dict[str, Any] = Field(default_factory=dict)


class LedgerDeleteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    expected_version: int = Field(ge=1)
    confirm: bool


class HabitCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    title: str = Field(min_length=1, max_length=120)
    note: str | None = Field(default=None, max_length=5000)
    frequency: HabitFrequency
    start_date: date | None = None


class HabitPatchRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    expected_version: int = Field(ge=1)
    changes: dict[str, Any] = Field(default_factory=dict)


class HabitActionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    expected_version: int = Field(ge=1)


class HabitDeleteRequest(HabitActionRequest):
    confirm: bool


class AnniversaryCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    title: str = Field(min_length=1, max_length=160)
    anchor_date: date
    kind: AnniversaryKind
    prepare_days: int = Field(default=0)
    note: str | None = Field(default=None, max_length=5000)


class AnniversaryPatchRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    expected_version: int = Field(ge=1)
    changes: dict[str, Any] = Field(default_factory=dict)


class AnniversaryDeleteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    expected_version: int = Field(ge=1)
    confirm: bool


class GeneratePreparationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
