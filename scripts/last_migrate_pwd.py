import bcrypt
import pypyodbc as pyodbc

# TODO: change to your own vm ip dont change the port number
conn = pyodbc.connect(
    "DRIVER={SQL Server};SERVER=192.168.0.21,1433;"
    "DATABASE=MiniLibraryDB;UID=lib_admin;PWD=Pa$$w0rd;"
    "TrustServerCertificate=yes;"
)
cursor = conn.cursor()

# Fetch all users with plaintext passwords
cursor.execute("SELECT userId, password FROM LibrarySchema.Users")
users = cursor.fetchall()

for user_id, plaintext in users:
    hashed = bcrypt.hashpw(
        plaintext.encode('utf-8'),
        bcrypt.gensalt()
    ).decode('utf-8')
    
    cursor.execute(
        "UPDATE LibrarySchema.Users SET password = ? WHERE userId = ?",
        (hashed, user_id)
    )
    print(f"Migrated userId {user_id}")

conn.commit()
conn.close()
print("Migration complete.")