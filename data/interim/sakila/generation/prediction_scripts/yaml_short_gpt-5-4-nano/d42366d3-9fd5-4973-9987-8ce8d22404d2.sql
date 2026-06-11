WITH
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS home_store_id,
    cnt.c02 AS country_name,
    city.d02 AS city_name
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty city ON city.d01 = a.e05
  JOIN cnt ON cnt.c01 = city.d03
),
monthly_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(CAST(p.p05 AS REAL)) AS month_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    SUM(CASE WHEN st.o07 <> c.home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_staff_payment_share
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN stf st ON st.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
personal_prev2 AS (
  SELECT
    mc.*,
    (LAG(mc.month_amount, 1) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
    ) + LAG(mc.month_amount, 2) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
    )) / 2.0 AS personal_avg_prev2
  FROM monthly_customer mc
),
country_days_95 AS (
  SELECT
    country_name,
    month_start,
    month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY country_name, month_start
      ORDER BY month_amount
    ) AS rn,
    COUNT(*) OVER (PARTITION BY country_name, month_start) AS cnt
  FROM (
    SELECT
      cg.country_name,
      mc.month_start,
      mc.month_amount
    FROM monthly_customer mc
    JOIN customer_geo cg ON cg.customer_id = mc.customer_id
  )
),
country_percentile_95 AS (
  SELECT
    country_name,
    month_start,
    AVG(month_amount) AS country_p95_month_amount
  FROM country_days_95
  WHERE rn >= CAST((95.0 * cnt + 1) / 100 AS INTEGER)
  GROUP BY country_name, month_start
),
scored AS (
  SELECT
    pp.customer_id,
    pp.month_start,
    cg.country_name,
    pp.month_amount,
    pp.payment_count,
    pp.staff_count,
    pp.off_home_staff_payment_share,
    pp.personal_avg_prev2,
    (pp.month_amount - pp.personal_avg_prev2) AS deviation_from_personal_avg_prev2,
    cp.country_p95_month_amount,
    CASE
      WHEN cp.country_p95_month_amount > 0
      THEN pp.month_amount / cp.country_p95_month_amount
      ELSE NULL
    END AS ratio_to_country_p95
  FROM personal_prev2 pp
  JOIN customer_geo cg ON cg.customer_id = pp.customer_id
  JOIN country_percentile_95 cp
    ON cp.country_name = cg.country_name
   AND cp.month_start = pp.month_start
  WHERE pp.personal_avg_prev2 IS NOT NULL
    AND pp.personal_avg_prev2 > 0
    AND pp.month_amount > 3.0 * pp.personal_avg_prev2
    AND pp.off_home_staff_payment_share > 0
),
ranked AS (
  SELECT
    s.*,
    RANK() OVER (
      PARTITION BY s.country_name, s.month_start
      ORDER BY s.month_amount DESC
    ) AS country_month_amount_rank
  FROM scored s
)
SELECT
  customer_id,
  country_name AS country,
  date(month_start) AS month_start,
  ROUND(month_amount, 2) AS month_payment_amount,
  payment_count,
  staff_count,
  ROUND(off_home_staff_payment_share, 4) AS off_home_staff_payment_share,
  ROUND(personal_avg_prev2, 2) AS personal_avg_prev2,
  ROUND(deviation_from_personal_avg_prev2, 2) AS deviation_from_personal_avg_prev2,
  ROUND(country_p95_month_amount, 2) AS country_p95_month_amount,
  country_month_amount_rank
FROM ranked
ORDER BY
  country,
  month_start,
  country_month_amount_rank,
  customer_id;