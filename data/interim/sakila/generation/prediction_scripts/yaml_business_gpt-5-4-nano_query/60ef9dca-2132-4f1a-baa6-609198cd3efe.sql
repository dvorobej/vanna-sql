WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    strftime('%Y-%m', p.p06) AS month_key
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS registration_store_id,
    ci.d02 AS city,
    cn.c02 AS country
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    p.customer_id,
    p.month_start,
    COUNT(p.payment_id) AS payment_count,
    SUM(p.payment_amount) AS monthly_amount
  FROM payments_2005 AS p
  GROUP BY
    p.customer_id,
    p.month_start
),
personal_avg AS (
  SELECT
    customer_id,
    AVG(monthly_amount) AS personal_avg_monthly_amount
  FROM monthly_customer
  GROUP BY customer_id
),
store_monthly AS (
  SELECT
    p.customer_id,
    p.month_start,
    c.registration_store_id,
    COUNT(p.payment_id) AS store_customer_month_payment_count,
    SUM(p.payment_amount) AS store_customer_month_amount
  FROM payments_2005 AS p
  JOIN customer_geo AS c
    ON c.customer_id = p.customer_id
  GROUP BY
    p.customer_id,
    p.month_start,
    c.registration_store_id
),
store_monthly_ranked AS (
  SELECT
    sm.customer_id,
    sm.month_start,
    sm.registration_store_id AS store_id,
    sm.store_customer_month_amount,
    RANK() OVER (
      PARTITION BY sm.registration_store_id, sm.month_start
      ORDER BY sm.store_customer_month_amount DESC
    ) AS store_month_customer_rank,
    (1.0 * DENSE_RANK() OVER (
      PARTITION BY sm.registration_store_id, sm.month_start
      ORDER BY sm.store_customer_month_amount DESC
    )) AS dense_rank_tmp,
    (1.0 * COUNT(*) OVER (
      PARTITION BY sm.registration_store_id, sm.month_start
    )) AS store_month_customer_cnt
  FROM store_monthly AS sm
),
top5pct_ok AS (
  SELECT
    smr.customer_id,
    smr.month_start,
    smr.store_id,
    smr.store_customer_month_amount,
    smr.store_month_customer_rank
  FROM store_monthly_ranked AS smr
  WHERE smr.store_month_customer_rank <= CEIL(0.05 * smr.store_month_customer_cnt)
),
all_months_flag AS (
  SELECT
    pi.customer_id,
    COUNT(*) AS months_cnt_meeting_condition
  FROM (
    SELECT
      mc.customer_id,
      mc.month_start,
      mc.monthly_amount,
      pa.personal_avg_monthly_amount,
      t5.store_id,
      t5.store_month_customer_rank
    FROM monthly_customer AS mc
    JOIN personal_avg AS pa
      ON pa.customer_id = mc.customer_id
    JOIN top5pct_ok AS t5
      ON t5.customer_id = mc.customer_id
     AND t5.month_start = mc.month_start
     AND t5.store_id = (SELECT registration_store_id FROM customer_geo cg WHERE cg.customer_id = mc.customer_id)
    WHERE mc.monthly_amount > pa.personal_avg_monthly_amount * 2
  ) pi
  GROUP BY pi.customer_id
)
SELECT
  ag.customer_id,
  cg.registration_store_id AS store_id,
  cg.city,
  cg.country,
  strftime('%Y-%m', mc.month_start) AS month,
  ROUND(mc.monthly_amount, 2) AS month_amount,
  mc.payment_count,
  ROUND(mc.monthly_amount - pa.personal_avg_monthly_amount, 2) AS deviation_from_personal_avg,
  smr.store_month_customer_rank AS store_month_rank,
  last_staff.staff_id AS last_staff_id
FROM all_months_flag AS am
JOIN monthly_customer AS mc
  ON mc.customer_id = am.customer_id
JOIN personal_avg AS pa
  ON pa.customer_id = mc.customer_id
JOIN customer_geo AS cg
  ON cg.customer_id = mc.customer_id
JOIN store_monthly_ranked AS smr
  ON smr.customer_id = mc.customer_id
 AND smr.month_start = mc.month_start
 AND smr.store_id = cg.registration_store_id
JOIN (
  SELECT
    p.customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id
  FROM payments_2005 AS p
  JOIN (
    SELECT
      customer_id,
      date(p06, 'start of month') AS month_start,
      MAX(p06) AS max_payment_ts
    FROM pay
    WHERE p06 >= '2005-01-01' AND p06 < '2006-01-01'
    GROUP BY customer_id, date(p06, 'start of month')
  ) mx
    ON mx.customer_id = p.customer_id
   AND mx.month_start = date(p.p06, 'start of month')
   AND p.p06 = mx.max_payment_ts
) AS last_staff
  ON last_staff.customer_id = mc.customer_id
 AND last_staff.month_start = mc.month_start
JOIN all_months_flag AS ag
  ON ag.customer_id = am.customer_id
WHERE ag.months_cnt_meeting_condition = 12
  AND mc.monthly_amount > pa.personal_avg_monthly_amount * 2
ORDER BY
  cg.country, cg.city, cg.registration_store_id, mc.month_start, ag.customer_id;