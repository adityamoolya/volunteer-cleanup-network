import requests
import json

base_url = 'http://127.0.0.1:8080'

# Register
resp = requests.post(f'{base_url}/auth/register', json={'email':'admin_test@test.com','username':'admin_test','password':'password123'})
print('Register:', resp.status_code, resp.text)

# Login
resp = requests.post(f'{base_url}/auth/login', json={'email':'admin_test@test.com','password':'password123'})
print('Login:', resp.status_code, resp.text)
if resp.status_code == 200:
    token = resp.json()['access_token']
    
    # Get Me via auth
    headers = {'Authorization': f'Bearer {token}'}
    resp = requests.get(f'{base_url}/auth/me', headers=headers)
    print('Auth Me:', resp.status_code, resp.text)
    
    # Get Me via users
    resp = requests.get(f'{base_url}/users/me', headers=headers)
    print('Users Me:', resp.status_code, resp.text)
    
    user_id = resp.json()['id']
    
    # Delete Self
    resp = requests.delete(f'{base_url}/users/delete/{user_id}', headers=headers)
    print('Delete:', resp.status_code, resp.text)
