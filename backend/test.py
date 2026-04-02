'''
    File: backend/test.py
    Description:
        Full API test suite. Covers internal operations including auth, oauth, user management,
        posts, volunteer workflow gamification, comments, images upload and admin endpoints.

    Usage:
        python test.py
        Make sure the development server is running locally on port 8080 before executing.
'''

import requests
import os
import uuid
import json

BASE_URL = "http://127.0.0.1:8080"
IMAGE_PATH = "Template.png"


# ─── Helpers ──────────────────────────────────────────────────────────────────

def log(title, response, expected_status=None):
    is_success = response.status_code == expected_status if expected_status else response.ok
    status_mark = "PASS" if is_success else "FAIL"

    print(f"\n{'─'*60}")
    print(f"[{status_mark}] {title}")
    print(f"       {response.request.method} {response.request.url}")
    print(f"       Status: {response.status_code} (expected {expected_status if expected_status else '2xx'})")

    if response.request.headers.get("Authorization"):
        print("       Auth: Bearer token present")

    if response.request.body:
        try:
            body = json.loads(response.request.body)
            print(f"       Body: {json.dumps(body)}")
        except Exception:
            print("       Body: [form-data or binary]")

    try:
        resp_json = response.json()
        print(f"       Response: {json.dumps(resp_json, indent=2)}")
        return resp_json
    except Exception:
        print(f"       Response: {response.text}")
        return response.text


def get_me(headers):
    return requests.get(f"{BASE_URL}/auth/me", headers=headers).json()


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("STARTING API TEST SUITE\n")

    # ── 1. Admin Auth ──────────────────────────────────────────────────────────
    print("\n=== ADMIN AUTH ===")

    res = requests.post(f"{BASE_URL}/auth/login", json={
        "email": "admin@admin.com",
        "username": "admin",
        "password": "12345678"
    })
    admin_auth = log("Admin login", res, 200)
    if res.status_code != 200:
        print("CRITICAL: Cannot proceed without admin auth.")
        return

    admin_token   = admin_auth.get("access_token")
    admin_headers = {"Authorization": f"Bearer {admin_token}"}

    res = requests.get(f"{BASE_URL}/auth/me", headers=admin_headers)
    log("Admin /auth/me", res, 200)

    # ── 2. Register test users ─────────────────────────────────────────────────
    print("\n=== USER REGISTRATION ===")

    users = []
    for i in range(1, 4):
        num = str(uuid.uuid4())[:6]
        user_data = {
            "email":    f"testuser_{num}@example.com",
            "username": f"test_{num}",
            "password": "password123"
        }
        res = requests.post(f"{BASE_URL}/auth/register", json=user_data)
        log(f"Register user {i}", res, 201)
        users.append(user_data)

    # ── 3. Login users ─────────────────────────────────────────────────────────
    print("\n=== USER LOGIN ===")

    def login_user(user_data, label):
        res = requests.post(f"{BASE_URL}/auth/login", json={
            "email":     user_data["email"],
            "password":  user_data["password"],
            "fcm_token": f"mock_fcm_token_{label}"   # registers device token on login
        })
        auth = log(f"Login {label}", res, 200)
        headers = {"Authorization": f"Bearer {auth['access_token']}"}
        uid = get_me(headers)["id"]
        return auth, headers, uid

    u1_auth, u1_headers, u1_uuid = login_user(users[0], "user1")
    u2_auth, u2_headers, u2_uuid = login_user(users[1], "user2")
    u3_auth, u3_headers, u3_uuid = login_user(users[2], "user3")

    # ── 4. Token refresh ───────────────────────────────────────────────────────
    print("\n=== TOKEN REFRESH ===")

    res = requests.post(f"{BASE_URL}/auth/refresh", json={"refresh_token": u1_auth["refresh_token"]})
    refresh_data = log("User 1 token refresh", res, 200)
    if res.status_code == 200:
        u1_headers = {"Authorization": f"Bearer {refresh_data['access_token']}"}

    # ── 5. OAuth mock test ─────────────────────────────────────────────────────
    print("\n=== OAUTH (GITHUB) ===")
    # Simulates what Flutter sends after receiving a Supabase/Firebase token
    # Replace mock_firebase_token_value with a real token when testing end-to-end

    res = requests.post(f"{BASE_URL}/auth/github", json={
        "firebase_token": "mock_firebase_token_value",
        "device_info":    "test-runner/python-requests"
    })
    log(
        "GitHub OAuth login (mock token — expects 401 unless real token provided)",
        res,
        401   # expected to fail with mock token; change to 200 for real token test
    )

    # ── 6. User profile ────────────────────────────────────────────────────────
    print("\n=== USER PROFILE ===")

    res = requests.get(f"{BASE_URL}/users/me", headers=u1_headers)
    log("User 1 /users/me", res, 200)

    res = requests.get(f"{BASE_URL}/users/profile/stats", headers=u1_headers)
    log("User 1 profile stats", res, 200)

    res = requests.get(f"{BASE_URL}/users/leaderboard", headers=u1_headers)
    log("Leaderboard", res, 200)

    # ── 7. Image upload ────────────────────────────────────────────────────────
    print("\n=== IMAGE UPLOAD ===")

    mock_img_url   = "http://fake.url/image.webp"
    mock_public_id = "fake_id"

    if os.path.exists(IMAGE_PATH):
        try:
            with open(IMAGE_PATH, "rb") as f:
                res = requests.post(
                    f"{BASE_URL}/images/upload/",
                    headers=u1_headers,
                    files={"file": (IMAGE_PATH, f, "image/png")}
                )
            upload_data = log("Image upload", res, 200)
            if res.status_code == 200:
                mock_img_url   = upload_data.get("url", mock_img_url)
                mock_public_id = upload_data.get("public_id", mock_public_id)
        except Exception as e:
            print(f"       Image upload skipped: {e}")

    # ── 8. Post CRUD ───────────────────────────────────────────────────────────
    print("\n=== POSTS ===")

    post_payload = {
        "image_url":      mock_img_url,
        "image_public_id": mock_public_id,
        "caption":        "Terrible mess in the park.",
        "latitude":       40.7128,
        "longitude":      -74.0060
    }

    res = requests.post(f"{BASE_URL}/posts/", headers=u1_headers, json=post_payload)
    post_data = log("Create post", res, 201)
    post_id = post_data.get("id") if res.status_code in [200, 201] else None

    if post_id:
        res = requests.patch(f"{BASE_URL}/posts/{post_id}", headers=u1_headers, json={
            "caption": "Updated: please clean this mess."
        })
        log("Update post caption", res, 200)

    res = requests.get(f"{BASE_URL}/posts/", headers=u1_headers)
    log("Get post feed", res, 200)

    # ── 9. Volunteer workflow ──────────────────────────────────────────────────
    print("\n=== VOLUNTEER WORKFLOW ===")

    if post_id:
        res = requests.post(f"{BASE_URL}/posts/{post_id}/start_work", headers=u2_headers, json={
            "start_image_url": mock_img_url
        })
        log("Volunteer clock in", res, 200)

        res = requests.post(f"{BASE_URL}/posts/{post_id}/submit_proof", headers=u2_headers, json={
            "end_image_url": mock_img_url
        })
        log("Volunteer submit proof", res, 200)

        res = requests.post(f"{BASE_URL}/posts/{post_id}/approve", headers=u1_headers, json={
            "final_points": 15
        })
        log("Author approve work", res, 200)

    # ── 10. Comments ───────────────────────────────────────────────────────────
    print("\n=== COMMENTS ===")

    comment_id = None
    if post_id:
        res = requests.post(f"{BASE_URL}/comments/?post_id={post_id}", headers=u1_headers, json={
            "content": "Looks much better now."
        })
        comment_data = log("Create comment", res, 200)
        comment_id = comment_data.get("id") if res.status_code in [200, 201] else None

        res = requests.get(f"{BASE_URL}/comments/?post_id={post_id}", headers=u2_headers)
        log("Get comments", res, 200)

        if comment_id:
            res = requests.delete(f"{BASE_URL}/comments/{comment_id}", headers=u1_headers)
            log("Delete comment", res, 204)

    # ── 11. Post deletion ──────────────────────────────────────────────────────
    print("\n=== POST DELETION ===")

    res = requests.post(f"{BASE_URL}/posts/", headers=u1_headers, json=post_payload)
    temp_post = res.json() if res.status_code in [200, 201] else {}
    temp_post_id = temp_post.get("id")
    if temp_post_id:
        res = requests.delete(f"{BASE_URL}/posts/{temp_post_id}", headers=u1_headers)
        log("Delete temp post", res, 204)

    # ── 12. Admin endpoints ────────────────────────────────────────────────────
    print("\n=== ADMIN ===")

    res = requests.get(
        f"{BASE_URL}/admin/users/search?username={users[1]['username']}",
        headers=admin_headers
    )
    log("Admin search user by username", res, 200)

    res = requests.post(f"{BASE_URL}/admin/promote/{u2_uuid}", headers=admin_headers)
    log("Admin promote user 2", res, 200)

    res = requests.post(f"{BASE_URL}/admin/ban/{u3_uuid}", headers=admin_headers, json={
        "ban": True,
        "reason": "Spam account"
    })
    log("Admin ban user 3", res, 200)

    res = requests.delete(f"{BASE_URL}/admin/remove/{u3_uuid}", headers=admin_headers)
    log("Admin remove user 3", res, 200)

    # ── 13. Logout ─────────────────────────────────────────────────────────────
    print("\n=== LOGOUT ===")

    res = requests.post(f"{BASE_URL}/auth/logout", json={"refresh_token": u1_auth["refresh_token"]})
    log("User 1 logout", res, 200)

    # ── 14. Cleanup ────────────────────────────────────────────────────────────
    print("\n=== CLEANUP ===")

    res = requests.delete(f"{BASE_URL}/users/delete/{u1_uuid}", headers=u1_headers)
    log("Delete user 1", res, 200)

    res = requests.delete(f"{BASE_URL}/users/delete/{u2_uuid}", headers=u2_headers)
    log("Delete user 2", res, 200)

    print("\n\nALL TESTS COMPLETED")


if __name__ == "__main__":
    main()