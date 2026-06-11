WITH payment_days AS (
    SELECT
        p.p02 AS customer_id,
        p.p06 AS payment_ts,
        date(p.p06) AS payment_date,
        p.p05 AS payment_amount,
        p.p03 AS staff_id,
        st.o07 AS staff_store_id,
        s.customer_store_id AS customer_store_id_placeholder
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN stf AS st
        ON st.o01 = p.p03
    JOIN (
        SELECT
            c2.h01 AS customer_id,
            c2.h02 AS customer_store_id
        FROM cus AS c2
    ) AS s
        ON s.customer_id = c.h01
),
daily_customer_staff_store AS (
    SELECT
        pd.customer_id,
        pd.payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(pd.payment_amount AS REAL)) AS day_amount,
        COUNT(DISTINCT pd.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT pd.staff_store_id) AS distinct_store_count
    FROM payment_days AS pd
    GROUP BY
        pd.customer_id,
        pd.payment_date
),
flagged_days AS (
    SELECT
        d.customer_id,
        d.payment_date,
        d.payment_count,
        d.day_amount,
        d.distinct_staff_count,
        d.distinct_store_count,
        d.day_amount
          / NULLIF((
              SELECT AVG(CAST(p2.p05 AS REAL))
              FROM pay AS p2
              WHERE p2.p02 = d.customer_id
                AND date(p2.p06) >= date(d.payment_date, '-30 days')
                AND date(p2.p06) < d.payment_date
              GROUP BY p2.p02, date(p2.p06)
          ), 0) AS unused_ratio
    FROM daily_customer_staff_store AS d
    WHERE d.payment_count >= 3
      AND (d.distinct_staff_count >= 2 OR d.distinct_store_count >= 2)
),
daily_with_customer_geo AS (
    SELECT
        fd.customer_id,
        fd.payment_date,
        fd.payment_count,
        fd.day_amount,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city,
        cn.c02 AS country,
        cn.c01 AS country_id
    FROM flagged_days AS fd
    JOIN cus AS c
        ON c.h01 = fd.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
),
daily_with_prev_avg AS (
    SELECT
        dwg.*,
        (
            SELECT AVG(CAST(t.day_amount AS REAL))
            FROM (
                SELECT
                    p2.p02 AS customer_id,
                    date(p2.p06) AS payment_date,
                    SUM(CAST(p2.p05 AS REAL)) AS day_amount
                FROM pay AS p2
                WHERE p2.p02 = dwg.customer_id
                  AND date(p2.p06) >= date(dwg.payment_date, '-30 days')
                  AND date(p2.p06) < dwg.payment_date
                GROUP BY p2.p02, date(p2.p06)
            ) AS t
        ) AS avg_prev_30d_amount
    FROM daily_with_customer_geo AS dwg
),
country_daily_distribution AS (
    SELECT
        d.*,
        ROW_NUMBER() OVER (
            PARTITION BY d.country_id, d.payment_date
            ORDER BY d.day_amount
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY d.country_id, d.payment_date
        ) AS n
    FROM daily_with_prev_avg AS d
),
country_p95 AS (
    SELECT
        country_id,
        payment_date,
        MIN(day_amount) AS p95_day_amount
    FROM (
        SELECT
            cdd.*,
            (0.95 * (n - 1) + 1) AS p95_pos
        FROM country_daily_distribution AS cdd
    ) AS x
    WHERE rn >= CAST(p95_pos AS INTEGER)
    GROUP BY
        country_id,
        payment_date
),
result_ranked AS (
    SELECT
        d.*,
        cp.p95_day_amount,
        RANK() OVER (
            PARTITION BY d.country_id, d.payment_date
            ORDER BY d.day_amount DESC
        ) AS day_amount_rank_in_country_by_p95
    FROM daily_with_prev_avg AS d
    LEFT JOIN country_p95 AS cp
        ON cp.country_id = d.country_id
       AND cp.payment_date = d.payment_date
    WHERE d.avg_prev_30d_amount IS NOT NULL
      AND d.avg_prev_30d_amount > 0
)
SELECT
    rr.customer_id AS h01,
    rr.country,
    rr.city AS d02,
    rr.payment_date AS p06_date,
    rr.payment_count,
    ROUND(rr.day_amount, 2) AS day_amount,
    ROUND(rr.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
    ROUND(rr.day_amount - rr.avg_prev_30d_amount, 2) AS deviation_from_prev_avg,
    rr.day_amount_rank_in_country_by_p95 AS daily_amount_rank_by_p95,
    (
        SELECT GROUP_CONCAT(DISTINCT p3.p03)
        FROM pay AS p3
        WHERE p3.p02 = rr.customer_id
          AND date(p3.p06) = rr.payment_date
    ) AS distinct_staff_ids_o01,
    (
        SELECT GROUP_CONCAT(DISTINCT st2.o07)
        FROM pay AS p4
        JOIN stf AS st2 ON st2.o01 = p4.p03
        WHERE p4.p02 = rr.customer_id
          AND date(p4.p06) = rr.payment_date
    ) AS distinct_store_ids_j01
FROM result_ranked AS rr
WHERE rr.day_amount >= 3 * rr.avg_prev_30d_amount
ORDER BY
    rr.country,
    rr.payment_date,
    rr.day_amount DESC,
    rr.customer_id;