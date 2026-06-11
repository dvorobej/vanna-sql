SELECT AVG(dp2.day_sum)
            FROM daily_pay AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.day_date >= DATE(dp.day_date, '-30 days')
              AND dp2.day_date < dp.day_date
        ) AS avg_prev_30d
    FROM daily_pay AS dp
),
daily_with_country95 AS (
    SELECT
        dwh.*,
        cd.country_id,
        cd.city_name,
        cd.country_name,
        (
            SELECT cp.day_sum
            FROM (
                SELECT
                    dp3.day_sum,
                    NTILE(20) OVER (ORDER BY dp3.day_sum) AS tile20
                FROM daily_pay AS dp3
                JOIN customer_country_city AS cd3
                    ON cd3.customer_id = dp3.customer_id
                WHERE cd3.country_id = dwh.country_id
                  AND dp3.day_date = dwh.day_date
            ) AS cp
            WHERE cp.tile20 = 20
            ORDER BY cp.day_sum DESC
            LIMIT 1
        ) AS country_p95_day_sum
    FROM daily_with_hist AS dwh
    JOIN customer_country_city AS cd
        ON cd.customer_id = dwh.customer_id
),
flagged AS (
    SELECT
        d.*,
        (
            SELECT MAX(p2.p05)
            FROM pay AS p2
            WHERE p2.p02 = d.customer_id
              AND DATE(p2.p06) = d.day_date
        ) AS max_day_payment,
        (
            d.day_sum / NULLIF(d.avg_prev_30d, 0)
        ) AS exceed_ratio_vs_customer_hist
    FROM daily_with_country95 AS d
    WHERE d.avg_prev_30d IS NOT NULL
      AND d.avg_prev_30d > 0
      AND d.day_sum > 3.0 * d.avg_prev_30d
      AND d.payment_count >= 3
      AND d.staff_count >= 2
      AND d.country_p95_day_sum IS NOT NULL
      AND d.day_sum > d.country_p95_day_sum
),
ranked AS (
    SELECT
        f.*,
        RANK() OVER (
            PARTITION BY f.country_id
            ORDER BY f.exceed_ratio_vs_customer_hist DESC,
                     f.day_sum DESC,
                     f.customer_id
        ) AS suspicion_rank_in_country
    FROM flagged AS f
)
SELECT
    r.customer_id AS customer_id,
    r.city_name AS city,
    r.country_name AS country,
    r.day_date AS payment_day,
    r.payment_count,
    ROUND(r.day_sum, 2) AS total_day_amount,
    r.staff_count AS distinct_staff_count,
    r.store_count AS distinct_store_count,
    r.min_payment_ts AS min_operation_time,
    r.max_payment_ts AS max_operation_time,
    ROUND(r.max_day_payment, 2) AS max_day_payment,
    r.suspicion_rank_in_country AS suspicion_rank
FROM ranked AS r
ORDER BY
    r.country_name,
    r.suspicion_rank_in_country,
    r.day_date,
    r.customer_id;