"""
Hashing e verifica delle password con bcrypt.

bcrypt è lento by design: rende costoso il brute-force anche se il DB
venisse compromesso. Non usare mai MD5/SHA per le password.
"""

from passlib.context import CryptContext

_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(plain: str) -> str:
    """Restituisce l'hash bcrypt della password. Non invertibile."""
    return _pwd_context.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    """True se plain corrisponde all'hash bcrypt memorizzato."""
    return _pwd_context.verify(plain, hashed)
