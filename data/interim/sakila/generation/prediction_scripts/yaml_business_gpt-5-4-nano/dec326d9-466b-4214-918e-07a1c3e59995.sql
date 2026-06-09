SELECT AVG(h.payment_sum_30d)
      FROM (
        SELECT
          date(h.payment_day) AS h_day,
          SUM(h.payment_amount) AS payment_sum_30d
        FROM base_payments AS h
        WHERE h.customer_id = e.customer_id
          AND h.payment_day >= date(e.window_start_day, '-30 days')
          AND h.payment_day < e.window_start_day
        GROUP BY date(h.payment_day)
      ) AS x
    ) AS avg_daily_window_sum_30d
  FROM events AS e
),
candidates AS (
  SELECT
    bp.customer_id,
    bp.customer_name,
    bp.country_name,
    bp.city_name,
    bp.window_start_day,
    -- sums/counts for 7-day window starting at each date
    (
      SELECT SUM(bp7.payment_amount)
      FROM base_payments AS bp7
      WHERE bp7.customer_id = bp.customer_id
        AND bp7.payment_day >= bp.window_start_day
        AND bp7.payment_day <= date(bp.window_start_day, '+6 day')
    ) AS window_payment_sum,
    (
      SELECT COUNT(*)
      FROM base_payments AS bp7
      WHERE bp7.customer_id = bp.customer_id
        AND bp7.payment_day >= bp.window_start_day
        AND bp7.payment_day <= date(bp.window_start_day, '+6 day')
    ) AS window_payment_count,
    (
      SELECT AVG(hist.payment_amount_sum)
      FROM (
        SELECT
          SUM(bp30.payment_amount) AS payment_amount_sum
        FROM base_payments AS bp30
        WHERE bp30.customer_id = bp.customer_id
          AND bp30.payment_day >= date(bp.window_start_day, '-30 days')
          AND bp30.payment_day < bp.window_start_day
        GROUP BY bp30.payment_day
      ) AS hist
    ) AS avg_daily_payment_sum_prev_30d
  FROM (
    SELECT DISTINCT
      customer_id,
      customer_name,
      country_name,
      city_name,
      payment_day AS window_start_day
    FROM base_payments
  ) AS bp
),
filtered AS (
  SELECT *
  FROM candidates
  WHERE avg_daily_payment_sum_prev_30d IS NOT NULL
    AND window_payment_count >= 5
    AND window_payment_sum >= avg_daily_payment_sum_prev_30d * 3 * 7
),
window_dim AS (
  SELECT
    f.customer_id,
    f.customer_name,
    f.country_name,
    f.city_name,
    f.window_start_day,
    -- distinct staff in the window
    COUNT(DISTINCT p7.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT p7.staff_store_id) AS distinct_store_count,
    -- distinct films in the window
    COUNT(DISTINCT i.n02) AS distinct_films_count,
    -- top staff by amount in window
    (
      SELECT p_top.staff_id
      FROM (
        SELECT
          p8.p03 AS staff_id,
          SUM(p8.p05) AS staff_amount,
          ROW_NUMBER() OVER (ORDER BY SUM(p8.p05) DESC, p8.p03) AS rn
        FROM pay AS p8
        WHERE p8.p02 = f.customer_id
          AND DATE(p8.p06) >= f.window_start_day
          AND DATE(p8.p06) <= date(f.window_start_day, '+6 day')
        GROUP BY p8.p03
      ) AS p_top
      WHERE p_top.rn = 1
    ) AS top_staff_id,
    (
      SELECT SUM(p8.p05)
      FROM pay AS p8
      WHERE p8.p02 = f.customer_id
        AND p8.p03 IN (
          SELECT p9.p03
          FROM pay AS p9
          WHERE p9.p02 = f.customer_id
            AND DATE(p9.p06) >= f.window_start_day
            AND DATE(p9.p06) <= date(f.window_start_day, '+6 day')
          GROUP BY p9.p03
          ORDER BY SUM(p9.p05) DESC
          LIMIT 1
        )
    ) AS top_staff_amount
  FROM filtered AS f
  LEFT JOIN pay AS p7
    ON p7.p02 = f.customer_id
   AND DATE(p7.p06) >= f.window_start_day
   AND DATE(p7.p06) <= date(f.window_start_day, '+6 day')
  LEFT JOIN ren AS r7
    ON r7.q01 = p7.p04
  LEFT JOIN inv AS i
    ON i.n01 = r7.q03
  GROUP BY
    f.customer_id,
    f.customer_name,
    f.country_name,
    f.city_name,
    f.window_start_day
),
final_rank AS (
  SELECT
    wd.*,
    f.window_payment_sum,
    f.window_payment_count,
    RANK() OVER (
      PARTITION BY wd.country_name, wd.window_start_day
      ORDER BY f.window_payment_sum DESC
    ) AS suspicious_customer_rank_in_country
  FROM window_dim AS wd
  JOIN filtered AS f
    ON f.customer_id = wd.customer_id
   AND f.window_start_day = wd.window_start_day
)
SELECT
  fr.window_start_day,
  fr.customer_id,
  fr.customer_name,
  fr.country_name,
  fr.city_name,
  fr.window_payment_count AS window_payment_operations,
  ROUND(fr.window_payment_sum, 2) AS window_payment_amount_sum,
  fr.distinct_staff_count AS staff_count_in_window,
  fr.distinct_store_count AS store_count_in_window,
  fr.distinct_films_count AS rented_films_count_in_window,
  fr.top_staff_id,
  st.o02 || ' ' || st.o03 AS top_staff_name,
  ROUND(fr.top_staff_amount, 2) AS top_staff_amount,
  fr.suspicious_customer_rank_in_country AS suspicious_rank_in_country
FROM final_rank AS fr
LEFT JOIN stf AS st
  ON st.o01 = fr.top_staff_id
ORDER BY
  fr.window_start_day,
  fr.country_name,
  fr.window_payment_amount_sum DESC,
  fr.customer_id;