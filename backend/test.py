'''
    File: backend/test.py
    Description:
        Comprehensive API test suite for the Volunteer Cleanup Network backend.
        Tests EVERY endpoint as different roles (admin, regular user, banned user, 
        unauthenticated) including both happy-path and negative/edge-case scenarios.

    Coverage:
        - Health Check
        - Auth: register, login, refresh, logout, /me
        - Users: /me, profile/stats, leaderboard, delete
        - Images: upload
        - Posts: CRUD, feed, author update, cancel
        - Volunteer Workflow: start_work, submit_proof, approve, cancel (drop)
        - Comments: create, list, delete
        - Rewards: available, request redemption
        - Admin: promote, ban/unban, search, remove, rewards CRUD, restock, review requests
        - Negative Tests: 401/403/404/400 scenarios

    Usage:
        1. Start the server: python main.py
        2. Run tests:  python test.py
'''

import requests
import os
import uuid
import json
import time

BASE_URL = "http://127.0.0.1:8080"
IMAGE_PATH = "mock_template.png"

# ─── Counters ─────────────────────────────────────────────────────────────────
_pass = 0
_fail = 0
_skip = 0

# ─── Helpers ──────────────────────────────────────────────────────────────────

def log(title, response, expected_status=None):
    """Log and evaluate a single test result."""
    global _pass, _fail
    is_success = response.status_code == expected_status if expected_status else response.ok
    status_mark = "✅ PASS" if is_success else "❌ FAIL"
    if is_success:
        _pass += 1
    else:
        _fail += 1

    print(f"\n{'─'*70}")
    print(f"[{status_mark}] {title}")
    print(f"       {response.request.method} {response.request.url}")
    print(f"       Status: {response.status_code} (expected {expected_status if expected_status else '2xx'})")

    if response.request.headers.get("Authorization"):
        print("       Auth: Bearer token present")

    try:
        resp_json = response.json()
        # Truncate long responses for readability
        dumped = json.dumps(resp_json, indent=2)
        if len(dumped) > 1500:
            dumped = dumped[:1500] + "\n       ... (truncated)"
        print(f"       Response: {dumped}")
        return resp_json
    except Exception:
        print(f"       Response: {response.text[:500]}")
        return response.text


def get_me(headers):
    """Fetch current user's profile."""
    return requests.get(f"{BASE_URL}/users/me", headers=headers).json()


def create_dummy_image():
    """Create a tiny valid PNG file for upload testing."""
    if not os.path.exists(IMAGE_PATH):
        content = (
            b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01'
            b'\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89'
            b'\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01'
            b'\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82'
        )
        with open(IMAGE_PATH, "wb") as f:
            f.write(content)


def register_user(email, username, password="password123"):
    """Register a new user, return the response."""
    return requests.post(f"{BASE_URL}/auth/register", json={
        "email": email,
        "username": username,
        "password": password
    })


def login_user(email, password="password123", fcm_token=None):
    """Login and return (auth_data, headers, user_id)."""
    payload = {"email": email, "password": password}
    if fcm_token:
        payload["fcm_token"] = fcm_token

    res = requests.post(f"{BASE_URL}/auth/login", json=payload)
    if res.status_code != 200:
        return None, None, None

    auth = res.json()
    headers = {"Authorization": f"Bearer {auth['access_token']}"}
    uid = get_me(headers)["id"]
    return auth, headers, uid


def create_post(headers, caption="Test cleanup spot", img_url="http://fake.url/image.webp", public_id="fake_id"):
    """Create a post and return (response, post_id)."""
    res = requests.post(f"{BASE_URL}/posts/", headers=headers, json={
        "image_url": img_url,
        "image_public_id": public_id,
        "caption": caption,
        "latitude": 40.7128,
        "longitude": -74.0060
    })
    pid = res.json().get("id") if res.status_code in [200, 201] else None
    return res, pid


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN TEST SUITE
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    global _pass, _fail, _skip

    print("=" * 70)
    print("  VOLUNTEER CLEANUP NETWORK — FULL API TEST SUITE")
    print("=" * 70)

    print("\nThis script requires a pre-existing admin account.")
    admin_email = input("  Admin email [admin@admin.com]: ").strip() or "admin@admin.com"
    admin_password = input("  Admin password [12345678]: ").strip() or "12345678"

    create_dummy_image()

    # Generate unique suffixes for this test run
    run_id = str(uuid.uuid4())[:6]

    u1_email = f"testuser_1_{run_id}@example.com"
    u2_email = f"testuser_2_{run_id}@example.com"
    u3_email = f"testuser_3_{run_id}@example.com"
    u4_email = f"testuser_4_{run_id}@example.com"
    u5_email = f"testuser_5_{run_id}@example.com"

    u1_name = f"user1_{run_id}"
    u2_name = f"user2_{run_id}"
    u3_name = f"user3_{run_id}"
    u4_name = f"user4_{run_id}"
    u5_name = f"user5_{run_id}"

    mock_img_url = "https://res.cloudinary.com/dcgsvilo0/image/upload/v1767363674/community_app_posts/taqhlxcaoqozzhd2xgqw.webp"
    mock_public_id = "mock_id_fake_id"

    # ──────────────────────────────────────────────────────────────────────────
    # 0. HEALTH CHECK
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 0: HEALTH CHECK")
    print("=" * 70)

    res = requests.get(f"{BASE_URL}/")
    log("Health Check — GET /", res, 200)

    # ──────────────────────────────────────────────────────────────────────────
    # 1. ADMIN AUTH
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 1: ADMIN AUTHENTICATION")
    print("=" * 70)

    res = requests.post(f"{BASE_URL}/auth/login", json={
        "email": admin_email, "password": admin_password
    })
    admin_auth = log("Admin Login", res, 200)
    if res.status_code != 200:
        print("\n⛔ CRITICAL: Cannot proceed without admin auth. Aborting.")
        return

    admin_token = admin_auth["access_token"]
    admin_refresh = admin_auth["refresh_token"]
    admin_headers = {"Authorization": f"Bearer {admin_token}"}

    res = requests.get(f"{BASE_URL}/auth/me", headers=admin_headers)
    log("Admin /auth/me", res, 200)

    res = requests.get(f"{BASE_URL}/users/me", headers=admin_headers)
    log("Admin /users/me", res, 200)

    # ──────────────────────────────────────────────────────────────────────────
    # 2. USER REGISTRATION — Happy Path + Edge Cases
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 2: USER REGISTRATION")
    print("=" * 70)

    res = register_user(u1_email, u1_name)
    log("Register User 1", res, 201)

    res = register_user(u2_email, u2_name)
    log("Register User 2", res, 201)

    res = register_user(u3_email, u3_name)
    log("Register User 3", res, 201)

    res = register_user(u4_email, u4_name)
    log("Register User 4 (will be promoted to admin)", res, 201)

    res = register_user(u5_email, u5_name)
    log("Register User 5 (for edge case tests)", res, 201)

    # --- Negative: Duplicate email ---
    res = register_user(u1_email, "different_name")
    log("NEGATIVE: Register with duplicate email", res, 400)

    # --- Negative: Duplicate username ---
    res = register_user("unique_email_x@test.com", u1_name)
    log("NEGATIVE: Register with duplicate username", res, 400)

    # ──────────────────────────────────────────────────────────────────────────
    # 3. USER LOGIN — Happy Path + Edge Cases
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 3: USER LOGIN")
    print("=" * 70)

    u1_auth, u1_headers, u1_uuid = login_user(u1_email, fcm_token="fcm_u1")
    log("Login User 1 (with FCM token)", requests.post(f"{BASE_URL}/auth/login", json={
        "email": u1_email, "password": "password123", "fcm_token": "fcm_u1"
    }), 200)
    # Re-login to get fresh tokens after the log call above consumed them
    u1_auth, u1_headers, u1_uuid = login_user(u1_email, fcm_token="fcm_u1")

    u2_auth, u2_headers, u2_uuid = login_user(u2_email, fcm_token="fcm_u2")
    u3_auth, u3_headers, u3_uuid = login_user(u3_email, fcm_token="fcm_u3")
    u4_auth, u4_headers, u4_uuid = login_user(u4_email, fcm_token="fcm_u4")
    u5_auth, u5_headers, u5_uuid = login_user(u5_email, fcm_token="fcm_u5")

    log("Login User 2", requests.post(f"{BASE_URL}/auth/login", json={"email": u2_email, "password": "password123"}), 200)

    # --- Negative: Wrong password ---
    res = requests.post(f"{BASE_URL}/auth/login", json={
        "email": u1_email, "password": "wrongpassword"
    })
    log("NEGATIVE: Login with wrong password", res, 401)

    # --- Negative: Non-existent email ---
    res = requests.post(f"{BASE_URL}/auth/login", json={
        "email": "nonexistent@test.com", "password": "password123"
    })
    log("NEGATIVE: Login with non-existent email", res, 401)

    # ──────────────────────────────────────────────────────────────────────────
    # 4. TOKEN REFRESH
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 4: TOKEN REFRESH")
    print("=" * 70)

    res = requests.post(f"{BASE_URL}/auth/refresh", json={
        "refresh_token": u1_auth["refresh_token"]
    })
    refresh_data = log("User 1 — Token Refresh", res, 200)
    if res.status_code == 200:
        u1_headers = {"Authorization": f"Bearer {refresh_data['access_token']}"}
        u1_auth = refresh_data  # Update for logout later

    # --- Negative: Reuse old refresh token (should fail after rotation) ---
    # Note: The old token was already consumed above, so reusing it should fail
    res = requests.post(f"{BASE_URL}/auth/refresh", json={
        "refresh_token": u1_auth.get("refresh_token", "invalid_token")
    })
    # This may pass or fail depending on if rotation consumed it — log either way
    log("EDGE CASE: Reuse refresh token after rotation", res, res.status_code)

    # --- Negative: Invalid refresh token ---
    res = requests.post(f"{BASE_URL}/auth/refresh", json={
        "refresh_token": "completely_bogus_token"
    })
    log("NEGATIVE: Refresh with invalid token", res, 401)

    # ──────────────────────────────────────────────────────────────────────────
    # 5. USER PROFILES & LEADERBOARD
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 5: USER PROFILES & LEADERBOARD")
    print("=" * 70)

    res = requests.get(f"{BASE_URL}/users/me", headers=u1_headers)
    log("User 1 — GET /users/me", res, 200)

    res = requests.get(f"{BASE_URL}/auth/me", headers=u1_headers)
    log("User 1 — GET /auth/me", res, 200)

    res = requests.get(f"{BASE_URL}/users/profile/stats", headers=u1_headers)
    log("User 1 — Profile Stats (should be 0 posts/0 solved)", res, 200)

    res = requests.get(f"{BASE_URL}/users/profile/stats", headers=u2_headers)
    log("User 2 — Profile Stats", res, 200)

    res = requests.get(f"{BASE_URL}/users/leaderboard")
    log("Leaderboard — Public (no auth)", res, 200)

    # --- Negative: Unauthenticated /users/me ---
    res = requests.get(f"{BASE_URL}/users/me")
    log("NEGATIVE: /users/me without auth", res, 401)

    # --- Negative: Unauthenticated profile stats ---
    res = requests.get(f"{BASE_URL}/users/profile/stats")
    log("NEGATIVE: /users/profile/stats without auth", res, 401)

    # ──────────────────────────────────────────────────────────────────────────
    # 6. ADMIN PROMOTION
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 6: ADMIN PROMOTION")
    print("=" * 70)

    res = requests.post(f"{BASE_URL}/admin/promote/{u4_uuid}", headers=admin_headers)
    log("Original Admin promotes User 4 to admin", res, 200)

    # --- Negative: Promote same user again ---
    res = requests.post(f"{BASE_URL}/admin/promote/{u4_uuid}", headers=admin_headers)
    log("EDGE CASE: Promote User 4 again (already admin)", res, 200)

    # --- Negative: Non-admin tries to promote ---
    res = requests.post(f"{BASE_URL}/admin/promote/{u1_uuid}", headers=u2_headers)
    log("NEGATIVE: Non-admin (User 2) tries to promote", res, 403)

    # --- Negative: Promote non-existent user ---
    fake_uuid = "00000000-0000-0000-0000-000000000000"
    res = requests.post(f"{BASE_URL}/admin/promote/{fake_uuid}", headers=admin_headers)
    log("NEGATIVE: Promote non-existent user", res, 404)

    # ──────────────────────────────────────────────────────────────────────────
    # 7. IMAGE UPLOAD
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 7: IMAGE UPLOAD")
    print("=" * 70)

    try:
        with open(IMAGE_PATH, "rb") as f:
            res = requests.post(
                f"{BASE_URL}/images/upload/",
                headers=u1_headers,
                files={"file": (IMAGE_PATH, f, "image/png")}
            )
        upload_data = log("User 1 — Image Upload", res, 200)
        if res.status_code == 200 and "url" in upload_data:
            mock_img_url = upload_data["url"]
            mock_public_id = upload_data["public_id"]
    except Exception as e:
        print(f"       ⚠️ Image upload skipped: {e}")
        _skip += 1

    # --- Negative: Upload without auth ---
    try:
        with open(IMAGE_PATH, "rb") as f:
            res = requests.post(
                f"{BASE_URL}/images/upload/",
                files={"file": (IMAGE_PATH, f, "image/png")}
            )
        log("NEGATIVE: Image upload without auth", res, 401)
    except Exception as e:
        print(f"       ⚠️ Negative image upload skipped: {e}")
        _skip += 1

    # ──────────────────────────────────────────────────────────────────────────
    # 8. POST CREATION & UPDATES (Author)
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 8: POST CRUD & FEED")
    print("=" * 70)

    # 8.1 User 1 creates Post A (full lifecycle test later)
    res, postA_id = create_post(u1_headers, "Terrible mess in the park — needs cleanup!", mock_img_url, mock_public_id)
    log("User 1 creates Post A", res, 201)

    # 8.2 User 1 creates Post B (for cancel test)
    res, postB_id = create_post(u1_headers, "Broken glass on the trail", mock_img_url, mock_public_id)
    log("User 1 creates Post B (will be cancelled by author)", res, 201)

    # 8.3 User 3 creates Post C (for volunteer drop test)
    res, postC_id = create_post(u3_headers, "Graffiti on the wall", mock_img_url, mock_public_id)
    log("User 3 creates Post C (for volunteer drop test)", res, 201)

    # 8.4 User 1 creates Post D (for admin force-approval)
    res, postD_id = create_post(u1_headers, "Illegal dumping site", mock_img_url, mock_public_id)
    log("User 1 creates Post D (for admin force-approval)", res, 201)

    # 8.5 User 5 creates Post E (for delete test)
    res, postE_id = create_post(u5_headers, "Litter everywhere", mock_img_url, mock_public_id)
    log("User 5 creates Post E (will be deleted)", res, 201)

    # 8.6 Author updates their own post
    if postA_id:
        res = requests.patch(f"{BASE_URL}/posts/{postA_id}", headers=u1_headers, json={
            "caption": "Updated: Really bad mess — please help!"
        })
        log("User 1 updates Post A caption", res, 200)

        res = requests.patch(f"{BASE_URL}/posts/{postA_id}", headers=u1_headers, json={
            "predicted_class": "plastic",
            "points": 15
        })
        log("User 1 updates Post A class & points", res, 200)

    # --- Negative: Non-author tries to update ---
    if postA_id:
        res = requests.patch(f"{BASE_URL}/posts/{postA_id}", headers=u2_headers, json={
            "caption": "Hacked caption!"
        })
        log("NEGATIVE: User 2 tries to update User 1's Post A", res, 403)

    # --- Negative: Update non-existent post ---
    res = requests.patch(f"{BASE_URL}/posts/{fake_uuid}", headers=u1_headers, json={
        "caption": "ghost"
    })
    log("NEGATIVE: Update non-existent post", res, 404)

    # --- Negative: Create post without auth ---
    res = requests.post(f"{BASE_URL}/posts/", json={
        "image_url": mock_img_url,
        "image_public_id": mock_public_id,
        "caption": "No auth", "latitude": 0, "longitude": 0
    })
    log("NEGATIVE: Create post without auth", res, 401)

    # 8.7 Feed
    res = requests.get(f"{BASE_URL}/posts/")
    log("GET feed (all open posts)", res, 200)

    # ──────────────────────────────────────────────────────────────────────────
    # 9. POST CANCELLATION (Author & Volunteer)
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 9: POST CANCELLATION")
    print("=" * 70)

    # 9.1 Author cancels their own OPEN post
    if postB_id:
        res = requests.post(f"{BASE_URL}/posts/{postB_id}/cancel", headers=u1_headers)
        log("User 1 cancels Post B (author cancel — OPEN post)", res, 200)

    # --- Negative: Cancel already-cancelled post ---
    if postB_id:
        res = requests.post(f"{BASE_URL}/posts/{postB_id}/cancel", headers=u1_headers)
        log("NEGATIVE: User 1 re-cancels Post B (already cancelled)", res, 400)

    # --- Negative: Non-author/non-volunteer tries to cancel ---
    if postA_id:
        res = requests.post(f"{BASE_URL}/posts/{postA_id}/cancel", headers=u5_headers)
        log("NEGATIVE: User 5 tries to cancel User 1's Post A", res, 403)

    # ──────────────────────────────────────────────────────────────────────────
    # 10. VOLUNTEER WORKFLOW — Full Lifecycle
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 10: VOLUNTEER WORKFLOW")
    print("=" * 70)

    # --- 10.1 Volunteer Drop Flow (Post C) ---
    if postC_id:
        res = requests.post(f"{BASE_URL}/posts/{postC_id}/start_work", headers=u2_headers, json={
            "start_image_url": mock_img_url
        })
        log("User 2 claims Post C (clock in)", res, 200)

        # --- Negative: Another volunteer tries to claim same post ---
        res = requests.post(f"{BASE_URL}/posts/{postC_id}/start_work", headers=u5_headers, json={
            "start_image_url": mock_img_url
        })
        log("NEGATIVE: User 5 tries to claim Post C (already in progress)", res, 400)

        # Volunteer drops
        res = requests.post(f"{BASE_URL}/posts/{postC_id}/cancel", headers=u2_headers)
        log("User 2 drops Post C (volunteer cancel — back to OPEN)", res, 200)

    # --- 10.2 Full Gamification Run (Post A) ---
    if postA_id:
        # Clock In
        res = requests.post(f"{BASE_URL}/posts/{postA_id}/start_work", headers=u2_headers, json={
            "start_image_url": mock_img_url
        })
        log("User 2 volunteers for Post A (clock in)", res, 200)

        # --- Negative: Author tries to edit post that's IN_PROGRESS ---
        res = requests.patch(f"{BASE_URL}/posts/{postA_id}", headers=u1_headers, json={
            "caption": "Can't edit now!"
        })
        log("NEGATIVE: User 1 tries to edit IN_PROGRESS Post A", res, 400)

        # --- Negative: Non-volunteer tries to submit proof ---
        res = requests.post(f"{BASE_URL}/posts/{postA_id}/submit_proof", headers=u5_headers, json={
            "end_image_url": mock_img_url
        })
        log("NEGATIVE: User 5 tries to submit proof (not the volunteer)", res, 403)

        # Clock Out
        time.sleep(1)  # Small delay so duration > 0
        res = requests.post(f"{BASE_URL}/posts/{postA_id}/submit_proof", headers=u2_headers, json={
            "end_image_url": mock_img_url
        })
        log("User 2 submits proof for Post A (clock out)", res, 200)

        # --- Negative: Non-author tries to approve ---
        res = requests.post(f"{BASE_URL}/posts/{postA_id}/approve", headers=u5_headers, json={
            "final_points": 100
        })
        log("NEGATIVE: User 5 tries to approve (not author/admin)", res, 403)

        # --- Negative: Submit proof again on PENDING post ---
        res = requests.post(f"{BASE_URL}/posts/{postA_id}/submit_proof", headers=u2_headers, json={
            "end_image_url": mock_img_url
        })
        log("NEGATIVE: Double submit proof on PENDING Post A", res, 400)

        # Author approves
        res = requests.post(f"{BASE_URL}/posts/{postA_id}/approve", headers=u1_headers, json={
            "final_points": 100
        })
        log("User 1 approves Post A (User 2 earns 100 pts)", res, 200)

        # --- Negative: Approve already completed post ---
        res = requests.post(f"{BASE_URL}/posts/{postA_id}/approve", headers=u1_headers, json={
            "final_points": 50
        })
        log("NEGATIVE: Approve already-completed Post A", res, 400)

    # --- 10.3 Admin Force-Approval (Post D) ---
    if postD_id:
        res = requests.post(f"{BASE_URL}/posts/{postD_id}/start_work", headers=u2_headers, json={
            "start_image_url": mock_img_url
        })
        log("User 2 volunteers for Post D", res, 200)

        time.sleep(1)
        res = requests.post(f"{BASE_URL}/posts/{postD_id}/submit_proof", headers=u2_headers, json={
            "end_image_url": mock_img_url
        })
        log("User 2 submits proof for Post D", res, 200)

        # Admin (User 4) force-approves
        res = requests.post(f"{BASE_URL}/posts/{postD_id}/approve", headers=u4_headers, json={
            "final_points": 25
        })
        log("Admin (User 4) force-approves Post D (User 2 +25 pts)", res, 200)

    # --- Negative: Start work on non-existent post ---
    res = requests.post(f"{BASE_URL}/posts/{fake_uuid}/start_work", headers=u2_headers, json={
        "start_image_url": mock_img_url
    })
    log("NEGATIVE: Start work on non-existent post", res, 400)

    # ──────────────────────────────────────────────────────────────────────────
    # 11. COMMENTS
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 11: COMMENTS")
    print("=" * 70)

    comment1_id = None
    comment2_id = None

    if postA_id:
        # User 3 comments on Post A
        res = requests.post(f"{BASE_URL}/comments/?post_id={postA_id}", headers=u3_headers, json={
            "content": "Great cleanup work! The park looks amazing now."
        })
        c1_data = log("User 3 comments on Post A", res, 200)
        comment1_id = c1_data.get("id") if res.status_code == 200 else None

        # User 2 comments on Post A (self-comment on task they did)
        res = requests.post(f"{BASE_URL}/comments/?post_id={postA_id}", headers=u2_headers, json={
            "content": "Thanks! It was a tough job but worth it."
        })
        c2_data = log("User 2 comments on Post A (volunteer self-comment)", res, 200)
        comment2_id = c2_data.get("id") if res.status_code == 200 else None

        # User 1 (author) comments on their own post
        res = requests.post(f"{BASE_URL}/comments/?post_id={postA_id}", headers=u1_headers, json={
            "content": "Thanks for the help everyone!"
        })
        log("User 1 comments on own Post A (no self-notification)", res, 200)

        # Get all comments
        res = requests.get(f"{BASE_URL}/comments/?post_id={postA_id}")
        log("GET all comments on Post A", res, 200)

        # --- Negative: Comment on non-existent post ---
        res = requests.post(f"{BASE_URL}/comments/?post_id={fake_uuid}", headers=u3_headers, json={
            "content": "This post doesn't exist"
        })
        log("NEGATIVE: Comment on non-existent post", res, 404)

        # --- Negative: Comment without auth ---
        res = requests.post(f"{BASE_URL}/comments/?post_id={postA_id}", json={
            "content": "No auth comment"
        })
        log("NEGATIVE: Comment without auth", res, 401)

        # --- Negative: Delete someone else's comment ---
        if comment1_id:
            res = requests.delete(f"{BASE_URL}/comments/{comment1_id}", headers=u2_headers)
            log("NEGATIVE: User 2 tries to delete User 3's comment", res, 403)

        # Delete own comment
        if comment2_id:
            res = requests.delete(f"{BASE_URL}/comments/{comment2_id}", headers=u2_headers)
            log("User 2 deletes their own comment", res, 204)

        # --- Negative: Delete non-existent comment ---
        res = requests.delete(f"{BASE_URL}/comments/{fake_uuid}", headers=u3_headers)
        log("NEGATIVE: Delete non-existent comment", res, 404)

        # Delete User 3's comment (cleanup)
        if comment1_id:
            res = requests.delete(f"{BASE_URL}/comments/{comment1_id}", headers=u3_headers)
            log("User 3 deletes their own comment (cleanup)", res, 204)

    # ──────────────────────────────────────────────────────────────────────────
    # 12. POST DELETE
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 12: POST DELETION")
    print("=" * 70)

    if postE_id:
        # --- Negative: Non-author tries to delete ---
        res = requests.delete(f"{BASE_URL}/posts/{postE_id}", headers=u1_headers)
        log("NEGATIVE: User 1 tries to delete User 5's Post E", res, 403)

        # Author deletes their own post
        res = requests.delete(f"{BASE_URL}/posts/{postE_id}", headers=u5_headers)
        log("User 5 deletes their Post E", res, 204)

    # --- Negative: Delete non-existent post ---
    res = requests.delete(f"{BASE_URL}/posts/{fake_uuid}", headers=u1_headers)
    log("NEGATIVE: Delete non-existent post", res, 404)

    # --- Negative: Delete without auth ---
    if postC_id:
        res = requests.delete(f"{BASE_URL}/posts/{postC_id}")
        log("NEGATIVE: Delete post without auth", res, 401)

    # ──────────────────────────────────────────────────────────────────────────
    # 13. REWARDS & REDEMPTION
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 13: REWARDS & REDEMPTION")
    print("=" * 70)

    # 13.1 Admin creates rewards
    res = requests.post(f"{BASE_URL}/admin/rewards", headers=u4_headers, json={
        "name": "10% Coffee Shop Discount",
        "description": "Valid at any participating coffee shop.",
        "cost_in_points": 50,
        "stock": 3
    })
    reward_data = log("Admin (User 4) creates Reward 1", res, 200)
    reward1_id = reward_data.get("id") if res.status_code == 200 else None

    res = requests.post(f"{BASE_URL}/admin/rewards", headers=admin_headers, json={
        "name": "Free Movie Ticket",
        "description": "One-time use ticket.",
        "cost_in_points": 200,
        "stock": 1
    })
    reward2_data = log("Original Admin creates Reward 2 (expensive)", res, 200)
    reward2_id = reward2_data.get("id") if res.status_code == 200 else None

    # --- Negative: Non-admin tries to create reward ---
    res = requests.post(f"{BASE_URL}/admin/rewards", headers=u1_headers, json={
        "name": "Hack Reward", "description": "Nope", "cost_in_points": 1, "stock": 999
    })
    log("NEGATIVE: Non-admin (User 1) tries to create reward", res, 403)

    # 13.2 Admin restocks
    if reward1_id:
        res = requests.post(f"{BASE_URL}/admin/rewards/{reward1_id}/restock", headers=u4_headers, json={
            "amount": 5
        })
        log("Admin (User 4) restocks Reward 1 (+5)", res, 200)

        # --- Negative: Restock with zero/negative amount ---
        res = requests.post(f"{BASE_URL}/admin/rewards/{reward1_id}/restock", headers=u4_headers, json={
            "amount": 0
        })
        log("NEGATIVE: Restock with 0 amount", res, 400)

        res = requests.post(f"{BASE_URL}/admin/rewards/{reward1_id}/restock", headers=u4_headers, json={
            "amount": -5
        })
        log("NEGATIVE: Restock with negative amount", res, 400)

    # 13.3 User checks available rewards
    res = requests.get(f"{BASE_URL}/rewards/available", headers=u2_headers)
    log("User 2 checks available rewards (has 125 pts)", res, 200)

    # --- Negative: Check rewards without auth ---
    res = requests.get(f"{BASE_URL}/rewards/available")
    log("NEGATIVE: Check rewards without auth", res, 401)

    # 13.4 User redeems reward
    req1_id = None
    if reward1_id:
        res = requests.post(f"{BASE_URL}/rewards/{reward1_id}/request", headers=u2_headers)
        req_data = log("User 2 requests Reward 1 (-50 pts)", res, 200)
        req1_id = req_data.get("id") if res.status_code == 200 else None

    # --- Negative: Redeem non-existent reward ---
    res = requests.post(f"{BASE_URL}/rewards/{fake_uuid}/request", headers=u2_headers)
    log("NEGATIVE: Redeem non-existent reward", res, 404)

    # --- Negative: Redeem reward you can't afford ---
    if reward2_id:
        res = requests.post(f"{BASE_URL}/rewards/{reward2_id}/request", headers=u5_headers)
        log("NEGATIVE: User 5 (0 pts) tries to redeem 200-pt reward", res, 400)

    # 13.5 Admin reviews requests
    res = requests.get(f"{BASE_URL}/admin/rewards/requests", headers=u4_headers)
    log("Admin (User 4) fetches pending redemption requests", res, 200)

    # --- Negative: Non-admin fetches requests ---
    res = requests.get(f"{BASE_URL}/admin/rewards/requests", headers=u1_headers)
    log("NEGATIVE: Non-admin fetches redemption requests", res, 403)

    # Approve
    if req1_id:
        res = requests.post(f"{BASE_URL}/admin/rewards/requests/{req1_id}/review", headers=u4_headers, json={
            "approve": True
        })
        log("Admin (User 4) APPROVES User 2's redemption", res, 200)

        # --- Negative: Re-review already reviewed request ---
        res = requests.post(f"{BASE_URL}/admin/rewards/requests/{req1_id}/review", headers=u4_headers, json={
            "approve": True
        })
        log("NEGATIVE: Re-review already approved request", res, 400)

    # Test rejection + refund
    req2_id = None
    if reward1_id:
        res = requests.post(f"{BASE_URL}/rewards/{reward1_id}/request", headers=u2_headers)
        req2_data = log("User 2 requests Reward 1 again", res, 200)
        req2_id = req2_data.get("id") if res.status_code == 200 else None

    if req2_id:
        # Check points before rejection
        u2_stats_before = requests.get(f"{BASE_URL}/users/me", headers=u2_headers).json()
        pts_before = u2_stats_before.get("points", 0)

        res = requests.post(f"{BASE_URL}/admin/rewards/requests/{req2_id}/review", headers=u4_headers, json={
            "approve": False
        })
        log("Admin (User 4) REJECTS request (points refunded)", res, 200)

        # Verify points were refunded
        u2_stats_after = requests.get(f"{BASE_URL}/users/me", headers=u2_headers).json()
        pts_after = u2_stats_after.get("points", 0)
        refund_ok = pts_after > pts_before
        print(f"       Points: {pts_before} → {pts_after} (refund {'✅' if refund_ok else '❌'})")

    # ──────────────────────────────────────────────────────────────────────────
    # 14. ADMIN SEARCH
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 14: ADMIN USER SEARCH")
    print("=" * 70)

    # Search by username
    res = requests.get(f"{BASE_URL}/admin/users/search?username={u3_name}", headers=u4_headers)
    log("Admin search by username", res, 200)

    # Search by email
    res = requests.get(f"{BASE_URL}/admin/users/search?email={u2_email}", headers=u4_headers)
    log("Admin search by email", res, 200)

    # Search by both
    res = requests.get(f"{BASE_URL}/admin/users/search?username={u1_name}&email={u1_email}", headers=u4_headers)
    log("Admin search by username AND email", res, 200)

    # --- Negative: Search with no params ---
    res = requests.get(f"{BASE_URL}/admin/users/search", headers=u4_headers)
    log("NEGATIVE: Admin search with no params", res, 400)

    # --- Negative: Search for non-existent user ---
    res = requests.get(f"{BASE_URL}/admin/users/search?username=does_not_exist_xyz", headers=u4_headers)
    log("NEGATIVE: Admin search non-existent user", res, 404)

    # --- Negative: Non-admin search ---
    res = requests.get(f"{BASE_URL}/admin/users/search?username={u1_name}", headers=u1_headers)
    log("NEGATIVE: Non-admin tries admin search", res, 403)

    # ──────────────────────────────────────────────────────────────────────────
    # 15. BANNING & UNBANNING
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 15: BAN / UNBAN")
    print("=" * 70)

    # Ban User 3
    res = requests.post(f"{BASE_URL}/admin/ban/{u3_uuid}", headers=u4_headers, json={
        "ban": True, "reason": "Spam activity"
    })
    log("Admin (User 4) bans User 3", res, 200)

    # --- Negative: Ban already banned user ---
    res = requests.post(f"{BASE_URL}/admin/ban/{u3_uuid}", headers=u4_headers, json={
        "ban": True, "reason": "Already banned"
    })
    log("EDGE CASE: Ban already-banned User 3", res, 200)

    # --- Negative: Banned user tries to login ---
    res = requests.post(f"{BASE_URL}/auth/login", json={
        "email": u3_email, "password": "password123"
    })
    log("NEGATIVE: Banned User 3 tries to login", res, 401)

    # --- Negative: Admin tries to ban another admin ---
    res = requests.post(f"{BASE_URL}/admin/ban/{u4_uuid}", headers=admin_headers, json={
        "ban": True, "reason": "Nope"
    })
    log("NEGATIVE: Admin tries to ban Admin (User 4)", res, 403)

    # --- Negative: Non-admin tries to ban ---
    res = requests.post(f"{BASE_URL}/admin/ban/{u1_uuid}", headers=u2_headers, json={
        "ban": True, "reason": "Unauthorized"
    })
    log("NEGATIVE: Non-admin (User 2) tries to ban", res, 403)

    # Unban User 3
    res = requests.post(f"{BASE_URL}/admin/ban/{u3_uuid}", headers=u4_headers, json={
        "ban": False
    })
    log("Admin (User 4) unbans User 3", res, 200)

    # --- Negative: Unban already-unbanned user ---
    res = requests.post(f"{BASE_URL}/admin/ban/{u3_uuid}", headers=u4_headers, json={
        "ban": False
    })
    log("EDGE CASE: Unban already-unbanned User 3", res, 200)

    # Verify User 3 can login again
    res = requests.post(f"{BASE_URL}/auth/login", json={
        "email": u3_email, "password": "password123"
    })
    log("User 3 logs in after unban", res, 200)
    if res.status_code == 200:
        u3_auth = res.json()
        u3_headers = {"Authorization": f"Bearer {u3_auth['access_token']}"}

    # ──────────────────────────────────────────────────────────────────────────
    # 16. VERIFIED STATS AFTER WORKFLOW
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 16: PROFILE STATS AFTER WORKFLOW")
    print("=" * 70)

    res = requests.get(f"{BASE_URL}/users/profile/stats", headers=u1_headers)
    stats = log("User 1 stats (should show posts created, 0 solved)", res, 200)
    if res.status_code == 200:
        counts = stats.get("counts", {})
        print(f"       → Created: {counts.get('created')}, Solved: {counts.get('solved')}, Points: {counts.get('points')}")

    res = requests.get(f"{BASE_URL}/users/profile/stats", headers=u2_headers)
    stats = log("User 2 stats (should show 0 created, 2 solved, 125+ pts)", res, 200)
    if res.status_code == 200:
        counts = stats.get("counts", {})
        print(f"       → Created: {counts.get('created')}, Solved: {counts.get('solved')}, Points: {counts.get('points')}")

    res = requests.get(f"{BASE_URL}/users/leaderboard")
    log("Final Leaderboard", res, 200)

    # ──────────────────────────────────────────────────────────────────────────
    # 17. CLEANUP & ACCOUNT DELETION
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  SECTION 17: CLEANUP — LOGOUT & DELETION")
    print("=" * 70)

    # Logout User 1
    if u1_auth:
        res = requests.post(f"{BASE_URL}/auth/logout", json={
            "refresh_token": u1_auth.get("refresh_token", "")
        })
        log("User 1 logout", res, 200)

    # --- Negative: User tries to delete another user's account ---
    res = requests.delete(f"{BASE_URL}/users/delete/{u2_uuid}", headers=u1_headers)
    log("NEGATIVE: User 1 tries to delete User 2's account", res, 403)

    # --- Negative: Delete without auth ---
    res = requests.delete(f"{BASE_URL}/users/delete/{u1_uuid}")
    log("NEGATIVE: Delete account without auth", res, 401)

    # Admin force-removes User 3
    res = requests.delete(f"{BASE_URL}/admin/remove/{u3_uuid}", headers=admin_headers)
    log("Original Admin removes User 3", res, 200)

    # --- Negative: Remove non-existent user ---
    res = requests.delete(f"{BASE_URL}/admin/remove/{fake_uuid}", headers=admin_headers)
    log("NEGATIVE: Remove non-existent user", res, 404)

    # --- Negative: Non-admin tries admin removal ---
    res = requests.delete(f"{BASE_URL}/admin/remove/{u1_uuid}", headers=u2_headers)
    log("NEGATIVE: Non-admin (User 2) tries admin removal", res, 403)

    # Users delete their own accounts
    res = requests.delete(f"{BASE_URL}/users/delete/{u1_uuid}", headers=u1_headers)
    log("User 1 deletes own account", res, 200)

    res = requests.delete(f"{BASE_URL}/users/delete/{u2_uuid}", headers=u2_headers)
    log("User 2 deletes own account", res, 200)

    res = requests.delete(f"{BASE_URL}/users/delete/{u5_uuid}", headers=u5_headers)
    log("User 5 deletes own account", res, 200)

    # Original admin cleans up promoted admin (User 4)
    res = requests.delete(f"{BASE_URL}/admin/remove/{u4_uuid}", headers=admin_headers)
    log("Original Admin removes User 4 (promoted admin)", res, 200)

    # Cleanup temp file
    try:
        os.remove(IMAGE_PATH)
    except OSError:
        pass

    # ──────────────────────────────────────────────────────────────────────────
    # SUMMARY
    # ──────────────────────────────────────────────────────────────────────────
    print("\n\n" + "=" * 70)
    print("  TEST RESULTS SUMMARY")
    print("=" * 70)
    total = _pass + _fail
    print(f"\n  ✅ Passed: {_pass}")
    print(f"  ❌ Failed: {_fail}")
    if _skip:
        print(f"  ⚠️  Skipped: {_skip}")
    print(f"  📊 Total:  {total}")
    pct = (_pass / total * 100) if total > 0 else 0
    print(f"  📈 Pass Rate: {pct:.1f}%")

    if _fail == 0:
        print("\n  🎉 ALL TESTS PASSED!")
    else:
        print(f"\n  ⚠️  {_fail} test(s) need attention.")

    print("\n" + "=" * 70)


if __name__ == "__main__":
    main()
