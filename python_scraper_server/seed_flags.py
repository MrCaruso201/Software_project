from sqlalchemy.orm import Session
from db.database import SessionLocal
from db.models import PenaltyType

db: Session = SessionLocal()
flags = [
    {"code": "black_flag", "name": "Bandiera Nera (Espulsione)", "action": "warning", "default_seconds": None, "warning_threshold": None, "auto_penalty_code": None, "sort_order": 110},
    {"code": "blue_flag", "name": "Bandiera Blu (Doppiaggio)", "action": "warning", "default_seconds": None, "warning_threshold": None, "auto_penalty_code": None, "sort_order": 120},
]
for data in flags:
    if not db.query(PenaltyType).filter_by(code=data["code"]).first():
        db.add(PenaltyType(**data))
db.commit()
print("Flags added")
