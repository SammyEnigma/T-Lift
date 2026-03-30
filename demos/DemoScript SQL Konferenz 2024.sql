/*=====================================================================
  T-Lift Demo Script — current install/execution model

  Prerequisites:
	1. Run intern_stuff/test_setup.sql to create TLift_Engine and TLift_TestDB.
	2. Execute sp_tlift.sql in TLift_Engine.

  This demo uses the same split as the README and internal tests:
	- TLift_Engine hosts dbo.sp_tlift
	- TLift_TestDB hosts the source and rendered procedures
=====================================================================*/

USE [TLift_TestDB];
GO

DROP PROCEDURE IF EXISTS dbo.tlift_demo_search_orders;
DROP PROCEDURE IF EXISTS dbo.tlift_demo_search_orders_rendered;
GO

CREATE OR ALTER PROCEDURE dbo.tlift_demo_search_orders
	@CustomerID INT = NULL,
	@Status NVARCHAR(20) = NULL
AS
										--#[ DemoSearchOrders
SELECT o.OrderID, o.CustomerID, o.OrderDate, o.Status, o.TotalAmount
FROM dbo.Orders o
WHERE                                   --#if @CustomerID IS NOT NULL OR @Status IS NOT NULL
(                                       --#-
@CustomerID IS NULL OR                  --#-
o.CustomerID = @CustomerID              --#if @CustomerID IS NOT NULL
)                                       --#-
AND                                     --#if @CustomerID IS NOT NULL AND @Status IS NOT NULL
(                                       --#-
@Status IS NULL OR                      --#-
o.Status = @Status                      --#if @Status IS NOT NULL
)                                       --#-
ORDER BY o.OrderDate DESC               --#c
										--#]
GO

PRINT 'Source procedure — still valid plain T-SQL';
EXEC dbo.tlift_demo_search_orders @CustomerID = 1;
EXEC dbo.tlift_demo_search_orders @Status = N'Shipped';
EXEC dbo.tlift_demo_search_orders;
GO

DECLARE @dynsql NVARCHAR(MAX);

EXEC [TLift_Engine].dbo.sp_tlift
	@DatabaseName = 'TLift_TestDB',
	@SchemaName = 'dbo',
	@ProcedureName = 'tlift_demo_search_orders',
	@ProcedureNameNew = 'tlift_demo_search_orders_rendered',
	@Result = @dynsql OUTPUT;

SELECT @dynsql AS RenderedProcedure;

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
GO

PRINT 'Rendered procedure — now backed by dynamic SQL';
EXEC dbo.tlift_demo_search_orders_rendered @CustomerID = 1;
EXEC dbo.tlift_demo_search_orders_rendered @Status = N'Shipped';
EXEC dbo.tlift_demo_search_orders_rendered;
GO

SELECT cplan.usecounts, qtext.text, qplan.query_plan
FROM sys.dm_exec_cached_plans AS cplan
CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS qtext
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qplan
WHERE qtext.text LIKE '%/*DemoSearchOrders*/%'
  AND qtext.text NOT LIKE '%dm_exec_cached_plans%'
ORDER BY cplan.usecounts DESC;
GO