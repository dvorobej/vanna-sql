WITH base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p06 AS payment_ts,
    date(p.p06) AS payment_day,
    co.c02 AS country,
    ci.d02 AS city,
    c.h02 AS home_store_id
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  JOIN cnt co
    ON co.c01 = ci.d03
),
windowed AS (
  SELECT
    b.customer_id,
    b.country,
    b.city,
    b.home_store_id,
    b.payment_day,
    b.payment_ts,
    b.payment_amount,

    SUM(b.payment_amount) OVER (
      PARTITION BY b.customer_id
      ORDER BY b.payment_ts
      RANGE BETWEEN 6.999999 DAY PRECEDING AND CURRENT ROW
    ) AS win_sum_7d,

    COUNT(b.payment_id) OVER (
      PARTITION BY b.customer_id
      ORDER BY b.payment_ts
      RANGE BETWEEN 6.999999 DAY PRECEDING AND CURRENT ROW
    ) AS win_count_7d,

    /* previous 30 days (excluding current 7-day window end day) */
    SUM(b.payment_amount) OVER (
      PARTITION BY b.customer_id
      ORDER BY b.payment_ts
      RANGE BETWEEN 30.000001 DAY PRECEDING AND 7.000001 DAY PRECEDING
    ) AS hist_sum_30d_excl_current_window,

    COUNT(b.payment_id) OVER (
      PARTITION BY b.customer_id
      ORDER BY b.payment_ts
      RANGE BETWEEN 30.000001 DAY PRECEDING AND 7.000001 DAY PRECEDING
    ) AS hist_count_30d_excl_current_window
  FROM base b
),
suspicious_events AS (
  SELECT DISTINCT
    w.customer_id,
    w.country,
    w.city,
    w.home_store_id,
    w.payment_day,
    w.payment_ts,
    w.win_sum_7d,
    w.win_count_7d,
    (w.hist_sum_30d_excl_current_window * 1.0) / NULLIF(w.hist_count_30d_excl_current_window, 0) AS hist_avg_payment_amount_30d
  FROM windowed w
  WHERE w.win_count_7d >= 5
    AND w.hist_count_30d_excl_current_window > 0
    AND w.win_sum_7d >= 3.0 * ((w.hist_sum_30d_excl_current_window * 1.0) / w.hist_count_30d_excl_current_window) * w.win_count_7d
),
agg_suspicious AS (
  SELECT
    se.customer_id,
    se.payment_day,
    se.country,
    se.city,

    COUNT(DISTINCT p.p03) AS staff_count_distinct,
    COUNT(DISTINCT c.h02) AS store_count_distinct,

    COUNT(DISTINCT fc.l01) AS distinct_rented_films_in_window,

    /* rank customers by total suspicious-window sum */
    SUM(se.win_sum_7d) OVER (
      PARTITION BY se.customer_id
    ) AS customer_suspicious_total_sum
  FROM suspicious_events se
  JOIN pay p
    ON p.p02 = se.customer_id
   AND p.p06 >= datetime(se.payment_day || ' 00:00:00')
   AND p.p06 <  datetime(date(se.payment_day, '+1 day'))
  LEFT JOIN cus c
    ON c.h01 = p.p02
  LEFT JOIN ren r
    ON r.q01 = p.p04
  LEFT JOIN inv i
    ON i.n01 = r.q03
  LEFT JOIN flc fc
    ON fc.l01 = i.n02
  GROUP BY
    se.customer_id, se.payment_day, se.country, se.city
),
final_events AS (
  SELECT
    se.customer_id,
    (c.h03 || ' ' || c.h04) AS customer_name,
    se.country,
    se.city,
    se.payment_day AS window_end_day,
    se.win_count_7d AS payments_in_window,
    ROUND(se.win_sum_7d, 2) AS payments_sum_in_window,

    /* collect staff and stores through which payments passed */
    GROUP_CONCAT(DISTINCT st.o02 || ' ' || st.o03) AS staff_names_in_window,
    GROUP_CONCAT(DISTINCT c.h02) AS home_store_ids_in_window,

    a.distinct_rented_films_in_window AS distinct_rented_films_in_window,
    DENSE_RANK() OVER (
      ORDER BY a.customer_suspicious_total_sum DESC
    ) AS customer_risk_rank
  FROM suspicious_events se
  JOIN cus c
    ON c.h01 = se.customer_id
  JOIN pay p
    ON p.p02 = se.customer_id
   AND p.p06 >= datetime(se.payment_day || ' 00:00:00','-6 days')
   AND p.p06 <= datetime(se.payment_day || ' 23:59:59')
  LEFT JOIN stf st
    ON st.o01 = p.p03
  LEFT JOIN ren r
    ON r.q01 = p.p04
  LEFT JOIN inv i
    ON i.n01 = r.q03
  LEFT JOIN flc fc
    ON fc.l01 = i.n02
  LEFT JOIN agg_suspicious a
    ON a.customer_id = se.customer_id
   AND a.payment_day = se.payment_day
  GROUP BY
    se.customer_id, customer_name, se.country, se.city, se.payment_day, se.win_count_7d, se.win_sum_7d, a.distinct_rented_films_in_window, a.customer_suspicious_total_sum
)
SELECT
  *
FROM final_events
ORDER BY
  customer_risk_rank,
  payments_sum_in_window DESC;