USE [DEPLcontrol]
GO
/****** Object:  StoredProcedure [dbo].[dpsp_Cancel_Gears_dummy]    Script Date: 10/4/2013 11:02:04 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[dpsp_Cancel_Gears_dummy] (@gears_id int = null)
  as
BEGIN
INSERT INTO dbo.dummyresults (data)
SELECT	'EXEC [DEPLcontrol].[dbo].[dpsp_Cancel_Gears]'
	+ ' @gears_id = ' +  CAST(@gears_id AS VarChar(20))
END

GO
