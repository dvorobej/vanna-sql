WITH RECURSIVE months AS (
  SELECT date('2005-01-01') AS month_start
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2005-12-01')
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    ct.d02 AS city_name,
    cn.c02 AS country_name,
    cn.c01 AS country_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS cn ON cn.c01 = ct.d03
),
payment_monthly AS (
  SELECT
    p.p02 AS customer_id,
    date(strftime('%Y-%m-01', p.p06)) AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS total_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(strftime('%Y-%m-01', p.p06))
),
late_return_ratio AS (
  SELECT
    p.p02 AS customer_id,
    date(strftime('%Y-%m-01', p.p06)) AS month_start,
    AVG(
      CASE
        WHEN r.q05 IS NOT NULL
         AND julianday(r.q05) > julianday(r.q02, '+' || fl.i07 || ' days')
        THEN 1.0 ELSE 0.0
      END
    ) AS late_return_share
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  JOIN inv AS i ON i.n01 = r.q03
  JOIN flm AS fl ON fl.i01 = i.n02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(strftime('%Y-%m-01', p.p06))
),
country_month_avg AS (
  SELECT
    cg.country_id,
    pm.month_start,
    AVG(pm.total_amount) AS country_avg_monthly_amount
  FROM payment_monthly AS pm
  JOIN customer_geo AS cg ON cg.customer_id = pm.customer_id
  GROUP BY
    cg.country_id,
    pm.month_start
),
ranked AS (
  SELECT
    cg.country_name,
    cg.city_name,
    pm.month_start,
    pm.customer_id,
    pm.total_amount,
    pm.payment_count,
    pm.distinct_staff_count,
    pm.distinct_store_count,
    COALESCE(lr.late_return_share, 0.0) AS late_return_share,
    cma.country_avg_monthly_amount,
    RANK() OVER (
      PARTITION BY cg.country_id, pm.month_start
      ORDER BY pm.total_amount DESC, pm.customer_id
    ) AS country_month_rank
  FROM payment_monthly AS pm
  JOIN customer_geo AS cg ON cg.customer_id = pm.customer_id
  JOIN country_month_avg AS cma
    ON cma.country_id = cg.country_id
   AND cma.month_start = pm.month_start
  LEFT JOIN late_return_ratio AS lr
    ON lr.customer_id = pm.customer_id
   AND lr.month_start = pm.month_start
  WHERE pm.payment_count >= 3
    AND (pm.distinct_staff_count >= 3 OR pm.distinct_store_count >= 3)
)
SELECT
  strftime('%Y-%m', month_start) AS payment_month,
  country_name,
  city_name,
  ROUND(total_amount, 2) AS total_amount,
  payment_count,
  ROUND(late_return_share, 4) AS late_return_share,
  country_month_rank
FROM ranked
WHERE total_amount > 1.5 * country_avg_monthly_amount
ORDER BY
  payment_month,
  country_name,
  country_month_rank,
  total_amount DESC,
  city_name;