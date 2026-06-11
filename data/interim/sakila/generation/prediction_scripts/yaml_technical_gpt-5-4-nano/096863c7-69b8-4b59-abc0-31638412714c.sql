SELECT AVG(d2.daily_sum)
            FROM daily_agg AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_day >= DATE(d.payment_day, '-30 days')
              AND d2.payment_day < d.payment_day
        ) AS personal_avg_daily_prev_30,
        (
            SELECT AVG(d3.daily_sum)
            FROM daily_agg AS d3
            WHERE d3.country_id = d.country_id
              AND d3.payment_day = d.payment_day
        ) AS country_avg_daily_that_day
    FROM daily_agg AS d
),
suspicious AS (
    SELECT
        dwa.*,
        (dwa.daily_sum - dwa.personal_avg_daily_prev_30) AS deviation_personal_avg,
        (dwa.daily_sum - dwa.country_avg_daily_that_day) AS deviation_country_avg
    FROM daily_with_avgs AS dwa
    WHERE dwa.personal_avg_daily_prev_30 IS NOT NULL
      AND dwa.personal_avg_daily_prev_30 > 0
      AND dwa.country_avg_daily_that_day IS NOT NULL
      AND dwa.daily_sum > 3.0 * dwa.personal_avg_daily_prev_30
      AND dwa.daily_sum > dwa.country_avg_daily_that_day
      AND (dwa.staff_count >= 2 OR dwa.store_count >= 2)
)
SELECT
    s.customer_id AS h01,
    s.country_name AS c02,
    s.city_name AS d02,
    s.payment_day AS payment_date,
    ROUND(s.daily_sum, 2) AS daily_sum,
    s.payment_count,
    ROUND(s.deviation_personal_avg, 2) AS deviation_from_personal_avg,
    ROUND(s.deviation_country_avg, 2) AS deviation_from_country_avg,
    s.staff_count AS distinct_staff_count,
    s.store_count AS distinct_store_count,
    RANK() OVER (
        PARTITION BY s.country_id
        ORDER BY s.daily_sum DESC
    ) AS suspicion_rank_in_country
FROM suspicious AS s
ORDER BY
    s.country_name,
    suspicion_rank_in_country,
    s.payment_day,
    s.customer_id;