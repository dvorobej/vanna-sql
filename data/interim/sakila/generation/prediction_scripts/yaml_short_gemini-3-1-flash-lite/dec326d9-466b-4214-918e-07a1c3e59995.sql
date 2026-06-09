WITH payment_data AS (
    SELECT
        p.p02 AS customer_id,
        p.p06 AS payment_timestamp,
        DATE(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        inv.n02 AS film_id
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS inv ON inv.n01 = r.q03
),
daily_metrics AS (
    SELECT
        customer_id,
        payment_date,
        SUM(amount) AS daily_amount,
        COUNT(*) AS daily_count,
        COUNT(DISTINCT staff_id) AS daily_staff_count,
        COUNT(DISTINCT store_id) AS daily_store_count,
        COUNT(DISTINCT film_id) AS daily_film_count
    FROM payment_data
    GROUP BY customer_id, payment_date
),
rolling_metrics AS (
    SELECT
        dm.*,
        SUM(daily_amount) OVER (
            PARTITION BY customer_id
            ORDER BY JULIANDAY(payment_date)
            RANGE BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS amount_7d,
        AVG(daily_amount) OVER (
            PARTITION BY customer_id
            ORDER BY JULIANDAY(payment_date)
            RANGE BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_amount_30d,
        COUNT(*) OVER (
            PARTITION BY customer_id
            ORDER BY JULIANDAY(payment_date)
            RANGE BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS days_in_30d_window
    FROM daily_metrics AS dm
),
suspicious_activity AS (
    SELECT
        rm.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM rolling_metrics AS rm
    JOIN cus AS c ON c.h01 = rm.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    WHERE days_in_30d_window >= 5
      AND avg_amount_30d > 0
      AND amount_7d >= 3 * avg_amount_30d
),
ranked_suspicious AS (
    SELECT
        *,
        DENSE_RANK() OVER (
            PARTITION BY country
            ORDER BY amount_7d DESC
        ) AS country_risk_rank
    FROM suspicious_activity
)
SELECT
    payment_date,
    customer_name,
    country,
    city,
    ROUND(amount_7d, 2) AS amount_7d,
    ROUND(avg_amount_30d, 2) AS avg_amount_30d,
    daily_count,
    daily_staff_count,
    daily_store_count,
    daily_film_count,
    country_risk_rank
FROM ranked_suspicious
ORDER BY
    country,
    country_risk_rank,
    payment_date;