SELECT AVG(prev.daily_amount)
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= date(dc.payment_day, '-30 day')
              AND prev.payment_day < dc.payment_day
        ) AS prev30_avg_daily_amount,
        (
            SELECT AVG(prev.daily_amount)
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= date(dc.payment_day, '-30 day')
              AND prev.payment_day < dc.payment_day
        ) AS prev30_median_daily_amount
    FROM daily_customer AS dc
),
window_7d AS (
    SELECT
        a.customer_id,
        a.payment_day AS window_start,
        date(a.payment_day, '+6 day') AS window_end,
        SUM(b.daily_amount) AS window_7d_sum,
        SUM(b.daily_payment_count) AS window_7d_payment_count,
        MAX(b.daily_staff_count) AS window_staff_count,
        MAX(b.daily_store_count) AS window_store_count,
        AVG(a.prev30_avg_daily_amount) AS baseline_avg_daily_amount,
        AVG(a.prev30_median_daily_amount) AS baseline_median_daily_amount
    FROM customer_daily_baseline AS a
    JOIN customer_daily_baseline AS b
      ON b.customer_id = a.customer_id
     AND b.payment_day >= a.payment_day
     AND b.payment_day < date(a.payment_day, '+7 day')
    GROUP BY
        a.customer_id,
        a.payment_day
),
country_percentiles AS (
    SELECT
        cg.country_name,
        dc.payment_day,
        PERCENT_RANK() OVER (
            PARTITION BY cg.country_name, dc.payment_day
            ORDER BY dc.daily_amount
        ) AS country_day_percentile,
        dc.daily_amount,
        dc.customer_id
    FROM daily_customer AS dc
    JOIN customer_geo AS cg
      ON cg.customer_id = dc.customer_id
),
country_95 AS (
    SELECT DISTINCT
        country_name,
        payment_day,
        MAX(CASE WHEN country_day_percentile <= 0.95 THEN daily_amount END) OVER (
            PARTITION BY country_name, payment_day
        ) AS country_p95_daily_amount
    FROM country_percentiles
),
suspicious_windows AS (
    SELECT
        w.customer_id,
        w.window_start,
        w.window_end,
        w.window_7d_sum,
        w.window_7d_payment_count,
        w.window_staff_count,
        w.window_store_count,
        w.baseline_avg_daily_amount,
        w.baseline_median_daily_amount,
        AVG(c95.country_p95_daily_amount) AS country_p95_daily_amount
    FROM window_7d AS w
    JOIN customer_daily_baseline AS d
      ON d.customer_id = w.customer_id
     AND d.payment_day >= w.window_start
     AND d.payment_day < w.window_end
    JOIN customer_geo AS cg
      ON cg.customer_id = w.customer_id
    JOIN country_95 AS c95
      ON c95.country_name = cg.country_name
     AND c95.payment_day = d.payment_day
    GROUP BY
        w.customer_id,
        w.window_start,
        w.window_end,
        w.window_7d_sum,
        w.window_7d_payment_count,
        w.window_staff_count,
        w.window_store_count,
        w.baseline_avg_daily_amount,
        w.baseline_median_daily_amount
)
SELECT
    sw.customer_id,
    cg.first_name,
    cg.last_name,
    cg.country_name,
    cg.city_name,
    sw.window_start,
    sw.window_end,
    ROUND(sw.window_7d_sum, 2) AS window_7d_sum,
    sw.window_7d_payment_count,
    sw.window_staff_count,
    sw.window_store_count,
    ROUND(sw.baseline_avg_daily_amount, 2) AS baseline_avg_daily_amount,
    ROUND(sw.baseline_median_daily_amount, 2) AS baseline_median_daily_amount,
    ROUND(sw.country_p95_daily_amount, 2) AS country_p95_daily_amount,
    ROUND(
        sw.window_7d_sum / NULLIF(sw.baseline_avg_daily_amount, 0),
        2
    ) AS suspiciousness_ratio,
    RANK() OVER (
        ORDER BY sw.window_7d_sum / NULLIF(sw.baseline_avg_daily_amount, 0) DESC,
                 sw.window_7d_sum DESC
    ) AS suspicion_rank
FROM suspicious_windows AS sw
JOIN customer_geo AS cg
  ON cg.customer_id = sw.customer_id
WHERE sw.baseline_avg_daily_amount IS NOT NULL
  AND sw.baseline_avg_daily_amount > 0
  AND sw.country_p95_daily_amount IS NOT NULL
  AND sw.window_7d_payment_count >= 3
  AND sw.window_7d_sum > 3.0 * sw.baseline_avg_daily_amount
  AND sw.window_7d_sum > sw.country_p95_daily_amount
  AND (sw.window_staff_count > 1 OR sw.window_store_count > 1)
ORDER BY
    suspicion_rank,
    sw.window_start,
    sw.customer_id;