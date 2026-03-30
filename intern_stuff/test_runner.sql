/*=====================================================================
  T-Lift Test Suite — Test Runner
  
  This script:
    1. Runs sp_tlift against each test procedure
    2. Captures the rendered output
    3. Attempts to CREATE the rendered procedure in TLift_TestDB
    4. Executes the rendered procedure with various parameter combos
    5. Reports PASS / FAIL for each test
  
  Prerequisites:
    - test_setup.sql has been executed
    - sp_tlift.sql has been installed into TLift_Engine
    - test_procedures.sql has been executed
=====================================================================*/

USE [TLift_TestDB];
GO

SET NOCOUNT ON;
GO

-- Results table
IF OBJECT_ID('tempdb..#TestResults') IS NOT NULL DROP TABLE #TestResults;
CREATE TABLE #TestResults (
    TestID      INT,
    TestName    NVARCHAR(200),
    Phase       NVARCHAR(50),   -- 'RENDER' or 'EXECUTE'
    Status      NVARCHAR(10),   -- 'PASS' or 'FAIL'
    Detail      NVARCHAR(MAX)
);
GO

-- ===================================================================
-- Helper: Run T-Lift and deploy the rendered procedure
-- ===================================================================
CREATE OR ALTER PROCEDURE dbo.tlift_test_runner
    @TestID INT,
    @TestName NVARCHAR(200),
    @ProcedureName NVARCHAR(128),
    @ProcedureNameNew NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @dynsql NVARCHAR(MAX);
    DECLARE @err NVARCHAR(MAX);

    -- Phase 1: RENDER
    BEGIN TRY
        EXEC [TLift_Engine].dbo.sp_tlift
            @DatabaseName = 'TLift_TestDB',
            @SchemaName = 'dbo',
            @ProcedureName = @ProcedureName,
            @ProcedureNameNew = @ProcedureNameNew,
            @Result = @dynsql OUTPUT;

        IF LEN(@dynsql) > 0
        BEGIN
            INSERT INTO #TestResults (TestID, TestName, Phase, Status, Detail)
            VALUES (@TestID, @TestName, 'RENDER', 'PASS', 
                    'Rendered ' + CAST(LEN(@dynsql) AS VARCHAR) + ' chars');
        END
        ELSE
        BEGIN
            INSERT INTO #TestResults (TestID, TestName, Phase, Status, Detail)
            VALUES (@TestID, @TestName, 'RENDER', 'FAIL', 'Empty output from sp_tlift');
            RETURN;
        END
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
        INSERT INTO #TestResults (TestID, TestName, Phase, Status, Detail)
        VALUES (@TestID, @TestName, 'RENDER', 'FAIL', @err);
        RETURN;
    END CATCH

    -- Phase 2: DEPLOY — create the rendered procedure
    BEGIN TRY
        -- Ensure we use CREATE OR ALTER so re-runs work
        SET @dynsql = REPLACE(@dynsql, 'create   procedure', 'CREATE OR ALTER PROCEDURE');
        SET @dynsql = REPLACE(@dynsql, 'create  procedure', 'CREATE OR ALTER PROCEDURE');
        SET @dynsql = REPLACE(@dynsql, 'create procedure', 'CREATE OR ALTER PROCEDURE');
        SET @dynsql = REPLACE(@dynsql, 'CREATE  PROCEDURE', 'CREATE OR ALTER PROCEDURE');
        SET @dynsql = REPLACE(@dynsql, 'CREATE   PROCEDURE', 'CREATE OR ALTER PROCEDURE');
        -- Also handle "create or alter" already present (avoid double)
        SET @dynsql = REPLACE(@dynsql, 'CREATE OR ALTER OR ALTER', 'CREATE OR ALTER');

        EXEC sp_executesql @dynsql;

        INSERT INTO #TestResults (TestID, TestName, Phase, Status, Detail)
        VALUES (@TestID, @TestName, 'DEPLOY', 'PASS', 'Procedure ' + @ProcedureNameNew + ' created');
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
        INSERT INTO #TestResults (TestID, TestName, Phase, Status, Detail)
        VALUES (@TestID, @TestName, 'DEPLOY', 'FAIL', @err);

        -- Print the rendered SQL for debugging
        PRINT '=== FAILED DEPLOY for ' + @TestName + ' ===';
        PRINT @dynsql;
        PRINT '=== END ===';
        RETURN;
    END CATCH
END;
GO

-- ===================================================================
-- Run T-Lift for each test procedure
-- ===================================================================

-- Test 1: Simple single-parameter
EXEC dbo.tlift_test_runner 1, 'Single param NULL check', 'test01_single_param', 'rendered_test01';

-- Test 2: Two parameters with AND
EXEC dbo.tlift_test_runner 2, 'Two params with AND', 'test02_two_params', 'rendered_test02';

-- Test 3: Three parameters
EXEC dbo.tlift_test_runner 3, 'Three params AND chain', 'test03_three_params', 'rendered_test03';

-- Test 4: Variables
EXEC dbo.tlift_test_runner 4, 'Variables var/usevar', 'test04_variables', 'rendered_test04';

-- Test 5: Block conditions
EXEC dbo.tlift_test_runner 5, 'Block condition {if/}', 'test05_block_condition', 'rendered_test05';

-- Test 6: Named section
EXEC dbo.tlift_test_runner 6, 'Named section label', 'test06_named_section', 'rendered_test06';

-- Test 7: Mixed data types
EXEC dbo.tlift_test_runner 7, 'Mixed types (varchar/date)', 'test07_mixed_types', 'rendered_test07';

-- Test 8: JOIN query
EXEC dbo.tlift_test_runner 8, 'JOIN with filters', 'test08_join_query', 'rendered_test08';

-- Test 9: No directives (passthrough)
EXEC dbo.tlift_test_runner 9, 'No directives baseline', 'test09_no_directives', 'rendered_test09';

-- Test 10: Comment directive
EXEC dbo.tlift_test_runner 10, 'Comment directive --#c', 'test10_comment_directive', 'rendered_test10';

-- Test 11: ELSE directive
EXEC dbo.tlift_test_runner 11, 'ELSE directive --#else', 'test11_else_directive', 'rendered_test11';

-- Test 12: ELSEIF directive
EXEC dbo.tlift_test_runner 12, 'ELSEIF directive --#{elseif', 'test12_elseif_directive', 'rendered_test12';
GO

-- ===================================================================
-- Phase 3: EXECUTE — run rendered procedures with various params
-- ===================================================================
PRINT '';
PRINT '=== Phase 3: Execution tests ===';
PRINT '';

-- Test 1 execution
BEGIN TRY
    EXEC dbo.rendered_test01 @CustomerID = 1;
    EXEC dbo.rendered_test01 @CustomerID = NULL;
    INSERT INTO #TestResults VALUES (1, 'Single param NULL check', 'EXECUTE', 'PASS', 'Both calls succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (1, 'Single param NULL check', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 2 execution
BEGIN TRY
    EXEC dbo.rendered_test02 @ProductID = 1, @MinQuantity = NULL;
    EXEC dbo.rendered_test02 @ProductID = NULL, @MinQuantity = 5;
    EXEC dbo.rendered_test02 @ProductID = 1, @MinQuantity = 3;
    EXEC dbo.rendered_test02;
    INSERT INTO #TestResults VALUES (2, 'Two params with AND', 'EXECUTE', 'PASS', 'All 4 combos succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (2, 'Two params with AND', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 3 execution
BEGIN TRY
    EXEC dbo.rendered_test03 @CustomerID = 1;
    EXEC dbo.rendered_test03 @Status = 'Shipped';
    EXEC dbo.rendered_test03 @OrderDateFrom = '2025-06-01';
    EXEC dbo.rendered_test03 @CustomerID = 1, @Status = 'Shipped';
    EXEC dbo.rendered_test03 @CustomerID = 1, @OrderDateFrom = '2025-01-01';
    EXEC dbo.rendered_test03 @Status = 'Shipped', @OrderDateFrom = '2025-01-01';
    EXEC dbo.rendered_test03 @CustomerID = 1, @Status = 'Shipped', @OrderDateFrom = '2025-01-01';
    EXEC dbo.rendered_test03;
    INSERT INTO #TestResults VALUES (3, 'Three params AND chain', 'EXECUTE', 'PASS', 'All 8 combos succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (3, 'Three params AND chain', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 4 execution
BEGIN TRY
    EXEC dbo.rendered_test04 @Category = 'Electronics';
    EXEC dbo.rendered_test04 @Category = NULL;
    INSERT INTO #TestResults VALUES (4, 'Variables var/usevar', 'EXECUTE', 'PASS', 'Both calls succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (4, 'Variables var/usevar', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 5 execution
BEGIN TRY
    EXEC dbo.rendered_test05 @CustomerID = 1, @IncludeOrderDetails = 0;
    EXEC dbo.rendered_test05 @CustomerID = 1, @IncludeOrderDetails = 1;
    EXEC dbo.rendered_test05;
    INSERT INTO #TestResults VALUES (5, 'Block condition {if/}', 'EXECUTE', 'PASS', 'All 3 combos succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (5, 'Block condition {if/}', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 6 execution
BEGIN TRY
    EXEC dbo.rendered_test06 @OrderID = 1;
    EXEC dbo.rendered_test06 @OrderID = NULL;
    INSERT INTO #TestResults VALUES (6, 'Named section label', 'EXECUTE', 'PASS', 'Both calls succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (6, 'Named section label', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 7 execution
BEGIN TRY
    EXEC dbo.rendered_test07 @City = 'Berlin';
    EXEC dbo.rendered_test07 @CreatedAfter = '2025-06-01';
    EXEC dbo.rendered_test07 @Country = 'Germany';
    EXEC dbo.rendered_test07 @City = 'Berlin', @Country = 'Germany';
    EXEC dbo.rendered_test07 @City = 'Berlin', @CreatedAfter = '2025-06-01';
    EXEC dbo.rendered_test07 @CreatedAfter = '2025-06-01', @Country = 'Germany';
    EXEC dbo.rendered_test07 @City = 'Berlin', @CreatedAfter = '2025-06-01', @Country = 'Germany';
    EXEC dbo.rendered_test07;
    INSERT INTO #TestResults VALUES (7, 'Mixed types (varchar/date)', 'EXECUTE', 'PASS', 'All 8 combos succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (7, 'Mixed types (varchar/date)', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 8 execution
BEGIN TRY
    EXEC dbo.rendered_test08 @CustomerID = 1;
    EXEC dbo.rendered_test08 @ProductID = 1;
    EXEC dbo.rendered_test08 @CustomerID = 1, @ProductID = 1;
    EXEC dbo.rendered_test08;
    INSERT INTO #TestResults VALUES (8, 'JOIN with filters', 'EXECUTE', 'PASS', 'All 4 combos succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (8, 'JOIN with filters', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 9 execution
BEGIN TRY
    EXEC dbo.rendered_test09 @CustomerID = 1;
    INSERT INTO #TestResults VALUES (9, 'No directives baseline', 'EXECUTE', 'PASS', 'Call succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (9, 'No directives baseline', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 10 execution
BEGIN TRY
    EXEC dbo.rendered_test10 @OrderID = 1;
    EXEC dbo.rendered_test10 @OrderID = NULL;
    INSERT INTO #TestResults VALUES (10, 'Comment directive --#c', 'EXECUTE', 'PASS', 'Both calls succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (10, 'Comment directive --#c', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 11 execution
BEGIN TRY
    EXEC dbo.rendered_test11 @CustomerID = 1, @IncludeInactive = 0;
    EXEC dbo.rendered_test11 @CustomerID = 1, @IncludeInactive = 1;
    EXEC dbo.rendered_test11 @CustomerID = NULL, @IncludeInactive = 0;
    INSERT INTO #TestResults VALUES (11, 'ELSE directive --#else', 'EXECUTE', 'PASS', 'All 3 combos succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (11, 'ELSE directive --#else', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH

-- Test 12 execution
BEGIN TRY
    EXEC dbo.rendered_test12 @SortMode = 0;
    EXEC dbo.rendered_test12 @SortMode = 1;
    EXEC dbo.rendered_test12 @SortMode = 2;
    INSERT INTO #TestResults VALUES (12, 'ELSEIF directive --#{elseif', 'EXECUTE', 'PASS', 'All 3 SortMode values succeeded');
END TRY BEGIN CATCH
    INSERT INTO #TestResults VALUES (12, 'ELSEIF directive --#{elseif', 'EXECUTE', 'FAIL', ERROR_MESSAGE());
END CATCH
GO

-- ===================================================================
-- Final Report
-- ===================================================================
PRINT '';
PRINT '====================================================';
PRINT '  T-LIFT TEST SUITE — RESULTS';
PRINT '====================================================';
PRINT '';

SELECT 
    TestID,
    TestName,
    Phase,
    Status,
    Detail
FROM #TestResults
ORDER BY TestID, 
    CASE Phase WHEN 'RENDER' THEN 1 WHEN 'DEPLOY' THEN 2 WHEN 'EXECUTE' THEN 3 END;

-- Summary
SELECT 
    Phase,
    COUNT(CASE WHEN Status = 'PASS' THEN 1 END) AS Passed,
    COUNT(CASE WHEN Status = 'FAIL' THEN 1 END) AS Failed,
    COUNT(*) AS Total
FROM #TestResults
GROUP BY Phase
ORDER BY CASE Phase WHEN 'RENDER' THEN 1 WHEN 'DEPLOY' THEN 2 WHEN 'EXECUTE' THEN 3 END;

DECLARE @failCount INT = (SELECT COUNT(*) FROM #TestResults WHERE Status = 'FAIL');
IF @failCount = 0
    PRINT 'ALL TESTS PASSED';
ELSE
    PRINT CAST(@failCount AS VARCHAR) + ' TEST(S) FAILED';

-- Clean up helper
DROP PROCEDURE IF EXISTS dbo.tlift_test_runner;
GO
