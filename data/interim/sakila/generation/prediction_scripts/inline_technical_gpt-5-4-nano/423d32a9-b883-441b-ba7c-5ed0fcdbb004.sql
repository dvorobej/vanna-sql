WITH monthly_customer AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_key,
    date(p.p06, 'start of month') AS month_start,
    c.h03 || ' ' || c.h04 AS customer_name,
    adr_cty.d02 AS city,
    cnt.c02 AS country,
    c.h02 AS customer_store_id,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_total_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS adr_cty
    ON adr_cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = adr_cty.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN ren AS r
    ON r.q01 = p.p04
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06),
    date(p.p06, 'start of month'),
    c.h03, c.h04,
    adr_cty.d02,
    cnt.c02,
    c.h02
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_amount,
    COUNT(*) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_count
  FROM monthly_customer AS mc
),
ranked AS (
  SELECT
    mwh.*,
    RANK() OVER (
      PARTITION BY mwh.country
      ORDER BY (mwh.month_total_amount - mwh.prev_months_avg_amount) DESC
    ) AS customer_country_rank
  FROM monthly_with_history AS mwh
)
SELECT
  r.month_key AS month,
  r.customer_id,
  r.customer_name,
  r.country,
  r.city,
  r.payment_count,
  ROUND(r.month_total_amount, 2) AS month_total_amount,
  ROUND(r.prev_months_avg_amount, 2) AS prev_months_avg_amount,
  ROUND(r.month_total_amount / NULLIF(r.prev_months_avg_amount, 0), 2) AS vs_prev_avg_multiplier,
  (r.month_total_amount - r.prev_months_avg_amount) AS deviation_from_prev_avg,
  r.distinct_staff_count,
  r.distinct_store_count,
  r.customer_country_rank
FROM ranked AS r
WHERE r.prev_months_count >= 1
  AND r.payment_count >= 5
  AND r.distinct_staff_count >= 2
   AND r.month_total_amount >= 2.0 * r.prev_months_avg_amount
ORDER BY
  r.country,
  r.month_key,
  r.customer_country_rank,
  r.month_total_amount DESC,
  r.customer_id;