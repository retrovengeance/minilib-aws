"""
CCS6344 — MiniLibrary Flask Backend (v4 — Route-Corrected)
All route names and parameter names match the Assignment 1 templates exactly.

Routes mapped from template url_for() calls:
  login, logout, register, dashboard
  list_books, add_book, delete_book(book_id)
  place_reservation(book_id)
  my_reservations
  all_reservations[?status=...]
  cancel_reservation(res_id)
  request_return(res_id)
  approve_return(res_id)
  collect_reservation(res_id)
  mark_overdue
  list_members, add_member, toggle_member(member_id), delete_member(member_id)
  audit_log
  health
"""

import os
import re
import base64
import datetime as dt
from functools import wraps

import bcrypt
import pymysql
import pymysql.cursors
from cryptography.fernet import Fernet
from flask import (Flask, render_template, request,
                   redirect, url_for, session, flash, jsonify)
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

# ─────────────────────────────────────────────
#  App & rate limiter
# ─────────────────────────────────────────────
app = Flask(__name__)
app.secret_key = os.environ.get('FLASK_SECRET_KEY', 'fallback-insecure-key-change-me')

limiter = Limiter(
    get_remote_address,
    app=app,
    default_limits=["200 per hour", "50 per minute"],
    storage_uri="memory://",
)

# ─────────────────────────────────────────────
#  IC Number Encryption (Fernet AES-128)
# ─────────────────────────────────────────────
_IC_KEY_RAW = os.environ.get('IC_ENCRYPTION_KEY', '')

def _get_fernet():
    try:
        key = base64.urlsafe_b64encode(_IC_KEY_RAW[:32].encode().ljust(32, b'0'))
        return Fernet(key)
    except Exception:
        return Fernet(Fernet.generate_key())

def encrypt_ic(ic_plaintext):
    if not ic_plaintext:
        return ''
    return _get_fernet().encrypt(ic_plaintext.encode()).decode()

def decrypt_ic(ic_ciphertext):
    if not ic_ciphertext:
        return ''
    try:
        return _get_fernet().decrypt(ic_ciphertext.encode()).decode()
    except Exception:
        return '[decryption error]'

# ─────────────────────────────────────────────
#  DDM (Dynamic Data Masking)
# ─────────────────────────────────────────────
def mask_email(email):
    if not email or '@' not in email:
        return email
    local, domain = email.split('@', 1)
    return local[0] + 'XXX@XXXX.' + domain.rsplit('.', 1)[-1]

def mask_phone(phone):
    if not phone:
        return phone
    digits = re.sub(r'\D', '', phone)
    return 'XXX-XXXX-' + digits[-3:]

# ─────────────────────────────────────────────
#  Database connections
# ─────────────────────────────────────────────
DB_HOST = os.environ.get('DB_HOST', '127.0.0.1')
DB_PORT = int(os.environ.get('DB_PORT', '3306'))
DB_NAME = os.environ.get('DB_NAME', 'MiniLibraryDB')

_CREDS = {
    'Librarian': {
        'user':     'lib_admin',
        'password': 'LibAdminSecure2026!',
    },
    'Member': {
        'user':     'lib_member',
        'password': 'LibMemberSecure2026!',
    },
}

def get_db(role=None):
    r = role or session.get('role', 'Member')
    creds = _CREDS.get(r, _CREDS['Member'])
    return pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=creds['user'],
        password=creds['password'],
        ssl={'ssl': {}},
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        connect_timeout=10,
    )

def normalize(rows):
    """
    Lowercase all dict keys so templates can use r.reservationid,
    r.userid, r.bookid etc regardless of MySQL column casing.
    """
    if rows is None:
        return []
    result = []
    for row in rows:
        new_row = {}
        for k, v in row.items():
            if isinstance(v, (dt.datetime, dt.date)):
                new_row[k.lower()] = str(v)
            else:
                new_row[k.lower()] = v
        result.append(new_row)
    return result

def remap_statuses(rows):
    """
    Remap DB internal status 'reserved' to 'pending' for template display.
    Templates use 'pending' to mean 'reserved but not yet collected'.
    """
    for r in rows:
        if r.get('status') == 'reserved':
            r['status'] = 'pending'
    return rows

def callproc(cursor, proc_name, args=()):
    cursor.callproc(proc_name, args)
    rows = cursor.fetchall()
    if not rows:
        try:
            cursor.nextset()
            rows = cursor.fetchall() or []
        except Exception:
            pass
    return normalize(rows)

# ─────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────
def friendly_error(exc):
    msg = str(exc)
    match = re.search(r"'(.+)'", msg)
    if match:
        return match.group(1)
    return 'A database error occurred. Please try again.'

def hash_password(plaintext):
    return bcrypt.hashpw(plaintext.encode(), bcrypt.gensalt()).decode()

def check_password(plaintext, hashed):
    try:
        return bcrypt.checkpw(plaintext.encode(), hashed.encode())
    except Exception:
        return False

# ─────────────────────────────────────────────
#  Decorators
# ─────────────────────────────────────────────
def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if 'user' not in session:
            flash("Please log in to continue.", "error")
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return wrapper

def librarian_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if session.get('role') != 'Librarian':
            flash("Access denied — Librarians only.", "error")
            return redirect(url_for('dashboard'))
        return f(*args, **kwargs)
    return wrapper

# ─────────────────────────────────────────────
#  Health check
# ─────────────────────────────────────────────
@app.route('/health')
def health():
    return jsonify({'status': 'ok'}), 200

# ─────────────────────────────────────────────
#  AUTH
# ─────────────────────────────────────────────
@app.route('/', methods=['GET', 'POST'])
@limiter.limit("20 per minute")
def login():
    if 'user' in session:
        return redirect(url_for('dashboard'))
    if request.method == 'GET':
        return render_template('login.html')

    username = request.form.get('username', '').strip()
    password = request.form.get('password', '')

    if not username or not password:
        flash("Username and password are required.", "error")
        return render_template('login.html')

    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            rows = callproc(cur, 'sp_getUserByUsername', (username,))
            conn.commit()

        if not rows:
            flash("Invalid username or password.", "error")
            return render_template('login.html')

        user = rows[0]

        import datetime
        if user.get('lockeduntil') and user['lockeduntil'] > datetime.datetime.now():
            flash("Account locked. Try again in 15 minutes.", "error")
            return render_template('login.html')

        if not user.get('isactive'):
            flash("Account is deactivated. Contact the librarian.", "error")
            return render_template('login.html')

        if not check_password(password, user['password']):
            with conn.cursor() as cur:
                callproc(cur, 'sp_incrementFailedAttempts', (user['userid'],))
                conn.commit()
            flash("Invalid username or password.", "error")
            return render_template('login.html')

        with conn.cursor() as cur:
            callproc(cur, 'sp_resetFailedAttempts', (user['userid'],))
            conn.commit()

        session.clear()
        session['userId']   = user['userid']
        session['user']     = user['username']
        session['role']     = user['role']
        session['name']     = user['fullname']
        return redirect(url_for('dashboard'))

    except Exception as e:
        flash(f"Login error: {friendly_error(e)}", "error")
        return render_template('login.html')
    finally:
        conn.close()


@app.route('/logout')
@login_required
def logout():
    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_logLogout', (session['userId'], session['user']))
            conn.commit()
    except Exception:
        pass
    finally:
        conn.close()
    session.clear()
    flash("Logged out successfully.", "success")
    return redirect(url_for('login'))


@app.route('/register', methods=['GET', 'POST'])
@limiter.limit("10 per hour")
def register():
    if request.method == 'GET':
        return render_template('register.html')

    username = request.form.get('username', '').strip()
    fullname = request.form.get('fullName', '').strip()
    email    = request.form.get('email', '').strip()
    password = request.form.get('password', '')
    confirm  = request.form.get('confirm', '')
    phone    = request.form.get('phoneNumber', '').strip()
    ic       = request.form.get('icNumber', '').strip()

    if not all([username, fullname, email, password]):
        flash("All fields except phone and IC are required.", "error")
        return render_template('register.html')
    if len(password) < 6:
        flash("Password must be at least 6 characters.", "error")
        return render_template('register.html')
    if password != confirm and confirm:
        flash("Passwords do not match.", "error")
        return render_template('register.html')
    if not re.match(r'^[\w.-]+@[\w.-]+\.\w+$', email):
        flash("Invalid email format.", "error")
        return render_template('register.html')

    hashed_pw    = hash_password(password)
    encrypted_ic = encrypt_ic(ic) if ic else ''

    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_registerMember',
                     (username, fullname, email, hashed_pw, phone, encrypted_ic))
            conn.commit()
        flash("Registration successful! Please log in.", "success")
        return redirect(url_for('login'))
    except Exception as e:
        flash(f"Registration error: {friendly_error(e)}", "error")
        return render_template('register.html')
    finally:
        conn.close()

# ─────────────────────────────────────────────
#  DASHBOARD
# ─────────────────────────────────────────────
@app.route('/dashboard')
@login_required
def dashboard():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            if session['role'] == 'Librarian':
                callproc(cur, 'sp_markOverdue', ())
                conn.commit()
                rows = callproc(cur, 'sp_getAllReservations', ())
                overdue_count   = sum(1 for r in rows if r['status'] == 'overdue')
                pending_returns = sum(1 for r in rows if r['status'] == 'returnrequested')
            else:
                rows = callproc(cur, 'sp_getMemberReservations', (session['userId'],))
                overdue_count = pending_returns = 0
    except Exception as e:
        flash(f"Error loading dashboard: {friendly_error(e)}", "error")
        rows, overdue_count, pending_returns = [], 0, 0
    finally:
        conn.close()

    rows = remap_statuses(rows)
    return render_template('dashboard.html',
                           reservations=rows,
                           overdue_count=overdue_count,
                           pending_returns=pending_returns)

# ─────────────────────────────────────────────
#  MY RESERVATIONS (Member view — separate page)
# ─────────────────────────────────────────────
@app.route('/my_reservations')
@login_required
def my_reservations():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            rows = callproc(cur, 'sp_getMemberReservations', (session['userId'],))
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
        rows = []
    finally:
        conn.close()
    return render_template('my_reservations.html', reservations=remap_statuses(rows))

# ─────────────────────────────────────────────
#  ALL RESERVATIONS (Librarian view)
# ─────────────────────────────────────────────
@app.route('/all_reservations')
@login_required
@librarian_required
def all_reservations():
    status = request.args.get('status')
    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            rows = callproc(cur, 'sp_getAllReservations', ())
        # Filter BEFORE remapping so we can still match 'reserved'
        if status == 'pending':
            rows = [r for r in rows if r['status'] == 'reserved']
        elif status:
            rows = [r for r in rows if r['status'] == status.lower()]
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
        rows = []
    finally:
        conn.close()
    return render_template('all_reservations.html', reservations=remap_statuses(rows), status_filter=status)

# ─────────────────────────────────────────────
#  BOOKS
# ─────────────────────────────────────────────
@app.route('/books')
@login_required
def list_books():
    q = request.args.get('q', '').strip() or None
    conn = get_db()
    try:
        with conn.cursor() as cur:
            books = callproc(cur, 'sp_getAllBooks', (q,))
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
        books = []
    finally:
        conn.close()
    return render_template('books.html', books=books, query=q or '')


@app.route('/books/add', methods=['GET', 'POST'])
@login_required
@librarian_required
def add_book():
    if request.method == 'GET':
        return render_template('add_book.html')

    title    = request.form.get('title', '').strip()
    author   = request.form.get('author', '').strip()
    isbn     = request.form.get('isbn', '').strip() or None
    genre    = request.form.get('genre', '').strip() or None
    quantity = request.form.get('quantity', '1')

    if not title or not author:
        flash("Title and author are required.", "error")
        return render_template('add_book.html')
    try:
        quantity = int(quantity)
        if quantity < 1:
            raise ValueError
    except ValueError:
        flash("Quantity must be a positive integer.", "error")
        return render_template('add_book.html')

    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_addBook',
                     (title, author, isbn, genre, quantity, session['userId']))
            conn.commit()
        flash(f'Book "{title}" added successfully.', "success")
        return redirect(url_for('list_books'))
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
        return render_template('add_book.html')
    finally:
        conn.close()


@app.route('/books/delete/<int:book_id>', methods=['POST'])
@login_required
@librarian_required
def delete_book(book_id):
    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_deleteBook', (book_id, session['userId']))
            conn.commit()
        flash("Book deleted.", "success")
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
    finally:
        conn.close()
    return redirect(url_for('list_books'))

# ─────────────────────────────────────────────
#  RESERVATIONS
# ─────────────────────────────────────────────
@app.route('/place_reservation/<int:book_id>', methods=['POST'])
@login_required
def place_reservation(book_id):
    if session['role'] != 'Member':
        flash("Only members can place reservations.", "error")
        return redirect(url_for('list_books'))
    conn = get_db('Member')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_createReservation', (session['userId'], book_id))
            conn.commit()
        flash("Reservation placed successfully.", "success")
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
    finally:
        conn.close()
    return redirect(url_for('my_reservations'))


# Alias — dashboard form JS overrides action to /reserve/<id>
@app.route('/reserve/<int:book_id>', methods=['POST'])
@login_required
def reserve_book(book_id):
    return place_reservation(book_id)


@app.route('/cancel/<int:res_id>', methods=['POST'])
@login_required
def cancel_reservation(res_id):
    conn = get_db('Member')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_cancelReservation', (res_id, session['userId']))
            conn.commit()
        flash("Reservation cancelled.", "success")
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
    finally:
        conn.close()
    return redirect(url_for('my_reservations'))


@app.route('/return/request/<int:res_id>', methods=['POST'])
@login_required
def request_return(res_id):
    conn = get_db('Member')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_requestReturn', (res_id, session['userId']))
            conn.commit()
        flash("Return requested.", "success")
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
    finally:
        conn.close()
    return redirect(url_for('my_reservations'))


@app.route('/return/approve/<int:res_id>', methods=['POST'])
@login_required
@librarian_required
def approve_return(res_id):
    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_approveReturn', (res_id, session['userId']))
            conn.commit()
        flash("Return approved.", "success")
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
    finally:
        conn.close()
    return redirect(url_for('all_reservations'))


@app.route('/collect_reservation/<int:res_id>', methods=['POST'])
@login_required
@librarian_required
def collect_reservation(res_id):
    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_confirmCollection', (res_id, session['userId']))
            conn.commit()
        flash("Collection confirmed.", "success")
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
    finally:
        conn.close()
    return redirect(url_for('all_reservations'))


@app.route('/mark_overdue', methods=['POST'])
@login_required
@librarian_required
def mark_overdue():
    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_markOverdue', ())
            conn.commit()
        flash("Overdue reservations updated.", "success")
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
    finally:
        conn.close()
    return redirect(url_for('all_reservations'))

# ─────────────────────────────────────────────
#  MEMBERS
# ─────────────────────────────────────────────
@app.route('/members')
@login_required
@librarian_required
def list_members():
    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            members = callproc(cur, 'sp_getAllMembers', ())
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
        members = []
    finally:
        conn.close()
    return render_template('members.html', members=members)


@app.route('/members/toggle/<int:member_id>', methods=['POST'])
@login_required
@librarian_required
def toggle_member(member_id):
    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            callproc(cur, 'sp_deactivateMember', (member_id, session['userId']))
            conn.commit()
        flash("Member status updated.", "success")
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
    finally:
        conn.close()
    return redirect(url_for('list_members'))


@app.route('/members/delete/<int:member_id>', methods=['POST'])
@login_required
@librarian_required
def delete_member(member_id):
    # Reuse deactivate for now — templates may call this for soft-delete
    return redirect(url_for('toggle_member', member_id=member_id))


@app.route('/members/add', methods=['GET', 'POST'])
@login_required
@librarian_required
def add_member():
    # Redirect to register page — librarian can also register members
    return redirect(url_for('register'))

# ─────────────────────────────────────────────
#  AUDIT LOG
# ─────────────────────────────────────────────
@app.route('/audit')
@login_required
@librarian_required
def audit_log():
    conn = get_db('Librarian')
    try:
        with conn.cursor() as cur:
            logs = callproc(cur, 'sp_getAuditLog', ())
    except Exception as e:
        flash(f"Error: {friendly_error(e)}", "error")
        logs = []
    finally:
        conn.close()
    return render_template('audit.html', logs=logs)

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
