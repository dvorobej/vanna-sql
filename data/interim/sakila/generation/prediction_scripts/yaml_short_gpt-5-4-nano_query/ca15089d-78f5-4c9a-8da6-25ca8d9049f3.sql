WITH monthly_payments AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_fio,
    co.c02 AS country,
    ci.d02 AS city,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS monthly_amount,
    MAX(p.p05) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(s.o07, -1)) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p06 IS NOT NULL
  GROUP BY
    c.h01, c.h03, c.h04,
    co.c02, ci.d02,
    strftime('%Y-%m', p.p06)
),
with_history AS (
  SELECT
    mp.*,
    AVG(mp.monthly_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.payment_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_months
  FROM monthly_payments AS mp
),
qualified AS (
  SELECT
    wh.*
  FROM with_history AS wh
  WHERE wh.personal_avg_prev_months IS NOT NULL
    AND wh.personal_avg_prev_months > 0
    AND wh.monthly_amount >= 3 * wh.personal_avg_prev_months
    AND wh.payment_count >= 3
    AND (wh.distinct_staff_count >= 2 OR wh.distinct_store_count >= 2)
),
ranked AS (
  SELECT
    q.*,
    RANK() OVER (
      PARTITION BY q.country, q.payment_month
      ORDER BY q.monthly_amount DESC
    ) AS customer_country_month_rank
  FROM qualified AS q
),
-- ensure "different days" requirement
daily_distinct_days AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(DISTINCT date(p.p06)) AS distinct_payment_days
  FROM pay AS p
  GROUP BY p.p02, strftime('%Y-%m', p.p06)
)
SELECT
  r.payment_month AS month,
  r.customer_fio AS fio,
  r.country,
  r.city,
  r.payment_count,
  ROUND(r.monthly_amount, 2) AS total_amount,
  ROUND(r.max_payment, 2) AS max_payment,
  ROUND(r.max_payment / NULLIF(r.monthly_amount, 0), 4) AS max_payment_share_in_month,
  r.distinct_staff_count AS different_staff_count,
  r.distinct_store_count AS different_store_count,
  r.customer_country_month_rank AS country_month_rank
FROM ranked AS r
JOIN daily_distinct_days AS d
  ON d.customer_id = r.customer_id
 AND d.payment_month = r.payment_month
WHERE d.distinct_payment_days >= 3
ORDER BY
  r.country,
  r.payment_month,
  r.customer_country_month_rank,
  r.customer_id;