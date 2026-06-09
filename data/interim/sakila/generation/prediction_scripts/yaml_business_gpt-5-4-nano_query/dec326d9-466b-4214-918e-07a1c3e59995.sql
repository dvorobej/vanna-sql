SELECT SUM(pe2.payment_amount)
      FROM payments_enriched pe2
      WHERE pe2.customer_id = pe.customer_id
        AND pe2.payment_day BETWEEN date(pe.payment_day, '-6 day') AND pe.payment_day
    ) AS window_sum_7d_calc,
    (
      SELECT COUNT(*)
      FROM payments_enriched pe2
      WHERE pe2.customer_id = pe.customer_id
        AND pe2.payment_day BETWEEN date(pe.payment_day, '-6 day') AND pe.payment_day
    ) AS window_count_7d_calc
  FROM payments_enriched pe
  GROUP BY pe.customer_id, pe.country_name, pe.city_name, pe.payment_day
),
history_30d AS (
  SELECT
    pe.customer_id,
    pe.payment_day,
    (
      SELECT AVG(pe2.payment_amount_sum)
      FROM (
        SELECT
          pe3.customer_id,
          DATE(pe3.payment_day) AS d,
          SUM(pe3.payment_amount) AS payment_amount_sum
        FROM payments_enriched pe3
        GROUP BY pe3.customer_id, DATE(pe3.payment_day)
      ) AS daily
      JOIN payments_enriched pe2
        ON pe2.customer_id = daily.customer_id
       AND pe2.payment_day = daily.d
      WHERE pe2.customer_id = pe.customer_id
        AND pe2.payment_day BETWEEN date(pe.payment_day, '-30 day') AND date(pe.payment_day, '-1 day')
    ) AS history_avg_sum_30d,
    (
      SELECT AVG(pe4.cnt)
      FROM (
        SELECT
          pe5.customer_id,
          DATE(pe5.payment_day) AS d2,
          COUNT(*) AS cnt
        FROM payments_enriched pe5
        GROUP BY pe5.customer_id, DATE(pe5.payment_day)
      ) AS daily_cnt
      JOIN payments_enriched pe4
        ON pe4.customer_id = daily_cnt.customer_id
       AND pe4.payment_day = daily_cnt.d2
      WHERE pe4.customer_id = pe.customer_id
        AND pe4.payment_day BETWEEN date(pe.payment_day, '-30 day') AND date(pe.payment_day, '-1 day')
    ) AS history_avg_count_30d
  FROM payments_enriched pe
  GROUP BY pe.customer_id, pe.payment_day
),
filtered AS (
  SELECT
    r.customer_id,
    r.country_name,
    r.city_name,
    r.payment_day,
    r.window_sum_7d_calc AS window_sum,
    r.window_count_7d_calc AS window_count,
    (
      SELECT AVG(x.daily_sum)
      FROM (
        SELECT
          pe2.payment_day AS d,
          SUM(pe2.payment_amount) AS daily_sum
        FROM payments_enriched pe2
        WHERE pe2.customer_id = r.customer_id
          AND pe2.payment_day BETWEEN date(r.payment_day, '-30 day') AND date(r.payment_day, '-1 day')
        GROUP BY pe2.payment_day
      ) x
    ) AS history_avg_daily_sum,
    (
      SELECT AVG(y.daily_cnt)
      FROM (
        SELECT
          pe3.payment_day AS d,
          COUNT(*) AS daily_cnt
        FROM payments_enriched pe3
        WHERE pe3.customer_id = r.customer_id
          AND pe3.payment_day BETWEEN date(r.payment_day, '-30 day') AND date(r.payment_day, '-1 day')
        GROUP BY pe3.payment_day
      ) y
    ) AS history_avg_daily_count
  FROM rolling_7d_final r
),
suspicious AS (
  SELECT
    f.*,
    RANK() OVER (
      ORDER BY f.window_sum DESC
    ) AS suspicious_customer_rank
  FROM filtered f
  WHERE f.history_avg_daily_sum IS NOT NULL
    AND f.history_avg_daily_sum > 0
    AND f.window_count >= 5
    AND f.window_sum >= 3 * f.history_avg_daily_sum
),
staffs_stores_in_window AS (
  SELECT
    pe.customer_id,
    pe.payment_day,
    COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT cu.h02) AS distinct_store_count,
    GROUP_CONCAT(DISTINCT CAST(pe.staff_id AS TEXT)) AS staff_ids_list,
    GROUP_CONCAT(DISTINCT CAST(cu.h02 AS TEXT)) AS store_ids_list
  FROM payments_enriched pe
  JOIN cus cu ON cu.h01 = pe.customer_id
  WHERE pe.payment_day IS NOT NULL
  GROUP BY pe.customer_id, pe.payment_day
),
window_films AS (
  SELECT
    pe.customer_id,
    pe.payment_day,
    COUNT(DISTINCT i.n02) AS distinct_rented_films_count
  FROM payments_enriched pe
  JOIN ren r ON r.q01 = pe.rental_id
  JOIN inv i ON i.n01 = r.q03
  WHERE pe.payment_day IS NOT NULL
  GROUP BY pe.customer_id, pe.payment_day
)
SELECT
  s.customer_id,
  s.country_name,
  s.city_name,
  s.payment_day AS window_end_day,
  ROUND(s.window_sum, 2) AS window_sum_7d,
  s.window_count AS window_payment_count_7d,
  ROUND(s.history_avg_daily_sum, 2) AS history_avg_daily_sum_prev_30d,
  s.suspicious_customer_rank AS customer_rank_by_window_sum,
  COALESCE(wff.distinct_rented_films_count, 0) AS distinct_rented_films_count_in_window,
  COALESCE(ssw.distinct_staff_count, 0) AS distinct_staff_count_in_window,
  COALESCE(ssw.distinct_store_count, 0) AS distinct_store_count_in_window,
  s.payment_day AS suspicious_month_day,
  s.customer_id AS customer_key
FROM suspicious s
LEFT JOIN window_films wff
  ON wff.customer_id = s.customer_id
 AND wff.payment_day = s.payment_day
LEFT JOIN staffs_stores_in_window ssw
  ON ssw.customer_id = s.customer_id
 AND ssw.payment_day = s.payment_day
ORDER BY
  s.window_sum DESC,
  s.customer_id,
  s.payment_day;