# Mini Library Book Reservation System
 
> CCS6344 Database & Cloud Security — Assignment 1

A secure web-based library book reservation system built with **Python Flask** and **Microsoft SQL Server**, demonstrating 15 layered database security measures including RBAC, Row-Level Security, Dynamic Data Masking, Transparent Data Encryption, Always Encrypted, and more.

### Installation
 
```bash
# Clone the repository
git clone <url>
```
```bash
# Create virtual env 
py -m venv .venv
```
```bash
# Activate .venv
.venv\Scripts\activate.bat
```
```bash
# Install requirements
py -m pip install -r requirements.txt
```

### Configuration
 
Update the database connection in `app.py`:
 
```python
_DB_SERVER = '192.168.x.x,1433'   # your VM IP
_DB_NAME   = 'MiniLibraryDB'
```

### Run
 
```bash
py app.py
```
