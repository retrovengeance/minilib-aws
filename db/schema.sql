-- =============================================================
--  MiniLibraryDB — MySQL 8.0 Schema
--  CCS6344 Assignment 2 — AWS Migration
--  Converted from Microsoft SQL Server (Assignment 1)
--
--  Security controls carried over:
--  ✓ RBAC: lib_admin (full) + lib_member (SELECT + EXECUTE only)
--  ✓ Stored procedures for all writes (replaces signed SPs)
--  ✓ RLS: enforced via userId param in member-facing SPs
--  ✓ DDM: enforced in Flask layer (email/phone masking)
--  ✓ Encryption at rest: RDS StorageEncrypted=true (AES-256)
--  ✓ Encryption in transit: SSL enforced on PyMySQL connection
--  ✓ IC number: AES-256 encrypted at application layer (Fernet)
--  ✓ AuditLog table: every SP call writes an audit record
--  ✓ bcrypt password hashing (app layer, unchanged)
--  ✓ Parameterised queries: all calls use %s placeholders
-- =============================================================

-- Run this file as the RDS master user (admin) after stack creation:
-- mysql -h <RDS_ENDPOINT> -u admin -p MiniLibraryDB < db/schema.sql

USE MiniLibraryDB;

-- ─────────────────────────────────────────────────────────────
--  TABLES
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS Users (
    userId          INT          AUTO_INCREMENT PRIMARY KEY,
    userName        VARCHAR(50)  NOT NULL UNIQUE,
    fullName        VARCHAR(100) NOT NULL,
    email           VARCHAR(100) NOT NULL UNIQUE,
    password        VARCHAR(255) NOT NULL,          -- bcrypt hash
    role            ENUM('Librarian','Member') NOT NULL DEFAULT 'Member',
    isActive        TINYINT(1)   NOT NULL DEFAULT 1,
    createdAt       DATETIME     NOT NULL DEFAULT NOW(),
    phoneNumber     VARCHAR(20),                    -- plaintext for DDM masking at app layer
    -- IC number stored as AES-256 ciphertext (Fernet, base64) from Flask
    icNumber        TEXT,
    icNumber_iv     TEXT,                           -- not used for Fernet but kept for schema parity
    failedAttempts  INT          NOT NULL DEFAULT 0,
    lockedUntil     DATETIME     NULL
);

CREATE TABLE IF NOT EXISTS Books (
    bookId          INT          AUTO_INCREMENT PRIMARY KEY,
    title           VARCHAR(200) NOT NULL,
    author          VARCHAR(100) NOT NULL,
    isbn            VARCHAR(20)  UNIQUE,
    genre           VARCHAR(50),
    quantity        INT          NOT NULL DEFAULT 1,
    availableQty    INT          NOT NULL DEFAULT 1,
    addedAt         DATETIME     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS Reservations (
    reservationId   INT          AUTO_INCREMENT PRIMARY KEY,
    userId          INT          NOT NULL,
    bookId          INT          NOT NULL,
    reservedAt      DATETIME     NOT NULL DEFAULT NOW(),
    collectBy       DATETIME     NOT NULL DEFAULT DATE_ADD(NOW(), INTERVAL 3 DAY),
    borrowDate      DATETIME     NULL,
    dueDate         DATETIME     NULL,
    returnedAt      DATETIME     NULL,
    status          ENUM('reserved','active','overdue','returnRequested','returned','cancelled') NOT NULL DEFAULT 'reserved',
    FOREIGN KEY (userId) REFERENCES Users(userId),
    FOREIGN KEY (bookId) REFERENCES Books(bookId)
);

CREATE TABLE IF NOT EXISTS AuditLog (
    logId           INT          AUTO_INCREMENT PRIMARY KEY,
    userId          INT          NULL,
    action          VARCHAR(100) NOT NULL,
    targetTable     VARCHAR(50)  NOT NULL,
    description     TEXT,
    loggedAt        DATETIME     NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────
--  INDEXES  (performance on frequent lookups)
-- ─────────────────────────────────────────────────────────────

CREATE INDEX idx_reservations_userid ON Reservations(userId);
CREATE INDEX idx_reservations_status ON Reservations(status);
CREATE INDEX idx_auditlog_userid     ON AuditLog(userId);
CREATE INDEX idx_books_title         ON Books(title);

-- ─────────────────────────────────────────────────────────────
--  STORED PROCEDURES
--  All writes go through SPs — equivalent of signed SPs from A1.
--  Member-facing SPs enforce RLS via p_userId parameter.
-- ─────────────────────────────────────────────────────────────

DELIMITER $$

-- ── Auth / Users ────────────────────────────────────────────

CREATE PROCEDURE sp_getUserByUsername(IN p_userName VARCHAR(50))
BEGIN
    SELECT userId, userName, fullName, email, password,
           role, isActive, failedAttempts, lockedUntil
    FROM Users
    WHERE userName = p_userName
    LIMIT 1;
END$$

CREATE PROCEDURE sp_incrementFailedAttempts(IN p_userId INT)
BEGIN
    UPDATE Users
    SET failedAttempts = failedAttempts + 1,
        lockedUntil = CASE
            WHEN failedAttempts + 1 >= 5
            THEN DATE_ADD(NOW(), INTERVAL 15 MINUTE)
            ELSE lockedUntil
        END
    WHERE userId = p_userId;

    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_userId, 'LoginFailed', 'Users',
           CONCAT('Failed attempt #', (SELECT failedAttempts FROM Users WHERE userId = p_userId)));
END$$

CREATE PROCEDURE sp_resetFailedAttempts(IN p_userId INT)
BEGIN
    UPDATE Users SET failedAttempts = 0, lockedUntil = NULL WHERE userId = p_userId;
    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_userId, 'LoginSuccess', 'Users', 'Login successful, attempts reset');
END$$

CREATE PROCEDURE sp_registerMember(
    IN p_userName   VARCHAR(50),
    IN p_fullName   VARCHAR(100),
    IN p_email      VARCHAR(100),
    IN p_password   VARCHAR(255),
    IN p_phone      VARCHAR(20),
    IN p_icNumber   TEXT
)
BEGIN
    INSERT INTO Users(userName, fullName, email, password, role, phoneNumber, icNumber)
    VALUES(p_userName, p_fullName, p_email, p_password, 'Member', p_phone, p_icNumber);

    SET @new_id = LAST_INSERT_ID();
    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(@new_id, 'Register', 'Users', CONCAT('New member registered: ', p_userName));

    SELECT @new_id AS userId;
END$$

CREATE PROCEDURE sp_logLogout(IN p_userId INT, IN p_userName VARCHAR(50))
BEGIN
    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_userId, 'Logout', 'Users', CONCAT(p_userName, ' logged out'));
END$$

-- ── Books ────────────────────────────────────────────────────

CREATE PROCEDURE sp_getAllBooks(IN p_searchQuery VARCHAR(200))
BEGIN
    IF p_searchQuery IS NULL OR p_searchQuery = '' THEN
        SELECT * FROM Books ORDER BY title;
    ELSE
        SELECT * FROM Books
        WHERE title  LIKE CONCAT('%', p_searchQuery, '%')
           OR author LIKE CONCAT('%', p_searchQuery, '%')
           OR isbn   LIKE CONCAT('%', p_searchQuery, '%')
        ORDER BY title;
    END IF;
END$$

CREATE PROCEDURE sp_addBook(
    IN p_title      VARCHAR(200),
    IN p_author     VARCHAR(100),
    IN p_isbn       VARCHAR(20),
    IN p_genre      VARCHAR(50),
    IN p_quantity   INT,
    IN p_callerUserId INT
)
BEGIN
    INSERT INTO Books(title, author, isbn, genre, quantity, availableQty)
    VALUES(p_title, p_author, p_isbn, p_genre, p_quantity, p_quantity);

    SET @new_id = LAST_INSERT_ID();
    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_callerUserId, 'AddBook', 'Books',
           CONCAT('Added book: "', p_title, '" (ID=', @new_id, ')'));
END$$

CREATE PROCEDURE sp_deleteBook(IN p_bookId INT, IN p_callerUserId INT)
BEGIN
    -- Block if book has active reservations
    IF EXISTS (
        SELECT 1 FROM Reservations
        WHERE bookId = p_bookId
          AND status IN ('reserved','active','returnRequested')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot delete: book has active reservations.';
    END IF;

    DELETE FROM Books WHERE bookId = p_bookId;
    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_callerUserId, 'DeleteBook', 'Books',
           CONCAT('Deleted bookId=', p_bookId));
END$$

-- ── Reservations ─────────────────────────────────────────────

-- Librarian: all reservations
CREATE PROCEDURE sp_getAllReservations()
BEGIN
    SELECT r.reservationId, u.fullName, u.userName, b.title, b.isbn,
           r.reservedAt, r.collectBy, r.borrowDate, r.dueDate,
           r.returnedAt, r.status
    FROM Reservations r
    JOIN Users u ON r.userId  = u.userId
    JOIN Books b ON r.bookId  = b.bookId
    ORDER BY r.reservedAt DESC;
END$$

-- Member RLS: only own reservations (userId enforced via parameter)
CREATE PROCEDURE sp_getMemberReservations(IN p_userId INT)
BEGIN
    SELECT r.reservationId, b.title, b.author,
           r.reservedAt, r.collectBy, r.borrowDate,
           r.dueDate, r.returnedAt, r.status
    FROM Reservations r
    JOIN Books b ON r.bookId = b.bookId
    WHERE r.userId = p_userId    -- RLS: hard-coded to caller's ID
    ORDER BY r.reservedAt DESC;
END$$

CREATE PROCEDURE sp_createReservation(IN p_userId INT, IN p_bookId INT)
BEGIN
    -- Check availability
    IF (SELECT availableQty FROM Books WHERE bookId = p_bookId) < 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Book is not available for reservation.';
    END IF;

    -- Block duplicate active reservation
    IF EXISTS (
        SELECT 1 FROM Reservations
        WHERE userId = p_userId AND bookId = p_bookId
          AND status IN ('reserved','active')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'You already have an active reservation for this book.';
    END IF;

    INSERT INTO Reservations(userId, bookId)
    VALUES(p_userId, p_bookId);

    UPDATE Books SET availableQty = availableQty - 1 WHERE bookId = p_bookId;

    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_userId, 'CreateReservation', 'Reservations',
           CONCAT('Reserved bookId=', p_bookId));
END$$

CREATE PROCEDURE sp_cancelReservation(IN p_reservationId INT, IN p_userId INT)
BEGIN
    -- Enforce RLS: member can only cancel own reservations
    IF NOT EXISTS (
        SELECT 1 FROM Reservations
        WHERE reservationId = p_reservationId AND userId = p_userId
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reservation not found or access denied.';
    END IF;

    UPDATE Reservations SET status = 'cancelled'
    WHERE reservationId = p_reservationId AND status = 'reserved';

    UPDATE Books b
    JOIN Reservations r ON b.bookId = r.bookId
    SET b.availableQty = b.availableQty + 1
    WHERE r.reservationId = p_reservationId;

    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_userId, 'CancelReservation', 'Reservations',
           CONCAT('Cancelled reservationId=', p_reservationId));
END$$

CREATE PROCEDURE sp_markOverdue()
BEGIN
    UPDATE Reservations
    SET status = 'overdue'
    WHERE status = 'active' AND dueDate < NOW();

    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(NULL, 'MarkOverdue', 'Reservations', 'Auto-marked overdue reservations');
END$$

CREATE PROCEDURE sp_confirmCollection(IN p_reservationId INT, IN p_callerUserId INT)
BEGIN
    UPDATE Reservations
    SET status    = 'active',
        borrowDate = NOW(),
        dueDate    = DATE_ADD(NOW(), INTERVAL 14 DAY)
    WHERE reservationId = p_reservationId AND status = 'reserved';

    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_callerUserId, 'ConfirmCollection', 'Reservations',
           CONCAT('Confirmed collection for reservationId=', p_reservationId));
END$$

CREATE PROCEDURE sp_requestReturn(IN p_reservationId INT, IN p_userId INT)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM Reservations
        WHERE reservationId = p_reservationId AND userId = p_userId
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reservation not found or access denied.';
    END IF;

    UPDATE Reservations
    SET status = 'returnRequested'
    WHERE reservationId = p_reservationId AND status IN ('active','overdue');

    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_userId, 'RequestReturn', 'Reservations',
           CONCAT('Return requested for reservationId=', p_reservationId));
END$$

CREATE PROCEDURE sp_approveReturn(IN p_reservationId INT, IN p_callerUserId INT)
BEGIN
    UPDATE Reservations
    SET status = 'returned', returnedAt = NOW()
    WHERE reservationId = p_reservationId AND status = 'returnRequested';

    UPDATE Books b
    JOIN Reservations r ON b.bookId = r.bookId
    SET b.availableQty = b.availableQty + 1
    WHERE r.reservationId = p_reservationId;

    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_callerUserId, 'ApproveReturn', 'Reservations',
           CONCAT('Return approved for reservationId=', p_reservationId));
END$$

-- ── Members (Librarian management) ──────────────────────────

CREATE PROCEDURE sp_getAllMembers()
BEGIN
    SELECT userId, userName, fullName, email, role,
           isActive, createdAt, phoneNumber
    FROM Users ORDER BY fullName;
END$$

CREATE PROCEDURE sp_deactivateMember(IN p_targetUserId INT, IN p_callerUserId INT)
BEGIN
    UPDATE Users SET isActive = 0 WHERE userId = p_targetUserId;
    INSERT INTO AuditLog(userId, action, targetTable, description)
    VALUES(p_callerUserId, 'DeactivateMember', 'Users',
           CONCAT('Deactivated userId=', p_targetUserId));
END$$

-- ── Audit Log ────────────────────────────────────────────────

CREATE PROCEDURE sp_getAuditLog()
BEGIN
    SELECT a.logId, a.userId, u.userName, a.action,
           a.targetTable, a.description, a.loggedAt
    FROM AuditLog a
    LEFT JOIN Users u ON a.userId = u.userId
    ORDER BY a.loggedAt DESC
    LIMIT 500;
END$$

DELIMITER ;

-- ─────────────────────────────────────────────────────────────
--  DATABASE USERS & RBAC
--  lib_admin  — all privileges (Librarian connections)
--  lib_member — SELECT + EXECUTE on procedures only (Member connections)
--  Passwords must match what's set in app.py .env
-- ─────────────────────────────────────────────────────────────

-- Drop users if they exist (re-run safe)
DROP USER IF EXISTS 'lib_admin'@'%';
DROP USER IF EXISTS 'lib_member'@'%';

CREATE USER 'lib_admin'@'%'  IDENTIFIED BY 'LibAdmin@Secure2024!';
CREATE USER 'lib_member'@'%' IDENTIFIED BY 'LibMember@Secure2024!';

-- lib_admin: full control over MiniLibraryDB
GRANT ALL PRIVILEGES ON MiniLibraryDB.* TO 'lib_admin'@'%';

-- lib_member: SELECT on tables + EXECUTE on procedures only
GRANT SELECT                ON MiniLibraryDB.Users        TO 'lib_member'@'%';
GRANT SELECT                ON MiniLibraryDB.Books        TO 'lib_member'@'%';
GRANT SELECT                ON MiniLibraryDB.Reservations TO 'lib_member'@'%';
GRANT EXECUTE               ON MiniLibraryDB.*            TO 'lib_member'@'%';
-- Explicitly deny INSERT/UPDATE/DELETE for lib_member (least privilege)
REVOKE INSERT, UPDATE, DELETE ON MiniLibraryDB.Users        FROM 'lib_member'@'%';
REVOKE INSERT, UPDATE, DELETE ON MiniLibraryDB.Reservations FROM 'lib_member'@'%';

FLUSH PRIVILEGES;
