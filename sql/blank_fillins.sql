-- 
-- Oracle version
create table blank_fillins (
   cardmem_acnt_num varchar2(19) primary key, 
   surname varchar2(32),
   firstname varchar2(32),
   business_unit varchar2(8),
   department_id varchar2(8),
   distribution_point varchar2(32),
   location varchar2(32)
);

-- Postgresql version
--create table blank_fillins (
--   cardmem_acnt_num varchar(19) primary key, 
--   surname varchar(32),
--   firstname varchar(32),
--   business_unit varchar(8),
--   department_id varchar(8),
--   distribution_point varchar(32),
--   location varchar(32)
--);




