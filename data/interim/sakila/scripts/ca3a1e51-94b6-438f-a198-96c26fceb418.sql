WITH payment_enriched AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    p.p05 AS payment_amount,
    p.p03 AS staff_id,
    s.o02 || ' ' || s.o03 AS staff_name,
    COALESCE(i.n03, s.o07) AS store_id
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
),
daily_payments AS (
  SELECT
    customer_id,
    payment_date,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS daily_payment_sum,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT store_id) AS distinct_store_count,
    group_concat(DISTINCT CAST(store_id AS TEXT)) AS stores,
    group_concat(DISTINCT CAST(staff_id AS TEXT) || ':' || staff_name) AS staff_members
  FROM payment_enriched
  GROUP BY
    customer_id,
    payment_date
),
daily_with_norm AS (
  SELECT
    d.customer_id,
    d.payment_date,
    d.payment_count,
    d.daily_payment_sum,
    d.distinct_staff_count,
    d.distinct_store_count,
    d.stores,
    d.staff_members,
    COALESCE(SUM(p.daily_payment_sum), 0) / 30.0 AS avg_daily_sum_prev_30d,
    COUNT(p.payment_date) AS payment_days_prev_30d
  FROM daily_payments AS d
  LEFT JOIN daily_payments AS p
    ON p.customer_id = d.customer_id
   AND p.payment_date >= date(d.payment_date, '-30 days')
   AND p.payment_date < d.payment_date
  GROUP BY
    d.customer_id,
    d.payment_date,
    d.payment_count,
    d.daily_payment_sum,
    d.distinct_staff_count,
    d.distinct_store_count,
    d.stores,
    d.staff_members
),
flagged AS (
  SELECT
    *,
    daily_payment_sum - avg_daily_sum_prev_30d AS deviation_amount,
    daily_payment_sum / avg_daily_sum_prev_30d AS deviation_ratio
  FROM daily_with_norm
  WHERE payment_count >= 3
    AND (distinct_staff_count >= 2 OR distinct_store_count >= 2)
    AND avg_daily_sum_prev_30d > 0
    AND daily_payment_sum > avg_daily_sum_prev_30d * 2
)
SELECT
  f.customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  city.d02 AS city,
  country.c02 AS country,
  f.payment_date,
  f.payment_count,
  ROUND(f.daily_payment_sum, 2) AS daily_payment_sum,
  f.distinct_store_count,
  f.stores,
  f.distinct_staff_count,
  f.staff_members,
  ROUND(f.avg_daily_sum_prev_30d, 2) AS avg_daily_sum_prev_30d,
  ROUND(f.deviation_amount, 2) AS deviation_amount,
  ROUND(f.deviation_ratio, 2) AS deviation_ratio,
  RANK() OVER (
    PARTITION BY f.customer_id
    ORDER BY f.deviation_amount DESC
  ) AS deviation_rank
FROM flagged AS f
JOIN cus AS c
  ON c.h01 = f.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty AS city
  ON city.d01 = a.e05
JOIN cnt AS country
  ON country.c01 = city.d03
ORDER BY
  f.customer_id,
  deviation_rank,
  f.payment_date;