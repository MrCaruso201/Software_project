from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from db.models import Base, EventRegistration, User
from db.database import DATABASE_URL
import uuid

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine)
db = SessionLocal()

admin = db.query(User).filter_by(email="admin@admin.com").first()
print(f"Admin ID: {admin.id}")

reg = db.query(EventRegistration).filter_by(team_name="test_team").first()
if not reg:
    team_id = str(uuid.uuid4())
    reg = EventRegistration(user_id=1, event_id=6, team_name="test_team", team_id=team_id, is_team_leader=True, status="confirmed")
    db.add(reg)
    db.commit()
    print(f"Created team {team_id}")
else:
    team_id = reg.team_id
    print(f"Found team {team_id}")

# Test notify_user explicitly!
from notifications.router import notify_user

try:
    notify_user(db, 1, 6, "admin_registered", "Squadra modificata", "L'organizzatore ha modificato la tua squadra.")
    db.refresh(reg)
    print("Success!")
except Exception as e:
    print(f"Error: {e}")

