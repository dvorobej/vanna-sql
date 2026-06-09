WITH pay_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum
    FROM pay AS p
    GROUP BY p.p02, date(p.p06)
),
pay_daily_staff_store AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        ct.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt AS ct
        ON ct.c01 = cty.d03
),
daily_with_avgs AS (
    SELECT
        pd.customer_id,
        pd.payment_date,
        pd.payment_count,
        pd.day_sum,
        (
            SELECT AVG(pd2.day_sum)
            FROM pay_daily AS pd2
            WHERE pd2.customer_id = pd.customer_id
              AND pd2.payment_date >= date(pd.payment_date, '-30 day')
              AND pd2.payment_date < pd.payment_date
        ) AS personal_avg_prev_30d
    FROM pay_daily AS pd
),
country_avg_prev_same_day AS (
    SELECT
        d.customer_id,
        d.payment_date,
        AVG(d.day_sum) AS country_avg_day_sum
    FROM (
        SELECT
            p2.p02 AS customer_id,
            date(p2.p06) AS payment_date,
            SUM(CAST(p2.p05 AS REAL)) AS day_sum
        FROM pay AS p2
        GROUP BY p2.p02, date(p2.p06)
    ) AS d
    GROUP BY d.customer_id, d.payment_date
),
country_daily_avg_by_date AS (
    SELECT
        cc.payment_date,
        AVG(cc.day_sum) AS country_avg_day_sum
    FROM (
        SELECT
            p2.p02 AS customer_id,
            date(p2.p06) AS payment_date,
            SUM(CAST(p2.p05 AS REAL)) AS day_sum
        FROM pay AS p2
        GROUP BY p2.p02, date(p2.p06)
    ) AS cc
    JOIN customer_geo cg
        ON cg.customer_id = cc.customer_id
    GROUP BY cc.payment_date
),
rank_in_country AS (
    SELECT
        d.customer_id,
        cg.country_name,
        SUM(CASE WHEN d.payment_date IS NOT NULL THEN d.day_sum ELSE 0 END) AS suspicious_total_sum,
        DENSE_RANK() OVER (
            PARTITION BY cg.country_name
            ORDER BY SUM(CASE WHEN d.payment_date IS NOT NULL THEN d.day_sum ELSE 0 END) DESC
        ) AS country_rank
    FROM (
        SELECT
            pd.customer_id,
            pd.payment_date,
            pd.day_sum
        FROM pay_daily pd
    ) AS d
    JOIN customer_geo cg
        ON cg.customer_id = d.customer_id
    GROUP BY d.customer_id, cg.country_name
),
candidates AS (
    SELECT
        dwa.customer_id,
        cg.country_name,
        cg.city_name,
        cg.first_name,
        cg.last_name,
        dwa.payment_date,
        dwa.payment_count,
        dwa.day_sum,
        dwa.personal_avg_prev_30d,
        cdab.country_avg_day_sum,
        ps.distinct_staff_count,
        ps.distinct_store_count
    FROM daily_with_avgs AS dwa
    JOIN customer_geo AS cg
        ON cg.customer_id = dwa.customer_id
    JOIN pay_daily_staff_store AS ps
        ON ps.customer_id = dwa.customer_id
       AND ps.payment_date = dwa.payment_date
    JOIN country_daily_avg_by_date AS cdab
        ON cdab.payment_date = dwa.payment_date
    WHERE dwa.personal_avg_prev_30d IS NOT NULL
)
SELECT
    c.first_name || ' ' || c.last_name AS customer_name,
    c.country_name,
    c.city_name,
    c.payment_date,
    ROUND(c.day_sum, 2) AS day_sum,
    c.payment_count,
    ROUND(c.day_sum - c.personal_avg_prev_30d, 2) AS personal_deviation,
    ROUND(c.day_sum - c.country_avg_day_sum, 2) AS country_deviation,
    c.distinct_staff_count AS staff_count_distinct,
    c.distinct_store_count AS store_count_distinct,
    r.country_rank AS country_suspicious_rank
FROM candidates AS c
JOIN rank_in_country AS r
    ON r.customer_id = c.customer_id
   AND r.country_name = c.country_name
WHERE c.day_sum > 3.0 * c.personal_avg_prev_30d
  AND c.day_sum > c.country_avg_day_sum
  AND (c.distinct_staff_count > 1 OR c.distinct_store_count > 1)
ORDER BY
    c.country_name,
    c.payment_date,
    c.day_sum DESC,
    customer_name;