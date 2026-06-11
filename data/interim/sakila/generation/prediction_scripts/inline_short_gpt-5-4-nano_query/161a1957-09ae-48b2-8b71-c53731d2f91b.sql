WITH pay_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum
    FROM pay AS p
    GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_with_context AS (
    SELECT
        pd.customer_id,
        cg.country_name,
        cg.city_name,
        pd.pay_date,
        pd.payment_count,
        pd.day_sum,
        (
            SELECT AVG(CAST(p2.p05 AS REAL))
            FROM pay AS p2
            WHERE p2.p02 = pd.customer_id
              AND date(p2.p06) >= date(pd.pay_date, '-30 days')
              AND date(p2.p06) <  pd.pay_date
        ) AS personal_avg_prev_30d,
        (
            SELECT p95.day_sum_p95
            FROM (
                SELECT
                    pd2.pay_date,
                    pd2.day_sum AS day_sum_val,
                    ROW_NUMBER() OVER (PARTITION BY pd2.customer_id, pd2.pay_date ORDER BY pd2.day_sum) AS rn_dummy
                FROM pay_daily AS pd2
            ) dummy
            JOIN (
                SELECT
                    cg2.country_name,
                    pd3.pay_date,
                    /* 95-й перцентиль по клиентам этой страны за этот день */
                    (SELECT AVG(x.day_sum_val)
                     FROM (
                         SELECT pd4.day_sum AS day_sum_val
                         FROM pay_daily AS pd4
                         JOIN customer_geo AS cg4 ON cg4.customer_id = pd4.customer_id
                         WHERE cg4.country_name = cg2.country_name
                           AND pd4.pay_date = pd3.pay_date
                           AND pd4.day_sum IS NOT NULL
                         ORDER BY pd4.day_sum
                         LIMIT 1 OFFSET (
                           CAST((0.95 * (COUNT(*) - 1)) AS INTEGER)
                         )
                     ) x) AS day_sum_p95
                FROM pay_daily AS pd3
                JOIN customer_geo AS cg2 ON 1=1
                GROUP BY cg2.country_name, pd3.pay_date
            ) p95
              ON p95.country_name = cg.country_name
             AND p95.pay_date = pd.pay_date
            LIMIT 1
        ) AS country_p95_same_day
    FROM pay_daily AS pd
    JOIN customer_geo AS cg ON cg.customer_id = pd.customer_id
),
day_staff_store AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        GROUP_CONCAT(DISTINCT (s.o02 || ' ' || s.o03)) AS staff_list,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
final_base AS (
    SELECT
        d.customer_id,
        d.country_name,
        d.city_name,
        d.pay_date,
        d.payment_count,
        d.day_sum,
        d.personal_avg_prev_30d,
        (d.day_sum - d.personal_avg_prev_30d) AS personal_deviation,
        d.country_p95_same_day,
        ds.staff_list,
        ds.distinct_staff_count,
        ds.distinct_store_count
    FROM daily_with_context AS d
    JOIN day_staff_store AS ds
      ON ds.customer_id = d.customer_id
     AND ds.pay_date = d.pay_date
    WHERE ds.distinct_staff_count >= 2
       OR ds.distinct_store_count >= 2
)
, suspicious_cases AS (
    SELECT
        fb.*,
        DENSE_RANK() OVER (
            PARTITION BY fb.country_name
            ORDER BY (fb.day_sum - fb.personal_avg_prev_30d) DESC
        ) AS suspicion_rank_in_country
    FROM final_base AS fb
    WHERE fb.personal_avg_prev_30d IS NOT NULL
      AND fb.personal_avg_prev_30d > 0
      AND fb.payment_count >= 3
      AND fb.day_sum >= 2.0 * fb.personal_avg_prev_30d
      AND fb.country_p95_same_day IS NOT NULL
      AND fb.day_sum > fb.country_p95_same_day
)
SELECT
    customer_id,
    country_name AS country,
    city_name AS city,
    pay_date AS suspicious_date,
    payment_count,
    ROUND(day_sum, 2) AS day_sum,
    staff_list,
    ROUND(personal_deviation, 2) AS deviation_from_personal_avg,
    suspicion_rank_in_country AS country_suspicion_rank
FROM suspicious_cases
ORDER BY
    country,
    country_suspicion_rank,
    pay_date,
    customer_id;