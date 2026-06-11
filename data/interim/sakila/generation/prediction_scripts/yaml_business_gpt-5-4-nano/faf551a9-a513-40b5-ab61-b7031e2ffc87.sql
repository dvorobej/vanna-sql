WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city_name,
        cn.c02 AS country_name,
        s.h01 AS store_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN sto AS s ON s.j01 = c.h02
),
daily_customer_pay AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS day_date,
        cg.customer_name,
        cg.country_name,
        cg.city_name,
        cg.store_id,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_sum
    FROM pay AS p
    JOIN customer_geo AS cg
      ON cg.customer_id = p.p02
    GROUP BY
        p.p02, date(p.p06),
        cg.customer_name, cg.country_name, cg.city_name, cg.store_id
),
daily_with_baselines AS (
    SELECT
        d.*,
        (
            SELECT AVG(d2.day_sum)
            FROM daily_customer_pay AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.day_date >= date(d.day_date, '-30 days')
              AND d2.day_date < d.day_date
        ) AS avg_prev_30d_day_sum,
        (
            SELECT AVG(d2.payment_count * 1.0)
            FROM daily_customer_pay AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.day_date >= date(d.day_date, '-30 days')
              AND d2.day_date < d.day_date
        ) AS avg_prev_30d_day_payment_count
    FROM daily_customer_pay AS d
),
daily_spike_flag AS (
    SELECT
        d.*,
        (d.day_sum - d.avg_prev_30d_day_sum) AS deviation_from_personal_avg,
        RANK() OVER (
            PARTITION BY d.country_name
            ORDER BY d.day_sum DESC
        ) AS country_spike_rank
    FROM daily_with_baselines AS d
    WHERE d.avg_prev_30d_day_sum IS NOT NULL
      AND d.avg_prev_30d_day_sum > 0
      AND d.day_sum >= d.avg_prev_30d_day_sum * 3
),
filtered_spikes AS (
    SELECT *
    FROM daily_spike_flag
    WHERE country_spike_rank = 1
       OR day_sum >= (
            SELECT AVG(d3.day_sum) * 2.0
            FROM daily_customer_pay AS d3
            WHERE d3.country_name = daily_spike_flag.country_name
        )
)
SELECT
    fs.day_date AS spike_date,
    fs.customer_name,
    fs.country_name AS country,
    fs.city_name AS city,
    fs.store_id AS store,
    fs.payment_count,
    ROUND(fs.day_sum, 2) AS daily_sum,
    ROUND(fs.avg_prev_30d_day_sum, 2) AS avg_prev_30d_day_sum,
    ROUND(fs.deviation_from_personal_avg, 2) AS deviation_from_avg,
    RANK() OVER (
        PARTITION BY fs.country_name
        ORDER BY fs.day_sum DESC
    ) AS spike_amount_rank_in_country
FROM filtered_spikes AS fs
ORDER BY
    fs.country_name,
    spike_amount_rank_in_country,
    fs.day_sum DESC,
    fs.customer_name;