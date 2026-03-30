USE TLift_TestDB;
GO

CREATE OR ALTER PROCEDURE dbo.SearchOrders
    @CustomerID INT = NULL,
    @Status NVARCHAR(20) = NULL
AS
                                        --#[
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
                                        --#]
GO

DECLARE @dynsql NVARCHAR(MAX);

EXEC TLift_Engine.dbo.sp_tlift
    @DatabaseName   = 'TLift_TestDB',
    @ProcedureName  = 'SearchOrders',
    @Result         = @dynsql OUTPUT;

PRINT '--- GENERATED OUTPUT ---';
PRINT @dynsql;
PRINT '------------------------';
