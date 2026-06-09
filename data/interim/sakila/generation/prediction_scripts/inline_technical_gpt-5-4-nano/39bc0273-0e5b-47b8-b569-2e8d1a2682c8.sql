WITH
daily_monthly AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS monthly_amount,
    AVG(CAST(p.p05 AS REAL)) AS avg_check,
    COUNT(DISTINCT date(p.p06)) AS distinct_payment_dates
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  GROUP BY
    c.h01, c.h02, date(p.p06, 'start of month')
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c01 AS country_id,
    co.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
country_monthly_avg AS (
  SELECT
    dm.month_start,
    cg.country_id,
    AVG(dm.monthly_amount) AS avg_country_monthly_amount
  FROM daily_monthly AS dm
  JOIN customer_geo AS cg
    ON cg.customer_id = dm.customer_id
  GROUP BY
    dm.month_start, cg.country_id
),
monthly_with_prev AS (
  SELECT
    dm.*,
    cg.country_id,
    cg.country_name,
    LAG(dm.monthly_amount) OVER (
      PARTITION BY dm.customer_id
      ORDER BY dm.month_start
    ) AS prev_month_amount
  FROM daily_monthly AS dm
  JOIN customer_geo AS cg
    ON cg.customer_id = dm.customer_id
),
ranked AS (
  SELECT
    mwp.*,
    cma.avg_country_monthly_amount,
    CASE
      WHEN mwp.prev_month_amount IS NOT NULL AND mwp.prev_month_amount <> 0
      THEN mwp.monthly_amount / mwp.prev_month_amount
      ELSE NULL
    END AS growth_ratio_vs_prev_month,
    RANK() OVER (
      PARTITION BY mwp.country_id, mwp.month_start
      ORDER BY mwp.monthly_amount DESC
    ) AS customer_amount_rank_in_country
  FROM monthly_with_prev AS mwp
  JOIN country_monthly_avg AS cma
    ON cma.month_start = mwp.month_start
   AND cma.country_id = mwp.country_id
),
top_staff_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(CAST(p.p05 AS REAL)) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.p03
    ) AS rn
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
),
filtered AS (
  SELECT
    r.*
  FROM ranked AS r
  WHERE
    (
      r.growth_ratio_vs_prev_month IS NOT NULL
      AND r.growth_ratio_vs_prev_month >= 3.0
    )
    OR (
      r.avg_country_monthly_amount IS NOT NULL
      AND r.avg_country_monthly_amount <> 0
      AND r.monthly_amount / r.avg_country_monthly_amount > 2.0
    )
)
SELECT
  f.customer_id AS h01,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  f.month_start AS month,
  ROUND(f.monthly_amount, 2) AS monthly_amount,
  f.payment_count AS payment_count,
  ROUND(f.avg_check, 2) AS avg_check,
  f.distinct_payment_dates AS distinct_payment_dates,
  f.country_id AS c01,
  f.country_name AS cnt,
  f.customer_amount_rank_in_country AS country_month_amount_rank,
  s_top.staff_id AS top_staff_id,
  stf.o01 AS top_staff_o01,
  stf.o02 || ' ' || stf.o03 AS top_staff_name,
  f.store_id AS j01,
  sto.j01 AS store_j01
FROM filtered AS f
JOIN cus AS c
  ON c.h01 = f.customer_id
JOIN sto
  ON sto.j01 = f.store_id
LEFT JOIN top_staff_month AS s_top
  ON s_top.customer_id = f.customer_id
 AND s_top.month_start = f.month_start
 AND s_top.rn = 1
LEFT JOIN stf
  ON stf.o01 = s_top.staff_id
ORDER BY
  f.month_start,
  f.country_name,
  f.monthly_amount DESC,
  f.customer_id;