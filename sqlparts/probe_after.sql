select p.oid::regprocedure::text as fn,
       position('bos112' in d) > 0 as bos112, position('bos113' in d) > 0 as bos113,
       position('bos87'  in d) > 0 as bos87,  position('bos402' in d) > 0 as bos402
from pg_proc p, lateral (select pg_get_functiondef(p.oid) as d) x
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('lock_check','biz_items','customer_dues','sale_return','stock_receive_transfer')
order by 1;
