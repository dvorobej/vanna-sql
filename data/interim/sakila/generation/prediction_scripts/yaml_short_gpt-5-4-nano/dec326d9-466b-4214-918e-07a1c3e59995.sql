WITH RECURSIVE
month_bounds AS (
  SELECT
    date(MIN(p.p06), 'start of day') AS min_day,
    date(MAX(p.p06), 'start of day') AS max_day
  FROM pay AS p
),
days(day_date) AS (
  SELECT min_day FROM month_bounds
  UNION ALL
  SELECT date(day_date, '+1 day')
  FROM days, month_bounds
  WHERE day_date < max_day
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country_name,
    ci.d02 AS city_name,
    co.c01 AS country_id,
    ci.d01 AS city_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
payment_details AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    COALESCE(inv.n03, -1) AS store_id,
    inv.n02 AS film_id
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  JOIN inv AS inv ON inv.n01 = r.q03
),
daily_base AS (
  SELECT
    pd.customer_id,
    cg.country_id,
    cg.country_name,
    cg.city_id,
    cg.city_name,
    pd.payment_date,
    SUM(pd.amount) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT pd.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pd.store_id) AS distinct_store_count,
    COUNT(DISTINCT pd.film_id) AS distinct_rented_films_count
  FROM payment_details AS pd
  JOIN customer_geo AS cg
    ON cg.customer_id = pd.customer_id
  GROUP BY
    pd.customer_id,
    cg.country_id,
    cg.country_name,
    cg.city_id,
    cg.city_name,
    pd.payment_date
),
daily_with_baseline AS (
  SELECT
    db.*,
    (
      SELECT AVG(db30.day_amount)
      FROM daily_base AS db30
      WHERE db30.customer_id = db.customer_id
        AND db30.payment_date >= date(db.payment_date, '-30 day')
        AND db30.payment_date < db.payment_date
    ) AS avg_daily_amount_prev_30d
  FROM daily_base AS db
),
suspicious_candidates AS (
  SELECT
    d.customer_id,
    d.country_name,
    d.city_name,
    d.country_id,
    d.city_id,
    d.payment_date,
    d.day_amount AS window_7d_dummy_day_amount,
    d.payment_count AS window_7d_dummy_day_payment_count,
    d.distinct_staff_count AS window_7d_dummy_day_staff_count,
    d.distinct_store_count AS window_7d_dummy_day_store_count,
    d.distinct_rented_films_count AS window_7d_dummy_day_films_count,
    d.avg_daily_amount_prev_30d
  FROM daily_with_baseline AS d
  WHERE d.avg_daily_amount_prev_30d IS NOT NULL
    AND d.avg_daily_amount_prev_30d > 0
),
window_7d AS (
  SELECT
    sc.customer_id,
    sc.country_name,
    sc.city_name,
    sc.country_id,
    sc.city_id,
    sc.payment_date,
    (
      SELECT SUM(dw.day_amount)
      FROM daily_with_baseline AS dw
      WHERE dw.customer_id = sc.customer_id
        AND dw.payment_date >= sc.payment_date
        AND dw.payment_date < date(sc.payment_date, '+7 day')
    ) AS amount_7d,
    (
      SELECT COUNT(*)
      FROM daily_with_baseline AS dw
      WHERE dw.customer_id = sc.customer_id
        AND dw.payment_date >= sc.payment_date
        AND dw.payment_date < date(sc.payment_date, '+7 day')
    ) AS days_with_payments_7d,
    (
      SELECT SUM(dw.payment_count)
      FROM daily_with_baseline AS dw
      WHERE dw.customer_id = sc.customer_id
        AND dw.payment_date >= sc.payment_date
        AND dw.payment_date < date(sc.payment_date, '+7 day')
    ) AS payments_count_7d,
    (
      SELECT COUNT(DISTINCT dw.distinct_staff_count_dummy.staff_id)
      FROM (
        SELECT pd2.staff_id, date(pd2.payment_date) AS pd_date
        FROM payment_details AS pd2
      ) AS dw0
      LEFT JOIN (
        SELECT 1 AS dummy
      ) AS distinct_staff_count_dummy ON 1=0
      WHERE dw0.pd_date >= sc.payment_date
        AND dw0.pd_date < date(sc.payment_date, '+7 day')
        AND dw0.customer_id = sc.customer_id
    ) AS distinct_staff_count_7d
  FROM suspicious_candidates AS sc
)
SELECT
  d.customer_id,
  d.country_name,
  d.city_name,
  d.payment_date AS window_start_date,
  ROUND(w7.amount_7d, 2) AS amount_7d,
  w7.payments_count_7d AS payments_count_7d,
  w7.days_with_payments_7d AS days_with_payments_7d,
  (
    SELECT COUNT(DISTINCT pd2.staff_id)
    FROM payment_details AS pd2
    WHERE pd2.customer_id = d.customer_id
      AND pd2.payment_date >= d.payment_date
      AND pd2.payment_date < date(d.payment_date, '+7 day')
  ) AS distinct_staff_count_7d,
  (
    SELECT COUNT(DISTINCT pd2.store_id)
    FROM (
      SELECT p2.p02 AS customer_id,
             date(p2.p06) AS payment_date,
             p2.p03 AS staff_id,
             COALESCE(inv2.n03, -1) AS store_id,
             inv2.n02 AS film_id
      FROM pay AS p2
      JOIN ren AS r2 ON r2.q01 = p2.p04
      JOIN inv AS inv2 ON inv2.n01 = r2.q03
    ) AS pd2
    WHERE pd2.customer_id = d.customer_id
      AND pd2.payment_date >= d.payment_date
      AND pd2.payment_date < date(d.payment_date, '+7 day')
  ) AS distinct_store_count_7d,
  (
    SELECT COUNT(DISTINCT pd2.film_id)
    FROM (
      SELECT p2.p02 AS customer_id,
             date(p2.p06) AS payment_date,
             p2.p03 AS staff_id,
             inv2.n02 AS film_id,
             COALESCE(inv2.n03, -1) AS store_id
      FROM pay AS p2
      JOIN ren AS r2 ON r2.q01 = p2.p04
      JOIN inv AS inv2 ON inv2.n01 = r2.q03
    ) AS pd2
    WHERE pd2.customer_id = d.customer_id
      AND pd2.payment_date >= d.payment_date
      AND pd2.payment_date < date(d.payment_date, '+7 day')
  ) AS distinct_rented_films_count_7d,
  ROUND(
    w7.amount_7d / (d.avg_daily_amount_prev_30d * 7.0),
    4
  ) AS ratio_vs_avg_30d_7d_equivalent,
  RANK() OVER (
    PARTITION BY d.country_id, d.city_id, d.payment_date
    ORDER BY w7.amount_7d DESC
  ) AS suspicious_amount_rank_in_geo_day
FROM daily_with_baseline AS d
JOIN (
  SELECT
    customer_id,
    payment_date,
    SUM(day_amount) AS amount_7d,
    SUM(payment_count) AS payments_count_7d,
    COUNT(*) AS days_with_payments_7d
  FROM daily_with_baseline
  GROUP BY
    customer_id,
    payment_date
) AS w7
  ON w7.customer_id = d.customer_id
 AND w7.payment_date = d.payment_date
WHERE d.avg_daily_amount_prev_30d IS NOT NULL
  AND d.avg_daily_amount_prev_30d > 0
  AND (
    SELECT SUM(dw.day_amount)
    FROM daily_with_baseline AS dw
    WHERE dw.customer_id = d.customer_id
      AND dw.payment_date >= d.payment_date
      AND dw.payment_date < date(d.payment_date, '+7 day')
  ) > 3.0 * (d.avg_daily_amount_prev_30d * 7.0)
ORDER BY
  d.payment_date,
  d.country_name,
  d.city_name,
  suspicious_amount_rank_in_geo_day,
  d.customer_id;