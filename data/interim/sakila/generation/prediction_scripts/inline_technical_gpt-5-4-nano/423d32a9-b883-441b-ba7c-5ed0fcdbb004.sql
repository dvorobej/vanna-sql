WITH
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country_name,
    ct.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS cnt ON cnt.c01 = ct.d03
),
monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    date(p.p06, 'start of month') AS month_date,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_staff_store_count
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06),
    date(p.p06, 'start of month')
),
monthly_with_prev_avg AS (
  SELECT
    mp.*,
    AVG(mp.month_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_amount
  FROM monthly_pay AS mp
),
qualified AS (
  SELECT
    mwa.*,
    (mwa.month_amount - mwa.prev_months_avg_amount) AS deviation_from_prev_avg
  FROM monthly_with_prev_avg AS mwa
  WHERE mwa.prev_months_avg_amount IS NOT NULL
    AND mwa.payment_count >= 5
    AND mwa.month_amount >= 2.0 * mwa.prev_months_avg_amount
    AND (mwa.distinct_staff_count >= 2 OR mwa.distinct_staff_store_count >= 2)
),
ranked AS (
  SELECT
    q.*,
    cg.country_name,
    cg.city_name,
    cg.customer_name,
    RANK() OVER (
      PARTITION BY cg.country_name, q.month_date
      ORDER BY q.deviation_from_prev_avg DESC
    ) AS customer_country_month_rank
  FROM qualified AS q
  JOIN customer_geo AS cg
    ON cg.customer_id = q.customer_id
)
SELECT
  customer_id AS h01,
  customer_name,
  country_name AS cty_cnt_c02,
  city_name,
  month_start AS month,
  payment_count,
  ROUND(month_amount, 2) AS month_amount,
  ROUND(prev_months_avg_amount, 2) AS prev_months_avg_amount,
  ROUND(deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  customer_country_month_rank
FROM ranked
ORDER BY
  month_date,
  country_name,
  customer_country_month_rank,
  customer_id;