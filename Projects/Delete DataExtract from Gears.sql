  
  DELETE [gears].[dbo].[PROJECT_COMPONENTS]
  WHERE [project_id] = 844
  AND [component_id] = 157
  
  DELETE [gears].[dbo].[BUILD_REQUEST_COMPONENTS]
  WHERE build_request_id IN (59500,59502,59503)
  AND component_id = 157
  
  
  