WITH payment_base AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        a.e05 AS city_id,
        ct.d02 AS city_name,
        cn.c02 AS country_name,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        p.p05 AS amount,
        p.p06 AS payment_ts,
        date(p.p06) AS pay_day
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN stf AS s ON s.o01 = p.p03
),
daily_agg AS (
    SELECT
        customer_id,
        customer_name,
        city_id,
        city_name,
        country_name,
        pay_day,
        COUNT(*) AS payment_count,
        SUM(amount) AS day_amount,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT store_id) AS distinct_store_count,
        GROUP_CONCAT(DISTINCT store_id) AS store_ids,
        GROUP_CONCAT(DISTINCT staff_id) AS staff_ids
    FROM payment_base
    GROUP BY
        customer_id,
        customer_name,
        city_id,
        city_name,
        country_name,
        pay_day
),
daily_with_history AS (
    SELECT
        da.*,
        (
            SELECT AVG(prev_day_amount)
            FROM (
                SELECT
                    da2.day_amount AS prev_day_amount
                FROM daily_agg AS da2
                WHERE da2.customer_id = da.customer_id
                  AND da2.pay_day < da.pay_day
                  AND da2.pay_day >= date(da.pay_day, '-30 days')
            )
        ) AS avg_prev_30d_day_amount
    FROM daily_agg AS da
),
ranked_days AS (
    SELECT
        dwh.*,
        ROUND(dwh.day_amount - dwh.avg_prev_30d_day_amount, 2) AS deviation_amount,
        ROUND(dwh.day_amount / NULLIF(dwh.avg_prev_30d_day_amount, 0), 2) AS deviation_ratio,
        RANK() OVER (
            PARTITION BY dwh.customer_id
            ORDER BY (dwh.day_amount - dwh.avg_prev_30d_day_amount) DESC
        ) AS deviation_rank
    FROM daily_with_history AS dwh
)
SELECT
    customer_name,
    city_name,
    country_name,
    pay_day,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(avg_prev_30d_day_amount, 2) AS avg_prev_30d_day_amount,
    deviation_amount,
    deviation_ratio,
    distinct_staff_count,
    distinct_store_count,
    store_ids,
    staff_ids,
    deviation_rank
FROM ranked_days
WHERE payment_count >= 3
  AND (distinct_staff_count >= 2 OR distinct_store_count >= 2)
  AND day_amount > 2 * avg_prev_30d_day_amount
ORDER BY
    deviation_rank,
    day_amount DESC,
    customer_name,
    pay_day;