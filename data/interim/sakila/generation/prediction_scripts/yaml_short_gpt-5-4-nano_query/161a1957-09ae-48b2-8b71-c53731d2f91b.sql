WITH pay_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum
    FROM pay AS p
    GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS country,
        ci.d02 AS city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
customer_daily_with_prev_avg AS (
    SELECT
        pd.customer_id,
        pd.payment_date,
        pd.payment_count,
        pd.day_sum,
        (
            SELECT AVG(CAST(p2.day_sum AS REAL))
            FROM pay_daily AS p2
            WHERE p2.customer_id = pd.customer_id
              AND p2.payment_date >= date(pd.payment_date, '-30 days')
              AND p2.payment_date < pd.payment_date
        ) AS personal_avg_prev_30
    FROM pay_daily AS pd
),
country_daily_p95 AS (
    /* compute the 95th percentile threshold per country based on customer daily sums */
    SELECT country_id, p95_day_sum
    FROM (
        SELECT
            cg.country,
            cg.country_id,
            daily_sum,
            ROW_NUMBER() OVER (PARTITION BY cg.country_id ORDER BY daily_sum) AS rn,
            COUNT(*) OVER (PARTITION BY cg.country_id) AS cnt,
            daily_sum AS daily_sum_val
        FROM (
            SELECT
                p.p02 AS customer_id,
                date(p.p06) AS payment_date,
                SUM(CAST(p.p05 AS REAL)) AS daily_sum
            FROM pay AS p
            GROUP BY p.p02, date(p.p06)
        ) d
        JOIN (
            SELECT
                c.h01 AS customer_id,
                co.c01 AS country_id,
                co.c02 AS country
            FROM cus AS c
            JOIN adr AS a ON a.e01 = c.h06
            JOIN cty AS ci ON ci.d01 = a.e05
            JOIN cnt AS co ON co.c01 = ci.d03
        ) cg ON cg.customer_id = d.customer_id
    ) x
    /* approximate p95 via selecting rows near index (works in SQLite with window funcs) */
    JOIN (
        SELECT
            country_id,
            MIN(daily_sum_val) AS p95_day_sum
        FROM (
            SELECT
                cg2.country_id,
                d2.daily_sum_val,
                ROW_NUMBER() OVER (PARTITION BY cg2.country_id ORDER BY d2.daily_sum_val) AS rn2,
                COUNT(*) OVER (PARTITION BY cg2.country_id) AS cnt2
            FROM (
                SELECT
                    p.p02 AS customer_id,
                    date(p.p06) AS payment_date,
                    SUM(CAST(p.p05 AS REAL)) AS daily_sum_val
                FROM pay AS p
                GROUP BY p.p02, date(p.p06)
            ) d2
            JOIN (
                SELECT
                    c.h01 AS customer_id,
                    co.c01 AS country_id
                FROM cus AS c
                JOIN adr AS a ON a.e01 = c.h06
                JOIN cty AS ci ON ci.d01 = a.e05
                JOIN cnt AS co ON co.c01 = ci.d03
            ) cg2 ON cg2.customer_id = d2.customer_id
        ) y
        WHERE rn2 >= CAST((95 * cnt2 + 99) / 100 AS INTEGER)
        GROUP BY country_id
    ) t ON t.country_id = x.country_id
),
customer_staff_distinct AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        GROUP_CONCAT(DISTINCT (s.o02 || ' ' || s.o03)) AS staff_list,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT p.p04) AS rental_count
    FROM pay p
    JOIN stf s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
scored_days AS (
    SELECT
        cdp.customer_id,
        cg.country,
        cg.city,
        cdp.payment_date,
        cdp.payment_count,
        cdp.day_sum,
        cdp.personal_avg_prev_30,
        (cdp.day_sum - cdp.personal_avg_prev_30) AS deviation_from_personal_avg,
        cs.staff_list,
        cs.staff_count,
        cs.rental_count,
        cp.p95_day_sum
    FROM customer_daily_with_prev_avg cdp
    JOIN (
        SELECT
            c.h01 AS customer_id,
            co.c01 AS country_id,
            co.c02 AS country,
            ci.d02 AS city
        FROM cus c
        JOIN adr a ON a.e01 = c.h06
        JOIN cty ci ON ci.d01 = a.e05
        JOIN cnt co ON co.c01 = ci.d03
    ) cg ON cg.customer_id = cdp.customer_id
    JOIN (
        SELECT
            co2.c01 AS country_id,
            t.p95_day_sum
        FROM cnt co2
        JOIN (
            /* rebuild per-country p95 thresholds using existing logic */
            SELECT
                country_id,
                MIN(daily_sum_val) AS p95_day_sum
            FROM (
                SELECT
                    cg2.country_id,
                    d2.daily_sum_val,
                    ROW_NUMBER() OVER (PARTITION BY cg2.country_id ORDER BY d2.daily_sum_val) AS rn2,
                    COUNT(*) OVER (PARTITION BY cg2.country_id) AS cnt2
                FROM (
                    SELECT
                        p.p02 AS customer_id,
                        date(p.p06) AS payment_date,
                        SUM(CAST(p.p05 AS REAL)) AS daily_sum_val
                    FROM pay p
                    GROUP BY p.p02, date(p.p06)
                ) d2
                JOIN (
                    SELECT
                        c.h01 AS customer_id,
                        co.c01 AS country_id
                    FROM cus c
                    JOIN adr a ON a.e01 = c.h06
                    JOIN cty ci ON ci.d01 = a.e05
                    JOIN cnt co ON co.c01 = ci.d03
                ) cg2 ON cg2.customer_id = d2.customer_id
            ) y
            WHERE rn2 >= CAST((95 * cnt2 + 99) / 100 AS INTEGER)
            GROUP BY country_id
        ) t ON t.country_id = co2.c01
    ) cp ON cp.country_id = cg.country_id
    LEFT JOIN customer_staff_distinct cs
      ON cs.customer_id = cdp.customer_id
     AND cs.payment_date = cdp.payment_date
    WHERE cdp.personal_avg_prev_30 IS NOT NULL
)
SELECT
    sd.customer_id,
    sd.country,
    sd.city,
    sd.payment_date AS spike_date,
    sd.payment_count,
    ROUND(sd.day_sum, 2) AS day_sum,
    ROUND(sd.personal_avg_prev_30, 2) AS personal_avg_prev_30,
    ROUND(sd.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    sd.staff_list,
    DENSE_RANK() OVER (
        PARTITION BY sd.country
        ORDER BY sd.deviation_from_personal_avg DESC
    ) AS suspicious_rank_in_country
FROM scored_days sd
WHERE
    sd.payment_count >= 3
    AND sd.staff_count >= 2
    AND sd.day_sum > 2.0 * sd.personal_avg_prev_30
    AND sd.day_sum > sd.p95_day_sum
ORDER BY
    sd.country,
    suspicious_rank_in_country,
    sd.payment_date,
    sd.customer_id;