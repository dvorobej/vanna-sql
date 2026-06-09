SELECT AVG(prev.day_amount)
            FROM daily_base AS prev
            WHERE prev.customer_id = db.customer_id
              AND prev.payment_day >= DATE(db.payment_day, '-30 days')
              AND prev.payment_day < db.payment_day
        ) AS personal_avg_prev_30d,
        (
            SELECT AVG(prev_country.day_amount)
            FROM daily_base AS prev_country
            WHERE prev_country.country_name = db.country_name
              AND prev_country.payment_day >= DATE(db.payment_day, '-30 days')
              AND prev_country.payment_day < db.payment_day
        ) AS country_avg_prev_30d
    FROM daily_base AS db
),
suspicious_days AS (
    SELECT
        d.*,
        (d.day_amount / NULLIF(d.personal_avg_prev_30d, 0)) AS personal_exceed_ratio,
        (d.day_amount - d.personal_avg_prev_30d) AS personal_deviation,
        (d.day_amount - d.country_avg_prev_30d) AS country_deviation
    FROM daily_with_personal_and_country AS d
    WHERE d.personal_avg_prev_30d IS NOT NULL
      AND d.personal_avg_prev_30d > 0
      AND d.country_avg_prev_30d IS NOT NULL
      AND d.country_avg_prev_30d > 0
      AND d.day_amount > 3 * d.personal_avg_prev_30d
      AND d.day_amount > d.country_avg_prev_30d
),
final_ranked AS (
    SELECT
        sd.*,
        SUM(sd.day_amount) OVER (
            PARTITION BY sd.customer_id, sd.country_name
        ) AS customer_total_suspicious_amount
    FROM suspicious_days AS sd
),
distinct_customer_rank AS (
    SELECT
        customer_id,
        country_name,
        DENSE_RANK() OVER (
            PARTITION BY country_name
            ORDER BY customer_total_suspicious_amount DESC
        ) AS customer_rank_in_country
    FROM final_ranked
    GROUP BY customer_id, country_name, customer_total_suspicious_amount
)
SELECT
    sd.customer_id,
    sd.country_name,
    sd.city_name,
    sd.payment_day,
    sd.day_amount AS total_amount,
    sd.payment_count,
    ROUND(sd.personal_deviation, 2) AS personal_deviation,
    ROUND(sd.country_deviation, 2) AS country_deviation,
    sd.staff_count AS distinct_staff_count,
    sd.store_count AS distinct_store_count,
    dcr.customer_rank_in_country
FROM suspicious_days AS sd
JOIN distinct_customer_rank AS dcr
    ON dcr.customer_id = sd.customer_id
   AND dcr.country_name = sd.country_name
ORDER BY
    sd.country_name,
    dcr.customer_rank_in_country,
    sd.payment_day,
    sd.customer_id;