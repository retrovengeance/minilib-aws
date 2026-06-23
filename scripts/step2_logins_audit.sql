-- ============================================================
-- FEATURE: SQL SERVER LOGIN
-- ============================================================
USE master;
GO

-- Librarian login (full access)
CREATE LOGIN lib_admin 
    WITH PASSWORD = 'Pa$$w0rd',
    DEFAULT_DATABASE = MiniLibraryDB,
    CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO

-- Member login (restricted access)
CREATE LOGIN lib_member
    WITH PASSWORD = 'Pa$$w0rd',
    DEFAULT_DATABASE = MiniLibraryDB,
    CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO

USE MiniLibraryDB;
GO

CREATE USER lib_admin FOR LOGIN lib_admin;
CREATE USER lib_member FOR LOGIN lib_member;
GO

-- Librarian: full control
ALTER ROLE db_owner ADD MEMBER lib_admin;
GO

-- Member: read-only via schema, no direct write
GRANT SELECT ON LibrarySchema.Books TO lib_member;
GRANT SELECT ON LibrarySchema.Reservations TO lib_member;
GRANT SELECT ON LibrarySchema.Users TO lib_member;
GO

-- ============================================================
-- FEATURE: SERVER AUDIT
-- Writes all audit events to a file on the server
-- ============================================================
USE master;
GO

IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'MiniLibrary_ServerAudit')
BEGIN
    ALTER SERVER AUDIT MiniLibrary_ServerAudit WITH (STATE = OFF);
    DROP SERVER AUDIT MiniLibrary_ServerAudit;
END
GO

CREATE SERVER AUDIT MiniLibrary_ServerAudit
TO FILE (
    FILEPATH = 'C:\asg_auditLog\', 
    MAXSIZE  = 100 MB,
    MAX_ROLLOVER_FILES = 5,
    RESERVE_DISK_SPACE = OFF
)
WITH (
    QUEUE_DELAY = 1000,
    ON_FAILURE  = CONTINUE
);
GO

ALTER SERVER AUDIT MiniLibrary_ServerAudit WITH (STATE = ON);
GO


-- SERVER AUDIT SPECIFICATION - Login Events
-- Captures every login attempt against this SQL Server instance.
IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = 'MiniLibrary_LoginSpec')
BEGIN
    ALTER SERVER AUDIT SPECIFICATION MiniLibrary_LoginSpec WITH (STATE = OFF);
    DROP SERVER AUDIT SPECIFICATION MiniLibrary_LoginSpec;
END
GO

CREATE SERVER AUDIT SPECIFICATION MiniLibrary_LoginSpec
FOR SERVER AUDIT MiniLibrary_ServerAudit
ADD (FAILED_LOGIN_GROUP),   
ADD (SUCCESSFUL_LOGIN_GROUP)
WITH (STATE = ON);
GO

-- DATABASE AUDIT SPECIFICATION — DML on Sensitive Tables
USE MiniLibraryDB;
GO

IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = 'MiniLibrary_DBSpec')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION MiniLibrary_DBSpec WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION MiniLibrary_DBSpec;
END
GO

CREATE DATABASE AUDIT SPECIFICATION MiniLibrary_DBSpec
FOR SERVER AUDIT MiniLibrary_ServerAudit
ADD (SCHEMA_OBJECT_ACCESS_GROUP)
WITH (STATE = ON);
GO

-- to verify, login (success/fail) as admin or member OR perform dml on tables in sql server and run:
SELECT TOP 20
    event_time,
    action_id,
    server_principal_name,
    succeeded,
    statement
FROM sys.fn_get_audit_file('C:\asg_auditLog\*.sqlaudit', DEFAULT, DEFAULT)
WHERE server_principal_name = 'lib_member' OR server_principal_name = 'lib_admin'
ORDER BY event_time DESC;