WITH payment_enriched AS (
  SELECT
    p.p02 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    date(p.p06) AS payment_day,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    s.o07 AS store_id,
    cnt.c02 AS country_name,
    cnt.c01 AS country_id
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN stf s ON s.o01 = p.p03
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
daily AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    payment_day,
    country_id,
    country_name,
    COUNT(*) AS payment_count,
    SUM(amount) AS day_amount,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT store_id) AS distinct_store_count
  FROM payment_enriched
  GROUP BY
    customer_id,
    first_name,
    last_name,
    payment_day,
    country_id,
    country_name
),
daily_with_prev_avg AS (
  SELECT
    d.*,
    COALESCE((
      SELECT AVG(d2.day_amount)
      FROM daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_day >= date(d.payment_day, '-30 days')
        AND d2.payment_day < d.payment_day
    ), 0.0) AS avg_prev_30d
  FROM daily d
),
country_daily_ranked AS (
  SELECT
    dw.*,
    RANK() OVER (
      PARTITION BY dw.country_id
      ORDER BY dw.day_amount DESC
    ) AS day_amount_rank_in_country
  FROM daily_with_prev_avg dw
)
SELECT
  customer_id,
  first_name,
  last_name,
  payment_day,
  payment_count,
  ROUND(day_amount, 2) AS day_amount,
  ROUND(avg_prev_30d, 2) AS avg_prev_30d,
  ROUND(day_amount / NULLIF(avg_prev_30d, 0.0), 2) AS exceed_ratio_over_customer_avg,
  country_id,
  country_name,
  distinct_staff_count,
  distinct_store_count,
  day_amount_rank_in_country
FROM country_daily_ranked
WHERE avg_prev_30d > 0
  AND day_amount > 3.0 * avg_prev_30d
  AND (
    distinct_staff_count > 1
    OR distinct_store_count > 1
  )
ORDER BY
  country_name,
  day_amount_rank_in_country,
  day_amount DESC,
  payment_day,
  customer_id;