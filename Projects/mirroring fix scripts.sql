ALTER ENDPOINT Mirroring STATE = STOPPED

ALTER ENDPOINT Mirroring STATE = STARTED

ALTER DATABASE [DeliveryDB] SET PARTNER SUSPEND;

ALTER DATABASE [DeliveryDB] SET PARTNER RESUME;


SELECT * FROM sys.database_mirroring_endpoints