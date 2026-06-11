WITH pay_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(st.o07, -1)) AS store_count
    FROM pay AS p
    LEFT JOIN stf AS st ON st.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
customer_daily_with_avg AS (
    SELECT
        pd.*,
        (
            SELECT AVG(p2.daily_sum)
            FROM pay_daily AS p2
            WHERE p2.customer_id = pd.customer_id
              AND p2.payment_date >= date(pd.payment_date, '-30 days')
              AND p2.payment_date < pd.payment_date
        ) AS personal_avg_prev_30d
    FROM pay_daily AS pd
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
country_daily_values AS (
    SELECT
        cg.country,
        pd.payment_date,
        pd.daily_sum
    FROM pay_daily pd
    JOIN customer_geo cg ON cg.customer_id = pd.customer_id
),
country_p95 AS (
    SELECT
        country,
        MIN(daily_sum) AS country_p95_daily_sum
    FROM (
        SELECT
            cdv.*,
            ROW_NUMBER() OVER (PARTITION BY country ORDER BY daily_sum) AS rn,
            COUNT(*) OVER (PARTITION BY country) AS cnt
        FROM country_daily_values cdv
    ) x
    WHERE rn >= CAST((95 * cnt + 99) / 100 AS INTEGER)
    GROUP BY country
),
suspicious_days AS (
    SELECT
        cd.customer_id,
        cg.country,
        cg.city,
        cd.payment_date,
        cd.payment_count,
        cd.daily_sum,
        cd.staff_count,
        cd.store_count,
        cd.personal_avg_prev_30d,
        (cd.daily_sum - cd.personal_avg_prev_30d) AS deviation_from_personal_avg
    FROM customer_daily_with_avg cd
    JOIN customer_geo cg ON cg.customer_id = cd.customer_id
    JOIN country_p95 cp95 ON cp95.country = cg.country
    WHERE
        cd.payment_count >= 3
        AND (cd.staff_count >= 2 OR cd.store_count >= 2)
        AND cd.personal_avg_prev_30d IS NOT NULL
        AND cd.personal_avg_prev_30d > 0
        AND cd.daily_sum > 2.0 * cd.personal_avg_prev_30d
        AND cd.daily_sum > cp95.country_p95_daily_sum
),
staff_list AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        GROUP_CONCAT(DISTINCT (s.o02 || ' ' || s.o03)) AS staff_list
    FROM pay p
    JOIN stf s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
)
SELECT
    sd.customer_id,
    sd.country,
    sd.city,
    sd.payment_date,
    sd.payment_count,
    ROUND(sd.daily_sum, 2) AS daily_sum,
    sl.staff_list,
    ROUND(sd.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    DENSE_RANK() OVER (
        PARTITION BY sd.country
        ORDER BY sd.deviation_from_personal_avg DESC
    ) AS country_suspicion_rank_in_country
FROM suspicious_days sd
LEFT JOIN staff_list sl
    ON sl.customer_id = sd.customer_id
   AND sl.payment_date = sd.payment_date
ORDER BY
    sd.country,
    country_suspicion_rank_in_country,
    sd.payment_date,
    sd.customer_id;