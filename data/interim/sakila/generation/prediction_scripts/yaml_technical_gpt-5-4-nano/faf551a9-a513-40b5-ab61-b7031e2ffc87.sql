WITH daily_customer AS (
    SELECT
        p.p02 AS customer_id,
        c.h03,
        c.h04,
        c.h02 AS customer_store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country,
        cty.d02 AS city,
        date(p.p06) AS day_date,
        COUNT(p.p01) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
    GROUP BY
        p.p02, c.h03, c.h04, c.h02,
        cnt.c01, cnt.c02, cty.d02,
        date(p.p06)
),
with_prev_avg AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dcp.day_sum)
            FROM daily_customer AS dcp
            WHERE dcp.customer_id = dc.customer_id
              AND dcp.day_date >= date(dc.day_date, '-30 day')
              AND dcp.day_date < dc.day_date
        ) AS avg_prev_30d
    FROM daily_customer AS dc
),
country_days_ranked AS (
    SELECT
        wpa.*,
        PERCENT_RANK() OVER (
            PARTITION BY wpa.country_id, wpa.day_date
            ORDER BY wpa.day_sum
        ) AS pr_in_country_day
    FROM with_prev_avg AS wpa
),
country_p95 AS (
    SELECT
        country_id,
        day_date,
        day_sum
    FROM (
        SELECT
            wpa.country_id,
            wpa.day_date,
            wpa.day_sum,
            ROW_NUMBER() OVER (
                PARTITION BY wpa.country_id, wpa.day_date
                ORDER BY wpa.day_sum DESC
            ) AS rn_desc,
            COUNT(*) OVER (
                PARTITION BY wpa.country_id, wpa.day_date
            ) AS cnt_days
        FROM with_prev_avg AS wpa
    ) x
    WHERE rn_desc <= CAST(0.05 * cnt_days AS INTEGER)
),
suspicious AS (
    SELECT
        wpa.customer_id,
        wpa.h03,
        wpa.h04,
        wpa.country,
        wpa.city,
        wpa.customer_store_id,
        wpa.day_date AS spike_date,
        wpa.payment_count,
        wpa.day_sum,
        wpa.avg_prev_30d,
        (wpa.day_sum - wpa.avg_prev_30d) AS deviation_from_avg,
        RANK() OVER (
            PARTITION BY wpa.country_id
            ORDER BY wpa.day_sum DESC
        ) AS spike_rank_in_country
    FROM with_prev_avg AS wpa
    JOIN country_p95 AS p95
      ON p95.country_id = wpa.country_id
     AND p95.day_date = wpa.day_date
     AND p95.day_sum = wpa.day_sum
    WHERE wpa.avg_prev_30d IS NOT NULL
      AND wpa.avg_prev_30d > 0
      AND wpa.day_sum >= 3.0 * wpa.avg_prev_30d
)
SELECT
    customer_id,
    h03,
    h04,
    country,
    city AS city_d02,
    customer_store_id AS cus_h02,
    spike_date,
    payment_count,
    ROUND(day_sum, 2) AS day_sum,
    ROUND(avg_prev_30d, 2) AS avg_prev_30d,
    ROUND(deviation_from_avg, 2) AS deviation_from_avg,
    spike_rank_in_country
FROM suspicious
ORDER BY
    day_sum DESC,
    spike_date,
    customer_id;