create table uploads_and_progress (
  id varchar2(32), -- the date of an upload
  rows_loaded_so_far int, -- starts at zero,  works its way up from there
  total_rows_to_load int,  
  completed int -- 0 for incomplete, 1 for complete
);
  