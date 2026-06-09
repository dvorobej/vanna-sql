WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS home_store_id,
        ct.c01 AS country_id,
        ct.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS ct ON ct.c01 = ci.d03
),
monthly_pay AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(CAST(p.p05 AS REAL)) AS month_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN s.o07 <> cgeo.home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS staff_not_home_share
    FROM pay AS p
    JOIN customer_geo AS cgeo ON cgeo.customer_id = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
monthly_with_avgs AS (
    SELECT
        mp.*,
        AVG(month_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_prev2_months
    FROM monthly_pay AS mp
),
country_months AS (
    SELECT
        cgeo.country_id,
        mp.month_start,
        mp.month_amount
    FROM monthly_pay AS mp
    JOIN customer_geo AS cgeo ON cgeo.customer_id = mp.customer_id
),
country_p95 AS (
    SELECT
        country_id,
        month_start,
        day95.month_amount AS country_p95_amount
    FROM (
        SELECT
            country_id,
            month_start,
            month_amount,
            ROW_NUMBER() OVER (
                PARTITION BY country_id, month_start
                ORDER BY month_amount
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY country_id, month_start
            ) AS cnt
        FROM country_months
    ) AS ranked
    JOIN (
        SELECT 1 AS dummy
    ) AS dummy ON 1=1
    JOIN (
        SELECT
            country_id,
            month_start,
            MIN(CASE
                WHEN rn >= CAST((95 * cnt + 99) / 100 AS INTEGER) THEN month_amount
            END) AS month_amount
        FROM (
            SELECT
                country_id,
                month_start,
                month_amount,
                ROW_NUMBER() OVER (
                    PARTITION BY country_id, month_start
                    ORDER BY month_amount
                ) AS rn,
                COUNT(*) OVER (
                    PARTITION BY country_id, month_start
                ) AS cnt
            FROM country_months
        )
        GROUP BY country_id, month_start
    ) AS day95
      ON day95.country_id = ranked.country_id
     AND day95.month_start = ranked.month_start
    GROUP BY ranked.country_id, ranked.month_start
),
scored AS (
    SELECT
        mwa.customer_id,
        cgeo.country_name,
        mwa.month_start,
        mwa.month_amount,
        mwa.payment_count,
        mwa.staff_count,
        mwa.staff_not_home_share,
        mwa.personal_avg_prev2_months,
        (mwa.month_amount - mwa.personal_avg_prev2_months) AS deviation_from_personal_avg,
        cp95.country_p95_amount,
        RANK() OVER (
            PARTITION BY cgeo.country_id, mwa.month_start
            ORDER BY mwa.month_amount DESC
        ) AS country_amount_rank
    FROM monthly_with_avgs AS mwa
    JOIN customer_geo AS cgeo ON cgeo.customer_id = mwa.customer_id
    JOIN country_p95 AS cp95
      ON cp95.country_id = cgeo.country_id
     AND cp95.month_start = mwa.month_start
    WHERE mwa.personal_avg_prev2_months IS NOT NULL
)
SELECT
    s.customer_id,
    s.country_name,
    s.month_start,
    ROUND(s.month_amount, 2) AS month_amount,
    s.payment_count,
    ROUND(s.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    ROUND(s.personal_avg_prev2_months, 2) AS personal_avg_prev2_months,
    ROUND(s.country_p95_amount, 2) AS country_p95_amount,
    ROUND(s.staff_not_home_share, 4) AS staff_not_home_share,
    s.staff_count,
    s.country_amount_rank
FROM scored AS s
WHERE s.month_amount >= 2.0 * s.personal_avg_prev2_months
  AND s.month_amount >= s.country_p95_amount
ORDER BY
  s.country_name,
  s.month_start,
  s.country_amount_rank,
  s.customer_id;