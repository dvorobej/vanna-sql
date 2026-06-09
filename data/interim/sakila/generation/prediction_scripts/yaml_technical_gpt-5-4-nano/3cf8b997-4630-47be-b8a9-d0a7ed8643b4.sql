SELECT date('2005-01-01', '+' || (n) || ' months') AS month_start
  FROM (
    SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL
    SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL
    SELECT 10 UNION ALL SELECT 11
  )
),
pay_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start
  FROM pay p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
pay_with_rental AS (
  SELECT
    pb.*,
    r.q01 AS rental_id,
    r.q04 AS rental_customer_id,
    CASE WHEN p.p04 = r.q01 THEN 1 ELSE 0 END AS is_linked_pay_to_rental
  FROM pay_base pb
  LEFT JOIN ren r
    ON r.q01 = pb.payment_id  -- NOTE: placeholder join;