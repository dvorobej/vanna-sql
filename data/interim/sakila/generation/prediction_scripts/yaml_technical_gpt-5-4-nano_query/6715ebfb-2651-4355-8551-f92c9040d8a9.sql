WITH RECURSIVE months(month_start) AS (
  SELECT date('2004-11-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2006-01-01')
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS home_store_id,
    ct.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS ct ON ct.c01 = ci.d03
),
monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_total_amount,
    MAX(CAST(p.p05 AS REAL)) AS month_max_payment,
    SUM(CASE WHEN r.q01 IS NOT NULL AND cat.g02 IN ('Action','New') THEN CAST(p.p05 AS REAL) ELSE 0 END) AS amount_action_new,
    COUNT(CASE WHEN r.q01 IS NOT NULL AND cat.g02 IN ('Action','New') THEN 1 END) AS cnt_action_new
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  JOIN inv AS i ON i.n01 = r.q03
  JOIN flc AS fc ON fc.l01 = i.n02
  JOIN cat ON cat.g01 = fc.l02
  WHERE p.p04 IS NOT NULL
    AND p.p06 >= '2004-12-01' AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_complete AS (
  SELECT
    cg.customer_id,
    cg.country_name,
    cg.city_name,
    mp.month_start,
    mp.payment_count,
    mp.month_total_amount,
    mp.month_max_payment,
    mp.amount_action_new,
    mp.cnt_action_new
  FROM customer_geo AS cg
  CROSS JOIN months AS m
  LEFT JOIN monthly_pay AS mp
    ON mp.customer_id = cg.customer_id
   AND mp.month_start = m.month_start
  WHERE m.month_start >= '2005-01-01' AND m.month_start < '2006-01-01'
),
scored AS (
  SELECT
    mc.*,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_hist_avg_amount,
    AVG(mc.payment_count) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_hist_avg_count,
    LAG(mc.month_total_amount) OVER (PARTITION BY mc.customer_id ORDER BY mc.month_start) AS prev_amount
  FROM monthly_complete AS mc
),
country_month_median AS (
  SELECT
    s.country_name,
    s.month_start,
    AVG(s.payment_count) AS country_month_median_payment_count
  FROM (
    SELECT
      s.*,
      ROW_NUMBER() OVER (
        PARTITION BY s.country_name, s.month_start
        ORDER BY s.payment_count
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY s.country_name, s.month_start
      ) AS cnt
    FROM scored AS s
    WHERE s.payment_count IS NOT NULL
  ) AS s
  WHERE s.rn IN (
    CAST((s.cnt + 1) / 2 AS INTEGER),
    CAST((s.cnt + 2) / 2 AS INTEGER)
  )
  GROUP BY
    s.country_name,
    s.month_start
),
suspicious AS (
  SELECT
    s.customer_id,
    s.country_name,
    s.city_name,
    s.month_start,
    s.payment_count,
    s.month_total_amount,
    s.month_max_payment,
    s.amount_action_new,
    s.personal_hist_avg_amount,
    cmm.country_month_median_payment_count
  FROM scored AS s
  JOIN country_month_median AS cmm
    ON cmm.country_name = s.country_name
   AND cmm.month_start = s.month_start
  WHERE s.personal_hist_avg_amount IS NOT NULL
    AND s.personal_hist_avg_amount > 0
    AND s.month_total_amount > 3.0 * s.personal_hist_avg_amount
    AND s.payment_count > cmm.country_month_median_payment_count
),
ranked AS (
  SELECT
    suspicious.*,
    RANK() OVER (
      PARTITION BY suspicious.country_name, suspicious.month_start
      ORDER BY suspicious.month_total_amount DESC
    ) AS suspicious_rank_in_country
  FROM suspicious
)
SELECT
  r.country_name AS country,
  r.city_name AS city,
  c.h02 AS store_id,
  r.month_start AS month,
  r.payment_count,
  ROUND(r.month_total_amount, 2) AS total_amount,
  ROUND(r.month_max_payment, 2) AS max_payment,
  ROUND(r.amount_action_new / NULLIF(r.month_total_amount, 0), 4) AS share_amount_action_new,
  r.suspicious_rank_in_country
FROM ranked AS r
JOIN cus AS c ON c.h01 = r.customer_id
ORDER BY
  r.month_start,
  r.country_name,
  r.suspicious_rank_in_country,
  r.month_total_amount DESC,
  r.customer_id;