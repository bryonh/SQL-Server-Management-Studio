USE [DEPLcontrol]
GO
/****** Object:  UserDefinedFunction [dbo].[GetGoodFriday]    Script Date: 10/4/2013 11:02:04 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 
CREATE FUNCTION [dbo].[GetGoodFriday] 
( 
    @Y INT 
) 
RETURNS SMALLDATETIME 
AS 
BEGIN 
    RETURN (SELECT dbo.GetEasterSunday(@Y) - 2) 
END 

GO
