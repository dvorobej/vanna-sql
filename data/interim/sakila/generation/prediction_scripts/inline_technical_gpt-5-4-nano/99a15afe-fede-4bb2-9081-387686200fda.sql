WITH monthly_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount,
    COUNT(p.p01) AS payment_count,
    COUNT(DISTINCT p.p03) AS distinct_staff_count
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_amount
  FROM monthly_customer AS mc
),
customer_store_country AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    c.h06 AS address_id,
    date('now') AS dummy
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt ON cnt.c01 = ct.d03
),
monthly_scored AS (
  SELECT
    mwh.customer_id,
    mwh.month_start,
    mwh.month_amount,
    mwh.payment_count,
    mwh.distinct_staff_count,
    csc.store_id,
    csc.country_id,
    mwh.prev_avg_month_amount
  FROM monthly_with_history AS mwh
  JOIN customer_store_country AS csc
    ON csc.customer_id = mwh.customer_id
  WHERE mwh.prev_avg_month_amount IS NOT NULL
),
country_store_thresholds AS (
  SELECT
    store_id,
    country_id,
    month_start,
    (
      SELECT MAX(x.month_amount)
      FROM (
        SELECT
          ms.month_amount,
          NTILE(20) OVER (
            PARTITION BY ms.store_id, ms.country_id, ms.month_start
            ORDER BY ms.month_amount
          ) AS bucket
        FROM monthly_scored AS ms
      ) AS x
      WHERE x.bucket = 20
    ) AS amount_p95_or_top
  FROM monthly_scored
  GROUP BY store_id, country_id, month_start
),
qualifying_months AS (
  SELECT
    ms.*,
    cst.amount_p95_or_top
  FROM monthly_scored AS ms
  JOIN country_store_thresholds AS cst
    ON cst.store_id = ms.store_id
   AND cst.country_id = ms.country_id
   AND cst.month_start = ms.month_start
  WHERE ms.month_amount > 3.0 * ms.prev_avg_month_amount
    AND ms.month_amount > cst.amount_p95_or_top
),
return_penalty_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    AVG(
      CASE
        WHEN r.q05 IS NOT NULL AND r.q05 > r.q02 THEN 1.0
        ELSE 0.0
      END
    ) AS overdue_return_share
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_month_rank AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    c.h02 AS store_id,
    SUM(p.p05) AS month_amount_sum,
    RANK() OVER (
      PARTITION BY c.h02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC
    ) AS month_store_rank
  FROM pay AS p
  JOIN cus AS c ON c.h01 = p.p02
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    c.h02
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  ct.c02 AS country_name,
  cty.d02 AS city_name,
  c.h02 AS store_id AS j01,
  strftime('%Y-%m', q.month_start) AS month,
  ROUND(q.month_amount, 2) AS month_amount,
  q.payment_count,
  q.distinct_staff_count AS distinct_staff_count,
  ROUND(COALESCE(rps.overdue_return_share, 0), 4) AS overdue_return_share,
  cmr.month_store_rank AS month_store_rank
FROM qualifying_months AS q
JOIN cus AS c ON c.h01 = q.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt AS ct ON ct.c01 = cty.d03
LEFT JOIN return_penalty_share AS rps
  ON rps.customer_id = q.customer_id
 AND rps.month_start = q.month_start
LEFT JOIN customer_month_rank AS cmr
  ON cmr.customer_id = q.customer_id
 AND cmr.month_start = q.month_start
 AND cmr.store_id = q.store_id
ORDER BY
  ct.c02,
  cty.d02,
  q.month_start,
  q.month_amount DESC,
  c.h01;