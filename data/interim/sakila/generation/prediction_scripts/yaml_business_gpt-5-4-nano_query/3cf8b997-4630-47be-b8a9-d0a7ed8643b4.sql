WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS home_store_id,
    s.j04 AS store_last_update_dummy, -- не используем, чтобы не конфликтовать;