SELECT AVG(d2.daily_sum)
            FROM daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_day >= date(d.payment_day, '-30 days')
              AND d2.payment_day < d.payment_day
        ) AS personal_avg_prev_30d,
        (
            SELECT AVG(d3.daily_sum)
            FROM daily AS d3
            WHERE d3.country_name = d.country_name
              AND d3.payment_day = d.payment_day
        ) AS country_avg_day
    FROM daily AS d
),
suspicious_days AS (
    SELECT
        d.*,
        daily_with_avgs.personal_avg_prev_30d,
        daily_with_avgs.country_avg_day,
        (d.daily_sum - daily_with_avgs.personal_avg_prev_30d) AS deviation_from_personal_avg,
        (d.daily_sum - daily_with_avgs.country_avg_day) AS deviation_from_country_avg,
        (d.daily_sum / daily_with_avgs.personal_avg_prev_30d) AS personal_exceed_ratio,
        (d.daily_sum / daily_with_avgs.country_avg_day) AS country_exceed_ratio
    FROM daily_with_avgs AS d
    WHERE d.personal_avg_prev_30d IS NOT NULL
      AND d.personal_avg_prev_30d > 0
      AND d.country_avg_day IS NOT NULL
      AND d.country_avg_day > 0
      AND d.daily_sum > 3.0 * d.personal_avg_prev_30d
      AND d.daily_sum > d.country_avg_day
),
ranked_suspicious AS (
    SELECT
        sd.*,
        DENSE_RANK() OVER (
            PARTITION BY sd.country_name
            ORDER BY sd.daily_sum DESC
        ) AS country_suspicious_rank
    FROM suspicious_days AS sd
)
SELECT
    rs.customer_id AS h01,
    rs.country_name AS c02,
    rs.city_name AS d02,
    rs.payment_day AS payment_date,
    ROUND(rs.daily_sum, 2) AS daily_sum,
    rs.payment_count,
    ROUND(rs.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    ROUND(rs.deviation_from_country_avg, 2) AS deviation_from_country_avg,
    rs.staff_count AS staff_distinct_count,
    rs.store_count AS store_distinct_count,
    rs.country_suspicious_rank AS customer_rank_in_country_by_sum
FROM ranked_suspicious AS rs
ORDER BY
    rs.country_name,
    rs.country_suspicious_rank,
    rs.payment_day,
    rs.customer_id;