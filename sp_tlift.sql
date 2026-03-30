IF OBJECT_ID('dbo.sp_tlift') IS NULL
	EXEC ('CREATE PROCEDURE dbo.sp_tlift AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_tlift 
	@DatabaseName NVARCHAR(128) = NULL,
	@SchemaName NVARCHAR(128) = 'dbo',
	@ProcedureName NVARCHAR(128) = NULL,
	@ProcedureNameNew NVARCHAR(128) = 'tlift_version_of_your_sproc', -- to make our lives easier.
	@debugLevel INT = 0,
	@includeOurComments BIT = 0,
	@verboseMode BIT = 0,
	@validateOnly BIT = 0,
	@includeDebug BIT = 1,
	@help BIT = 0,
	@Result NVARCHAR(MAX) = N'' OUTPUT
WITH RECOMPILE
AS
SET XACT_ABORT, NOCOUNT ON;

-- I'm curious how long it will take!
DECLARE @StartTime DATETIME2;
DECLARE @EndTime DATETIME2;
DECLARE @ExecutionTime INT;

SET @StartTime = SYSUTCDATETIME();

DECLARE @Version CHAR(5) = '01.01'

PRINT ''
PRINT 'Welcome to T-Lift Version '+ @Version
PRINT ''
PRINT 'Main Reposiory for T-Lift is https://github.com/sasloz/T-Lift (There you can find also more info about the project.)'
PRINT ''
PRINT 'Maybe you guessed it already, but you can get help with ''exec dbo.sp_tlift @help = 1'''
PRINT ''

-- Help section
IF @help = 1
BEGIN
	PRINT 'Help:'
	PRINT ''
	PRINT 'T-Lift is a T-SQL precompiler that simplifies plan optimization in SQL Server.' 
	PRINT 'It maintains familiar development practices while automatically generating '
	PRINT 'optimized stored procedures using straightforward directives in T-SQL comments.'
	PRINT 'Enhance performance without sacrificing developer comfort.'
	PRINT ''
	PRINT 'Still there? Okay, how to archive this?'
	PRINT ''
	PRINT 'Basic Syntax:'
	PRINT ''
	PRINT 'DECLARE @dynsql NVARCHAR(MAX);'
	PRINT 'EXEC dbo.sp_tlift' 
    PRINT '  @DatabaseName = ''YourDatabase'', '
    PRINT '  @SchemaName = ''dbo'', '
    PRINT '  @ProcedureName = ''YourProcedure'', '
    PRINT '  @ProcedureNameNew = ''NewProcedure'', '
	PRINT '  @validateOnly = 0,  -- Set to 1 to validate without rendering'
	PRINT '  @Result = @dynsql OUTPUT;'
	PRINT ''
	PRINT 'Traditional methods of using dynamic T-SQL often involve tedious coding practices'
	PRINT 'that disrupt the development flow. T-Lift hopes to simplifies this by automatically generating'
	PRINT '(efficient) T-SQL from your existing stored procedures, guided by simple directives' 
	PRINT 'embedded in T-SQL comments.'
	PRINT ''
	PRINT 'In short: You can use SSMS as you are used to and decorate your T-SQL statements with comments.'
	PRINT ''
	PRINT 'Intrigued? Let''s go further.'
	PRINT ''
	PRINT 'So, the basic idea of T-Lift is to use dynamic T-SQL to render dynamic T-SQL. (Don''t panic!)'
	PRINT 'T-Lift will generate (we call this render) a new version of your already existing procedure, but now with dynamic T-SQL parts included.'
	PRINT ''
	PRINT 'Supported directives:'
	PRINT ''
	PRINT '''--#['' <- Opens a dynamic SQL Area'
	PRINT '''--#]'' <- Closes a dynamic SQL Area'
	PRINT ''
	PRINT '''--#IF'' <- Inside a dynamic SQL Area you can use conditions to control if this very T-SQL should be rendered.'
	PRINT '''--#-''  <-  We don''t need this line in a dynamic T-SQL scenario anymore. Get rid of it.' 
	PRINT '''--#else'' <- Inside a block condition (--#{if / --#}), provides an ELSE branch.'
	PRINT '''--#{elseif'' <- Inside a block condition, provides an ELSE IF branch with a new condition.'
	PRINT '''--#recompile'' <- Adds OPTION(RECOMPILE) to the dynamic SQL execution.'
	PRINT '''--#define <name> = <condition>'' <- Define a named condition for reuse in --#if / --#{if / --#{elseif.'
	PRINT '''--#{-'' <- Opens a removal block (all lines inside are treated as --#- and commented out).'
	PRINT '''--#-}'' <- Closes a removal block.'
	PRINT ''
	PRINT 'Wrapper procedure generation (splits plan cache per parameter pattern):'
	PRINT '''--#wrapper'' <- Enables wrapper generation mode.'
	PRINT '''--#branch <suffix> <condition>'' <- Defines a child branch.'
	PRINT '''--#branch-default <suffix>'' <- Default fallback child.'
	PRINT ''
	PRINT 'Here an example: '
	PRINT ''
	PRINT 'CREATE OR ALTER PROCEDURE tlift_demo_very_simple3 '
	PRINT '@id int = null,'
	PRINT '@orderQty int = null'
	PRINT 'AS'
	PRINT '						--#[ simple3'
	PRINT 'SELECT *'
	PRINT 'FROM sales.SalesOrderDetail sod '
	PRINT 'WHERE						--#if @id IS NOT NULL OR @orderQty IS NOT NULL'
	PRINT '(							--#-'
	PRINT '@id IS NULL or				--#-'
	PRINT '@id = sod.ProductID			--#if @id IS NOT NULL'
	PRINT ')							--#-'
	PRINT 'and							--#if @id IS NOT NULL AND @orderQty IS NOT NULL'
	PRINT '(@orderQty IS NULL OR		--#-'
	PRINT 'sod.OrderQty >= @orderQty	--#if @orderQty IS NOT NULL'
	PRINT ')							--#-'
	PRINT '						--#]'
	RETURN
END

PRINT 'Process starts'

IF NULLIF(@DatabaseName, '') IS NULL
BEGIN
	RAISERROR('@DatabaseName is missing or empty.', 16, 1);
    RETURN;
END
IF NULLIF(@SchemaName, '') IS NULL
BEGIN
	RAISERROR('@SchemaName is missing or empty.', 16, 1);
    RETURN;
END
IF NULLIF(@ProcedureName, '') IS NULL
BEGIN
	RAISERROR('@ProcedureName is missing or empty.', 16, 1);
    RETURN;
END
IF NULLIF(@ProcedureNameNew, '') IS NULL
BEGIN
	RAISERROR('@ProcedureNameNew is missing or empty.', 16, 1);
    RETURN;
END

-- TODO: use this guy here... so our users can set their own directive identifier
-- DECLARE @identifier CHAR(1) = '#'




DECLARE @SQL NVARCHAR(MAX);

-- ===================================================================
-- Step 1.1: Verify target procedure exists before processing
-- ===================================================================
DECLARE @procExists INT = 0;

SET @SQL = N'
SELECT @procExists = COUNT(*)
FROM ' + QUOTENAME(@DatabaseName) + N'.sys.objects o
INNER JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.schemas s ON o.schema_id = s.schema_id
WHERE s.name = @SchemaName
  AND o.name = @ProcedureName
  AND o.type = ''P'';
';

BEGIN TRY
	EXEC sp_executesql @SQL,
		N'@SchemaName NVARCHAR(128), @ProcedureName NVARCHAR(128), @procExists INT OUTPUT',
		@SchemaName, @ProcedureName, @procExists OUTPUT;
END TRY
BEGIN CATCH
	DECLARE @existsErr NVARCHAR(MAX) = ERROR_MESSAGE();
	RAISERROR('Failed to check procedure existence in database [%s]: %s', 16, 1, @DatabaseName, @existsErr);
	RETURN;
END CATCH

IF @procExists = 0
BEGIN
	DECLARE @errMsg NVARCHAR(500) = N'Procedure [' + @DatabaseName + N'].[' + @SchemaName + N'].[' + @ProcedureName + N'] was not found.';
	RAISERROR(@errMsg, 16, 1);
	RETURN;
END

PRINT 'Procedure found: [' + @DatabaseName + '].[' + @SchemaName + '].[' + @ProcedureName + ']';

-- ===================================================================
-- Step 1.4: TRY/CATCH wrapper for the entire processing pipeline
-- ===================================================================
BEGIN TRY

-- Create a temporary table to store the procedure text
CREATE TABLE #ProcText (
	LineNumber INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED
	,-- Creates a clustered index on LineNumber
	TEXT NVARCHAR(MAX)
	,CleanRow NVARCHAR(MAX)
	,DirectivePos INT NULL
	,Comment NVARCHAR(MAX)
	);

-- Construct the dynamic SQL
-- Step 1.3: Use STRING_SPLIT with enable_ordinal on SQL 2022+ for guaranteed line order.
-- On older versions, IDENTITY(1,1) provides ordering (works in practice but not guaranteed by docs).
DECLARE @useOrdinal BIT = 0;
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 16 -- SQL Server 2022+
	SET @useOrdinal = 1;

IF @useOrdinal = 1
BEGIN
	SET @SQL = N'
USE ' + QUOTENAME(@DatabaseName) + N';
WITH ProcDefinition AS (
    SELECT definition
    FROM sys.sql_modules sm
    INNER JOIN sys.objects o ON sm.object_id = o.object_id
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE s.name = @SchemaName
      AND o.name = @ProcedureName
      AND o.type = ''P''
)
INSERT INTO #ProcText (Text)
SELECT value+CHAR(13)+CHAR(10)
FROM ProcDefinition
CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(definition, CHAR(13), ''''), CHAR(10), CHAR(13)), CHAR(13), 1) ss
ORDER BY ss.ordinal;
';
END
ELSE
BEGIN
	SET @SQL = N'
USE ' + QUOTENAME(@DatabaseName) + N';
WITH ProcDefinition AS (
    SELECT definition
    FROM sys.sql_modules sm
    INNER JOIN sys.objects o ON sm.object_id = o.object_id
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE s.name = @SchemaName
      AND o.name = @ProcedureName
      AND o.type = ''P''
)
INSERT INTO #ProcText (Text)
SELECT value+CHAR(13)+CHAR(10)
FROM ProcDefinition
CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(definition, CHAR(13), ''''), CHAR(10), CHAR(13)), CHAR(13));
';
END

-- Execute the dynamic SQL
EXEC sp_executesql @SQL, 
    N'@SchemaName NVARCHAR(128), @ProcedureName NVARCHAR(128)', 
    @SchemaName, @ProcedureName;

PRINT 'Got the procedure text'
PRINT 'Looking for directives'

DECLARE @directiveScanLineNumber INT;
DECLARE @directiveScanText NVARCHAR(MAX);
DECLARE @directiveScanStartPos INT;
DECLARE @directiveScanQuotePos INT;
DECLARE @directiveScanTextLength INT;
DECLARE @nextDirectivePos INT;
DECLARE @directivePos INT;

SELECT @directiveScanLineNumber = MIN(LineNumber)
FROM #ProcText;

WHILE @directiveScanLineNumber IS NOT NULL
BEGIN
	SELECT @directiveScanText = TEXT
	FROM #ProcText
	WHERE LineNumber = @directiveScanLineNumber;

	SET @directivePos = NULL;
	SET @directiveScanStartPos = 1;
	SET @directiveScanTextLength = LEN(@directiveScanText);

	-- Only treat --# markers outside quoted string literals as directives.
	WHILE @directiveScanStartPos <= @directiveScanTextLength
	BEGIN
		SET @nextDirectivePos = CHARINDEX('--#', @directiveScanText, @directiveScanStartPos);
		IF @nextDirectivePos = 0
			BREAK;

		SET @directiveScanQuotePos = CHARINDEX('''', @directiveScanText, @directiveScanStartPos);
		IF @directiveScanQuotePos = 0 OR @nextDirectivePos < @directiveScanQuotePos
		BEGIN
			SET @directivePos = @nextDirectivePos;
			BREAK;
		END

		SET @directiveScanStartPos = @directiveScanQuotePos + 1;
		WHILE @directiveScanStartPos <= @directiveScanTextLength
		BEGIN
			SET @directiveScanQuotePos = CHARINDEX('''', @directiveScanText, @directiveScanStartPos);
			IF @directiveScanQuotePos = 0
			BEGIN
				SET @directiveScanStartPos = @directiveScanTextLength + 1;
				BREAK;
			END

			IF SUBSTRING(@directiveScanText, @directiveScanQuotePos + 1, 1) = ''''
				SET @directiveScanStartPos = @directiveScanQuotePos + 2;
			ELSE
			BEGIN
				SET @directiveScanStartPos = @directiveScanQuotePos + 1;
				BREAK;
			END
		END
	END

	UPDATE #ProcText
	SET DirectivePos = @directivePos
	WHERE LineNumber = @directiveScanLineNumber;

	SELECT @directiveScanLineNumber = MIN(LineNumber)
	FROM #ProcText
	WHERE LineNumber > @directiveScanLineNumber;
END

UPDATE p
SET p.CleanRow = CASE 
		WHEN p.DirectivePos IS NOT NULL
			THEN LEFT(p.TEXT, p.DirectivePos - 1) + CHAR(13) + CHAR(10)
		ELSE p.TEXT
		END
	,p.Comment = CASE 
		WHEN p.DirectivePos IS NOT NULL
			THEN LTRIM(SUBSTRING(p.TEXT, p.DirectivePos + 3, LEN(p.TEXT)))
		ELSE NULL
		END
FROM #ProcText p;

UPDATE p
SET p.Comment = CASE 
		WHEN RIGHT(p.Comment, 2) = CHAR(13) + CHAR(10)
			THEN LEFT(p.Comment, len(p.Comment) - 2)
		ELSE p.Comment
		END
FROM #ProcText p;

-- ===================================================================
-- Step 1.2: Validate matched directive brackets
-- ===================================================================
DECLARE @openBrackets INT = 0, @closeBrackets INT = 0;
DECLARE @openBlocks INT = 0, @closeBlocks INT = 0;
DECLARE @firstUnmatchedLine INT = NULL;
DECLARE @unmatchedType NVARCHAR(20) = NULL;

-- Count --#[ and --#] pairs
SELECT @openBrackets = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND LEFT(TRIM(Comment), 1) = '[';
SELECT @closeBrackets = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = ']';

-- Count --#{if and --#} pairs
SELECT @openBlocks = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND LEFT(LOWER(TRIM(Comment)), 3) = '{if';
SELECT @closeBlocks = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = '}';

IF @openBrackets <> @closeBrackets
BEGIN
	IF @openBrackets > @closeBrackets
	BEGIN
		-- Find latest --#[ without a matching --#] after it
		SELECT TOP 1 @firstUnmatchedLine = LineNumber
		FROM #ProcText WHERE Comment IS NOT NULL AND LEFT(TRIM(Comment), 1) = '['
		ORDER BY LineNumber DESC;
		SET @unmatchedType = '--#[';
	END
	ELSE
	BEGIN
		SELECT TOP 1 @firstUnmatchedLine = LineNumber
		FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = ']'
		ORDER BY LineNumber DESC;
		SET @unmatchedType = '--#]';
	END

	DECLARE @bracketErr NVARCHAR(500) = N'Unmatched ' + @unmatchedType + N' directive. Found ' 
		+ CAST(@openBrackets AS NVARCHAR) + N' opener(s) and ' 
		+ CAST(@closeBrackets AS NVARCHAR) + N' closer(s). Check near line ' 
		+ CAST(@firstUnmatchedLine AS NVARCHAR) + N'.';
	RAISERROR(@bracketErr, 16, 1);
	RETURN;
END

IF @openBlocks <> @closeBlocks
BEGIN
	IF @openBlocks > @closeBlocks
	BEGIN
		SELECT TOP 1 @firstUnmatchedLine = LineNumber
		FROM #ProcText WHERE Comment IS NOT NULL AND LEFT(LOWER(TRIM(Comment)), 3) = '{if'
		ORDER BY LineNumber DESC;
		SET @unmatchedType = '--#{if';
	END
	ELSE
	BEGIN
		SELECT TOP 1 @firstUnmatchedLine = LineNumber
		FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = '}'
		ORDER BY LineNumber DESC;
		SET @unmatchedType = '--#}';
	END

	DECLARE @blockErr NVARCHAR(500) = N'Unmatched ' + @unmatchedType + N' directive. Found ' 
		+ CAST(@openBlocks AS NVARCHAR) + N' opener(s) and ' 
		+ CAST(@closeBlocks AS NVARCHAR) + N' closer(s). Check near line ' 
		+ CAST(@firstUnmatchedLine AS NVARCHAR) + N'.';
	RAISERROR(@blockErr, 16, 1);
	RETURN;
END

-- Count --#{- and --#-} pairs
DECLARE @openRemoval INT = 0, @closeRemoval INT = 0;
SELECT @openRemoval = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = '{-';
SELECT @closeRemoval = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = '-}';

IF @openRemoval <> @closeRemoval
BEGIN
	DECLARE @removalErr NVARCHAR(500) = N'Unmatched removal block directive. Found ' 
		+ CAST(@openRemoval AS NVARCHAR) + N' --#{- opener(s) and ' 
		+ CAST(@closeRemoval AS NVARCHAR) + N' --#-} closer(s).';
	RAISERROR(@removalErr, 16, 1);
	RETURN;
END

PRINT 'Directive brackets validated'

-- ===================================================================
-- Detect unknown directives
-- ===================================================================
DECLARE @unknownDirectives NVARCHAR(MAX) = NULL;

SELECT @unknownDirectives = STRING_AGG(
	N'Line ' + CAST(LineNumber AS NVARCHAR) + N': --#' + Comment, ', '
)
FROM #ProcText
WHERE Comment IS NOT NULL
	AND LEFT(TRIM(Comment), 1) <> '['         -- --#[ opener
	AND TRIM(Comment) <> ']'                   -- --#] closer
	AND LOWER(LEFT(TRIM(Comment), 3)) <> '{if' -- --#{if block
	AND LOWER(LEFT(TRIM(Comment), 8)) <> '{elseif ' -- --#{elseif block  
	AND LOWER(TRIM(Comment)) <> '{else'        -- --#{else
	AND LOWER(TRIM(Comment)) <> 'else'         -- --#else
	AND TRIM(Comment) <> '}'                   -- --#} block closer
	AND TRIM(Comment) <> '-'                   -- --#- remove line
	AND LOWER(TRIM(Comment)) <> 'c'            -- --#c comment
	AND LOWER(LEFT(TRIM(Comment), 2)) <> 'if'  -- --#if condition
	AND LOWER(TRIM(Comment)) <> 'var'          -- --#var
	AND LOWER(LEFT(TRIM(Comment), 6)) <> 'usevar' -- --#usevar
	AND LOWER(LEFT(TRIM(Comment), 7)) <> 'buckets' -- --#buckets
	AND LOWER(TRIM(Comment)) <> 'recompile' -- --#recompile
	AND LOWER(LEFT(TRIM(Comment), 6)) <> 'define'  -- --#define
	AND TRIM(Comment) <> '{-'            -- --#{- removal block open
	AND TRIM(Comment) <> '-}'            -- --#-} removal block close
	AND LOWER(TRIM(Comment)) <> 'wrapper'   -- --#wrapper
	AND LOWER(LEFT(TRIM(Comment), 7)) <> 'branch '  -- --#branch
	AND LOWER(LEFT(TRIM(Comment), 14)) <> 'branch-default'; -- --#branch-default

IF @unknownDirectives IS NOT NULL
BEGIN
	PRINT 'WARNING: Unknown directive(s) found: ' + @unknownDirectives;
END

-- ===================================================================
-- Detect conditional directives outside dynamic SQL sections
-- ===================================================================
DECLARE @outsideConditionals NVARCHAR(MAX) = NULL;

;WITH SectionBoundaries AS (
	SELECT LineNumber, Comment,
		SUM(CASE 
			WHEN LEFT(TRIM(Comment), 1) = '[' THEN 1
			WHEN TRIM(Comment) = ']' THEN -1
			ELSE 0
		END) OVER (ORDER BY LineNumber ROWS UNBOUNDED PRECEDING) AS Depth
	FROM #ProcText
	WHERE Comment IS NOT NULL
)
SELECT @outsideConditionals = STRING_AGG(
	N'Line ' + CAST(LineNumber AS NVARCHAR) + N': --#' + Comment, ', '
)
FROM SectionBoundaries
WHERE Depth = 0
	AND (LOWER(LEFT(TRIM(Comment), 2)) = 'if' 
		OR LOWER(LEFT(TRIM(Comment), 3)) = '{if'
		OR LOWER(LEFT(TRIM(Comment), 8)) = '{elseif '
		OR LOWER(TRIM(Comment)) = 'else'
		OR LOWER(TRIM(Comment)) = '{else'
		OR TRIM(Comment) = '}'
		OR LOWER(LEFT(TRIM(Comment), 6)) = 'usevar'
		OR TRIM(Comment) = '-');

IF @outsideConditionals IS NOT NULL
BEGIN
	PRINT 'WARNING: Directive(s) found outside a dynamic SQL section (--#[ / --#]): ' + @outsideConditionals;
END

-- ===================================================================
-- Warn about unqualified table references in dynamic SQL sections
-- (Sommarskog: "always use two-part notation in dynamic SQL")
-- ===================================================================
DECLARE @unqualifiedTables NVARCHAR(MAX) = NULL;

;WITH DynSections AS (
	SELECT LineNumber, TEXT, CleanRow, Comment,
		SUM(CASE 
			WHEN Comment IS NOT NULL AND LEFT(TRIM(Comment), 1) = '[' THEN 1
			WHEN Comment IS NOT NULL AND TRIM(Comment) = ']' THEN -1
			ELSE 0
		END) OVER (ORDER BY LineNumber ROWS UNBOUNDED PRECEDING) AS Depth
	FROM #ProcText
),
TableRefs AS (
	SELECT LineNumber, LTRIM(RTRIM(CleanRow)) AS line
	FROM DynSections
	WHERE Depth > 0  -- inside a dynamic section
		AND UPPER(LTRIM(RTRIM(CleanRow))) LIKE '%FROM %'
		OR (Depth > 0 AND UPPER(LTRIM(RTRIM(CleanRow))) LIKE '%JOIN %')
)
SELECT @unqualifiedTables = STRING_AGG(
	N'Line ' + CAST(LineNumber AS NVARCHAR) + N': ' + LEFT(line, 60), '; '
)
FROM TableRefs
WHERE line NOT LIKE '%[.]%'  -- no dot = likely unqualified
	AND line NOT LIKE '%--%'  -- not a comment-only line
	AND LEN(LTRIM(RTRIM(line))) > 5;

IF @unqualifiedTables IS NOT NULL
BEGIN
	PRINT 'WARNING: Possible unqualified table reference(s) in dynamic SQL (consider schema.table): ' + @unqualifiedTables;
END

/* Getting the parameters... */
DECLARE @Parameters NVARCHAR(MAX) = '';
DECLARE @Parameters2 NVARCHAR(MAX) = '';

-- Dynamic SQL to fetch parameters of the procedure
SET @SQL = N'
SELECT 
    p.name AS ParameterName,
    t.name AS DataType,
    p.max_length AS MaxLength,
    p.precision AS Precision,
    p.scale AS Scale,
    p.is_output AS IsOutput
FROM ' + QUOTENAME(@DatabaseName) + '.sys.parameters p
INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.procedures sp ON p.object_id = sp.object_id
INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.types t ON p.user_type_id = t.user_type_id
WHERE sp.schema_id = (
select schema_id
from ' + QUOTENAME(@DatabaseName) + '.sys.schemas
where name = @SchemaName )
    AND sp.name = @ProcedureName
ORDER BY p.parameter_id;
';

-- Create a temporary table to hold the parameters 
CREATE TABLE #parameters (
	ParameterName SYSNAME
	,DataType SYSNAME
	,MaxLength SMALLINT
	,Precision TINYINT
	,Scale TINYINT
	,IsOutput BIT
	);

-- Insert the results of the parameter query into the temporary table
	INSERT INTO #parameters (
		ParameterName
		,DataType
		,MaxLength
		,Precision
		,Scale
		,IsOutput
		)
	EXEC sp_executesql @SQL
		,N'@SchemaName NVARCHAR(128), @ProcedureName NVARCHAR(128)'
		,@SchemaName
		,@ProcedureName;

-- Build the parameters string for the procedure
SELECT @Parameters = STRING_AGG(ParameterName + ' ' + DataType + CASE 
			WHEN DataType IN (
					'char'
					,'varchar'
					)
				THEN '(' + CASE 
						WHEN MaxLength = - 1
							THEN 'MAX'
						ELSE CAST(MaxLength AS VARCHAR(10))
						END + ')'
			WHEN DataType IN (
					'nchar'
					,'nvarchar'
					)
				THEN '(' + CASE 
						WHEN MaxLength = - 1
							THEN 'MAX'
						ELSE CAST(MaxLength / 2 AS VARCHAR(10))
						END + ')'
			WHEN DataType IN (
					'decimal'
					,'numeric'
					)
				THEN '(' + CAST(Precision AS VARCHAR(10)) + ',' + CAST(Scale AS VARCHAR(10)) + ')'
			ELSE ''
			END + CASE 
			WHEN IsOutput = 1
				THEN ' OUTPUT'
			ELSE ''
			END, ', ')
	,@Parameters2 = STRING_AGG(ParameterName + ' ', ', ')
FROM #parameters;

PRINT 'Got procedures parameters'

-- Catalog annotated variables
CREATE TABLE #AnnotatedVariables (
	VariableName NVARCHAR(128)
	,DataType SYSNAME
	,MaxLength SMALLINT
	,Precision TINYINT
	,Scale TINYINT
	,IsOutput BIT DEFAULT 0
	);

-- Create the temporary table #usedvars
CREATE TABLE #usedvars (VariableName NVARCHAR(128));

IF @debugLevel > 2
BEGIN
	SELECT *
	FROM #ProcText
	WHERE comment = 'var'
END

INSERT INTO #AnnotatedVariables (
	VariableName
	,DataType
	,MaxLength
	,Precision
	,Scale
	)
SELECT SUBSTRING(clean_decl, 1, CHARINDEX(' ', clean_decl) - 1) AS VariableName
	,CASE 
		WHEN CHARINDEX('(', clean_decl) > 0
			AND CHARINDEX('(', clean_decl) < COALESCE(NULLIF(CHARINDEX('=', clean_decl), 0), LEN(clean_decl) + 1)
			THEN LTRIM(SUBSTRING(clean_decl, CHARINDEX(' ', clean_decl) + 1, CHARINDEX('(', clean_decl) - CHARINDEX(' ', clean_decl) - 1))
		ELSE LTRIM(SUBSTRING(clean_decl, CHARINDEX(' ', clean_decl) + 1, CASE 
						WHEN CHARINDEX('=', clean_decl) > 0
							THEN CHARINDEX('=', clean_decl) - CHARINDEX(' ', clean_decl) - 1
						ELSE LEN(clean_decl)
						END))
		END AS DataType
	,CASE 
		WHEN CHARINDEX('(', clean_decl) > 0
			AND CHARINDEX('(', clean_decl) < COALESCE(NULLIF(CHARINDEX('=', clean_decl), 0), LEN(clean_decl) + 1)
			THEN CASE 
					WHEN CHARINDEX(',', clean_decl) > 0
						AND CHARINDEX(',', clean_decl) < COALESCE(NULLIF(CHARINDEX('=', clean_decl), 0), LEN(clean_decl) + 1)
						THEN TRY_CAST(SUBSTRING(clean_decl, CHARINDEX('(', clean_decl) + 1, CHARINDEX(',', clean_decl) - CHARINDEX('(', clean_decl) - 1) AS SMALLINT)
					ELSE TRY_CAST(SUBSTRING(clean_decl, CHARINDEX('(', clean_decl) + 1, CHARINDEX(')', clean_decl) - CHARINDEX('(', clean_decl) - 1) AS SMALLINT)
					END
		ELSE NULL
		END AS MaxLength
	,CASE 
		WHEN CHARINDEX(',', clean_decl) > 0
			AND CHARINDEX(',', clean_decl) < COALESCE(NULLIF(CHARINDEX('=', clean_decl), 0), LEN(clean_decl) + 1)
			THEN TRY_CAST(SUBSTRING(clean_decl, CHARINDEX('(', clean_decl) + 1, CHARINDEX(',', clean_decl) - CHARINDEX('(', clean_decl) - 1) AS TINYINT)
		ELSE NULL
		END AS Precision
	,CASE 
		WHEN CHARINDEX(',', clean_decl) > 0
			AND CHARINDEX(',', clean_decl) < COALESCE(NULLIF(CHARINDEX('=', clean_decl), 0), LEN(clean_decl) + 1)
			THEN TRY_CAST(SUBSTRING(clean_decl, CHARINDEX(',', clean_decl) + 1, CHARINDEX(')', clean_decl) - CHARINDEX(',', clean_decl) - 1) AS TINYINT)
		ELSE NULL
		END AS Scale
FROM (
	SELECT LTRIM(RTRIM(SUBSTRING(TEXT, CHARINDEX('@', TEXT), CHARINDEX(';', TEXT + ';') - CHARINDEX('@', TEXT)))) AS clean_decl
	FROM #ProcText
	WHERE Comment = 'var'
	) AS cleaned_declarations


PRINT 'Got marked variables'

IF @debugLevel > 2
BEGIN
	SELECT *
	FROM #AnnotatedVariables
END

IF @debugLevel > 2
BEGIN
	---- Now you can use the updated results in your normal control flow
	SELECT LineNumber
		,TEXT
		,len(TEXT)
		,CleanRow
		,Comment
		,len(trim(comment))
	FROM #ProcText;
END

-- ===================================================================
-- Validate --#usevar references match --#var declarations
-- ===================================================================
DECLARE @missingVars NVARCHAR(MAX) = NULL;

;WITH UsevarRefs AS (
	SELECT LTRIM(value) AS VariableName
	FROM #ProcText
	CROSS APPLY STRING_SPLIT(SUBSTRING(Comment, CHARINDEX('@', Comment), LEN(Comment)), ',')
	WHERE Comment IS NOT NULL AND lower(left(Comment, 6)) = 'usevar'
)
SELECT @missingVars = STRING_AGG(u.VariableName, ', ')
FROM (SELECT DISTINCT VariableName FROM UsevarRefs) u
WHERE NOT EXISTS (
	SELECT 1 FROM #AnnotatedVariables av WHERE av.VariableName = u.VariableName
);

IF @missingVars IS NOT NULL
BEGIN
	DECLARE @usevarErr NVARCHAR(500) = N'--#usevar references undeclared variable(s): ' + @missingVars 
		+ N'. Mark them with --#var first.';
	RAISERROR(@usevarErr, 16, 1);
	RETURN;
END

-- ===================================================================
-- Validation-only mode: stop here if @validateOnly = 1
-- ===================================================================
IF @validateOnly = 1
BEGIN
	PRINT 'Validation passed. No rendering performed (@validateOnly = 1).';
	SET @Result = N'';
	
	-- Clean up temp tables
	DROP TABLE #ProcText;
	DROP TABLE #parameters;
	DROP TABLE #AnnotatedVariables;
	DROP TABLE #usedvars;
	RETURN;
END

-- ===================================================================
-- Phase 3: Wrapper Procedure Generation — detect and parse
-- ===================================================================
DECLARE @wrapperMode BIT = 0;
DECLARE @branches TABLE (
	BranchOrder INT IDENTITY(1,1),
	Suffix NVARCHAR(128),
	Condition NVARCHAR(MAX),
	IsDefault BIT DEFAULT 0
);

IF EXISTS (SELECT 1 FROM #ProcText WHERE Comment IS NOT NULL AND LOWER(TRIM(Comment)) = 'wrapper')
	SET @wrapperMode = 1;

IF @wrapperMode = 1
BEGIN
	PRINT 'Wrapper generation mode enabled';

	-- Parse --#branch <suffix> <condition>
	INSERT INTO @branches (Suffix, Condition, IsDefault)
	SELECT 
		LEFT(rest, CHARINDEX(' ', rest + ' ') - 1),
		NULLIF(LTRIM(SUBSTRING(rest, CHARINDEX(' ', rest + ' '), LEN(rest) + 1)), ''),
		0
	FROM (
		SELECT LTRIM(RIGHT(TRIM(Comment), LEN(TRIM(Comment)) - 6)) AS rest, LineNumber
		FROM #ProcText 
		WHERE Comment IS NOT NULL 
			AND LOWER(LEFT(TRIM(Comment), 7)) = 'branch '
			AND LOWER(LEFT(TRIM(Comment), 14)) <> 'branch-default'
	) x
	ORDER BY LineNumber;

	-- Parse --#branch-default <suffix>
	INSERT INTO @branches (Suffix, Condition, IsDefault)
	SELECT LTRIM(RIGHT(TRIM(Comment), LEN(TRIM(Comment)) - 14)), NULL, 1
	FROM #ProcText
	WHERE Comment IS NOT NULL 
		AND LOWER(LEFT(TRIM(Comment), 14)) = 'branch-default';

	IF NOT EXISTS (SELECT 1 FROM @branches)
	BEGIN
		RAISERROR('--#wrapper specified but no --#branch or --#branch-default directives found.', 16, 1);
		RETURN;
	END

	-- Validate: non-default branches must have a condition
	IF EXISTS (SELECT 1 FROM @branches WHERE IsDefault = 0 AND (Condition IS NULL OR LEN(LTRIM(Condition)) = 0))
	BEGIN
		RAISERROR('--#branch directive must include a condition (--#branch <suffix> <condition>).', 16, 1);
		RETURN;
	END

	IF @debugLevel > 0
		SELECT * FROM @branches;
END

-- Setup Buckets feature:
DECLARE @buckets_statements TABLE (statement NVARCHAR(MAX));
DECLARE @buckets TABLE (param_name SYSNAME, valuelist NVARCHAR(MAX));

-- Named conditions (--#define)
DECLARE @conditions TABLE (
    ConditionName NVARCHAR(128),
    ConditionText NVARCHAR(MAX),
    UsedFlag BIT DEFAULT 0
);

-- Removal block state (--#{- / --#-})
DECLARE @removalBlockFlag BIT = 0

-- Condition resolution variables (declared before WHILE to avoid re-declaration)
DECLARE @resolvedCondition NVARCHAR(MAX)
DECLARE @condLookup NVARCHAR(MAX)

PRINT 'Start precompiler aka rendering loop'

-- START RENDER PROCESS "Light"... 
DECLARE @s NVARCHAR(max) = N''
DECLARE @lr CHAR(2) = CHAR(13) + CHAR(10)
DECLARE @dynSQLFlag BIT = 0
	,@firstDynSQLArea BIT = 0
	,@renameProc BIT = 0
	,@recompileFlag BIT = 0
DECLARE @LineNumber INT

SELECT @LineNumber = MIN(LineNumber)
FROM #ProcText

WHILE @LineNumber IS NOT NULL
BEGIN
	DECLARE @CleanRow NVARCHAR(MAX)
		,@Comment NVARCHAR(MAX)

	DECLARE @DynQueryName NVARCHAR(128)

	SELECT @CleanRow = TRIM(CleanRow)
		,@Comment = TRIM(Comment)
	FROM #ProcText
	WHERE LineNumber = @LineNumber

	IF @debugLevel > 0
	BEGIN
		SELECT @CleanRow
			,@Comment
			,len(@Comment)
	END

	-- Step 1.5: Only rename on the CREATE/ALTER PROCEDURE line
	IF @renameProc = 0
	BEGIN
		DECLARE @upperRow NVARCHAR(MAX) = UPPER(@CleanRow);

		IF @upperRow LIKE '%CREATE%PROCEDURE%' OR @upperRow LIKE '%ALTER%PROCEDURE%'
		BEGIN
			DECLARE @tempRow NVARCHAR(max) = @CleanRow

			SET @CleanRow = REPLACE(@CleanRow, @ProcedureName, @ProcedureNameNew)

			IF @CleanRow <> @tempRow
			BEGIN
				SET @renameProc = 1
			END
		END
	END

	IF @Comment IS NOT NULL
	BEGIN
		-- select 'a command'
		IF left(@Comment,1 ) = '['
		BEGIN
			SET @dynSQLFlag = 1;

			IF len(@Comment) > 1
				SET @DynQueryName = trim(right(@Comment, len(@Comment)-1))

			IF @debugLevel > 0
			BEGIN
				SELECT 'Start DynSQL Area';
			END

			PRINT 'Start DynSQL Area at line '+CAST(@LineNumber AS CHAR(4)) 

			-- Here we should setup a dynSQL Area... 
			-- If this is our first dynSQL Area... we need some boilerplate? Variables? 
			IF @firstDynSQLArea = 0
			BEGIN
				IF @includeOurComments = 1
					SET @s = @s + '-- SETUP DynSQL Stuff for the first time' + @lr
				SET @s = @s + N'declare @sql nvarchar(max) = N'''' ' + @lr
				IF @includeDebug = 1
					SET @s = @s + N'declare @debug BIT = 0 -- set to 1 to print dynamic SQL' + @lr
				SET @firstDynSQLArea = 1
			END
			ELSE
			BEGIN
				IF @includeOurComments = 1 --TODO: Check this crap out.. 
					SET @s = @s + '-- recycle DynSQL Stuff, set @s = ' + @lr
				SET @s = @s + 'SET @sql = N'''' ' + @lr
			END
		END

		IF @Comment = ']' -- here ends the dyn SQL section... and we have to execute what we have so far. 
		BEGIN
			DECLARE @has_parameters BIT = 0;
			DECLARE @has_usedvars BIT = 0;
			DECLARE @has_buckets BIT = 0;

			-- Check if we have any buckets here
			IF EXISTS (
					SELECT 1
					FROM @buckets_statements
					)
				SET @has_buckets = 1;

			-- Check if we have any existing parameters
			IF LEN(@parameters) > 0
				OR LEN(@parameters2) > 0
				SET @has_parameters = 1;

			-- Check if we have any used variables
			IF EXISTS (
					SELECT 1
					FROM #usedvars
					)
				SET @has_usedvars = 1;

			-- Prepare the parameter string
			DECLARE @full_parameter_string NVARCHAR(MAX) = @parameters;
			DECLARE @full_variable_string NVARCHAR(MAX) = @parameters2;

			IF @debugLevel > 2
			BEGIN
				print '@full_parameter_string '+ @full_parameter_string
				print '@full_variable_string '+ @full_variable_string
			END

			-- If we have used variables, add them to the parameter strings
			IF @has_usedvars = 1
			BEGIN
				DECLARE @parameter_string NVARCHAR(MAX) = N'';
				DECLARE @variable_string NVARCHAR(MAX) = N'';

				IF @debugLevel > 2
				BEGIN
					SELECT 'we have to add variables: '

					SELECT *
					FROM #usedvars
				END

				SELECT @parameter_string = @parameter_string + CASE 
						--WHEN left(av.DataType,4) = 'time' THEN 
						--	',' + av.VariableName + ' ' + av.DataType
						WHEN av.MaxLength IS NOT NULL
							THEN ',' + av.VariableName + ' ' + av.DataType + '(' + CAST(av.MaxLength AS NVARCHAR) + ')'
						WHEN av.Precision IS NOT NULL
							AND av.Scale IS NOT NULL
							THEN ',' + av.VariableName + ' ' + av.DataType + '(' + CAST(av.Precision AS NVARCHAR) + ',' + CAST(av.Scale AS NVARCHAR) + ')'
						WHEN av.Precision IS NOT NULL
							THEN ',' + av.VariableName + ' ' + av.DataType + '(' + CAST(av.Precision AS NVARCHAR) + ')'
						ELSE ',' + av.VariableName + ' ' + av.DataType 
						END + ' OUTPUT'
					,@variable_string = @variable_string + ',' + av.VariableName + ' OUTPUT'
				FROM #usedvars uv
				JOIN #AnnotatedVariables av ON uv.VariableName = av.VariableName;

				-- Remove leading comma
				SET @parameter_string = STUFF(@parameter_string, 1, 1, '');
				SET @variable_string = STUFF(@variable_string, 1, 1, '');

				-- Now @parameter_string and @variable_string can be used in sp_executesql
				IF @debugLevel > 2
				BEGIN
					PRINT 'Parameter String: ' + @parameter_string;
					PRINT 'Variable String: ' + @variable_string;
				END

				IF @has_parameters = 1
				BEGIN
					IF @debugLevel > 2
					BEGIN
						print '@has_parameters = 1'
					END
					SET @full_parameter_string = @full_parameter_string + N', ' + @parameter_string;
					SET @full_variable_string = @full_variable_string + N', ' + @variable_string;
				END
				ELSE
				BEGIN
					IF @debugLevel > 2
					BEGIN
						print '@has_parameters = 1 else...'
					END
					SET @full_parameter_string = @parameter_string;
					SET @full_variable_string = @variable_string;
				END
			END

			IF @has_buckets = 1
			BEGIN
				IF @debugLevel > 2
				BEGIN
					print 'we have buckets'
				END

				-- Validate bucket parameters before processing
				DECLARE @invalid_params TABLE (param_name NVARCHAR(128));
    
				INSERT INTO @invalid_params (param_name)
				SELECT DISTINCT 
					SUBSTRING(statement, CHARINDEX('@', statement) + 1, CHARINDEX(':', statement) - CHARINDEX('@', statement) - 1)
				FROM @buckets_statements bs
				WHERE NOT EXISTS (
					SELECT 1 
					FROM #parameters 
					WHERE ParameterName = '@' + SUBSTRING(bs.statement, CHARINDEX('@', bs.statement) + 1, CHARINDEX(':', bs.statement) - CHARINDEX('@', bs.statement) - 1)
				)
				AND NOT EXISTS (
					SELECT 1 
					FROM #usedvars 
					WHERE VariableName = '@' + SUBSTRING(bs.statement, CHARINDEX('@', bs.statement) + 1, CHARINDEX(':', bs.statement) - CHARINDEX('@', bs.statement) - 1)
				);

				IF EXISTS (SELECT 1 FROM @invalid_params)
				BEGIN
					DECLARE @error_message NVARCHAR(MAX);
        
					SELECT @error_message = 'The following bucket parameters are not declared or marked with usevar: ' + 
						STRING_AGG(param_name, ', ') WITHIN GROUP (ORDER BY param_name)
					FROM @invalid_params;
        
					RAISERROR(@error_message, 16, 1);
					RETURN;
				END

				-- Parse the bucket statements
				INSERT INTO @buckets (param_name, valuelist)
				SELECT 
					SUBSTRING(statement, CHARINDEX('@', statement) + 1, CHARINDEX(':', statement) - CHARINDEX('@', statement) - 1) AS param_name,
					LTRIM(SUBSTRING(statement, CHARINDEX(':', statement) + 1, LEN(statement))) AS valuelist
				FROM @buckets_statements;

				-- Generate the CASE statements
				DECLARE @case_statements NVARCHAR(MAX) = '';
				DECLARE @buckets_counter INT = 1;

				DECLARE @param_name SYSNAME, @valuelist NVARCHAR(MAX);

				DECLARE @bucket_concat NVARCHAR(MAX) = 'DECLARE @bucket NVARCHAR(MAX) = '''';';


				DECLARE buckets_cursor CURSOR FOR SELECT param_name, valuelist FROM @buckets;
				OPEN buckets_cursor;
				FETCH NEXT FROM buckets_cursor INTO @param_name, @valuelist;

				WHILE @@FETCH_STATUS = 0
				BEGIN
					DECLARE @case_structure NVARCHAR(MAX) = 'DECLARE @buckets' + CAST(@buckets_counter AS NVARCHAR(10)) + ' CHAR(2) = CASE '+ @lr;
					DECLARE @value_list TABLE (value NVARCHAR(100), row_num INT);
    
					-- Split the values and remove spaces
					INSERT INTO @value_list (value, row_num)
					SELECT LTRIM(RTRIM(value)), ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
					FROM STRING_SPLIT(@valuelist, ',');

					DECLARE @max_row INT = (SELECT MAX(row_num) FROM @value_list);

					-- Generate WHEN clauses
					SELECT @case_structure = @case_structure + 
						CASE 
							WHEN row_num = 1 THEN '        WHEN @' + @param_name + ' < ' + value + ' THEN ''' + FORMAT(row_num - 1, '00') + ''''+ @lr
							ELSE '        WHEN @' + @param_name + ' >= ' + LAG(value) OVER (ORDER BY row_num) + ' AND @' + @param_name + ' < ' + value + ' THEN ''' + FORMAT(row_num - 1, '00') + ''''+ @lr
						END
					FROM @value_list
					ORDER BY row_num;

					-- Add the ELSE clause
					SET @case_structure = @case_structure + '        ELSE ''' + FORMAT(@max_row, '00') + ''''+ @lr+' END;';

					SET @case_statements = @case_statements + @case_structure + @lr;

					-- Add to the bucket concatenation string
					SET @bucket_concat = @bucket_concat + ' SET @bucket = @bucket + @buckets' + CAST(@buckets_counter AS NVARCHAR(10)) + ';';
    
					SET @buckets_counter = @buckets_counter + 1;
					DELETE FROM @value_list;
					FETCH NEXT FROM buckets_cursor INTO @param_name, @valuelist;
				END

				CLOSE buckets_cursor;
				DEALLOCATE buckets_cursor;

				-- Add the bucket concatenation to the case statements
				SET @case_statements = @case_statements + CHAR(13) + CHAR(10) + @bucket_concat;

				
				IF @debugLevel > 2
				BEGIN
					PRINT @case_statements;
				END

				SET @s = @s + @case_statements + @lr+ @lr;

				SET @s = @s + N'set @sql = ''/*''+@bucket+''*/'' + @sql'  + @lr 

				DELETE FROM @buckets
				DELETE FROM @buckets_statements
			END

			IF len(@DynQueryName) > 0
			BEGIN
				SET @s = @s + N'set @sql = ''/*'+@DynQueryName+'*/'' + @sql'  + @lr 
				SET @DynQueryName = N''
			END

			-- Inject OPTION(RECOMPILE) if --#recompile was used in this section
			IF @recompileFlag = 1
			BEGIN
				SET @s = @s + N'set @sql = @sql + '' OPTION(RECOMPILE)''' + @lr
				SET @recompileFlag = 0
			END

			IF @has_parameters = 1 OR @has_usedvars = 1
				BEGIN
					IF @includeDebug = 1
						SET @s = @s + N'IF @debug = 1 PRINT @sql' + @lr
					SET @s = @s + N'exec sp_executesql @sql, N''' + @full_parameter_string + ''', ' + @full_variable_string + @lr;
				END
			ELSE
				BEGIN
					IF @includeDebug = 1
						SET @s = @s + N'IF @debug = 1 PRINT @sql' + @lr
					SET @s = @s + N'exec sp_executesql @sql' + @lr;
				END
			

			SET @dynSQLFlag = 0;

			TRUNCATE TABLE #usedvars

			IF @debugLevel > 0
			BEGIN
				SELECT 'End DynSQL Area';
			END

			PRINT 'End DynSQL Area at line '+CAST(@LineNumber AS CHAR(4)) 
		END

		IF @Comment = '}'
		BEGIN
			SET @s = @s + N'END' + @lr
		END

		IF LOWER(TRIM(@Comment)) = 'else' OR LOWER(TRIM(@Comment)) = '{else'
		BEGIN
			SET @s = @s + N'END' + @lr
			SET @s = @s + N'ELSE' + @lr
			SET @s = @s + N'BEGIN' + @lr
		END

		IF @Comment = '-'
			OR @Comment = 'c'
		BEGIN
			SET @s = @s + N'--' + @CleanRow
		END

		IF LOWER(TRIM(@Comment)) = 'recompile'
		BEGIN
			SET @recompileFlag = 1
		END

		IF @Comment = 'var'
		BEGIN
			SET @s = @s + @CleanRow
		END

		IF lower(left(@Comment, 6)) = 'usevar'
		BEGIN
			SET @s = @s + N'set @sql = @sql + ''' + REPLACE(@CleanRow, '''', '''''') + '''+CHAR(13)+CHAR(10)' + @lr

			IF @debugLevel > 2
			BEGIN
				SELECT @comment
			END

			-- Insert the extracted variable names into #usedvars
			INSERT INTO #usedvars (VariableName)
			SELECT LTRIM(value) AS VariableName
			FROM STRING_SPLIT(SUBSTRING(@Comment, CHARINDEX('@', @Comment), LEN(@Comment)), ',')
		END

		IF lower(left(@Comment, 7)) = 'buckets'
		BEGIN
			INSERT INTO @buckets_statements (statement) VALUES (@Comment);
			IF @debugLevel > 2
			BEGIN
				PRINT @comment
			END
		END

		IF lower(left(@Comment, 6)) = 'define'
		BEGIN
			-- Parse: define <name> = <condition>
			DECLARE @defineBody NVARCHAR(MAX) = LTRIM(RIGHT(@Comment, LEN(@Comment) - 6));
			DECLARE @eqPos INT = CHARINDEX('=', @defineBody);

			IF @eqPos > 0
			BEGIN
				DECLARE @condName NVARCHAR(128) = RTRIM(LTRIM(LEFT(@defineBody, @eqPos - 1)));
				DECLARE @condText NVARCHAR(MAX) = LTRIM(RIGHT(@defineBody, LEN(@defineBody) - @eqPos));

				IF LEN(@condName) > 0 AND LEN(@condText) > 0
				BEGIN
					IF LEFT(@condName, 1) = '@'
						PRINT 'WARNING: --#define name should not start with @ (found: ' + @condName + '). Use a plain name to avoid confusion with parameters.';

					IF EXISTS (SELECT 1 FROM @conditions WHERE ConditionName = LOWER(@condName))
					BEGIN
						PRINT 'WARNING: --#define name ''' + @condName + ''' is already defined. Overwriting previous definition.';
						DELETE FROM @conditions WHERE ConditionName = LOWER(@condName);
					END

					INSERT INTO @conditions (ConditionName, ConditionText)
					VALUES (LOWER(@condName), @condText);

					IF @debugLevel > 0
						PRINT '--#define: ' + @condName + ' = ' + @condText;
				END
				ELSE
					PRINT 'WARNING: --#define has empty name or condition at line ' + CAST(@LineNumber AS VARCHAR) + '.';
			END
			ELSE
				PRINT 'WARNING: --#define missing ''='' separator at line ' + CAST(@LineNumber AS VARCHAR) + '. Expected: --#define <name> = <condition>';
		END

		IF @Comment = '{-'
		BEGIN
			SET @removalBlockFlag = 1
		END

		IF @Comment = '-}'
		BEGIN
			SET @removalBlockFlag = 0
		END

		IF lower(LEFT(@Comment, 8)) = '{elseif '
		BEGIN
			-- Resolve named condition
			SET @resolvedCondition = LTRIM(RIGHT(@Comment, LEN(@Comment) - 7));
			SET @condLookup = NULL;
			SELECT @condLookup = ConditionText FROM @conditions WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
			IF @condLookup IS NOT NULL
			BEGIN
				UPDATE @conditions SET UsedFlag = 1 WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
				SET @resolvedCondition = @condLookup;
			END

			-- Block else-if: close current block, emit ELSE IF condition, open new block
			SET @s = @s + N'END' + @lr
			SET @s = @s + N'ELSE IF ' + @resolvedCondition + @lr
			SET @s = @s + N'BEGIN' + @lr
			IF @dynSQLFlag = 1 AND LEN(LTRIM(RTRIM(REPLACE(REPLACE(@CleanRow, CHAR(13), ''), CHAR(10), '')))) > 0
				SET @s = @s + N'set @sql = @sql + ''' + REPLACE(@CleanRow, '''', '''''') + '''+CHAR(13)+CHAR(10)' + @lr
		END
		ELSE IF lower(LEFT(@Comment, 3)) = '{if'
		BEGIN
			-- Resolve named condition
			SET @resolvedCondition = LTRIM(RIGHT(@Comment, LEN(@Comment) - 3));
			SET @condLookup = NULL;
			SELECT @condLookup = ConditionText FROM @conditions WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
			IF @condLookup IS NOT NULL
			BEGIN
				UPDATE @conditions SET UsedFlag = 1 WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
				SET @resolvedCondition = @condLookup;
			END

			SET @s = @s + N'IF ' + @resolvedCondition + @lr
			SET @s = @s + N'BEGIN' + @lr
			IF @dynSQLFlag = 1 AND LEN(LTRIM(RTRIM(REPLACE(REPLACE(@CleanRow, CHAR(13), ''), CHAR(10), '')))) > 0
				SET @s = @s + N'set @sql = @sql + ''' + REPLACE(@CleanRow, '''', '''''') + '''+CHAR(13)+CHAR(10)' + @lr
		END
		ELSE IF lower(LEFT(@Comment, 2)) = 'if' -- in ELSE because of a "shorter" if... 
		BEGIN
			-- Resolve named condition
			SET @resolvedCondition = LTRIM(RIGHT(@Comment, LEN(@Comment) - 2));
			SET @condLookup = NULL;
			SELECT @condLookup = ConditionText FROM @conditions WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
			IF @condLookup IS NOT NULL
			BEGIN
				UPDATE @conditions SET UsedFlag = 1 WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
				SET @resolvedCondition = @condLookup;
			END

			SET @s = @s + N'IF ' + @resolvedCondition + @lr
			IF RIGHT(@CleanRow, 2) = CHAR(13) + CHAR(10)
				SET @CleanRow = LEFT(@CleanRow, LEN(@CleanRow) - 2)
			SET @s = @s + N'set @sql = @sql + ''' + REPLACE(@CleanRow, '''', '''''') + '''+CHAR(13)+CHAR(10)' + @lr
		END
	END
	ELSE IF @dynSQLFlag = 1
	BEGIN
		IF @removalBlockFlag = 1
		BEGIN
			-- Inside --#{- block: treat as --#- (comment out)
			SET @s = @s + N'--' + @CleanRow
		END
		ELSE
		BEGIN
			IF RIGHT(@CleanRow, 2) = CHAR(13) + CHAR(10)
				SET @CleanRow = LEFT(@CleanRow, LEN(@CleanRow) - 2)
			SET @s = @s + N'set @sql = @sql + ''' + REPLACE(@CleanRow, '''', '''''') + '''+CHAR(13)+CHAR(10)' + @lr
		END
	END
	ELSE
	BEGIN
		-- Nothing special here... 
		SET @s = @s + @CleanRow -- dont need this here... -> +@lr
	END

	SELECT @LineNumber = MIN(LineNumber)
	FROM #ProcText
	WHERE LineNumber > @LineNumber
END

PRINT ''
PRINT 'Precompiler aka render loop is done.'

-- Warn about unused --#define definitions
DECLARE @unusedDefs NVARCHAR(MAX) = NULL;
SELECT @unusedDefs = STRING_AGG(ConditionName, ', ')
FROM @conditions
WHERE UsedFlag = 0;

IF @unusedDefs IS NOT NULL
	PRINT 'WARNING: --#define condition(s) defined but never referenced: ' + @unusedDefs;

IF @debugLevel > 2
BEGIN
	PRINT @s;
END

-- ===================================================================
-- Phase 3: Wrapper — generate wrapper + child procedures
-- ===================================================================
IF @wrapperMode = 1
BEGIN
	-- Build the EXEC parameter list: @p1 = @p1, @p2 = @p2, ...
	DECLARE @execParamList NVARCHAR(MAX) = N'';
	SELECT @execParamList = STRING_AGG(
		ParameterName + N' = ' + ParameterName +
		CASE WHEN IsOutput = 1 THEN N' OUTPUT' ELSE N'' END,
		N', ')
	FROM #parameters;

	-- Extract procedure header from @s (up to and including AS line)
	DECLARE @asSearchStr NVARCHAR(10) = CHAR(10) + N'AS' + CHAR(13) + CHAR(10);
	DECLARE @headerEndPos INT = CHARINDEX(@asSearchStr, @s);
	DECLARE @procHeader NVARCHAR(MAX);

	IF @headerEndPos > 0
		SET @procHeader = LEFT(@s, @headerEndPos + LEN(@asSearchStr) - 1);
	ELSE
	BEGIN
		-- Fallback: try \nAS\r without trailing \n
		SET @headerEndPos = CHARINDEX(CHAR(10) + N'AS' + CHAR(13), @s);
		IF @headerEndPos > 0
			SET @procHeader = LEFT(@s, @headerEndPos + 3) + CHAR(10);
		ELSE
		BEGIN
			RAISERROR('Wrapper mode: could not locate AS keyword in rendered output.', 16, 1);
			RETURN;
		END
	END

	-- Build wrapper body: header + IF/ELSE dispatch
	DECLARE @wrapperBody NVARCHAR(MAX) = @procHeader;
	DECLARE @brSuffix NVARCHAR(128), @brCondition NVARCHAR(MAX), @brIsDefault BIT;
	DECLARE @brFirst BIT = 1;

	DECLARE br_cursor CURSOR LOCAL FAST_FORWARD FOR 
		SELECT Suffix, Condition, IsDefault 
		FROM @branches 
		ORDER BY IsDefault, BranchOrder;
	OPEN br_cursor;
	FETCH NEXT FROM br_cursor INTO @brSuffix, @brCondition, @brIsDefault;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		IF @brIsDefault = 1
		BEGIN
			IF @brFirst = 1
				SET @wrapperBody = @wrapperBody; -- single default, no IF needed
			ELSE
				SET @wrapperBody = @wrapperBody + N'ELSE' + @lr;
		END
		ELSE IF @brFirst = 1
		BEGIN
			SET @wrapperBody = @wrapperBody + N'IF ' + @brCondition + @lr;
			SET @brFirst = 0;
		END
		ELSE
			SET @wrapperBody = @wrapperBody + N'ELSE IF ' + @brCondition + @lr;

		SET @wrapperBody = @wrapperBody + N'    EXEC ' + QUOTENAME(@SchemaName) + N'.'
			+ QUOTENAME(@ProcedureNameNew + @brSuffix);

		IF LEN(@execParamList) > 0
			SET @wrapperBody = @wrapperBody + N' ' + @execParamList;

		SET @wrapperBody = @wrapperBody + N';' + @lr;

		FETCH NEXT FROM br_cursor INTO @brSuffix, @brCondition, @brIsDefault;
	END

	CLOSE br_cursor;
	DEALLOCATE br_cursor;

	-- Build child procedures (each is @s with procedure name suffixed)
	DECLARE @allChildren NVARCHAR(MAX) = N'';
	DECLARE @childProc NVARCHAR(MAX);

	DECLARE child_cursor CURSOR LOCAL FAST_FORWARD FOR 
		SELECT Suffix FROM @branches ORDER BY BranchOrder;
	OPEN child_cursor;
	FETCH NEXT FROM child_cursor INTO @brSuffix;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @childProc = STUFF(@s,
			CHARINDEX(@ProcedureNameNew, @s),
			LEN(@ProcedureNameNew),
			@ProcedureNameNew + @brSuffix);

		SET @allChildren = @allChildren + @lr + N'GO' + @lr + @childProc;

		FETCH NEXT FROM child_cursor INTO @brSuffix;
	END

	CLOSE child_cursor;
	DEALLOCATE child_cursor;

	-- Final output: wrapper + GO + children
	SET @s = @wrapperBody + @allChildren;

	DECLARE @branchCount INT;
	SELECT @branchCount = COUNT(*) FROM @branches;
	PRINT 'Wrapper generation complete: 1 wrapper + '
		+ CAST(@branchCount AS VARCHAR) + ' child procedure(s)';
END

SET @Result = @s;

END TRY
BEGIN CATCH
	IF @@trancount > 0
		ROLLBACK TRANSACTION;

	-- Clean up temp tables on error
	IF OBJECT_ID('tempdb..#ProcText') IS NOT NULL
		DROP TABLE #ProcText;
	IF OBJECT_ID('tempdb..#parameters') IS NOT NULL
		DROP TABLE #parameters;
	IF OBJECT_ID('tempdb..#AnnotatedVariables') IS NOT NULL
		DROP TABLE #AnnotatedVariables;
	IF OBJECT_ID('tempdb..#usedvars') IS NOT NULL
		DROP TABLE #usedvars;

	;THROW;
END CATCH

-- Clean up
IF OBJECT_ID('tempdb..#ProcText') IS NOT NULL
	DROP TABLE #ProcText;

IF OBJECT_ID('tempdb..#parameters') IS NOT NULL
	DROP TABLE #parameters;

IF OBJECT_ID('tempdb..#AnnotatedVariables') IS NOT NULL
	DROP TABLE #AnnotatedVariables;

IF OBJECT_ID('tempdb..#usedvars') IS NOT NULL
	DROP TABLE #usedvars;

SET @EndTime = SYSUTCDATETIME();

SET @ExecutionTime = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

PRINT 'Execution time: ' + CAST(@ExecutionTime AS VARCHAR(20)) + ' milliseconds';
PRINT ''
PRINT 'Done.'
PRINT ''