
'''
    File: backend/test.py
    Description:
        Full API test suite. Covers internal operations including auth, oauth, user management,
        posts, volunteer workflow gamification, comments, images upload, rewards, and admin endpoints.

    Usage:
        python test.py
        Make sure the development server is running locally on port 8080 before executing.
'''

import requests
import os
import uuid
import json

BASE_URL = "http://127.0.0.1:8080"
IMAGE_PATH = "mock_template.png"


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

    try:
        resp_json = response.json()
        print(f"       Response: {json.dumps(resp_json, indent=2)}")
        return resp_json
    except Exception:
        print(f"       Response: {response.text}")
        return response.text


def get_me(headers):
    return requests.get(f"{BASE_URL}/users/me", headers=headers).json()

def create_dummy_image():
    if not os.path.exists(IMAGE_PATH):
        # Creates a 1x1 transparent PNG
        content = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82'
        with open(IMAGE_PATH, "wb") as f:
            f.write(content)

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("STARTING FULL API TEST SUITE\n")
    print("Welcome! To run the full test suite, we need the credentials of an existing admin.")
    
    admin_email = input("Enter admin email [admin@admin.com]: ").strip() or "admin@admin.com"
    admin_password = input("Enter admin password [12345678]: ").strip() or "12345678"

    create_dummy_image()

    # ── 1. Admin Auth ──────────────────────────────────────────────────────────
    print("\n=== 1. ADMIN AUTH ===")

    res = requests.post(f"{BASE_URL}/auth/login", json={
        "email": admin_email,
        "password": admin_password
    })
    
    admin_auth = log("Admin login", res, 200)
    if res.status_code != 200:
        print("\nCRITICAL: Cannot proceed without admin auth. Please check the credentials.")
        return

    admin_token   = admin_auth.get("access_token")
    admin_headers = {"Authorization": f"Bearer {admin_token}"}

    res = requests.get(f"{BASE_URL}/auth/me", headers=admin_headers)
    log("Admin /auth/me", res, 200)

    # ── 2. Register test users ─────────────────────────────────────────────────
    print("\n=== 2. USER REGISTRATION (4 USERS) ===")

    users = []
    for i in range(1, 5):
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
    print("\n=== 3. USER LOGIN ===")

    def login_user(user_data, label):
        res = requests.post(f"{BASE_URL}/auth/login", json={
            "email":     user_data["email"],
            "password":  user_data["password"],
            "fcm_token": f"mock_fcm_token_{label}"
        })
        auth = log(f"Login {label}", res, 200)
        headers = {"Authorization": f"Bearer {auth['access_token']}"}
        uid = get_me(headers)["id"]
        return auth, headers, uid

    u1_auth, u1_headers, u1_uuid = login_user(users[0], "user1")
    u2_auth, u2_headers, u2_uuid = login_user(users[1], "user2")
    u3_auth, u3_headers, u3_uuid = login_user(users[2], "user3")
    u4_auth, u4_headers, u4_uuid = login_user(users[3], "user4")

    # ── 4. Admin Promote & Users Management ────────────────────────────────────
    print("\n=== 4. USER PROMOTION ===")
    
    # 4.1 Promote User 4 to admin
    res = requests.post(f"{BASE_URL}/admin/promote/{u4_uuid}", headers=admin_headers)
    log("Original Admin promotes user 4", res, 200)

    # ── 5. User Profile & Tokens ───────────────────────────────────────────────
    print("\n=== 5. USER PROFILE & TOKENS ===")

    res = requests.post(f"{BASE_URL}/auth/refresh", json={"refresh_token": u1_auth["refresh_token"]})
    refresh_data = log("User 1 block token refresh", res, 200)
    if res.status_code == 200:
        u1_headers = {"Authorization": f"Bearer {refresh_data['access_token']}"}

    res = requests.get(f"{BASE_URL}/users/profile/stats", headers=u1_headers)
    log("User 1 profile stats", res, 200)

    res = requests.get(f"{BASE_URL}/users/leaderboard", headers=u1_headers)
    log("Leaderboard fetch", res, 200)

    # ── 6. Image Upload ────────────────────────────────────────────────────────
    print("\n=== 6. IMAGE UPLOAD ===")

    mock_img_url   = "http://fake.url/image.webp"
    mock_public_id = "fake_id"

    try:
        with open(IMAGE_PATH, "rb") as f:
            res = requests.post(
                f"{BASE_URL}/images/upload/",
                headers=u1_headers,
                files={"file": (IMAGE_PATH, f, "image/png")}
            )
        upload_data = log("Image upload", res, 200)
        if res.status_code == 200 and "url" in upload_data:
            mock_img_url   = upload_data["url"]
            mock_public_id = upload_data["public_id"]
    except Exception as e:
        print(f"       Image upload skipped/failed: {e}")

    # ── 7. Post CRUD & Status Modifications ────────────────────────────────────
    print("\n=== 7. POST CREATION & UPDATES ===")

    post_payload = {
        "image_url":      mock_img_url,
        "image_public_id": mock_public_id,
        "caption":        "Terrible mess in the park.",
        "latitude":       40.7128,
        "longitude":      -74.0060
    }

    # Author is User 1
    res = requests.post(f"{BASE_URL}/posts/", headers=u1_headers, json=post_payload)
    post_data = log("User 1 Creates post 1", res, 201)
    post1_id = post_data.get("id") if res.status_code in [200, 201] else None

    if post1_id:
        res = requests.patch(f"{BASE_URL}/posts/{post1_id}", headers=u1_headers, json={
            "caption": "Updated: please clean this mess. It's really bad!"
        })
        log("User 1 Updates post 1 caption", res, 200)

    # Author is User 3 -> cancels their post
    res = requests.post(f"{BASE_URL}/posts/", headers=u3_headers, json=post_payload)
    post_data3 = log("User 3 Creates post 2 (Will cancel)", res, 201)
    post2_id = post_data3.get("id") if res.status_code in [200, 201] else None

    if post2_id:
        res = requests.post(f"{BASE_URL}/posts/{post2_id}/cancel", headers=u3_headers)
        log("User 3 Cancels post 2", res, 200)

    res = requests.get(f"{BASE_URL}/posts/", headers=u1_headers)
    log("Get generic post feed", res, 200)

    # ── 8. Volunteer Workflow ──────────────────────────────────────────────────
    print("\n=== 8. VOLUNTEER WORKFLOW ===")

    # Setup Post 3 for volunteer dropping task
    res = requests.post(f"{BASE_URL}/posts/", headers=u1_headers, json=post_payload)
    post_data4 = log("User 1 Creates post 3 (For drop testing)", res, 201)
    post3_id = post_data4.get("id") if res.status_code in [200, 201] else None

    if post1_id and post3_id:
        # User 2 claims post 3
        res = requests.post(f"{BASE_URL}/posts/{post3_id}/start_work", headers=u2_headers, json={
            "start_image_url": mock_img_url
        })
        log("User 2 Volunteers (clocks in) on Post 3", res, 200)

        # User 2 drops post 3
        res = requests.post(f"{BASE_URL}/posts/{post3_id}/cancel", headers=u2_headers)
        log("User 2 Drops Post 3", res, 200)

        # Full Gamified run on Post 1
        res = requests.post(f"{BASE_URL}/posts/{post1_id}/start_work", headers=u2_headers, json={
            "start_image_url": mock_img_url
        })
        log("User 2 Volunteers (clocks in) on Post 1", res, 200)

        res = requests.post(f"{BASE_URL}/posts/{post1_id}/submit_proof", headers=u2_headers, json={
            "end_image_url": mock_img_url
        })
        log("User 2 Submits Proof on Post 1", res, 200)

        res = requests.post(f"{BASE_URL}/posts/{post1_id}/approve", headers=u1_headers, json={
            "final_points": 100
        })
        log("User 1 Approves work on Post 1 (User 2 gets 100pts)", res, 200)

        # Admin Force-Approve Test
        res = requests.post(f"{BASE_URL}/posts/", headers=u1_headers, json=post_payload)
        post_data5 = log("User 1 Creates post 4 (For admin approval test)", res, 201)
        post4_id = post_data5.get("id") if res.status_code in [200, 201] else None

        if post4_id:
            requests.post(f"{BASE_URL}/posts/{post4_id}/start_work", headers=u2_headers, json={"start_image_url": mock_img_url})
            requests.post(f"{BASE_URL}/posts/{post4_id}/submit_proof", headers=u2_headers, json={"end_image_url": mock_img_url})
            
            # Admin (User 4) force approves it
            res = requests.post(f"{BASE_URL}/posts/{post4_id}/approve", headers=u4_headers, json={
                "final_points": 25
            })
            log("Admin (User 4) Force-Approves work on Post 4 (User 2 gets 25pts)", res, 200)

    # ── 9. Comments ────────────────────────────────────────────────────────────
    print("\n=== 9. COMMENTS ===")

    comment_id = None
    if post1_id:
        # User 3 comments
        res = requests.post(f"{BASE_URL}/comments/?post_id={post1_id}", headers=u3_headers, json={
            "content": "Wow good job cleaning this!"
        })
        comment_data = log("User 3 Creates comment on post 1", res, 200)
        comment_id = comment_data.get("id") if res.status_code in [200, 201] else None

        res = requests.get(f"{BASE_URL}/comments/?post_id={post1_id}", headers=u2_headers)
        log("User 2 Gets comments on post 1", res, 200)

        if comment_id:
            res = requests.delete(f"{BASE_URL}/comments/{comment_id}", headers=u3_headers)
            log("User 3 Deletes their comment", res, 204)

    # ── 10. Rewards Management ─────────────────────────────────────────────────
    print("\n=== 10. REWARDS & REDEMPTION ===")
    
    # Newly promoted Admin (User 4) adds reward
    res = requests.post(f"{BASE_URL}/admin/rewards", headers=u4_headers, json={
        "name": "10% Coffee Shop Discount",
        "description": "Valid anywhere in town.",
        "cost_in_points": 50,
        "stock": 5
    })
    reward = log("Admin (User 4) Creates a new Reward", res, 200)
    reward_id = reward.get("id") if res.status_code == 200 else None

    if reward_id:
        if reward_id:
            res = requests.post(f"{BASE_URL}/admin/rewards/{reward_id}/restock", headers=u4_headers, json={
                "amount": 5
            })
            log("Admin (User 4) Restocks the reward (+5 coupons)", res, 200)

        res = requests.get(f"{BASE_URL}/rewards/available", headers=u2_headers)
        log("User 2 checks available rewards", res, 200)

        res = requests.post(f"{BASE_URL}/rewards/{reward_id}/request", headers=u2_headers)
        req = log("User 2 Requests the Reward (-50 points)", res, 200)
        req_id = req.get("id") if res.status_code == 200 else None

        res = requests.get(f"{BASE_URL}/admin/rewards/requests", headers=u4_headers)
        log("Admin (User 4) Fetches pending redemption requests", res, 200)

        if req_id:
            res = requests.post(f"{BASE_URL}/admin/rewards/requests/{req_id}/review", headers=u4_headers, json={
                "approve": True
            })
            log("Admin (User 4) Approves request", res, 200)

            # Test Rejection and Refund
            res = requests.post(f"{BASE_URL}/rewards/{reward_id}/request", headers=u2_headers)
            req2 = log("User 2 Requests another Reward", res, 200)
            req2_id = req2.get("id") if res.status_code == 200 else None
            
            if req2_id:
                res = requests.post(f"{BASE_URL}/admin/rewards/requests/{req2_id}/review", headers=u4_headers, json={
                    "approve": False
                })
                log("Admin (User 4) Rejects request (Refund generated)", res, 200)

    # ── 11. Banning and Account Modifications ──────────────────────────────────
    print("\n=== 11. MODERATION (Bans/Deletions) ===")

    res = requests.get(f"{BASE_URL}/admin/users/search?username={users[2]['username']}", headers=u4_headers)
    log("Admin (User 4) searches for User 3", res, 200)

    res = requests.post(f"{BASE_URL}/admin/ban/{u3_uuid}", headers=u4_headers, json={
        "ban": True,
        "reason": "Spam comments"
    })
    log("Admin (User 4) bans User 3", res, 200)

    res = requests.post(f"{BASE_URL}/auth/login", json={
        "email": users[2]["email"],
        "password": "password123"
    })
    log("User 3 Attempts Login (Should fail)", res, 401) # Backend uses 401/403 for banned, test expects it

    res = requests.post(f"{BASE_URL}/admin/ban/{u3_uuid}", headers=u4_headers, json={
        "ban": False,
        "reason": ""
    })
    log("Admin (User 4) unbans User 3", res, 200)

    res = requests.delete(f"{BASE_URL}/admin/remove/{u3_uuid}", headers=u4_headers)
    log("Admin (User 4) forcefully removes User 3", res, 200)

    if post3_id:
        res = requests.delete(f"{BASE_URL}/posts/{post3_id}", headers=u1_headers)
        log("User 1 Deletes their dropped Post 3", res, 204)

    # ── 12. Cleanup & Logout ───────────────────────────────────────────────────
    print("\n=== 12. LOGOUT & CLEANUP ===")

    res = requests.post(f"{BASE_URL}/auth/logout", json={"refresh_token": u1_auth["refresh_token"]})
    log("User 1 token logout", res, 200)

    res = requests.delete(f"{BASE_URL}/users/delete/{u1_uuid}", headers=u1_headers)
    log("User 1 Deletes their own account", res, 200)

    res = requests.delete(f"{BASE_URL}/users/delete/{u2_uuid}", headers=u2_headers)
    log("User 2 Deletes their own account", res, 200)

    # For safety, original admin drops user 4 that we promoted
    res = requests.delete(f"{BASE_URL}/admin/remove/{u4_uuid}", headers=admin_headers)
    log("Original Admin cleans up User 4 (Promoted Admin)", res, 200)

    try:
        os.remove(IMAGE_PATH)
    except OSError:
        pass

    print("\n\nALL TESTS COMPLETED 🎉")

if __name__ == "__main__":
    main()
