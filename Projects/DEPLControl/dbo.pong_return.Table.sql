USE [DEPLcontrol]
GO
/****** Object:  Table [dbo].[pong_return]    Script Date: 10/4/2013 11:02:05 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[pong_return](
	[pong_ID] [int] IDENTITY(1,1) NOT NULL,
	[pong_stamp] [sysname] NOT NULL,
	[pong_servername] [sysname] NOT NULL,
	[pong_detail01] [sysname] NOT NULL,
	[pong_detail02] [sysname] NULL
) ON [PRIMARY]

GO
