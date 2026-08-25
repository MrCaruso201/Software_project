import requests

# 1. Login
r = requests.post("http://localhost:8000/auth/login", data={"username": "user", "password": "user123"})
token = r.json().get("access_token")

# 2. Get notifications
r = requests.get("http://localhost:8000/notifications/me", headers={"Authorization": f"Bearer {token}"})
print(r.status_code)
print(r.text)
