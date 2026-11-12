-- ============================================================================
-- 1. СЪЗДАВАНЕ НА БАЗА ДАННИ
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'DiscordDB')
BEGIN
    CREATE DATABASE DiscordDB;
END;
GO

USE DiscordDB;
GO

-- Изтриване на съществуващи таблици (ако има такива) за чисто изпълнение
IF OBJECT_ID('User_Roles', 'U') IS NOT NULL DROP TABLE User_Roles;
IF OBJECT_ID('Messages', 'U') IS NOT NULL DROP TABLE Messages;
IF OBJECT_ID('Roles', 'U') IS NOT NULL DROP TABLE Roles;
IF OBJECT_ID('Channels', 'U') IS NOT NULL DROP TABLE Channels;
IF OBJECT_ID('Servers', 'U') IS NOT NULL DROP TABLE Servers;
IF OBJECT_ID('Users', 'U') IS NOT NULL DROP TABLE Users;
GO

-- ============================================================================
-- 2. СЪЗДАВАНЕ НА ТАБЛИЦИ (6 ОБЕКТА)
-- ============================================================================

-- Таблица 1: Users (Потребители)
CREATE TABLE Users (
    user_id INT IDENTITY(1,1) PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'offline' CHECK (status IN ('online', 'offline', 'dnd', 'idle')),
    created_at DATETIME DEFAULT GETDATE()
);

-- Таблица 2: Servers (Сървъри)
CREATE TABLE Servers (
    server_id INT IDENTITY(1,1) PRIMARY KEY,
    owner_id INT NOT NULL,
    server_name VARCHAR(100) NOT NULL,
    region VARCHAR(50) DEFAULT 'Europe',
    created_at DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Servers_Users FOREIGN KEY (owner_id) REFERENCES Users(user_id)
);

-- Таблица 3: Channels (Канали)
CREATE TABLE Channels (
    channel_id INT IDENTITY(1,1) PRIMARY KEY,
    server_id INT NOT NULL,
    channel_name VARCHAR(100) NOT NULL,
    channel_type VARCHAR(20) NOT NULL CHECK (channel_type IN ('text', 'voice')),
    created_at DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Channels_Servers FOREIGN KEY (server_id) REFERENCES Servers(server_id)
);

-- Таблица 4: Messages (Съобщения)
CREATE TABLE Messages (
    message_id INT IDENTITY(1,1) PRIMARY KEY,
    channel_id INT NOT NULL,
    author_id INT NOT NULL,
    content VARCHAR(MAX) NOT NULL,
    sent_at DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Messages_Channels FOREIGN KEY (channel_id) REFERENCES Channels(channel_id),
    CONSTRAINT FK_Messages_Users FOREIGN KEY (author_id) REFERENCES Users(user_id)
);

-- Таблица 5: Roles (Роли)
CREATE TABLE Roles (
    role_id INT IDENTITY(1,1) PRIMARY KEY,
    server_id INT NOT NULL,
    role_name VARCHAR(50) NOT NULL,
    color_hex VARCHAR(7) DEFAULT '#99AAB5',
    hoist BIT DEFAULT 0,
    CONSTRAINT FK_Roles_Servers FOREIGN KEY (server_id) REFERENCES Servers(server_id)
);

-- Таблица 6: User_Roles (Връзка M:N)
CREATE TABLE User_Roles (
    user_id INT NOT NULL,
    role_id INT NOT NULL,
    assigned_at DATETIME DEFAULT GETDATE(),
    assigned_by INT,
    CONSTRAINT PK_User_Roles PRIMARY KEY (user_id, role_id),
    CONSTRAINT FK_UserRoles_Users FOREIGN KEY (user_id) REFERENCES Users(user_id),
    CONSTRAINT FK_UserRoles_Roles FOREIGN KEY (role_id) REFERENCES Roles(role_id)
);
GO

-- ============================================================================
-- 3. НАПЪЛВАНЕ НА БАЗАТА С ДАННИ (INSERT DATA)
-- ============================================================================

INSERT INTO Users (username, email, password_hash, status) VALUES
('GamerPro', 'gamer@gmail.com', 'hash_pass1', 'online'),
('DevGeo', 'georgi@dev.bg', 'hash_pass2', 'dnd'),
('Elena_M', 'elena@yahoo.com', 'hash_pass3', 'idle'),
('Alex_Code', 'alex@tech.org', 'hash_pass4', 'offline'),
('Maria_Gaming', 'maria@gaming.net', 'hash_pass5', 'online');

INSERT INTO Servers (owner_id, server_name, region) VALUES
(1, 'Gaming Lounge BG', 'Europe Central'),
(2, 'Software Developers', 'Europe East'),
(5, 'Casual Streamers', 'Europe West');

INSERT INTO Channels (server_id, channel_name, channel_type) VALUES
(1, 'general', 'text'),
(1, 'voice-chat-1', 'voice'),
(2, 'sql-help', 'text'),
(2, 'csharp-chat', 'text'),
(3, 'stream-announcements', 'text');

INSERT INTO Messages (channel_id, author_id, content) VALUES
(1, 1, 'Здравейте и добре дошли в сървъра!'),
(1, 3, 'Привет на всички! Има ли свободни за игра?'),
(3, 2, 'Някой има ли въпроси относно базите данни и SQL Server?'),
(3, 4, 'Да, имам въпрос за външните ключове (FK).'),
(5, 5, 'Стриймът започва след 15 минути!');

INSERT INTO Roles (server_id, role_name, color_hex, hoist) VALUES
(1, 'Admin', '#FF0000', 1),
(1, 'VIP Gamer', '#00FF00', 0),
(2, 'Senior Developer', '#0000FF', 1),
(2, 'Student', '#FFFF00', 0);

-- Добавяне на присвоени роли (User_Roles)
INSERT INTO User_Roles (user_id, role_id, assigned_by) VALUES
(1, 1, 1),
(3, 2, 1),
(2, 3, 2),
(4, 4, 2);
GO

-- ============================================================================
-- 4. ПРОГРАМНИ ОБЕКТИ (ПРОЦЕДУРА, ФУНКЦИЯ, ТРИГЕР)
-- ============================================================================

-- 4.1. Съхранена процедура (Stored Procedure): Изпращане на съобщение
-- Цел: Автоматизира и сигурно управлява процеса по добавяне на ново съобщение в даден канал.
IF OBJECT_ID('sp_SendMessage', 'P') IS NOT NULL DROP PROCEDURE sp_SendMessage; -- Проверява дали процедура с това име вече съществува в базата данни. Ако я има, я изтрива, за да се създаде наново без конфликти.
GO
CREATE PROCEDURE sp_SendMessage -- Входните данни, които трябва да подадете при извикване — в кой канал се праща, кой го праща и какво е съдържанието.
    @ChannelID INT,
    @AuthorID INT,
    @Content VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON; -- Скрива служебните съобщения от рода на (1 row affected) за по-бързо изпълнение и по-чист резултат.
    
    -- Проверка дали каналът и авторът съществуват
    IF NOT EXISTS (SELECT 1 FROM Channels WHERE channel_id = @ChannelID)
    BEGIN
        RAISERROR ('Грешка: Несъществуващ канал!', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM Users WHERE user_id = @AuthorID)
    BEGIN
        RAISERROR ('Грешка: Несъществуващ потребител!', 16, 1);
        RETURN;
    END;

    INSERT INTO Messages (channel_id, author_id, content, sent_at) -- Ако валидациите минат успешно, прави запис в таблицата Messages, като системната функция GETDATE() автоматично записва текущата дата и час.
    VALUES (@ChannelID, @AuthorID, @Content, GETDATE());
    
    PRINT 'Съобщението беше изпратено успешно!';
END;
GO

-- 4.2. Скаларна функция (Function): Връща броя съобщения в даден канал
-- Премахва старата версия на функцията, ако съществува.
IF OBJECT_ID('fn_GetChannelMessageCount', 'FN') IS NOT NULL DROP FUNCTION fn_GetChannelMessageCount;
GO
CREATE FUNCTION fn_GetChannelMessageCount (@ChannelID INT) -- Приема @ChannelID (ID на канала) и декларира, че ще върне INT (цяло число).
RETURNS INT
AS
BEGIN
    DECLARE @Count INT;
    SELECT @Count = COUNT(*) FROM Messages WHERE channel_id = @ChannelID; -- Преброява колко реда има в таблица Messages, при които channel_id съвпада с подаденото ID, и записва резултата в променливата @Count.
    RETURN ISNULL(@Count, 0); -- Ако по някаква причина няма съобщения или резултатът е NULL, ISNULL(@Count, 0) гарантира, че функцията ще върне точно 0, а не празна стойност.
END;
GO

-- 4.3. Тригер (Trigger): Забранява изпращане на празни съобщения
-- Цел: Автоматичен пазач за интегритета на данните. Той се задейства сам при всеки опит за вмъкване (INSERT) или промяна (UPDATE) на запис в таблицата Messages.
IF OBJECT_ID('trg_PreventEmptyMessages', 'TR') IS NOT NULL DROP TRIGGER trg_PreventEmptyMessages; -- Изтрива предишна версия на тригера, ако има такава.
GO
CREATE TRIGGER trg_PreventEmptyMessages
ON Messages
FOR INSERT, UPDATE -- Указва, че тригерът следи оперативно таблицата Messages при добавяне или редактиране.
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1 
        FROM inserted -- Когато правите INSERT или UPDATE, MS SQL Server временно поставя новите данни в служебна таблица, наречена inserted.
        WHERE LTRIM(RTRIM(content)) = '' OR content IS NULL -- LTRIM(RTRIM(content)) = '' премахва всички празни разстояния (интервали) отляво и отдясно. Така съобщение съдържащо само спейсове ("   ") става "" (празен текст).
    )
    BEGIN
        RAISERROR ('Грешка: Съобщението не може да бъде празно или да съдържа само интервали!', 16, 1);
        ROLLBACK TRANSACTION;
    END;
END;
GO


USE DiscordDB;

-- 1. За листа "Users_Status"
SELECT status, COUNT(*) AS total_users 
FROM Users 
GROUP BY status;

-- 2. За листа "Messages_By_Channel"
SELECT c.channel_name, COUNT(m.message_id) AS total_messages
FROM Channels c
LEFT JOIN Messages m ON c.channel_id = m.channel_id
GROUP BY c.channel_name;

-- 3. За листа "KPI_Metrics"
SELECT 
    (SELECT COUNT(*) FROM Users) AS total_users,
    (SELECT COUNT(*) FROM Messages) AS total_messages,
    (SELECT COUNT(*) FROM Servers) AS total_servers;