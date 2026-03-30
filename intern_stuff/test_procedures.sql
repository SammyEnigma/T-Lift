/*=====================================================================
  T-Lift Test Suite — Annotated Test Procedures
  
  Each procedure demonstrates a specific T-Lift directive pattern.
  These are the "before" (annotated) procedures that T-Lift will 
  transform into dynamic SQL versions.
  
  Prerequisites: test_setup.sql has been executed.
=====================================================================*/

USE [TLift_TestDB];
GO

/* TEST 1: Simple single-parameter NULL check
   Pattern: WHERE (@param IS NULL OR @param = column)
   Directives used: open/close section, if, remove-line             */
PRINT 'Creating test01_single_param...';
GO
CREATE OR ALTER PROCEDURE dbo.test01_single_param
    @CustomerID INT = NULL
AS
                            --#[ Test01
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email, c.City
FROM dbo.Customers c
WHERE                       --#if @CustomerID IS NOT NULL
(                           --#-
@CustomerID IS NULL OR      --#-
c.CustomerID = @CustomerID  --#if @CustomerID IS NOT NULL
)                           --#-
                            --#]
GO

/* TEST 2: Two parameters with AND
   Pattern: WHERE (@p1 IS NULL OR ...) AND (@p2 IS NULL OR ...)
   Directives used: if with compound conditions, remove-line        */
PRINT 'Creating test02_two_params...';
GO
CREATE OR ALTER PROCEDURE dbo.test02_two_params
    @ProductID INT = NULL,
    @MinQuantity INT = NULL
AS
                                    --#[ Test02
SELECT oi.OrderItemID, oi.OrderID, oi.ProductID, oi.Quantity, oi.UnitPrice, oi.LineTotal
FROM dbo.OrderItems oi
WHERE                               --#if @ProductID IS NOT NULL OR @MinQuantity IS NOT NULL
(                                   --#-
@ProductID IS NULL OR               --#-
oi.ProductID = @ProductID           --#if @ProductID IS NOT NULL
)                                   --#-
AND                                 --#if @ProductID IS NOT NULL AND @MinQuantity IS NOT NULL
(                                   --#-
@MinQuantity IS NULL OR             --#-
oi.Quantity >= @MinQuantity         --#if @MinQuantity IS NOT NULL
)                                   --#-
                                    --#]
GO

/* TEST 3: Three parameters (stress-test AND chaining)
   Pattern: Multiple optional filters on different columns          */
PRINT 'Creating test03_three_params...';
GO
CREATE OR ALTER PROCEDURE dbo.test03_three_params
    @CustomerID INT = NULL,
    @Status NVARCHAR(20) = NULL,
    @OrderDateFrom DATE = NULL
AS
                                    --#[ Test03
SELECT o.OrderID, o.CustomerID, o.OrderDate, o.Status, o.TotalAmount
FROM dbo.Orders o
WHERE                               --#if @CustomerID IS NOT NULL OR @Status IS NOT NULL OR @OrderDateFrom IS NOT NULL
(                                   --#-
@CustomerID IS NULL OR              --#-
o.CustomerID = @CustomerID          --#if @CustomerID IS NOT NULL
)                                   --#-
AND                                 --#if @CustomerID IS NOT NULL AND @Status IS NOT NULL
(                                   --#-
@Status IS NULL OR                  --#-
o.Status = @Status                  --#if @Status IS NOT NULL
)                                   --#-
AND                                 --#if (@CustomerID IS NOT NULL OR @Status IS NOT NULL) AND @OrderDateFrom IS NOT NULL
(                                   --#-
@OrderDateFrom IS NULL OR           --#-
o.OrderDate >= @OrderDateFrom       --#if @OrderDateFrom IS NOT NULL
)                                   --#-
                                    --#]
GO

/* TEST 4: Variables with var and usevar directives
   Demonstrates passing local variables into dynamic SQL sections   */
PRINT 'Creating test04_variables...';
GO
CREATE OR ALTER PROCEDURE dbo.test04_variables
    @Category NVARCHAR(50) = NULL
AS
DECLARE @ActiveOnly BIT = 1;                --#var
                                            --#[ Test04
SELECT p.ProductID, p.ProductName,          --#usevar @ActiveOnly
       p.Category, p.UnitPrice, p.IsActive
FROM dbo.Products p
WHERE                                       --#if @Category IS NOT NULL OR @ActiveOnly = 1
(                                           --#-
@Category IS NULL OR                        --#-
p.Category = @Category                      --#if @Category IS NOT NULL
)                                           --#-
AND                                         --#if @Category IS NOT NULL AND @ActiveOnly = 1
p.IsActive = @ActiveOnly                    --#if @ActiveOnly = 1
                                            --#]
GO

/* TEST 5: Block conditions with block-if / block-close
   Demonstrates multi-line conditional blocks                       */
PRINT 'Creating test05_block_condition...';
GO
CREATE OR ALTER PROCEDURE dbo.test05_block_condition
    @CustomerID INT = NULL,
    @IncludeOrderDetails BIT = 0
AS
                                        --#[ Test05
SELECT o.OrderID, o.CustomerID, o.OrderDate, o.Status, o.TotalAmount
FROM dbo.Orders o
WHERE                                   --#if @CustomerID IS NOT NULL
(                                       --#-
@CustomerID IS NULL OR                  --#-
o.CustomerID = @CustomerID              --#if @CustomerID IS NOT NULL
)                                       --#-
                                        --#]

                                        --#{if @IncludeOrderDetails = 1
                                        --#[ Test05Detail
SELECT oi.OrderItemID, oi.OrderID, oi.ProductID, oi.Quantity, oi.LineTotal
FROM dbo.OrderItems oi
INNER JOIN dbo.Orders o ON oi.OrderID = o.OrderID
WHERE                                   --#if @CustomerID IS NOT NULL
(                                       --#-
@CustomerID IS NULL OR                  --#-
o.CustomerID = @CustomerID              --#if @CustomerID IS NOT NULL
)                                       --#-
                                        --#]
                                        --#}
GO

/* TEST 6: Named dynamic sections (label after open-bracket)
   The label is embedded as a SQL comment in the rendered SQL
   for plan cache identification.                                   */
PRINT 'Creating test06_named_section...';
GO
CREATE OR ALTER PROCEDURE dbo.test06_named_section
    @OrderID INT = NULL
AS
                                    --#[ FindOrder
SELECT o.OrderID, o.CustomerID, o.OrderDate, o.Status, o.TotalAmount
FROM dbo.Orders o
WHERE                               --#if @OrderID IS NOT NULL
(                                   --#-
@OrderID IS NULL OR                 --#-
o.OrderID = @OrderID                --#if @OrderID IS NOT NULL
)                                   --#-
                                    --#]
GO

/* TEST 7: Different data types in parameters
   VARCHAR, DATE, DECIMAL — ensures type handling in sp_executesql  */
PRINT 'Creating test07_mixed_types...';
GO
CREATE OR ALTER PROCEDURE dbo.test07_mixed_types
    @City NVARCHAR(50) = NULL,
    @CreatedAfter DATE = NULL,
    @Country NVARCHAR(50) = NULL
AS
                                        --#[ Test07
SELECT c.CustomerID, c.FirstName, c.LastName, c.City, c.Country, c.CreatedDate
FROM dbo.Customers c
WHERE                                   --#if @City IS NOT NULL OR @CreatedAfter IS NOT NULL OR @Country IS NOT NULL
(                                       --#-
@City IS NULL OR                        --#-
c.City = @City                          --#if @City IS NOT NULL
)                                       --#-
AND                                     --#if @City IS NOT NULL AND @CreatedAfter IS NOT NULL
(                                       --#-
@CreatedAfter IS NULL OR                --#-
c.CreatedDate >= @CreatedAfter          --#if @CreatedAfter IS NOT NULL
)                                       --#-
AND                                     --#if (@City IS NOT NULL OR @CreatedAfter IS NOT NULL) AND @Country IS NOT NULL
(                                       --#-
@Country IS NULL OR                     --#-
c.Country = @Country                    --#if @Country IS NOT NULL
)                                       --#-
                                        --#]
GO

/* TEST 8: JOIN with conditional filtering
   Ensures T-Lift works with JOINs, not just single-table queries. */
PRINT 'Creating test08_join_query...';
GO
CREATE OR ALTER PROCEDURE dbo.test08_join_query
    @CustomerID INT = NULL,
    @ProductID INT = NULL
AS
                                        --#[ Test08
SELECT o.OrderID, o.OrderDate, c.FirstName, c.LastName,
       oi.ProductID, p.ProductName, oi.Quantity, oi.LineTotal
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
INNER JOIN dbo.OrderItems oi ON o.OrderID = oi.OrderID
INNER JOIN dbo.Products p ON oi.ProductID = p.ProductID
WHERE                                   --#if @CustomerID IS NOT NULL OR @ProductID IS NOT NULL
(                                       --#-
@CustomerID IS NULL OR                  --#-
o.CustomerID = @CustomerID              --#if @CustomerID IS NOT NULL
)                                       --#-
AND                                     --#if @CustomerID IS NOT NULL AND @ProductID IS NOT NULL
(                                       --#-
@ProductID IS NULL OR                   --#-
oi.ProductID = @ProductID               --#if @ProductID IS NOT NULL
)                                       --#-
                                        --#]
GO

/* TEST 9: Procedure with no dynamic section (baseline sanity check)
   T-Lift should reproduce the procedure body unchanged.            */
PRINT 'Creating test09_no_directives...';
GO
CREATE OR ALTER PROCEDURE dbo.test09_no_directives
    @CustomerID INT
AS
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email
FROM dbo.Customers c
WHERE c.CustomerID = @CustomerID;
GO

/* TEST 10: Comment-out directive (c-directive)
   Lines marked with the comment directive become SQL comments.     */
PRINT 'Creating test10_comment_directive...';
GO
CREATE OR ALTER PROCEDURE dbo.test10_comment_directive
    @OrderID INT = NULL
AS
                                    --#[ Test10
SELECT o.OrderID, o.CustomerID,
       o.OrderDate, o.Status, o.TotalAmount
FROM dbo.Orders o
WHERE                               --#if @OrderID IS NOT NULL
(                                   --#-
@OrderID IS NULL OR                 --#-
o.OrderID = @OrderID                --#if @OrderID IS NOT NULL
)                                   --#-
ORDER BY o.OrderDate DESC           --#c
                                    --#]
GO

PRINT '=== All test procedures created successfully ===';
GO

/* TEST 11: ELSE directive in block conditions
   Demonstrates --#{if / --#else / --#} pattern for mutually
   exclusive branches in dynamic SQL.                                */
PRINT 'Creating test11_else_directive...';
GO
CREATE OR ALTER PROCEDURE dbo.test11_else_directive
    @CustomerID INT = NULL,
    @IncludeInactive BIT = 0
AS
                                        --#[ Test11
SELECT o.OrderID, o.CustomerID, o.OrderDate, o.Status, o.TotalAmount
FROM dbo.Orders o
WHERE                                   --#if @CustomerID IS NOT NULL
(                                       --#-
@CustomerID IS NULL OR                  --#-
o.CustomerID = @CustomerID              --#if @CustomerID IS NOT NULL
)                                       --#-
                                        --#]

                                        --#{if @IncludeInactive = 1
                                        --#[ Test11All
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email, c.City
FROM dbo.Customers c
                                        --#]
                                        --#else
                                        --#[ Test11Active
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email, c.City
FROM dbo.Customers c
WHERE c.CustomerID IS NOT NULL
                                        --#]
                                        --#}
GO

/* TEST 12: ELSEIF directive in block conditions
   Demonstrates --#{if / --#{elseif / --#else / --#} pattern        */
PRINT 'Creating test12_elseif_directive...';
GO
CREATE OR ALTER PROCEDURE dbo.test12_elseif_directive
    @SortMode INT = 0
AS
                                        --#[ Test12
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email, c.City
FROM dbo.Customers c
                                        --#]

                                        --#{if @SortMode = 1
PRINT 'Sorting by name'
                                        --#{elseif @SortMode = 2
PRINT 'Sorting by city'
                                        --#else
PRINT 'Default sort order'
                                        --#}
GO

/* TEST 13: Wrapper procedure generation
   Demonstrates --#wrapper / --#branch / --#branch-default pattern
   for generating a dispatcher wrapper + specialized child procs.
   Each child gets its own plan cache entry, avoiding parameter
   sniffing across different usage patterns.                         */
PRINT 'Creating test13_wrapper...';
GO
CREATE OR ALTER PROCEDURE dbo.test13_wrapper
    @CustomerID INT = NULL,
    @City NVARCHAR(50) = NULL
AS
--#wrapper
--#branch _byCust @CustomerID IS NOT NULL
--#branch _byCity @City IS NOT NULL
--#branch-default _all
                                        --#[ Test13
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email, c.City
FROM dbo.Customers c
WHERE                                   --#if @CustomerID IS NOT NULL OR @City IS NOT NULL
(                                       --#-
@CustomerID IS NULL OR                  --#-
c.CustomerID = @CustomerID              --#if @CustomerID IS NOT NULL
)                                       --#-
AND                                     --#if @CustomerID IS NOT NULL AND @City IS NOT NULL
(                                       --#-
@City IS NULL OR                        --#-
c.City = @City                          --#if @City IS NOT NULL
)                                       --#-
                                        --#]
GO

/* TEST 14: Block conditional inside dynamic SQL section — simple filter
   Demonstrates --#{if inside --#[ for a clean optional WHERE clause
   without catch-all scaffolding. The condition is stated once.
   Directives used: --#[, --#], --#{if, --#}                       */
PRINT 'Creating test14_block_if_simple_filter...';
GO
CREATE OR ALTER PROCEDURE dbo.test14_block_if_simple_filter
    @CustomerID INT = NULL
AS
                                        --#[ Test14
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email, c.City
FROM dbo.Customers c
                                        --#{if @CustomerID IS NOT NULL
WHERE
c.CustomerID = @CustomerID
                                        --#}
                                        --#]
GO

/* TEST 15: Block conditional inside dynamic SQL section — catch-all pattern
   Demonstrates --#{if inside --#[ with --#- scaffolding for
   catch-all static SQL. Condition is stated once instead of twice.
   Uses WHERE 1=1 pattern for clean multi-filter composition.
   Directives used: --#[, --#], --#{if, --#}, --#-                  */
PRINT 'Creating test15_block_if_catchall...';
GO
CREATE OR ALTER PROCEDURE dbo.test15_block_if_catchall
    @CustomerID INT = NULL,
    @City NVARCHAR(50) = NULL
AS
                                        --#[ Test15
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email, c.City
FROM dbo.Customers c
WHERE 1=1
                                        --#{if @CustomerID IS NOT NULL
AND
(                                       --#-
@CustomerID IS NULL OR                  --#-
c.CustomerID = @CustomerID
)                                       --#-
                                        --#}
                                        --#{if @City IS NOT NULL
AND
(                                       --#-
@City IS NULL OR                        --#-
c.City = @City
)                                       --#-
                                        --#}
                                        --#]
GO

/* TEST 16: Named condition with --#define
   Demonstrates --#define to name a condition and reference it
   in --#if directives, reducing repetition.
   Directives used: --#define, --#[, --#], --#if, --#-              */
PRINT 'Creating test16_named_condition...';
GO
CREATE OR ALTER PROCEDURE dbo.test16_named_condition
    @CustomerID INT = NULL
AS
                                        --#define custFilter = @CustomerID IS NOT NULL

                                        --#[ Test16
SELECT o.OrderID, o.CustomerID, o.OrderDate, o.Status, o.TotalAmount
FROM dbo.Orders o
WHERE                                   --#if custFilter
(                                       --#-
@CustomerID IS NULL OR                  --#-
o.CustomerID = @CustomerID              --#if custFilter
)                                       --#-
                                        --#]
GO

/* TEST 17: Named condition across multiple dynamic SQL sections
   The OrderReport pattern from v2.md — condition defined once,
   used in two separate --#[ sections.
   Directives used: --#define, --#[, --#], --#{if, --#}             */
PRINT 'Creating test17_named_condition_multi_section...';
GO
CREATE OR ALTER PROCEDURE dbo.test17_named_condition_multi_section
    @CustomerID INT = NULL,
    @IncludeDetails BIT = 0
AS
                                        --#define custFilter = @CustomerID IS NOT NULL

                                        --#[ Test17Summary
SELECT o.OrderID, o.CustomerID, o.OrderDate, o.TotalAmount
FROM dbo.Orders o
                                        --#{if custFilter
WHERE
o.CustomerID = @CustomerID
                                        --#}
                                        --#]

                                        --#{if @IncludeDetails = 1
                                        --#[ Test17Detail
SELECT oi.OrderItemID, oi.OrderID, oi.ProductID, oi.Quantity, oi.LineTotal
FROM dbo.OrderItems oi
INNER JOIN dbo.Orders o ON oi.OrderID = o.OrderID
                                        --#{if custFilter
WHERE
o.CustomerID = @CustomerID
                                        --#}
                                        --#]
                                        --#}
GO

/* TEST 18: Block removal with --#{- / --#-}
   Demonstrates removing multiple consecutive scaffolding lines
   with a single block directive pair instead of per-line --#-.
   Directives used: --#[, --#], --#{if, --#}, --#{-, --#-}          */
PRINT 'Creating test18_block_removal...';
GO
CREATE OR ALTER PROCEDURE dbo.test18_block_removal
    @CustomerID INT = NULL
AS
                                        --#[ Test18
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email, c.City
FROM dbo.Customers c
                                        --#{if @CustomerID IS NOT NULL
WHERE
                                        --#{-
(
@CustomerID IS NULL OR
                                        --#-}
c.CustomerID = @CustomerID
                                        --#{-
)
                                        --#-}
                                        --#}
                                        --#]
GO

/* TEST 19: nchar/nvarchar parameter length rendering
   Verifies that nvarchar(50) is rendered as nvarchar(50) in the
   generated signature, NOT nvarchar(100) due to byte-vs-char bug.
   Directives used: --#[, --#], --#if, --#-                         */
PRINT 'Creating test19_nvarchar_params...';
GO
CREATE OR ALTER PROCEDURE dbo.test19_nvarchar_params
    @SearchName NVARCHAR(50) = NULL,
    @CategoryCode NCHAR(10) = NULL
AS
                                        --#[ Test19
SELECT c.CustomerID, c.FirstName, c.LastName, c.Email, c.City
FROM dbo.Customers c
WHERE                                   --#if @SearchName IS NOT NULL OR @CategoryCode IS NOT NULL
(                                       --#-
@SearchName IS NULL OR                  --#-
c.LastName = @SearchName                --#if @SearchName IS NOT NULL
)                                       --#-
AND                                     --#if @SearchName IS NOT NULL AND @CategoryCode IS NOT NULL
(                                       --#-
@CategoryCode IS NULL OR                --#-
c.City = @CategoryCode                  --#if @CategoryCode IS NOT NULL
)                                       --#-
                                        --#]
GO

/* TEST 20: Long parameter name in buckets
   Verifies that parameter names longer than 10 characters work
   correctly with the --#buckets directive (no truncation).
   Directives used: --#[, --#], --#buckets                          */
PRINT 'Creating test20_long_param_buckets...';
GO
CREATE OR ALTER PROCEDURE dbo.test20_long_param_buckets
    @VeryLongParameterName INT = NULL
AS
                                        --#[ Test20
                                        --#buckets @VeryLongParameterName:10,100,1000
SELECT o.OrderID, o.CustomerID, o.OrderDate, o.TotalAmount
FROM dbo.Orders o
WHERE                                   --#if @VeryLongParameterName IS NOT NULL
(                                       --#-
@VeryLongParameterName IS NULL OR       --#-
o.CustomerID = @VeryLongParameterName   --#if @VeryLongParameterName IS NOT NULL
)                                       --#-
                                        --#]
GO

/* TEST 21: Directive marker inside string literal
    Verifies that --# tokens inside string literals are ignored by the
    directive scanner and preserved as plain text.
    Directives used: --#[, --#]                                       */
PRINT 'Creating test21_string_literal_directive_marker...';
GO
CREATE OR ALTER PROCEDURE dbo.test21_string_literal_directive_marker
AS
PRINT '--#if this stays a string literal';

                                                     --#[ Test21
SELECT TOP (1) c.CustomerID, c.FirstName
FROM dbo.Customers c
                                                     --#]
GO

/* TEST 22: Quoted string literal inside dynamic SQL section
    Verifies that single quotes inside rendered dynamic SQL lines are
    escaped correctly when T-Lift builds the generated @sql builder.
    Directives used: --#[, --#]                                       */
PRINT 'Creating test22_quoted_literal_dynamic_section...';
GO
CREATE OR ALTER PROCEDURE dbo.test22_quoted_literal_dynamic_section
AS
                                                                      --#[ Test22
SELECT N'Brian O''Brien' AS PersonName,
         N'--#if stays literal' AS DirectiveText
FROM dbo.Customers c
WHERE c.CustomerID = 1
                                                                      --#]
GO

/* TEST 23: GO inside multiline string literal outside dynamic SQL
    Verifies that deployment only splits on real top-level GO batch
    separators, not GO lines embedded inside string literals.
    Directives used: --#[, --#]                                       */
PRINT 'Creating test23_go_in_multiline_string...';
GO
CREATE OR ALTER PROCEDURE dbo.test23_go_in_multiline_string
AS
DECLARE @msg NVARCHAR(MAX) = N'alpha
GO
beta';
PRINT @msg;

                                                                      --#[ Test23
SELECT TOP (1) c.CustomerID, c.FirstName
FROM dbo.Customers c
                                                                      --#]
GO
