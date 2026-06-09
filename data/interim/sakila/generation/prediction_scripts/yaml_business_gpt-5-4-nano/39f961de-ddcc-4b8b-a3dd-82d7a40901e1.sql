WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    s.o07 AS store_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    a.e05 AS city_id,
    a.e05 AS customer_city_id,
    ci.d03 AS country_id,
    ci.d02 AS customer_country,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM ren r
        JOIN inv i ON i.n01 = r.q03
        JOIN flc fc ON fc.l01 = i.n02
        JOIN flm m ON m.i01 = i.n02
        WHERE r.q01 = p.p04
          AND (m.i11 IN ('R','NC-17'))
      )
      THEN 1
      ELSE 0
    END AS is_r_or_nc17
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN stf s
    ON s.o01 = p.p03
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  WHERE p.p06 IS NOT NULL
),
daily_customer AS (
  SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    customer_country,
    customer_city_id,
    payment_date,
    COUNT(payment_id) AS payment_count,
    SUM(payment_amount) AS daily_total_amount,
    MAX(payment_amount) AS max_payment_amount,
    COUNT(DISTINCT staff_id) AS staff_count,
    COUNT(DISTINCT store_id) AS store_count,
    SUM(is_r_or_nc17) AS r_or_nc17_payment_count,
    SUM(CASE WHEN is_r_or_nc17 = 1 THEN payment_amount ELSE 0 END) AS r_or_nc17_amount
  FROM payment_base
  GROUP BY
    customer_id,
    customer_first_name,
    customer_last_name,
    customer_country,
    customer_city_id,
    payment_date
),
daily_scored AS (
  SELECT
    dc.*,
    (
      SELECT AVG(d2.daily_total_amount)
      FROM daily_customer d2
      WHERE d2.customer_id = dc.customer_id
        AND d2.payment_date >= date(dc.payment_date, '-30 days')
        AND d2.payment_date < dc.payment_date
    ) AS avg_prev_30d_amount
  FROM daily_customer dc
),
suspicious_days AS (
  SELECT
    ds.*,
    (ds.daily_total_amount - ds.avg_prev_30d_amount) AS excess_amount
  FROM daily_scored ds
  WHERE ds.avg_prev_30d_amount IS NOT NULL
    AND ds.avg_prev_30d_amount > 0
    AND ds.daily_total_amount >= 2.0 * ds.avg_prev_30d_amount
    AND (ds.staff_count >= 2 OR ds.store_count >= 2)
)
SELECT
  sd.customer_id,
  sd.customer_first_name,
  sd.customer_last_name,
  sd.customer_country,
  sd.customer_city_id AS city_id,
  sd.payment_date,
  sd.payment_count,
  ROUND(sd.daily_total_amount, 2) AS daily_total_amount,
  ROUND(sd.max_payment_amount, 2) AS max_payment_amount,
  ROUND(
    1.0 * sd.r_or_nc17_amount / NULLIF(sd.daily_total_amount, 0),
    4
  ) AS r_nc17_payment_amount_share,
  RANK() OVER (
    PARTITION BY sd.customer_country
    ORDER BY sd.daily_total_amount DESC
  ) AS country_day_rank
FROM suspicious_days sd
ORDER BY
  sd.customer_country,
  country_day_rank,
  sd.customer_id,
  sd.payment_date;