-- ============================================================
-- RBAC — Roles, Permissions & Row-Level Security
-- ============================================================
USE MiniLibraryDB;
GO

-- Create roles if not exists
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='LibrarianRole' AND type='R')
    CREATE ROLE LibrarianRole;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='MemberRole' AND type='R')
    CREATE ROLE MemberRole;
GO

-- LibrarianRole: full CRUD on all tables
GRANT SELECT, INSERT, UPDATE, DELETE 
    ON LibrarySchema.Users TO LibrarianRole;
GRANT SELECT, INSERT, UPDATE, DELETE 
    ON LibrarySchema.Books TO LibrarianRole;
GRANT SELECT, INSERT, UPDATE, DELETE 
    ON LibrarySchema.Reservations TO LibrarianRole;
GRANT SELECT, INSERT, UPDATE, DELETE 
    ON LibrarySchema.AuditLog TO LibrarianRole;
GRANT EXECUTE ON SCHEMA::LibrarySchema TO LibrarianRole;
GO

-- MemberRole: read books + own reservations (RLS enforces "own")
GRANT SELECT ON LibrarySchema.Books TO MemberRole;
GRANT SELECT ON LibrarySchema.Reservations TO MemberRole;
GRANT SELECT ON LibrarySchema.Users TO MemberRole;
GRANT EXECUTE ON SCHEMA::LibrarySchema TO MemberRole;
GO

ALTER ROLE LibrarianRole ADD MEMBER lib_admin;
ALTER ROLE MemberRole ADD MEMBER lib_member;
GO

-- create user to impersonate
USE MiniLibraryDB;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='admin')
    CREATE USER [admin] WITHOUT LOGIN;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='ali.hassan')
    CREATE USER [ali.hassan] WITHOUT LOGIN;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='nurul.ain')
    CREATE USER [nurul.ain] WITHOUT LOGIN;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='raj.kumar')
    CREATE USER [raj.kumar] WITHOUT LOGIN;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='wei.ling')
    CREATE USER [wei.ling] WITHOUT LOGIN;
GO

-- Assign roles to individual users
ALTER ROLE LibrarianRole ADD MEMBER [admin];
ALTER ROLE MemberRole ADD MEMBER [ali.hassan];
ALTER ROLE MemberRole ADD MEMBER [nurul.ain];
ALTER ROLE MemberRole ADD MEMBER [raj.kumar];
ALTER ROLE MemberRole ADD MEMBER [wei.ling];
GO

-- Grant lib_member IMPERSONATE on each user
-- So Flask can: EXECUTE AS USER = 'ali.hassan' before queries
GRANT IMPERSONATE ON USER::[admin] TO lib_member;
GRANT IMPERSONATE ON USER::[ali.hassan] TO lib_member;
GRANT IMPERSONATE ON USER::[nurul.ain] TO lib_member;
GRANT IMPERSONATE ON USER::[raj.kumar] TO lib_member;
GRANT IMPERSONATE ON USER::[wei.ling] TO lib_member;
GO

-- ============================================================
-- FEATURE: ROW-LEVEL SECURITY (RLS)
-- Members see only their own reservations
-- ============================================================
USE MiniLibraryDB;
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'RLS')
    EXEC('CREATE SCHEMA RLS');
GO
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name='ReservationSecurityPolicy')
    DROP SECURITY POLICY RLS.ReservationSecurityPolicy;
GO
IF OBJECT_ID('RLS.fn_ReservationFilter','IF') IS NOT NULL
    DROP FUNCTION RLS.fn_ReservationFilter;
GO

CREATE FUNCTION RLS.fn_ReservationFilter(@userId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
    SELECT 1 AS fn_result
    FROM LibrarySchema.Users u
    WHERE u.userId = @userId AND u.userName = USER_NAME()  
    UNION ALL

    -- Librarian bypass: lib_admin sees all rows
    SELECT 1 WHERE USER_NAME() = 'lib_admin'

    UNION ALL

    -- DBA bypass: Windows admin in SSMS sees all rows
    SELECT 1 WHERE USER_NAME() = 'dbo'
);
GO

-- Apply the security policy
CREATE SECURITY POLICY RLS.ReservationSecurityPolicy
    ADD FILTER PREDICATE RLS.fn_ReservationFilter(userId)
    ON LibrarySchema.Reservations
    WITH (STATE = ON, SCHEMABINDING = ON);
GO

GRANT SELECT ON RLS.fn_ReservationFilter TO MemberRole;
GO

-- ============================================================
-- FEATURE: DYNAMIC DATA MASKING (DDM)
-- ============================================================

USE MiniLibraryDB;
GO

-- email() shows: aXXX@XXXX.com
ALTER TABLE LibrarySchema.Users
    ALTER COLUMN email
    ADD MASKED WITH (FUNCTION = 'email()');
GO

-- Shows: XXX-XXXX-347 (last 3 digits only)
ALTER TABLE LibrarySchema.Users
    ALTER COLUMN phoneNumber
    ADD MASKED WITH (FUNCTION = 'partial(0, "XXX-XXXX-", 3)');
GO

-- lib_member sees masked values
GRANT UNMASK TO lib_admin;
GO

--verify
-- AS lib_member (masked view)
EXECUTE AS USER = 'ali.hassan';
SELECT userName, email, phoneNumber 
FROM LibrarySchema.Users;
REVERT;
GO

-- AS lib_admin (unmasked — has UNMASK permission)
EXECUTE AS USER = 'lib_admin';
SELECT userName, email, phoneNumber 
FROM LibrarySchema.Users;
REVERT;
GO