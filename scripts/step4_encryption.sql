-- ============================================================
-- FEATURE: ENCRYPTION
-- encrypt phoneNumber column in Users table
-- ============================================================

-- == Master Key
USE MiniLibraryDB;
GO

IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Pa$$w0rd';
END
ELSE
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Pa$$w0rd';
END
GO

BACKUP MASTER KEY
    TO FILE = 'C:\keys\MiniLibrary_masterkey'
    ENCRYPTION BY PASSWORD = 'Pa$$w0rd';
GO

-- == Certificate + Symmetric Key
USE MiniLibraryDB;
GO

IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = 'LibraryKey')
    DROP SYMMETRIC KEY LibraryKey;

IF EXISTS (SELECT * FROM sys.certificates WHERE name = 'LibraryCert')
    DROP CERTIFICATE LibraryCert;
GO

-- create certificate and key
CREATE CERTIFICATE LibraryCert
    WITH SUBJECT = 'Library Sensitive Data';
GO

CREATE SYMMETRIC KEY LibraryKey
    WITH ALGORITHM = AES_128
    ENCRYPTION BY CERTIFICATE LibraryCert;
GO

-- == Add Encrypted Column + Encrypt Data
USE MiniLibraryDB;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('LibrarySchema.Users') AND name = 'phoneNumberEncrypted'
)
    ALTER TABLE LibrarySchema.Users
        ADD phoneNumberEncrypted VARBINARY(256) NULL;
GO

OPEN SYMMETRIC KEY LibraryKey
    DECRYPTION BY CERTIFICATE LibraryCert;

UPDATE LibrarySchema.Users
    SET phoneNumberEncrypted = ENCRYPTBYKEY(
        KEY_GUID('LibraryKey'),
        phoneNumber
    );

CLOSE SYMMETRIC KEY LibraryKey;
GO

-- Verify encrypted column has values
SELECT
    userName,
    phoneNumber AS plaintext,
    phoneNumberEncrypted AS encrypted_varbinary
FROM LibrarySchema.Users;
GO

-- ============================================================
-- Decrypt Test
-- ============================================================
USE MiniLibraryDB;
GO

OPEN SYMMETRIC KEY LibraryKey
    DECRYPTION BY CERTIFICATE LibraryCert;

SELECT
    userName,
    phoneNumber AS original,
    phoneNumberEncrypted AS encrypted,
    CONVERT(NVARCHAR(20), DECRYPTBYKEY(phoneNumberEncrypted)) AS decrypted
FROM LibrarySchema.Users;

CLOSE SYMMETRIC KEY LibraryKey;
GO

-- ============================================================
-- Certificate Backup
-- ============================================================
USE MiniLibraryDB;
GO

OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Pa$$w0rd';

BACKUP CERTIFICATE LibraryCert
    TO FILE = 'C:\certificates\LibraryCert.cer'
    WITH PRIVATE KEY (
        FILE = 'C:\certificates\LibraryCert.pvk',
        ENCRYPTION BY PASSWORD = 'Pa$$w0rd'
    );
GO

-- ============================================================
-- Transparent Data Encryption (TDE)
--   Encrypts entire MiniLibraryDB at rest (AES_256)
-- ============================================================
USE master;
GO

-- Open master DB's master key
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Pa$$w0rd';
GO

OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Pa$$w0rd';
GO

IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name = 'MiniLibraryServerCert')
    CREATE CERTIFICATE MiniLibraryServerCert
        WITH SUBJECT = 'MiniLibrary TDE Certificate';
GO

-- Enable TDE on MiniLibraryDB
USE MiniLibraryDB;
GO

IF NOT EXISTS (
    SELECT * FROM sys.dm_database_encryption_keys
    WHERE database_id = DB_ID('MiniLibraryDB')
)
BEGIN
    CREATE DATABASE ENCRYPTION KEY
        WITH ALGORITHM = AES_256
        ENCRYPTION BY SERVER CERTIFICATE MiniLibraryServerCert;
END
GO

ALTER DATABASE MiniLibraryDB
    SET ENCRYPTION ON;
GO

-- verify
SELECT
    DB_NAME(database_id) AS DatabaseName,
    encryption_state,
    CASE encryption_state
        WHEN 0 THEN 'No encryption key'
        WHEN 1 THEN 'Unencrypted'
        WHEN 2 THEN 'Encryption in progress'
        WHEN 3 THEN 'Encrypted'
        WHEN 4 THEN 'Key change in progress'
        WHEN 5 THEN 'Decryption in progress'
        WHEN 6 THEN 'Protection change in progress'
    END AS encryption_desc,
    percent_complete,
    encryptor_type
FROM sys.dm_database_encryption_keys
WHERE DB_NAME(database_id) = 'MiniLibraryDB';
GO