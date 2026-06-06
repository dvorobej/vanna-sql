WITH RECURSIVE
payment_details AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    strftime('%Y-%m', p.p06) AS payment_month,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    stf.o07 AS store_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    ct.d02 AS city_name,
    cn.c02 AS country_name
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  JOIN stf AS stf
    ON stf.o01 = p.p03
),
daily_agg AS (
  SELECT
    customer_id,
    payment_date,
    payment_month,
    customer_name,
    city_name,
    country_name,
    SUM(amount) AS daily_amount,
    COUNT(*) AS daily_count,
    COUNT(DISTINCT staff_id) AS staff_count,
    COUNT(DISTINCT store_id) AS store_count
  FROM payment_details
  GROUP BY
    customer_id,
    payment_date,
    payment_month,
    customer_name,
    city_name,
    country_name
),
rolling_7d AS (
  SELECT
    d1.customer_id,
    d1.payment_month,
    d1.payment_date AS window_end,
    date(d1.payment_date, '-6 days') AS window_start,
    d1.customer_name,
    d1.city_name,
    d1.country_name,
    SUM(d2.daily_amount) AS window_amount,
    SUM(d2.daily_count) AS window_payment_count,
    COUNT(DISTINCT d2.staff_count) AS dummy_staff_group,
    COUNT(DISTINCT d2.store_count) AS dummy_store_group,
    SUM(d2.staff_count) AS staff_count,
    SUM(d2.store_count) AS store_count
  FROM daily_agg AS d1
  JOIN daily_agg AS d2
    ON d2.customer_id = d1.customer_id
   AND d2.payment_date BETWEEN date(d1.payment_date, '-6 days') AND d1.payment_date
  GROUP BY
    d1.customer_id,
    d1.payment_month,
    d1.payment_date,
    d1.customer_name,
    d1.city_name,
    d1.country_name
),
rolling_30d_baseline AS (
  SELECT
    r.*,
    (
      SELECT AVG(x.daily_amount)
      FROM daily_agg AS x
      WHERE x.customer_id = r.customer_id
        AND x.payment_date >= date(r.window_end, '-30 days')
        AND x.payment_date < r.window_end
    ) AS prev30_avg_daily_amount,
    (
      SELECT AVG(x.daily_count)
      FROM daily_agg AS x
      WHERE x.customer_id = r.customer_id
        AND x.payment_date >= date(r.window_end, '-30 days')
        AND x.payment_date < r.window_end
    ) AS prev30_avg_daily_count
  FROM rolling_7d AS r
),
qualified AS (
  SELECT
    *,
    (window_amount - prev30_avg_daily_amount * 7.0) AS amount_excess,
    (window_payment_count - prev30_avg_daily_count * 7.0) AS count_excess
  FROM rolling_30d_baseline
  WHERE prev30_avg_daily_amount IS NOT NULL
    AND prev30_avg_daily_count IS NOT NULL
    AND prev30_avg_daily_amount > 0
    AND prev30_avg_daily_count > 0
    AND window_amount >= prev30_avg_daily_amount * 7.0 * 3.0
    AND window_payment_count >= prev30_avg_daily_count * 7.0 * 3.0
    AND (
      EXISTS (
        SELECT 1
        FROM daily_agg AS z
        WHERE z.customer_id = qualified.customer_id
          AND z.payment_date BETWEEN qualified.window_start AND qualified.window_end
        GROUP BY z.customer_id
        HAVING SUM(CASE WHEN z.staff_count > 1 THEN 1 ELSE 0 END) > 0
           OR SUM(CASE WHEN z.store_count > 1 THEN 1 ELSE 0 END) > 0
      )
    )
)
SELECT
  payment_month,
  customer_id,
  customer_name,
  city_name,
  country_name,
  window_start,
  window_end,
  ROUND(window_amount, 2) AS window_amount,
  window_payment_count,
  ROUND(prev30_avg_daily_amount, 2) AS prev30_avg_daily_amount,
  ROUND(prev30_avg_daily_count, 2) AS prev30_avg_daily_count,
  staff_count AS involved_staff_count,
  store_count AS involved_store_count,
  ROUND(amount_excess, 2) AS amount_excess,
  ROUND(count_excess, 2) AS count_excess,
  RANK() OVER (
    PARTITION BY payment_month
    ORDER BY amount_excess DESC, count_excess DESC
  ) AS suspicion_rank
FROM qualified
ORDER BY
  payment_month,
  suspicion_rank,
  customer_id;