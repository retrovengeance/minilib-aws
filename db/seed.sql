-- =============================================================
--  seed.sql — Test data for MiniLibraryDB (MySQL)
--  Run AFTER schema.sql
--
--  All passwords = "Test1234"
--  Hash generated with bcrypt cost factor 12
--  DB user passwords updated to match app.py _CREDS
-- =============================================================

USE MiniLibraryDB;

-- Update DB user passwords to match app.py
ALTER USER 'lib_admin'@'%'  IDENTIFIED BY 'LibAdminSecure2026!';
ALTER USER 'lib_member'@'%' IDENTIFIED BY 'LibMemberSecure2026!';
FLUSH PRIVILEGES;

-- Clear existing data (safe re-run)
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE AuditLog;
TRUNCATE TABLE Reservations;
TRUNCATE TABLE Books;
TRUNCATE TABLE Users;
SET FOREIGN_KEY_CHECKS = 1;

-- Users (password = "Test1234")
INSERT INTO Users (userName, fullName, email, password, role, phoneNumber, icNumber) VALUES
('admin',      'Library Admin',       'admin@minilib.my',   '$2b$12$QWUFbkJJ6bpRG096gzkGA.lS4LrHoyFYy3FneABlpQxdNdecGlwAO', 'Librarian', '012-3456789', ''),
('ali.hassan', 'Ali Hassan',          'ali@minilib.my',     '$2b$12$QWUFbkJJ6bpRG096gzkGA.lS4LrHoyFYy3FneABlpQxdNdecGlwAO', 'Member',    '011-2233445', ''),
('nur.aina',   'Nur Aina Sofea',      'aina@minilib.my',    '$2b$12$QWUFbkJJ6bpRG096gzkGA.lS4LrHoyFYy3FneABlpQxdNdecGlwAO', 'Member',    '013-9988776', ''),
('raj.kumar',  'Rajendran Kumar',     'raj@minilib.my',     '$2b$12$QWUFbkJJ6bpRG096gzkGA.lS4LrHoyFYy3FneABlpQxdNdecGlwAO', 'Member',    '016-5544332', '');

-- Books
INSERT INTO Books (title, author, isbn, genre, quantity, availableQty) VALUES
('Database System Concepts',   'Silberschatz, Korth, Sudarshan', '978-0-07-802215-9', 'Computer Science',    3, 3),
('Cloud Computing: Concepts',  'Thomas Erl',                     '978-0-13-379981-4', 'Computer Science',    2, 2),
('Introduction to Algorithms', 'Cormen, Leiserson, Rivest',      '978-0-26-204630-5', 'Computer Science',    2, 1),
('Clean Code',                 'Robert C. Martin',               '978-0-13-235088-4', 'Software Engineering',3, 3),
('The Art of War',             'Sun Tzu',                        '978-0-14-044501-2', 'Philosophy',          1, 1),
('Python Crash Course',        'Eric Matthes',                   '978-1-59327-928-8', 'Programming',         4, 4),
('Atomic Habits',              'James Clear',                    '978-0-73-521254-1', 'Self-Help',           2, 2);

-- One active reservation for ali.hassan (bookId=3 — Introduction to Algorithms)
INSERT INTO Reservations (userId, bookId, status, borrowDate, dueDate) VALUES
(2, 3, 'active', NOW(), DATE_ADD(NOW(), INTERVAL 14 DAY));

INSERT INTO AuditLog (userId, action, targetTable, description) VALUES
(1, 'SeedData', 'All', 'Database seeded for CCS6344 Assignment 2 Group 28');
