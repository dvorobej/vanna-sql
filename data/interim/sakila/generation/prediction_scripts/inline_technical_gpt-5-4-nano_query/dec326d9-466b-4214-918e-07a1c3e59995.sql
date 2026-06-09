WITH base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS payment_amount,
    DATE(p.p06) AS payment_date,
    cus.h02 AS home_store_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM pay p
  JOIN cus
    ON cus.h01 = p.p02
  JOIN adr a
    ON a.e01 = cus.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  JOIN cnt co
    ON co.c01 = ci.d03
),
windowed AS (
  SELECT
    b.customer_id,
    b.payment_date,
    b.country_name,
    b.city_name,
    b.home_store_id,
    b.staff_id,
    b.payment_amount,

    -- rolling 7-day window (including current date)
    (SELECT COALESCE(SUM(p2.p05), 0.0)
     FROM pay p2
     WHERE p2.p02 = b.customer_id
       AND DATE(p2.p06) BETWEEN DATE(b.payment_date, '-6 days') AND b.payment_date
    ) AS roll_sum_7d,

    (SELECT COALESCE(COUNT(*), 0)
     FROM pay p2
     WHERE p2.p02 = b.customer_id
       AND DATE(p2.p06) BETWEEN DATE(b.payment_date, '-6 days') AND b.payment_date
    ) AS roll_cnt_7d,

    -- historical previous 30 days (excluding current 7-day window end date)
    (SELECT AVG(p3.p05) * 7.0
     FROM pay p3
     WHERE p3.p02 = b.customer_id
       AND DATE(p3.p06) BETWEEN DATE(b.payment_date, '-36 days') AND DATE(b.payment_date, '-7 days')
    ) AS hist_avg_amount_per_txn_times_7,

    (SELECT COALESCE(COUNT(*), 0)
     FROM pay p3
     WHERE p3.p02 = b.customer_id
       AND DATE(p3.p06) BETWEEN DATE(b.payment_date, '-36 days') AND DATE(b.payment_date, '-7 days')
    ) AS hist_txn_cnt_30d
  FROM base b
),
suspicious_windows AS (
  SELECT *
  FROM windowed
  WHERE hist_txn_cnt_30d > 0
    AND roll_cnt_7d >= 5
    AND roll_sum_7d >= 3.0 * hist_avg_amount_per_txn_times_7
),
window_details AS (
  -- aggregate distinct staff/stores/films inside each suspicious 7-day window
  SELECT
    sw.customer_id,
    sw.payment_date,
    sw.country_name,
    sw.city_name,
    sw.home_store_id,
    sw.roll_sum_7d,
    sw.roll_cnt_7d,

    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT cus2.h02) AS distinct_store_count,

    COUNT(DISTINCT i.n02) AS distinct_rented_film_count
  FROM suspicious_windows sw
  JOIN pay p
    ON p.p02 = sw.customer_id
   AND DATE(p.p06) BETWEEN DATE(sw.payment_date, '-6 days') AND sw.payment_date
  JOIN cus cus2
    ON cus2.h01 = p.p02
  JOIN ren r
    ON r.q01 = p.p04
  JOIN inv i
    ON i.n01 = r.q03
  GROUP BY
    sw.customer_id,
    sw.payment_date,
    sw.country_name,
    sw.city_name,
    sw.home_store_id,
    sw.roll_sum_7d,
    sw.roll_cnt_7d
),
ranked AS (
  SELECT
    wd.*,
    RANK() OVER (ORDER BY wd.roll_sum_7d DESC) AS suspicious_customer_rank
  FROM window_details wd
)
SELECT
  ranked.customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  ranked.country_name,
  ranked.city_name,
  ranked.payment_date AS window_end_date,
  ranked.roll_cnt_7d AS window_payment_count_7d,
  ROUND(ranked.roll_sum_7d, 2) AS window_payment_sum_7d,
  ranked.distinct_staff_count,
  ranked.distinct_store_count,
  ranked.distinct_rented_film_count,
  ranked.suspicious_customer_rank
FROM ranked
JOIN cus c
  ON c.h01 = ranked.customer_id
ORDER BY
  ranked.suspicious_customer_rank,
  ranked.window_end_date,
  ranked.window_payment_sum_7d DESC;