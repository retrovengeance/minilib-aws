-- ============================================================
-- FEATURE: BACKUP CERTIFICATE
-- ============================================================
USE master;
GO

-- Open master key
OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Pa$$w0rd';
GO

-- Create backup encryption certificate
IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = 'BackupEncryptionCert')
    CREATE CERTIFICATE BackupEncryptionCert
        WITH SUBJECT = 'MiniLibrary Backup Encryption Certificate';
GO

-- Verify
SELECT name, subject, expiry_date 
FROM sys.certificates 
WHERE name = 'BackupEncryptionCert';
GO


-- ============================================================
-- FEATURE: CODE SIGNING
-- ============================================================
USE MiniLibraryDB;
GO

OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Pa$$w0rd';
GO

-- create code signing certificate
IF EXISTS (SELECT * FROM sys.certificates WHERE name = 'CodeSigningCert')
    DROP CERTIFICATE CodeSigningCert;
GO
CREATE CERTIFICATE CodeSigningCert
    WITH SUBJECT = 'MiniLibrary Stored Procedure Code Signing';
GO

-- Create user from certificate
-- This user holds permissions that signed SPs inherit
IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'CodeSigningUser')
    DROP USER CodeSigningUser;
GO
CREATE USER CodeSigningUser FROM CERTIFICATE CodeSigningCert;
GO

GRANT SELECT, INSERT, UPDATE, DELETE ON LibrarySchema.Books TO CodeSigningUser;
-- Reservations
GRANT SELECT, INSERT, UPDATE, DELETE ON LibrarySchema.Reservations TO CodeSigningUser;
-- Users
GRANT SELECT, UPDATE, DELETE ON LibrarySchema.Users TO CodeSigningUser;
GRANT SELECT, INSERT ON LibrarySchema.AuditLog TO CodeSigningUser;
GRANT EXECUTE ON SCHEMA::LibrarySchema TO CodeSigningUser;
GO

-- sign all stored procedures
ADD SIGNATURE TO LibrarySchema.sp_LogAudit BY CERTIFICATE CodeSigningCert;

-- Books
ADD SIGNATURE TO LibrarySchema.sp_getAllBooks BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_addBook BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_editBook BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_deleteBook BY CERTIFICATE CodeSigningCert;

-- Reservations
ADD SIGNATURE TO LibrarySchema.sp_getAllReservations BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_createReservation BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_cancelReservation BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_returnRequest BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_approveReturn BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_markOverdue BY CERTIFICATE CodeSigningCert;

-- Members
ADD SIGNATURE TO LibrarySchema.sp_getAllMembers BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_changeMemberStatus BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_deleteMember BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_registerUser BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_collectReservation BY CERTIFICATE CodeSigningCert;
ADD SIGNATURE TO LibrarySchema.sp_checkLoginAttempts BY CERTIFICATE CodeSigningCert;
GO

-- verify
SELECT
    OBJECT_NAME(cp.major_id) AS StoredProcedure,
    c.name AS SignedByCertificate,
    cp.crypt_type_desc AS SignatureType
FROM sys.crypt_properties cp
JOIN sys.certificates c ON cp.thumbprint = c.thumbprint
WHERE OBJECTPROPERTY(cp.major_id, 'IsProcedure') = 1
ORDER BY StoredProcedure;
GO