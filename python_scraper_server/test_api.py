from fastapi.testclient import TestClient
from main import app
import json

client = TestClient(app)

def login(username, pwd):
    resp = client.post("/auth/login", data={"username": username, "password": pwd})
    return resp.json().get("access_token")

token = login("admin", "admin")
if not token:
    print("Admin login failed")
    exit(1)

headers = {"Authorization": f"Bearer {token}"}

events_resp = client.get("/events")
event_id = events_resp.json()[0]["id"]
print(f"Using event ID {event_id}")

user_token = login("user", "user")
user_headers = {"Authorization": f"Bearer {user_token}"}
team_data_create = {
    "team_name": "Test Team 99",
    "member_emails": [],
    "accepts_extra_pilots": False
}
reg_resp = client.post(f"/events/{event_id}/register_team", json=team_data_create, headers=user_headers)
if reg_resp.status_code != 200:
    teams_resp = client.get(f"/events/{event_id}/registrations/teams", headers=user_headers)
    teams = teams_resp.json()
    if not teams:
        print("No teams found")
        exit(1)
    team_id = teams[-1]["team_id"]
else:
    team_id = reg_resp.json()["team_id"]

print(f"Team ID: {team_id}")

team_data_update = {
    "team_name": "Test Team 99 Edited",
    "member_emails": ["user2@user2.com"],
    "leader_email": "user@mail.it",
    "accepts_extra_pilots": False
}
update_resp = client.put(f"/events/{event_id}/registrations/team/{team_id}", json=team_data_update, headers=headers)
print(f"Update response: {update_resp.status_code}")
print(update_resp.json())

