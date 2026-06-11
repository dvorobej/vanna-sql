WITH month_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month_ym,
        SUM(CAST(p.p05 AS REAL)) AS month_amount,
        COUNT(*) AS month_payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS staff_non_home_share
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN stf AS s
        ON s.o01 = p.p03
    WHERE p.p04 IS NOT NULL
    GROUP BY
        p.p02,
        strftime('%Y-%m', p.p06)
),
personal_prev2 AS (
    SELECT
        mp.*,
        (
            LAG(mp.month_amount, 1) OVER (
                PARTITION BY mp.customer_id
                ORDER BY mp.month_ym
            ) +
            LAG(mp.month_amount, 2) OVER (
                PARTITION BY mp.customer_id
                ORDER BY mp.month_ym
            )
        ) / 2.0 AS personal_avg_prev2
    FROM month_payments AS mp
),
country_p95 AS (
    SELECT
        country_id,
        month_ym,
        p95_amount
    FROM (
        SELECT
            t.country_id,
            t.month_ym,
            t.month_amount AS amount_value,
            ROW_NUMBER() OVER (
                PARTITION BY t.country_id, t.month_ym
                ORDER BY t.month_amount
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY t.country_id, t.month_ym
            ) AS cnt
        FROM (
            SELECT
                p.p02 AS customer_id,
                strftime('%Y-%m', p.p06) AS month_ym,
                SUM(CAST(p.p05 AS REAL)) AS month_amount,
                co.c01 AS country_id
            FROM pay AS p
            JOIN cus AS c
                ON c.h01 = p.p02
            JOIN adr AS a
                ON a.e01 = c.h06
            JOIN cty AS ci
                ON ci.d01 = a.e05
            JOIN cnt AS co
                ON co.c01 = ci.d03
            WHERE p.p04 IS NOT NULL
            GROUP BY
                p.p02,
                strftime('%Y-%m', p.p06),
                co.c01
        ) AS t
    ) ranked
    JOIN (
        SELECT
            country_id,
            month_ym,
            MAX(CASE WHEN rn >= CAST((95 * cnt + 99) / 100 AS INTEGER) THEN amount_value END) AS p95_amount
        FROM (
            SELECT
                t.country_id,
                t.month_ym,
                t.month_amount AS amount_value,
                ROW_NUMBER() OVER (
                    PARTITION BY t.country_id, t.month_ym
                    ORDER BY t.month_amount
                ) AS rn,
                COUNT(*) OVER (
                    PARTITION BY t.country_id, t.month_ym
                ) AS cnt
            FROM (
                SELECT
                    p.p02 AS customer_id,
                    strftime('%Y-%m', p.p06) AS month_ym,
                    SUM(CAST(p.p05 AS REAL)) AS month_amount,
                    co.c01 AS country_id
                FROM pay AS p
                JOIN cus AS c
                    ON c.h01 = p.p02
                JOIN adr AS a
                    ON a.e01 = c.h06
                JOIN cty AS ci
                    ON ci.d01 = a.e05
                JOIN cnt AS co
                    ON co.c01 = ci.d03
                WHERE p.p04 IS NOT NULL
                GROUP BY
                    p.p02,
                    strftime('%Y-%m', p.p06),
                    co.c01
            ) AS t
        ) s
        GROUP BY country_id, month_ym
    ) p95
      USING (country_id, month_ym)
    WHERE 1=0
),
month_country_p95 AS (
    SELECT
        x.country_id,
        x.month_ym,
        x.p95_amount
    FROM (
        SELECT
            country_id,
            month_ym,
            MAX(amount_value) AS p95_amount
        FROM (
            SELECT
                country_id,
                month_ym,
                month_amount AS amount_value,
                ROW_NUMBER() OVER (
                    PARTITION BY country_id, month_ym
                    ORDER BY month_amount
                ) AS rn,
                COUNT(*) OVER (
                    PARTITION BY country_id, month_ym
                ) AS cnt
            FROM (
                SELECT
                    p.p02 AS customer_id,
                    strftime('%Y-%m', p.p06) AS month_ym,
                    SUM(CAST(p.p05 AS REAL)) AS month_amount,
                    co.c01 AS country_id
                FROM pay AS p
                JOIN cus AS c
                    ON c.h01 = p.p02
                JOIN adr AS a
                    ON a.e01 = c.h06
                JOIN cty AS ci
                    ON ci.d01 = a.e05
                JOIN cnt AS co
                    ON co.c01 = ci.d03
                WHERE p.p04 IS NOT NULL
                GROUP BY
                    p.p02,
                    strftime('%Y-%m', p.p06),
                    co.c01
            ) z
        ) q
        WHERE q.rn >= CAST((95 * q.cnt + 99) / 100 AS INTEGER)
        GROUP BY country_id, month_ym
    ) x
),
joined_geo AS (
    SELECT
        mp.customer_id,
        mp.month_ym,
        mp.month_amount,
        mp.month_payment_count,
        mp.staff_count,
        mp.staff_non_home_share,
        co.c01 AS country_id
    FROM month_payments AS mp
    JOIN cus AS c
        ON c.h01 = mp.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
)
,scored AS (
    SELECT
        j.customer_id,
        j.month_ym,
        j.country_id,
        j.month_amount,
        j.month_payment_count,
        j.staff_count,
        j.staff_non_home_share,
        pp2.personal_avg_prev2,
        (j.month_amount - pp2.personal_avg_prev2) AS deviation_from_personal_avg_prev2,
        mcp95.p95_amount AS country_p95_amount,
        j.month_amount / NULLIF(pp2.personal_avg_prev2, 0) AS ratio_to_personal_avg_prev2
    FROM joined_geo j
    JOIN personal_prev2 pp2
        ON pp2.customer_id = j.customer_id
       AND pp2.month_ym = j.month_ym
    JOIN month_country_p95 mcp95
        ON mcp95.country_id = j.country_id
       AND mcp95.month_ym = j.month_ym
    WHERE pp2.personal_avg_prev2 IS NOT NULL
)
SELECT
    s.month_ym AS payment_month,
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country,
    ct.d02 AS city,
    ROUND(s.month_amount, 2) AS month_payment_sum,
    s.month_payment_count,
    ROUND(s.deviation_from_personal_avg_prev2, 2) AS deviation_from_personal_avg_prev2,
    ROUND(s.staff_non_home_share, 4) AS non_home_staff_share,
    s.staff_count,
    RANK() OVER (
        PARTITION BY s.country_id, s.month_ym
        ORDER BY s.month_amount DESC
    ) AS country_amount_rank
FROM scored s
JOIN cus c
    ON c.h01 = s.customer_id
JOIN adr a
    ON a.e01 = c.h06
JOIN cty ct
    ON ct.d01 = a.e05
JOIN cnt co
    ON co.c01 = ct.d03
WHERE s.month_amount >= 2.0 * s.personal_avg_prev2
  AND s.month_amount >= s.country_p95_amount
  AND s.staff_non_home_share > 0.5
ORDER BY
    s.month_ym,
    co.c02,
    country_amount_rank,
    s.customer_id;