WITH RECURSIVE
pay_daily AS (
    SELECT
        p02 AS customer_id,
        date(p06) AS pay_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p05 AS REAL)) AS daily_sum
    FROM pay
    GROUP BY p02, date(p06)
),
customer_span AS (
    SELECT
        customer_id,
        date(MIN(pay_date), '-30 days') AS start_date,
        MAX(pay_date) AS end_date
    FROM pay_daily
    GROUP BY customer_id
),
date_series(customer_id, pay_date, end_date) AS (
    SELECT
        customer_id,
        start_date,
        end_date
    FROM customer_span

    UNION ALL

    SELECT
        customer_id,
        date(pay_date, '+1 day'),
        end_date
    FROM date_series
    WHERE pay_date < end_date
),
calendar_daily AS (
    SELECT
        ds.customer_id,
        ds.pay_date,
        COALESCE(pd.payment_count, 0) AS payment_count,
        COALESCE(pd.daily_sum, 0.0) AS daily_sum
    FROM date_series ds
    LEFT JOIN pay_daily pd
        ON pd.customer_id = ds.customer_id
       AND pd.pay_date = ds.pay_date
),
daily_with_avg AS (
    SELECT
        customer_id,
        pay_date,
        payment_count,
        daily_sum,
        AVG(daily_sum) OVER (
            PARTITION BY customer_id
            ORDER BY pay_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_30
    FROM calendar_daily
),
customer_geo AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 AS first_name,
        cus.h04 AS last_name,
        cus.h02 AS store_id,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        cnt.c02 AS country
    FROM cus
    JOIN adr
        ON adr.e01 = cus.h06
    JOIN cty
        ON cty.d01 = adr.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
),
country_daily_sums AS (
    SELECT
        cg.country_id,
        pd.daily_sum
    FROM pay_daily pd
    JOIN customer_geo cg
        ON cg.customer_id = pd.customer_id
),
country_ranked AS (
    SELECT
        country_id,
        daily_sum,
        ROW_NUMBER() OVER (
            PARTITION BY country_id
            ORDER BY daily_sum
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY country_id
        ) AS cnt
    FROM country_daily_sums
),
country_p95 AS (
    SELECT
        country_id,
        MIN(daily_sum) AS p95_daily_sum
    FROM country_ranked
    WHERE rn >= CAST((95 * cnt + 99) / 100 AS INTEGER)
    GROUP BY country_id
),
spikes AS (
    SELECT
        dwa.pay_date AS spike_date,
        cg.first_name,
        cg.last_name,
        cg.country_id,
        cg.country,
        cg.city,
        cg.store_id,
        dwa.payment_count,
        dwa.daily_sum,
        dwa.avg_prev_30,
        dwa.daily_sum - dwa.avg_prev_30 AS deviation_from_avg
    FROM daily_with_avg dwa
    JOIN customer_geo cg
        ON cg.customer_id = dwa.customer_id
    JOIN country_p95 cp
        ON cp.country_id = cg.country_id
    WHERE dwa.payment_count > 0
      AND dwa.avg_prev_30 > 0
      AND dwa.daily_sum >= 3 * dwa.avg_prev_30
      AND dwa.daily_sum > cp.p95_daily_sum
)
SELECT
    spike_date,
    first_name,
    last_name,
    country,
    city,
    store_id,
    payment_count,
    ROUND(daily_sum, 2) AS daily_sum,
    ROUND(avg_prev_30, 2) AS avg_prev_30,
    ROUND(deviation_from_avg, 2) AS deviation_from_avg,
    DENSE_RANK() OVER (
        PARTITION BY country_id
        ORDER BY deviation_from_avg DESC
    ) AS country_spike_rank
FROM spikes
ORDER BY
    country,
    country_spike_rank,
    spike_date,
    last_name,
    first_name;