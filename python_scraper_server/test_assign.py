from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from db.models import Base, EventRegistration, User
from db.database import DATABASE_URL
from events.router import assign_to_team
from events.schemas import AdminAssignTeamRequest
import uuid

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine)
db = SessionLocal()

# Setup test data
db.query(EventRegistration).filter_by(event_id=6, team_name="test_assign").delete()
db.query(EventRegistration).filter_by(event_id=6, user_id=4).delete()
db.query(EventRegistration).filter_by(event_id=6, user_id=5).delete()
db.commit()

team_id = str(uuid.uuid4())
leader = EventRegistration(user_id=1, event_id=6, team_name="test_assign", team_id=team_id, is_team_leader=True, status="confirmed")
db.add(leader)

reg1 = EventRegistration(user_id=4, event_id=6, team_name=None, team_id=None, is_team_leader=False, status="confirmed")
reg2 = EventRegistration(user_id=5, event_id=6, team_name=None, team_id=None, is_team_leader=False, status="confirmed")
db.add(reg1)
db.add(reg2)
db.commit()

req = AdminAssignTeamRequest(registration_ids=[reg1.id, reg2.id])
user_payload = {"role": "race_director"}

try:
    res = assign_to_team(6, team_id, req, user_payload, db)
    print("Success:", res)
except Exception as e:
    print("Error during assign_to_team:")
    import traceback
    traceback.print_exc()

