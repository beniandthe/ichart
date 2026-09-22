from dataclasses import dataclass


@dataclass(frozen=True)
class ContractError(Exception):
    code: str
    path: str
    detail: str

    def __str__(self) -> str:
        location = f" at {self.path}" if self.path else ""
        return f"{self.code}{location}: {self.detail}"


class OperationRefusedError(ContractError):
    pass
