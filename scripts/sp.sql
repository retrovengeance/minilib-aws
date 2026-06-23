-- ============================================================
-- STORED PROCEDURES
-- ============================================================
USE MiniLibraryDB;
GO

CREATE OR ALTER PROCEDURE LibrarySchema.sp_LogAudit
    @userId INT = NULL,
    @action NVARCHAR(100),
    @targetTable NVARCHAR(50) = NULL,
    @description NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO LibrarySchema.AuditLog 
        (userId, action, targetTable, description, loggedAt)
    VALUES 
        (@userId, @action, @targetTable, @description, SYSDATETIME());
END
GO

-- ==================================
-- BOOKS
-- ==================================
-- getAllBooks
CREATE OR ALTER PROCEDURE LibrarySchema.sp_getAllBooks
    @searchQuery NVARCHAR(300) = NULL
AS BEGIN
    SET NOCOUNT ON;
    SELECT bookId, title, author, isbn, genre, quantity, availableQty, addedAt
    FROM LibrarySchema.Books
    WHERE @searchQuery IS NULL
       OR title LIKE '%' + @searchQuery + '%'
       OR author LIKE '%' + @searchQuery + '%'
       OR isbn LIKE '%' + @searchQuery + '%'
       OR genre LIKE '%' + @searchQuery + '%'
    ORDER BY title;
END
GO

-- addBook
CREATE OR ALTER PROCEDURE LibrarySchema.sp_addBook
    @title NVARCHAR(300),
    @author NVARCHAR(200),
    @isbn NVARCHAR(20),
    @genre NVARCHAR(100),
    @quantity INT,
    @addedBy INT = NULL
AS BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM LibrarySchema.Books WHERE isbn = @isbn)
    BEGIN
        RAISERROR('A book with this ISBN already exists.', 16, 1);
        RETURN;
    END

    INSERT INTO LibrarySchema.Books 
        (title, author, isbn, genre, quantity, availableQty)
    VALUES 
        (@title, @author, @isbn, @genre, @quantity, @quantity);

    EXEC LibrarySchema.sp_LogAudit
        @userId = @addedBy, @action = 'AddBook', @targetTable = 'Books', @description = @title;
END
GO

-- editBook
CREATE OR ALTER PROCEDURE LibrarySchema.sp_editBook
    @bookId INT,
    @title NVARCHAR(300),
    @author NVARCHAR(200),
    @isbn NVARCHAR(20),
    @genre NVARCHAR(100),
    @quantity INT,
    @editedBy INT = NULL
AS BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM LibrarySchema.Books WHERE bookId = @bookId)
    BEGIN
        RAISERROR('Book not found.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1 FROM LibrarySchema.Books 
        WHERE isbn = @isbn AND bookId != @bookId
    )
    BEGIN
        RAISERROR('ISBN already used by another book.', 16, 1);
        RETURN;
    END

    -- Adjust availableQty proportionally
    DECLARE @oldQty INT;
    DECLARE @oldAvail INT;
    SELECT @oldQty = quantity, @oldAvail = availableQty
    FROM LibrarySchema.Books WHERE bookId = @bookId;

    DECLARE @newAvail INT = @oldAvail + (@quantity - @oldQty);
    IF @newAvail < 0 SET @newAvail = 0;

    UPDATE LibrarySchema.Books
    SET title = @title,
        author = @author,
        isbn = @isbn,
        genre = @genre,
        quantity = @quantity,
        availableQty = @newAvail
    WHERE bookId = @bookId;

    DECLARE @desc1 NVARCHAR(500);
    SET @desc1 = CONCAT('BookID:', @bookId, ' ', @title);
    EXEC LibrarySchema.sp_LogAudit
        @userId = @editedBy, @action = 'EditBook',
        @targetTable = 'Books',
        @description = @desc1;
END
GO

-- deleteBook
CREATE OR ALTER PROCEDURE LibrarySchema.sp_deleteBook
    @bookId INT,
    @deletedBy INT = NULL
AS BEGIN
    SET NOCOUNT ON;

    DECLARE @title NVARCHAR(300);
    SELECT @title = title FROM LibrarySchema.Books WHERE bookId = @bookId;

    DELETE FROM LibrarySchema.Books WHERE bookId = @bookId;

    DECLARE @desc2 NVARCHAR(500);
    SET @desc2 = CONCAT('BookID:', @bookId, ' ', @title);

    EXEC LibrarySchema.sp_LogAudit
        @userId = @deletedBy, @action = 'DeleteBook',
        @targetTable = 'Books',
        @description = @desc2;
END
GO

-- ==================================
-- RESERVATIONS
-- ==================================

-- getAllReservations
CREATE OR ALTER PROCEDURE LibrarySchema.sp_getAllReservations
    @statusFilter NVARCHAR(20) = NULL
AS BEGIN
    SET NOCOUNT ON;
    SELECT
        r.reservationId,
        r.userId,
        u.userName,
        u.fullName,
        r.bookId,
        b.title,
        r.reservedAt,
        r.collectBy,
        r.borrowDate,
        r.dueDate,
        r.returnDate,
        r.status
    FROM LibrarySchema.Reservations r
    JOIN LibrarySchema.Users u ON r.userId = u.userId
    JOIN LibrarySchema.Books b ON r.bookId = b.bookId
    WHERE @statusFilter IS NULL OR r.status = @statusFilter
    ORDER BY r.reservedAt DESC;
END
GO

-- create reservation
CREATE OR ALTER PROCEDURE LibrarySchema.sp_createReservation
    @userId INT,
    @bookId INT
AS BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (
        SELECT 1 FROM LibrarySchema.Users 
        WHERE userId = @userId AND isActive = 1
    )
    BEGIN
        RAISERROR('Member account is inactive.', 16, 1);
        RETURN;
    END

    -- Book must have stock
    IF NOT EXISTS (
        SELECT 1 FROM LibrarySchema.Books 
        WHERE bookId = @bookId AND availableQty > 0
    )
    BEGIN
        RAISERROR('Book is not available.', 16, 1);
        RETURN;
    END

    -- No duplicate active reservation
    IF EXISTS (
        SELECT 1 FROM LibrarySchema.Reservations
        WHERE userId = @userId AND bookId = @bookId
        AND status IN ('pending', 'active', 'returnRequested')
    )
    BEGIN
        RAISERROR('You already have an active reservation for this book.', 16, 1);
        RETURN;
    END

    INSERT INTO LibrarySchema.Reservations
        (userId, bookId, reservedAt, collectBy, dueDate, status)
    VALUES
        (@userId, @bookId, SYSDATETIME(),
         DATEADD(day, 3,  SYSDATETIME()),
         NULL,
         'pending');

    UPDATE LibrarySchema.Books
    SET availableQty = availableQty - 1
    WHERE bookId = @bookId;

    DECLARE @desc3 NVARCHAR(500);
    SET @desc3 = CONCAT('BookID:', @bookId);

    EXEC LibrarySchema.sp_LogAudit
        @userId = @userId, @action = 'CreateReservation',
        @targetTable = 'Reservations',
        @description = @desc3;
END
GO

-- cancel reservation
CREATE OR ALTER PROCEDURE LibrarySchema.sp_cancelReservation
    @reservationId INT,
    @userId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (
        SELECT 1 FROM LibrarySchema.Reservations
        WHERE reservationId = @reservationId
        AND userId = @userId AND status = 'pending'
    )
    BEGIN
        RAISERROR('Reservation not found or cannot be cancelled.', 16, 1);
        RETURN;
    END

    DECLARE @bookId INT;
    SELECT @bookId = bookId FROM LibrarySchema.Reservations
    WHERE reservationId = @reservationId;

    UPDATE LibrarySchema.Reservations
    SET status = 'cancelled'
    WHERE reservationId = @reservationId;

    UPDATE LibrarySchema.Books
    SET availableQty = availableQty + 1
    WHERE bookId = @bookId;

    DECLARE @desc4 NVARCHAR(500);
    SET @desc4 = CONCAT('ReservationID:', @reservationId);

    EXEC LibrarySchema.sp_LogAudit
        @userId = @userId, @action = 'CancelReservation',
        @targetTable = 'Reservations',
        @description = @desc4;
END
GO

-- return request
CREATE OR ALTER PROCEDURE LibrarySchema.sp_returnRequest
    @reservationId INT,
    @userId INT
AS BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (
        SELECT 1 FROM LibrarySchema.Reservations
        WHERE reservationId = @reservationId
        AND userId = @userId
        AND status IN ('active', 'overdue')
    )
    BEGIN
        RAISERROR('Reservation not found or cannot request return.', 16, 1);
        RETURN;
    END

    UPDATE LibrarySchema.Reservations
    SET status = 'returnRequested'
    WHERE reservationId = @reservationId;

    DECLARE @desc5 NVARCHAR(500);
    SET @desc5 = CONCAT('ReservationID:', @reservationId);

    EXEC LibrarySchema.sp_LogAudit
        @userId = @userId, @action = 'RequestReturn',
        @targetTable = 'Reservations',
        @description = @desc5;
END
GO

-- approve return
CREATE OR ALTER PROCEDURE LibrarySchema.sp_approveReturn
    @reservationId INT,
    @approvedBy INT = NULL
AS BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM LibrarySchema.Reservations
        WHERE reservationId = @reservationId
        AND status = 'returnRequested'
    )
    BEGIN
        RAISERROR('Reservation not found or not in returnRequested state.', 16, 1);
        RETURN;
    END

    DECLARE @bookId INT;
    SELECT @bookId = bookId FROM LibrarySchema.Reservations
    WHERE reservationId = @reservationId;

    UPDATE LibrarySchema.Reservations
    SET status = 'returned',
        returnDate = SYSDATETIME()
    WHERE reservationId = @reservationId;

    UPDATE LibrarySchema.Books
    SET availableQty = availableQty + 1
    WHERE bookId = @bookId;

    DECLARE @desc6 NVARCHAR(500);
    SET @desc6 = CONCAT('ReservationID:', @reservationId);
    EXEC LibrarySchema.sp_LogAudit
        @userId = @approvedBy, @action = 'ApproveReturn',
        @targetTable = 'Reservations',
        @description = @desc6;
END
GO

-- Mark overdue
CREATE OR ALTER PROCEDURE LibrarySchema.sp_markOverdue
AS BEGIN
    SET NOCOUNT ON;

    -- Step 1: active past dueDate → overdue
    UPDATE LibrarySchema.Reservations 
    SET status = 'overdue'
    WHERE status = 'active' AND dueDate < SYSDATETIME();

    -- Step 2: pending past collectBy → expired
    -- Use OUTPUT to capture which ones changed for stock restore
    DECLARE @expiredBooks TABLE (bookId INT);

    UPDATE LibrarySchema.Reservations
    SET status = 'expired'
    OUTPUT DELETED.bookId INTO @expiredBooks
    WHERE status = 'pending' AND collectBy < SYSDATETIME();

    -- Step 3: restore stock only for newly expired
    UPDATE LibrarySchema.Books
    SET availableQty = availableQty + 1
    WHERE bookId IN (SELECT bookId FROM @expiredBooks);

    DECLARE @desc NVARCHAR(500);
    SET @desc = 'Overdue and expired check completed';
    EXEC LibrarySchema.sp_LogAudit
        @action = 'MarkOverdue',
        @targetTable = 'Reservations',
        @description = @desc;
END
GO

-- collect reservation
CREATE OR ALTER PROCEDURE LibrarySchema.sp_collectReservation
    @reservationId INT,
    @collectedBy INT = NULL
AS BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM LibrarySchema.Reservations
        WHERE reservationId = @reservationId AND status = 'pending'
    )
    BEGIN
        RAISERROR('Reservation not found or not in pending state.', 16, 1);
        RETURN;
    END

    -- Set status to active, borrowDate = now, dueDate = now + 14 days
    UPDATE LibrarySchema.Reservations
    SET status = 'active',
        borrowDate = SYSDATETIME(),
        dueDate = DATEADD(day, 14, SYSDATETIME())
    WHERE reservationId = @reservationId;

    DECLARE @desc NVARCHAR(500);
    SET @desc = CONCAT('ReservationID:', @reservationId, ' collected');
    EXEC LibrarySchema.sp_LogAudit
        @userId = @collectedBy,
        @action = 'CollectReservation',
        @targetTable = 'Reservations',
        @description = @desc;
END
GO

-- ==================================
-- MEMBERS
-- ==================================

-- get members
CREATE OR ALTER PROCEDURE LibrarySchema.sp_getAllMembers
AS
BEGIN
    SET NOCOUNT ON;
    SELECT userId, userName, fullName, email, role, isActive, createdAt, phoneNumber
    FROM LibrarySchema.Users
    ORDER BY createdAt DESC;
END
GO

-- change member status
CREATE OR ALTER PROCEDURE LibrarySchema.sp_changeMemberStatus
    @memberId INT,
    @toggledBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM LibrarySchema.Users WHERE userId = @memberId)
    BEGIN
        RAISERROR('Member not found.', 16, 1);
        RETURN;
    END

    UPDATE LibrarySchema.Users
    SET isActive = CASE WHEN isActive = 1 THEN 0 ELSE 1 END
    WHERE userId = @memberId;

    DECLARE @desc8 NVARCHAR(500);
    SET @desc8 = CONCAT('MemberID:', @memberId);
    EXEC LibrarySchema.sp_LogAudit
        @userId = @toggledBy, @action = 'ChangeMemberStatus',
        @targetTable = 'Users',
        @description = @desc8;
END
GO

CREATE OR ALTER PROCEDURE LibrarySchema.sp_deleteMember
    @memberId INT,
    @deletedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 FROM LibrarySchema.Reservations
        WHERE userId = @memberId
        AND status IN ('pending','active','returnRequested','overdue')
    )
    BEGIN
        RAISERROR('Cannot delete: member has active reservations.', 16, 1);
        RETURN;
    END

    DECLARE @userName NVARCHAR(100);
    SELECT @userName = userName 
    FROM LibrarySchema.Users WHERE userId = @memberId;

    IF NOT EXISTS (SELECT 1 FROM LibrarySchema.Users WHERE userId = @memberId)
    BEGIN
        RAISERROR('Member not found.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @userName)
    BEGIN
        -- Revoke IMPERSONATE first (granted during registration)
        EXEC('REVOKE IMPERSONATE ON USER::[' + @userName + '] FROM lib_member');
        -- Remove from role
        EXEC('ALTER ROLE MemberRole DROP MEMBER [' + @userName + ']');
        -- Now safe to drop
        EXEC('DROP USER [' + @userName + ']');
    END

    DELETE FROM LibrarySchema.Users WHERE userId = @memberId;

    DECLARE @desc9 NVARCHAR(500);
    SET @desc9 = CONCAT('MemberID:', @memberId, ' ', @userName);
    EXEC LibrarySchema.sp_LogAudit
        @userId = @deletedBy,
        @action = 'DeleteMember',
        @targetTable = 'Users',
        @description = @desc9;
END
GO

CREATE OR ALTER PROCEDURE LibrarySchema.sp_registerUser
    @userName NVARCHAR(100),
    @fullName NVARCHAR(200),
    @email NVARCHAR(200),
    @password NVARCHAR(200),
    @phoneNumber NVARCHAR(15) = NULL
AS BEGIN
    SET NOCOUNT ON;

    -- Validate username uniqueness
    IF EXISTS (SELECT 1 FROM LibrarySchema.Users WHERE userName = @userName)
    BEGIN
        RAISERROR('Username already taken.', 16, 1);
        RETURN;
    END

    -- Validate email uniqueness
    IF EXISTS (SELECT 1 FROM LibrarySchema.Users WHERE email = @email)
    BEGIN
        RAISERROR('Email already registered.', 16, 1);
        RETURN;
    END

    -- Insert new member
    INSERT INTO LibrarySchema.Users
        (userName, fullName, email, password, role, isActive, phoneNumber)
    VALUES
        (@userName, @fullName, @email, @password, 'Member', 1, @phoneNumber);

    DECLARE @userId INT = SCOPE_IDENTITY();

    -- Create WITHOUT LOGIN DB user for RLS EXECUTE AS
    EXEC('CREATE USER [' + @userName + '] WITHOUT LOGIN');
    EXEC('ALTER ROLE MemberRole ADD MEMBER [' + @userName + ']');
    EXEC('GRANT IMPERSONATE ON USER::[' + @userName + '] TO lib_member');

    -- Log registration
    DECLARE @desc NVARCHAR(500);
    SET @desc = CONCAT('New member registered: ', @userName);
    EXEC LibrarySchema.sp_LogAudit
        @userId = @userId,
        @action = 'Register',
        @targetTable = 'Users',
        @description = @desc;
END
GO

CREATE OR ALTER PROCEDURE LibrarySchema.sp_checkLoginAttempts
    @userId   INT,
    @userName NVARCHAR(100)
AS BEGIN
    SET NOCOUNT ON;

    -- Count failed attempts in last 15 minutes
    DECLARE @failCount INT;
    SELECT @failCount = COUNT(*)
    FROM LibrarySchema.AuditLog
    WHERE userId  = @userId
    AND   action  = 'LoginFailed'
    AND   loggedAt > DATEADD(minute, -15, SYSDATETIME());

    -- 5th attempt (4 already logged + this one) → lock
    IF @failCount >= 4
    BEGIN
        UPDATE LibrarySchema.Users
        SET isActive = 0
        WHERE userId = @userId;

        DECLARE @desc NVARCHAR(500);
        SET @desc = CONCAT('Locked after 5 failed attempts: ', @userName);

        EXEC LibrarySchema.sp_LogAudit
            @userId = @userId,
            @action = 'AccountLocked',
            @targetTable = 'Users',
            @description = @desc;

        SELECT 1 AS isLocked;
    END
    ELSE
    BEGIN
        SELECT 0 AS isLocked;  -- still under limit
    END
END
GO

-- VERIFY — all SPs created
SELECT name, create_date
FROM sys.procedures
WHERE schema_id = SCHEMA_ID('LibrarySchema')
ORDER BY name;
GO