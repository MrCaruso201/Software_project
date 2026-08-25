import urllib.request, json
data = "username=user&password=user".encode()
req = urllib.request.Request("http://127.0.0.1:8000/auth/login", data=data)
token = json.loads(urllib.request.urlopen(req).read().decode())["access_token"]
req2 = urllib.request.Request("http://127.0.0.1:8000/notifications/me")
req2.add_header("Authorization", f"Bearer {token}")
print(urllib.request.urlopen(req2).read().decode())
