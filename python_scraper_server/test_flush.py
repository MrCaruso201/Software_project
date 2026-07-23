from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from db.models import Base, EventRegistration, User
from db.database import DATABASE_URL
import uuid

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine)
db = SessionLocal()

# Cleanup
db.query(EventRegistration).filter_by(event_id=6, user_id=99).delete()
db.commit()

team_id = str(uuid.uuid4())
reg_old = EventRegistration(user_id=99, event_id=6, team_name="test_flush", team_id=team_id, is_team_leader=False, status="confirmed")
db.add(reg_old)
db.commit()

# Now simulate update
db.delete(reg_old)
reg_new = EventRegistration(user_id=99, event_id=6, team_name="test_flush", team_id=team_id, is_team_leader=False, status="confirmed")
db.add(reg_new)

try:
    db.commit()
    print("Success!")
except Exception as e:
    print("Error:", e)

