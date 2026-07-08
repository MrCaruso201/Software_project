"""
Modelli Pydantic per le request/response degli endpoint di autenticazione.
"""

from pydantic import BaseModel


class RegisterRequest(BaseModel):
    username: str
    email: str
    password: str


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str


class UserResponse(BaseModel):
    id: int
    username: str
    first_name: str | None = None
    last_name: str | None = None
    profile_picture_url: str | None = None
    email: str
    role: str
    created_at: str


class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str

class UserUpdateRequest(BaseModel):
    first_name: str | None = None
    last_name: str | None = None
