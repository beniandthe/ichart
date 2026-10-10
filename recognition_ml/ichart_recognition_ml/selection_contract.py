"""Exact authority contract for development-model selection evidence."""

from __future__ import annotations

from typing import Optional, Tuple

from .errors import ContractError


BOUND_DEVELOPMENT_SELECTION_AUTHORITY = (
    "bound-development-writer-comparison-v4"
)
UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY = "unselected-development-training"
DEVELOPMENT_SELECTION_AUTHORITIES = (
    BOUND_DEVELOPMENT_SELECTION_AUTHORITY,
    UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY,
)


def validate_development_selection_binding(
    authority: object,
    report_sha256: object,
) -> Tuple[str, Optional[str]]:
    if authority not in DEVELOPMENT_SELECTION_AUTHORITIES:
        raise ContractError(
            "invalid_development_selection_authority",
            "development_selection_authority",
            "must be one of " + ", ".join(DEVELOPMENT_SELECTION_AUTHORITIES),
        )
    authority = str(authority)
    if authority == BOUND_DEVELOPMENT_SELECTION_AUTHORITY:
        if (
            not isinstance(report_sha256, str)
            or len(report_sha256) != 64
            or any(character not in "0123456789abcdef" for character in report_sha256)
        ):
            raise ContractError(
                "invalid_sha256",
                "development_selection_report_sha256",
                "bound selection requires 64 lowercase hexadecimal characters",
            )
        return authority, report_sha256
    if report_sha256 is not None:
        raise ContractError(
            "unexpected_development_selection_digest",
            "development_selection_report_sha256",
            "unselected development training must not claim a report digest",
        )
    return authority, None
