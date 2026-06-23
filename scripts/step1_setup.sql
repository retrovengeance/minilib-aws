-- ============================================================
-- CREATE DATABASE
-- ============================================================
USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'MiniLibraryDB')
BEGIN
    ALTER DATABASE MiniLibraryDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MiniLibraryDB;
END
GO

CREATE DATABASE MiniLibraryDB;
GO
USE MiniLibraryDB;
GO

-- ============================================================
-- SCHEMA
-- Security: schema separation (least privilege per schema)
-- ============================================================
USE MiniLibraryDB;
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'LibrarySchema')
    EXEC('CREATE SCHEMA LibrarySchema');
GO

-- ============================================================
-- CREATE TABLES
-- ============================================================
USE MiniLibraryDB;
GO

-- 3a. Users
CREATE TABLE LibrarySchema.Users (
    userId INT IDENTITY(1,1) PRIMARY KEY,
    userName NVARCHAR(100) NOT NULL UNIQUE,
    fullName NVARCHAR(200) NOT NULL,
    icNumber NVARCHAR(20) UNIQUE,
    email NVARCHAR(200) NOT NULL UNIQUE,
    password NVARCHAR(200) NOT NULL,
    phoneNumber NVARCHAR(15),
    role NVARCHAR(20)  NOT NULL DEFAULT 'Member' CHECK (Role IN ('Member','Librarian')),
    isActive BIT NOT NULL DEFAULT 1,
    createdAt DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- 2b. Books
CREATE TABLE LibrarySchema.Books (
    bookId INT IDENTITY(1,1) PRIMARY KEY,
    title NVARCHAR(300) NOT NULL,
    author NVARCHAR(200) NOT NULL,
    isbn NVARCHAR(20) NOT NULL UNIQUE,
    genre NVARCHAR(100) NOT NULL,
    quantity INT NOT NULL DEFAULT 1 CHECK (quantity >= 0),
    availableQty INT NOT NULL DEFAULT 1 CHECK (availableQty >= 0),
    addedAt DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- 2c. Reservations
-- Status flow: pending -> active -> returnRequested -> returned
--                                                   -> overdue
--                      -> cancelled
--                      -> expired
CREATE TABLE LibrarySchema.Reservations (
    reservationId INT IDENTITY(1,1) PRIMARY KEY,
    userId INT NOT NULL CONSTRAINT FK_Reservation_Users REFERENCES LibrarySchema.Users(userId) ON DELETE CASCADE,
    bookId INT NOT NULL CONSTRAINT FK_Reservation_Books REFERENCES LibrarySchema.Books(bookId) ON DELETE CASCADE,
    reservedAt DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    collectBy DATETIME2 NOT NULL DEFAULT DATEADD(day,3,SYSDATETIME()),
    borrowDate DATETIME2 NULL,
    dueDate DATETIME2 NULL DEFAULT DATEADD(day, 14, SYSDATETIME()),
    returnDate DATETIME2 NULL,
    status NVARCHAR(20)  NOT NULL DEFAULT 'pending' 
        CHECK (status IN (
            'pending',          -- reserved, awaiting collection
            'active',           -- collected, currently borrowed  
            'returnRequested',  -- user clicks returning
            'returned',         -- librarian confirmed return
            'overdue',          -- past dueDate, not returned
            'cancelled',        -- user cancelled reservation themselves
            'expired'           -- collectBy passed, reservation expired, not borrowed
        ))
);
GO

-- 2d. AuditLog 
CREATE TABLE LibrarySchema.AuditLog (
    logId INT IDENTITY(1,1) PRIMARY KEY,
    userId INT NULL CONSTRAINT FK_Audit_Users REFERENCES LibrarySchema.Users(userId) ON DELETE SET NULL,
    action NVARCHAR(100) NOT NULL,
    targetTable NVARCHAR(50) NULL,
    description NVARCHAR(500) NULL,
    loggedAt DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- ============================================================
-- INSERT DATA
-- ============================================================
USE MiniLibraryDB;
GO

-- Users
INSERT INTO LibrarySchema.Users 
    (userName, fullName, icNumber, email, password, phoneNumber, role, isActive)
VALUES
    -- Librarian / Admin
    ('admin', 'Sarah Abdullah', '951026-10-7341', 'sarah.admin@minilib.com', 'password123', '016-3234347', 'Librarian', 1),
    -- Members
    ('ali.hassan', 'Ali Hassan', '701202-12-5533', 'ali.hassan@edu.my', 'password123', '012-3456789', 'Member', 1),
    ('nurul.ain', 'Nurul Ain Binti Razak', '020612-05-1123', 'nurul.ain@edu.my', 'password123', '018-2345678', 'Member', 1),
    ('raj.kumar', 'Rajendran Kumar', '880715-14-6624', 'raj.kumar@edu.my', 'password123', '019-9826451', 'Member', 1),
    ('wei.ling', 'Tan Wei Ling', '000101-09-5589', 'wei.ling@edu.my', 'password123', '011-1234567', 'Member', 0);  -- inactive account
GO

-- Books
INSERT INTO LibrarySchema.Books 
    (title, author, isbn, genre, quantity, availableQty)
VALUES
    ('Clean Code', 'Robert C. Martin', '978-0132350884', 'Technology', 5, 3),
    ('The Pragmatic Programmer', 'David Thomas', '978-0135957059', 'Technology', 4, 4),
    ('Introduction to Algorithms', 'Thomas H. Cormen', '978-0262033848', 'Technology', 3, 1),
    ('Database System Concepts', 'Abraham Silberschatz', '978-0078022159', 'Technology', 6, 5),
    ('Thinking Fast and Slow', 'Daniel Kahneman', '978-0374533557', 'Psychology', 4, 4),
    ('Sapiens: A Brief History', 'Yuval Noah Harari', '978-0062316097', 'History', 5, 5),
    ('The Art of War', 'Sun Tzu', '978-1599869773', 'Philosophy', 3, 3),
    ('Rich Dad Poor Dad', 'Robert T. Kiyosaki', '978-1612680194', 'Finance', 4, 2),
    ('Atomic Habits', 'James Clear', '978-0735211292', 'Self-Help', 6, 6),
    ('Network Security Essentials', 'William Stallings', '978-0134527338', 'Technology', 2, 0);  -- 0 available
GO

-- Reservations
INSERT INTO LibrarySchema.Reservations 
    (userId, bookId, reservedAt, collectBy, borrowDate, dueDate, returnDate, status)
VALUES
    -- PENDING - Ali reserved Clean Code yesterday, collectBy tomorrow
    (2, 1, DATEADD(day,-1, SYSDATETIME()), DATEADD(day, 2, SYSDATETIME()), NULL, NULL, NULL, 'pending'),

    -- ACTIVE - Nurul collected Atomic Habits 3 days ago, due in 11 days
    (3, 9, DATEADD(day,-4, SYSDATETIME()), DATEADD(day,-3, SYSDATETIME()), DATEADD(day,-3, SYSDATETIME()), DATEADD(day,11, SYSDATETIME()), NULL, 'active'),

    -- returnRequested - Raj borrowed Intro to Algorithms, wants to return
    (4, 3, DATEADD(day,-16, SYSDATETIME()), DATEADD(day,-15, SYSDATETIME()), DATEADD(day,-15, SYSDATETIME()), DATEADD(day, -1, SYSDATETIME()), NULL, 'returnRequested'),

    -- RETURNED - Ali returned Rich Dad Poor Dad (completed)
    (2, 8, DATEADD(day,-25, SYSDATETIME()), DATEADD(day,-24, SYSDATETIME()), DATEADD(day,-22, SYSDATETIME()), DATEADD(day, -8, SYSDATETIME()), DATEADD(day,-10, SYSDATETIME()), 'returned'),

    -- OVERDUE - Wei Ling (inactive account) has Database System Concepts overdue
    (5, 4, DATEADD(day,-35, SYSDATETIME()), DATEADD(day,-34, SYSDATETIME()), DATEADD(day,-33, SYSDATETIME()), DATEADD(day,-19, SYSDATETIME()), NULL, 'overdue'),

    -- CANCELLED — Nurul reserved The Art of War but cancelled herself
    (3, 7, DATEADD(day,-5, SYSDATETIME()), DATEADD(day,-2, SYSDATETIME()), NULL, NULL, NULL, 'cancelled'),

    -- EXPIRED — Raj reserved Thinking Fast and Slow, never showed up
    (4, 5, DATEADD(day,-7, SYSDATETIME()), DATEADD(day,-4, SYSDATETIME()), NULL, NULL, NULL, 'expired');
GO

-- audit log stays empty (no insert for now)

-- verify
SELECT 'Users' AS [Table], COUNT(*) AS [Rows] FROM LibrarySchema.Users
UNION ALL
SELECT 'Books', COUNT(*) FROM LibrarySchema.Books
UNION ALL
SELECT 'Reservations', COUNT(*) FROM LibrarySchema.Reservations
UNION ALL
SELECT 'AuditLog', COUNT(*) FROM LibrarySchema.AuditLog;
GO
