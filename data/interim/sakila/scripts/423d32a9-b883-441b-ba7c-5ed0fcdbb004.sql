WITH monthly_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cn.c01 AS country_id,
        cn.c02 AS country,
        ct.d02 AS city,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(i.n03, s.o07)) AS store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS i
        ON i.n01 = r.q03
    WHERE p.p04 IS NOT NULL
      AND p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
    GROUP BY
        c.h01,
        c.h03,
        c.h04,
        cn.c01,
        cn.c02,
        ct.d02,
        strftime('%Y-%m', p.p06)
),
monthly_with_previous AS (
    SELECT
        mp.*,
        AVG(mp.monthly_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_avg_amount
    FROM monthly_payments AS mp
),
eligible_customers AS (
    SELECT
        customer_id
    FROM monthly_with_previous
    WHERE previous_avg_amount IS NOT NULL
    GROUP BY customer_id
    HAVING COUNT(*) = SUM(
        CASE
            WHEN monthly_amount >= previous_avg_amount * 2
             AND payment_count >= 5
             AND (staff_count >= 2 OR store_count >= 2)
            THEN 1
            ELSE 0
        END
    )
),
qualified_rows AS (
    SELECT
        mwp.customer_id,
        mwp.first_name,
        mwp.last_name,
        mwp.country_id,
        mwp.country,
        mwp.city,
        mwp.payment_month,
        mwp.monthly_amount,
        mwp.payment_count,
        mwp.previous_avg_amount,
        mwp.monthly_amount - mwp.previous_avg_amount AS deviation_from_previous_avg
    FROM monthly_with_previous AS mwp
    JOIN eligible_customers AS ec
        ON ec.customer_id = mwp.customer_id
    WHERE mwp.previous_avg_amount IS NOT NULL
      AND mwp.monthly_amount >= mwp.previous_avg_amount * 2
      AND mwp.payment_count >= 5
      AND (mwp.staff_count >= 2 OR mwp.store_count >= 2)
)
SELECT
    customer_id,
    first_name,
    last_name,
    payment_month,
    country,
    city,
    ROUND(monthly_amount, 2) AS payment_sum,
    payment_count,
    ROUND(deviation_from_previous_avg, 2) AS deviation_from_previous_avg,
    RANK() OVER (
        PARTITION BY country_id, payment_month
        ORDER BY deviation_from_previous_avg DESC
    ) AS country_deviation_rank
FROM qualified_rows
ORDER BY
    country,
    payment_month,
    country_deviation_rank,
    customer_id;