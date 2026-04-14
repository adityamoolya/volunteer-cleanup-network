import sqlite3

conn = sqlite3.connect('auth.db')
cursor = conn.cursor()

# Delete the sample/test rewards
cursor.execute("DELETE FROM rewards WHERE name = '10% Coffee Shop Discount'")
cursor.execute("DELETE FROM rewards WHERE name = 'Free Movie Ticket'")
conn.commit()

# Show remaining
rows = cursor.execute("SELECT id, name, cost_in_points, stock, image_url FROM rewards").fetchall()
for r in rows:
    print(r)
print(f"\nRemaining: {len(rows)} rewards")
conn.close()
