-- Check: must return NO rows after all parts.
select * from public._i2_state() where not present;
