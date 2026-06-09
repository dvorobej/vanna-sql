WITH RECURSIVE months(month_start) AS (
  SELECT date('2000-01-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2030-01-01')
),
payment_monthly AS (
  SELECT
    p.p02 AS customer_id,
    p.p04 AS rental_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_total_amount,
    MAX(CAST(p.p05 AS REAL)) AS max_payment_amount
  FROM pay AS p
  WHERE p.p06 IS NOT NULL
  GROUP BY
    p.p02,
    p.p04,
    date(p.p06, 'start of month')
),
monthly_customer AS (
  SELECT
    pm.customer_id,
    pm.month_start,
    pm.payment_count,
    pm.month_total_amount,
    pm.max_payment_amount
  FROM payment_monthly pm
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_month_total_amount,
    COUNT(*) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_cnt
  FROM monthly_customer mc
),
country_month_payment_counts AS (
  SELECT
    c.h01 AS customer_id,
    cn.c01 AS country_id,
    date(p.p06, 'start of month') AS month_start
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  JOIN cnt cn
    ON cn.c01 = ci.d03
),
country_month_customer_payments AS (
  SELECT
    p.p02 AS customer_id,
    cn.c01 AS country_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS month_payment_count
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  JOIN cnt cn
    ON cn.c01 = ci.d03
  GROUP BY
    p.p02,
    cn.c01,
    date(p.p06, 'start of month')
),
country_month_median_payment_count AS (
  SELECT
    cmcp.country_id,
    cmcp.month_start,
    AVG(cmcp.month_payment_count) AS country_median_payment_count
  FROM (
    SELECT
      cmcp.*,
      ROW_NUMBER() OVER (
        PARTITION BY cmcp.country_id, cmcp.month_start
        ORDER BY cmcp.month_payment_count
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY cmcp.country_id, cmcp.month_start
      ) AS cnt
    FROM country_month_customer_payments cmcp
  ) x
  WHERE rn IN (CAST((cnt + 1) / 2 AS INTEGER), CAST((cnt + 2) / 2 AS INTEGER))
  GROUP BY cmcp.country_id, cmcp.month_start
),
action_new_payment_shares AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(CASE WHEN cat.g02 IN ('Action') THEN  CAST(p.p05 AS REAL) ELSE 0 END) AS action_amount,
    SUM(CASE WHEN cat.g02 IN ('New') THEN CAST(p.p05 AS REAL) ELSE 0 END) AS new_amount,
    SUM(CAST(p.p05 AS REAL)) AS total_amount
  FROM pay p
  JOIN ren r
    ON r.q01 = p.p04
  JOIN inv i
    ON i.n01 = r.q03
  JOIN flc fc
    ON fc.l01 = i.n02
  JOIN cat
    ON cat.g01 = fc.l02
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
country_customer_rank AS (
  SELECT
    cm.customer_id,
    cm.month_start,
    DENSE_RANK() OVER (
      PARTITION BY cn.c01, cm.month_start
      ORDER BY cm.month_total_amount DESC
    ) AS country_rank
  FROM monthly_with_history cm
  JOIN cus c
    ON c.h01 = cm.customer_id
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  JOIN cnt cn
    ON cn.c01 = ci.d03
)
SELECT
  ctry.c02 AS customer_country,
  city.d02 AS customer_city,
  c.h02 AS store_id,
  mh.month_start AS payment_month,
  mh.payment_count,
  ROUND(mh.month_total_amount, 2) AS month_total_amount,
  ROUND(mh.max_payment_amount, 2) AS max_payment_amount,
  ROUND(
    (CASE
      WHEN COALESCE(an.total_amount, 0) > 0
      THEN (COALESCE(an.action_amount, 0) + COALESCE(an.new_amount, 0)) / an.total_amount
    END), 4
  ) AS action_new_payment_share,
  ccr.country_rank
FROM monthly_with_history mh
JOIN cus c
  ON c.h01 = mh.customer_id
JOIN adr a
  ON a.e01 = c.h06
JOIN cty city
  ON city.d01 = a.e05
JOIN cnt ctry
  ON ctry.c01 = city.d03
JOIN country_customer_rank ccr
  ON ccr.customer_id = mh.customer_id
 AND ccr.month_start = mh.month_start
JOIN country_month_median_payment_count cmmed
  ON cmmed.country_id = ctry.c01
 AND cmmed.month_start = mh.month_start
LEFT JOIN action_new_payment_shares an
  ON an.customer_id = mh.customer_id
 AND an.month_start = mh.month_start
WHERE mh.prev_months_cnt > 0
  AND mh.personal_avg_month_total_amount IS NOT NULL
  AND mh.personal_avg_month_total_amount > 0
  AND mh.month_total_amount > 3.0 * mh.personal_avg_month_total_amount
  AND mh.payment_count > cmmed.country_median_payment_count
ORDER BY
  mh.month_start,
  ctry.c02,
  ccr.country_rank,
  mh.month_total_amount DESC;