/*=====================================================================
  T-Lift Quick Test Runner — persistent result table
=====================================================================*/
USE [TLift_TestDB];
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID('dbo.TestResults') IS NOT NULL DROP TABLE dbo.TestResults;
CREATE TABLE dbo.TestResults (
    TestID   INT, TestName NVARCHAR(200), Phase NVARCHAR(50),
    Status   NVARCHAR(10), Detail NVARCHAR(MAX)
);
GO

CREATE OR ALTER PROCEDURE dbo.tlift_test_runner
    @TestID INT, @TestName NVARCHAR(200),
    @ProcedureName NVARCHAR(128), @ProcedureNameNew NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @dynsql NVARCHAR(MAX), @err NVARCHAR(MAX);

    BEGIN TRY
        EXEC [TLift_Engine].dbo.sp_tlift
            @DatabaseName = 'TLift_TestDB', @SchemaName = 'dbo',
            @ProcedureName = @ProcedureName,
            @ProcedureNameNew = @ProcedureNameNew,
            @Result = @dynsql OUTPUT;
        IF LEN(@dynsql) > 0
            INSERT INTO dbo.TestResults VALUES (@TestID, @TestName, 'RENDER', 'PASS',
                'Rendered ' + CAST(LEN(@dynsql) AS VARCHAR) + ' chars');
        ELSE BEGIN
            INSERT INTO dbo.TestResults VALUES (@TestID, @TestName, 'RENDER', 'FAIL', 'Empty output');
            RETURN;
        END
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.TestResults VALUES (@TestID, @TestName, 'RENDER', 'FAIL', ERROR_MESSAGE());
        RETURN;
    END CATCH

    BEGIN TRY
        -- Split on top-level GO lines only, ignoring GO inside strings/comments.
        DECLARE @batch NVARCHAR(MAX) = N'';
        DECLARE @line NVARCHAR(MAX);
        DECLARE @cursorPos INT = 1;
        DECLARE @lineEnd INT;
        DECLARE @trimmedLine NVARCHAR(MAX);
        DECLARE @inSingleQuote BIT = 0;
        DECLARE @inBlockComment BIT = 0;
        DECLARE @scanPos INT;
        DECLARE @scanLen INT;
        DECLARE @ch NCHAR(1);
        DECLARE @nextCh NCHAR(1);

        WHILE @cursorPos <= LEN(@dynsql)
        BEGIN
            SET @lineEnd = CHARINDEX(CHAR(10), @dynsql, @cursorPos);
            IF @lineEnd = 0
            BEGIN
                SET @line = SUBSTRING(@dynsql, @cursorPos, LEN(@dynsql) - @cursorPos + 1);
                SET @cursorPos = LEN(@dynsql) + 1;
            END
            ELSE
            BEGIN
                SET @line = SUBSTRING(@dynsql, @cursorPos, @lineEnd - @cursorPos + 1);
                SET @cursorPos = @lineEnd + 1;
            END

            SET @trimmedLine = LTRIM(RTRIM(REPLACE(REPLACE(@line, CHAR(13), ''), CHAR(10), '')));

            IF @inSingleQuote = 0 AND @inBlockComment = 0 AND UPPER(@trimmedLine) = 'GO'
            BEGIN
                IF LEN(LTRIM(RTRIM(@batch))) > 0
                BEGIN
                    SET @batch = REPLACE(@batch, 'create   procedure', 'CREATE OR ALTER PROCEDURE');
                    SET @batch = REPLACE(@batch, 'create  procedure',  'CREATE OR ALTER PROCEDURE');
                    SET @batch = REPLACE(@batch, 'create procedure',   'CREATE OR ALTER PROCEDURE');
                    SET @batch = REPLACE(@batch, 'CREATE  PROCEDURE',  'CREATE OR ALTER PROCEDURE');
                    SET @batch = REPLACE(@batch, 'CREATE   PROCEDURE', 'CREATE OR ALTER PROCEDURE');
                    SET @batch = REPLACE(@batch, 'CREATE OR ALTER OR ALTER', 'CREATE OR ALTER');
                    EXEC sp_executesql @batch;
                    SET @batch = N'';
                END
            END
            ELSE
            BEGIN
                SET @batch = @batch + @line;

                SET @scanPos = 1;
                SET @scanLen = LEN(@line);

                WHILE @scanPos <= @scanLen
                BEGIN
                    SET @ch = SUBSTRING(@line, @scanPos, 1);
                    SET @nextCh = SUBSTRING(@line, @scanPos + 1, 1);

                    IF @inSingleQuote = 1
                    BEGIN
                        IF @ch = ''''
                        BEGIN
                            IF @nextCh = ''''
                                SET @scanPos = @scanPos + 2;
                            ELSE
                            BEGIN
                                SET @inSingleQuote = 0;
                                SET @scanPos = @scanPos + 1;
                            END
                        END
                        ELSE
                            SET @scanPos = @scanPos + 1;
                    END
                    ELSE IF @inBlockComment = 1
                    BEGIN
                        IF @ch = '*' AND @nextCh = '/'
                        BEGIN
                            SET @inBlockComment = 0;
                            SET @scanPos = @scanPos + 2;
                        END
                        ELSE
                            SET @scanPos = @scanPos + 1;
                    END
                    ELSE IF @ch = '-' AND @nextCh = '-'
                        BREAK;
                    ELSE IF @ch = '/' AND @nextCh = '*'
                    BEGIN
                        SET @inBlockComment = 1;
                        SET @scanPos = @scanPos + 2;
                    END
                    ELSE IF @ch = ''''
                    BEGIN
                        SET @inSingleQuote = 1;
                        SET @scanPos = @scanPos + 1;
                    END
                    ELSE
                        SET @scanPos = @scanPos + 1;
                END
            END
        END

        IF LEN(LTRIM(RTRIM(@batch))) > 0
        BEGIN
            SET @batch = REPLACE(@batch, 'create   procedure', 'CREATE OR ALTER PROCEDURE');
            SET @batch = REPLACE(@batch, 'create  procedure',  'CREATE OR ALTER PROCEDURE');
            SET @batch = REPLACE(@batch, 'create procedure',   'CREATE OR ALTER PROCEDURE');
            SET @batch = REPLACE(@batch, 'CREATE  PROCEDURE',  'CREATE OR ALTER PROCEDURE');
            SET @batch = REPLACE(@batch, 'CREATE   PROCEDURE', 'CREATE OR ALTER PROCEDURE');
            SET @batch = REPLACE(@batch, 'CREATE OR ALTER OR ALTER', 'CREATE OR ALTER');
            EXEC sp_executesql @batch;
        END

        INSERT INTO dbo.TestResults VALUES (@TestID, @TestName, 'DEPLOY', 'PASS',
            'Procedure ' + @ProcedureNameNew + ' created');
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.TestResults VALUES (@TestID, @TestName, 'DEPLOY', 'FAIL', ERROR_MESSAGE());
        RETURN;
    END CATCH
END;
GO

EXEC dbo.tlift_test_runner  1, 'Single param',       'test01_single_param',      'rendered_test01';
EXEC dbo.tlift_test_runner  2, 'Two params',          'test02_two_params',        'rendered_test02';
EXEC dbo.tlift_test_runner  3, 'Three params',        'test03_three_params',      'rendered_test03';
EXEC dbo.tlift_test_runner  4, 'Variables',           'test04_variables',         'rendered_test04';
EXEC dbo.tlift_test_runner  5, 'Block condition',     'test05_block_condition',   'rendered_test05';
EXEC dbo.tlift_test_runner  6, 'Named section',       'test06_named_section',     'rendered_test06';
EXEC dbo.tlift_test_runner  7, 'Mixed types',         'test07_mixed_types',       'rendered_test07';
EXEC dbo.tlift_test_runner  8, 'JOIN query',          'test08_join_query',        'rendered_test08';
EXEC dbo.tlift_test_runner  9, 'No directives',       'test09_no_directives',     'rendered_test09';
EXEC dbo.tlift_test_runner 10, 'Comment directive',   'test10_comment_directive', 'rendered_test10';
EXEC dbo.tlift_test_runner 11, 'ELSE directive',      'test11_else_directive',    'rendered_test11';
EXEC dbo.tlift_test_runner 12, 'ELSEIF directive',    'test12_elseif_directive',  'rendered_test12';
EXEC dbo.tlift_test_runner 13, 'Wrapper',             'test13_wrapper',           'rendered_test13';
EXEC dbo.tlift_test_runner 14, 'Block IF simple',     'test14_block_if_simple_filter', 'rendered_test14';
EXEC dbo.tlift_test_runner 15, 'Block IF catchall',   'test15_block_if_catchall',      'rendered_test15';
EXEC dbo.tlift_test_runner 16, 'Named condition',     'test16_named_condition',                  'rendered_test16';
EXEC dbo.tlift_test_runner 17, 'Named cond multi-sec','test17_named_condition_multi_section',    'rendered_test17';
EXEC dbo.tlift_test_runner 18, 'Block removal',       'test18_block_removal',                    'rendered_test18';
EXEC dbo.tlift_test_runner 19, 'nvarchar param len',   'test19_nvarchar_params',                  'rendered_test19';
EXEC dbo.tlift_test_runner 20, 'Long param buckets',   'test20_long_param_buckets',               'rendered_test20';
EXEC dbo.tlift_test_runner 21, 'String literal marker','test21_string_literal_directive_marker',   'rendered_test21';
EXEC dbo.tlift_test_runner 22, 'Quoted dyn literal',   'test22_quoted_literal_dynamic_section',    'rendered_test22';
EXEC dbo.tlift_test_runner 23, 'GO in string literal', 'test23_go_in_multiline_string',            'rendered_test23';
GO

-- Execution phase
BEGIN TRY EXEC dbo.rendered_test01 @CustomerID=1; EXEC dbo.rendered_test01 @CustomerID=NULL;
    INSERT INTO dbo.TestResults VALUES (1,'Single param','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (1,'Single param','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test02 @ProductID=1,@MinQuantity=NULL; EXEC dbo.rendered_test02 @ProductID=NULL,@MinQuantity=5; EXEC dbo.rendered_test02 @ProductID=1,@MinQuantity=3; EXEC dbo.rendered_test02;
    INSERT INTO dbo.TestResults VALUES (2,'Two params','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (2,'Two params','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test03 @CustomerID=1; EXEC dbo.rendered_test03 @Status='Shipped'; EXEC dbo.rendered_test03 @OrderDateFrom='2025-06-01'; EXEC dbo.rendered_test03;
    INSERT INTO dbo.TestResults VALUES (3,'Three params','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (3,'Three params','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test04 @Category='Electronics'; EXEC dbo.rendered_test04 @Category=NULL;
    INSERT INTO dbo.TestResults VALUES (4,'Variables','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (4,'Variables','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test05 @CustomerID=1,@IncludeOrderDetails=0; EXEC dbo.rendered_test05 @CustomerID=1,@IncludeOrderDetails=1; EXEC dbo.rendered_test05;
    INSERT INTO dbo.TestResults VALUES (5,'Block condition','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (5,'Block condition','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test06 @OrderID=1; EXEC dbo.rendered_test06 @OrderID=NULL;
    INSERT INTO dbo.TestResults VALUES (6,'Named section','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (6,'Named section','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test07 @City='Berlin'; EXEC dbo.rendered_test07 @CreatedAfter='2025-06-01'; EXEC dbo.rendered_test07 @Country='Germany'; EXEC dbo.rendered_test07;
    INSERT INTO dbo.TestResults VALUES (7,'Mixed types','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (7,'Mixed types','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test08 @CustomerID=1; EXEC dbo.rendered_test08 @ProductID=1; EXEC dbo.rendered_test08 @CustomerID=1,@ProductID=1; EXEC dbo.rendered_test08;
    INSERT INTO dbo.TestResults VALUES (8,'JOIN query','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (8,'JOIN query','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test09 @CustomerID=1;
    INSERT INTO dbo.TestResults VALUES (9,'No directives','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (9,'No directives','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test10 @OrderID=1; EXEC dbo.rendered_test10 @OrderID=NULL;
    INSERT INTO dbo.TestResults VALUES (10,'Comment directive','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (10,'Comment directive','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test11 @CustomerID=1,@IncludeInactive=0; EXEC dbo.rendered_test11 @CustomerID=1,@IncludeInactive=1; EXEC dbo.rendered_test11 @CustomerID=NULL,@IncludeInactive=0;
    INSERT INTO dbo.TestResults VALUES (11,'ELSE directive','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (11,'ELSE directive','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test12 @SortMode=0; EXEC dbo.rendered_test12 @SortMode=1; EXEC dbo.rendered_test12 @SortMode=2;
    INSERT INTO dbo.TestResults VALUES (12,'ELSEIF directive','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (12,'ELSEIF directive','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test13 @CustomerID=1, @City=NULL; EXEC dbo.rendered_test13 @CustomerID=NULL, @City='Berlin'; EXEC dbo.rendered_test13;
    INSERT INTO dbo.TestResults VALUES (13,'Wrapper','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (13,'Wrapper','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test14 @CustomerID=1; EXEC dbo.rendered_test14 @CustomerID=NULL;
    INSERT INTO dbo.TestResults VALUES (14,'Block IF simple','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (14,'Block IF simple','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test15 @CustomerID=1,@City=NULL; EXEC dbo.rendered_test15 @CustomerID=NULL,@City='Berlin'; EXEC dbo.rendered_test15 @CustomerID=1,@City='Berlin'; EXEC dbo.rendered_test15;
    INSERT INTO dbo.TestResults VALUES (15,'Block IF catchall','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (15,'Block IF catchall','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test16 @CustomerID=1; EXEC dbo.rendered_test16 @CustomerID=NULL;
    INSERT INTO dbo.TestResults VALUES (16,'Named condition','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (16,'Named condition','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test17 @CustomerID=1,@IncludeDetails=0; EXEC dbo.rendered_test17 @CustomerID=1,@IncludeDetails=1; EXEC dbo.rendered_test17 @CustomerID=NULL,@IncludeDetails=1; EXEC dbo.rendered_test17 @CustomerID=NULL,@IncludeDetails=0;
    INSERT INTO dbo.TestResults VALUES (17,'Named cond multi-sec','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (17,'Named cond multi-sec','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test18 @CustomerID=1; EXEC dbo.rendered_test18 @CustomerID=NULL;
    INSERT INTO dbo.TestResults VALUES (18,'Block removal','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (18,'Block removal','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test19 @SearchName=N'Smith'; EXEC dbo.rendered_test19 @CategoryCode=N'ELEC'; EXEC dbo.rendered_test19 @SearchName=N'Smith',@CategoryCode=N'ELEC'; EXEC dbo.rendered_test19;
    INSERT INTO dbo.TestResults VALUES (19,'nvarchar param len','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (19,'nvarchar param len','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test20 @VeryLongParameterName=1; EXEC dbo.rendered_test20 @VeryLongParameterName=NULL;
    INSERT INTO dbo.TestResults VALUES (20,'Long param buckets','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (20,'Long param buckets','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test21;
    INSERT INTO dbo.TestResults VALUES (21,'String literal marker','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (21,'String literal marker','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test22;
    INSERT INTO dbo.TestResults VALUES (22,'Quoted dyn literal','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (22,'Quoted dyn literal','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH

BEGIN TRY EXEC dbo.rendered_test23;
    INSERT INTO dbo.TestResults VALUES (23,'GO in string literal','EXECUTE','PASS','OK');
END TRY BEGIN CATCH INSERT INTO dbo.TestResults VALUES (23,'GO in string literal','EXECUTE','FAIL',ERROR_MESSAGE()); END CATCH
GO

DROP PROCEDURE IF EXISTS dbo.tlift_test_runner;
GO
