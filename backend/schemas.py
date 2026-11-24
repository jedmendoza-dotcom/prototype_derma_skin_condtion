"""Request/response models. Validation rules mirror the Flutter forms and the
CHECK constraints in the database, so bad input is rejected early and clearly."""
import re

from pydantic import BaseModel, Field, field_validator

_NAME = re.compile(r"^[A-Za-zÀ-ÿñÑ][A-Za-zÀ-ÿñÑ .'\-]*$")
_PHONE = re.compile(r"^(09\d{9}|\+639\d{9})$")
_USERNAME = re.compile(r"^[A-Za-z0-9_]{4,20}$")


class RegisterIn(BaseModel):
    first_name: str
    last_name: str
    middle_name: str | None = None
    contact_number: str
    age: int
    username: str
    password: str = Field(repr=False)
    consent: bool

    @field_validator("first_name", "last_name")
    @classmethod
    def _required_name(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 2 or len(v) > 40 or not _NAME.match(v):
            raise ValueError("2-40 letters only")
        return v

    @field_validator("middle_name")
    @classmethod
    def _optional_name(cls, v: str | None) -> str | None:
        if v is None or not v.strip():
            return None
        v = v.strip()
        if len(v) > 40 or not _NAME.match(v):
            raise ValueError("letters only, max 40")
        return v

    @field_validator("contact_number")
    @classmethod
    def _phone(cls, v: str) -> str:
        v = re.sub(r"[\s-]", "", v)
        if not _PHONE.match(v):
            raise ValueError("use 09XXXXXXXXX or +639XXXXXXXXX")
        return v

    @field_validator("age")
    @classmethod
    def _age(cls, v: int) -> int:
        if not 1 <= v <= 120:
            raise ValueError("age must be 1-120")
        return v

    @field_validator("username")
    @classmethod
    def _username_ok(cls, v: str) -> str:
        v = v.strip()
        if not _USERNAME.match(v):
            raise ValueError("4-20 characters: letters, numbers, underscore")
        return v

    @field_validator("password")
    @classmethod
    def _password_ok(cls, v: str) -> str:
        if not 8 <= len(v) <= 64:
            raise ValueError("password must be 8-64 characters")
        if not (re.search(r"[a-z]", v) and re.search(r"[A-Z]", v)
                and re.search(r"\d", v) and re.search(r"[^A-Za-z0-9]", v)):
            raise ValueError("use upper and lower case, a number and a symbol")
        return v

    @field_validator("consent")
    @classmethod
    def _consent_given(cls, v: bool) -> bool:
        if v is not True:
            raise ValueError("consent to data processing is required")
        return v


class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=40)
    password: str = Field(min_length=1, max_length=64, repr=False)
    remember_me: bool = False


class RefreshIn(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200, repr=False)


class UserOut(BaseModel):
    user_id: int
    username: str
    first_name: str
    last_name: str
    role: str


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int                 # seconds until the access token expires
    refresh_expires_at: str         # ISO time when the refresh token (remember me) expires
    user: UserOut


class AccessOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
