import sys
from sqlalchemy.orm import Session
from sqlalchemy import func
from db.database import SessionLocal
from db.models import User

def resolve_user_by_identifier(db: Session, identifier: str):
    identifier = identifier.strip()
    if not identifier:
        return None
    if identifier.startswith("@"):
        username = identifier[1:]
        return db.query(User).filter(func.lower(User.username) == username.lower()).first()
    return db.query(User).filter(func.lower(User.email) == identifier.lower()).first()

db = SessionLocal()
u = resolve_user_by_identifier(db, sys.argv[1])
if u:
    print(f"Found: {u.id} - {u.email} - {u.username}")
else:
    print("Not found")
