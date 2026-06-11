WITH monthly_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cn.c02 AS country_name,
        ct.d02 AS city_name,
        date(p.p06, 'start of month') AS month_start,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS monthly_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p06) AS distinct_payment_days,
        COUNT(DISTINCT p.p03) AS staff_count_distinct,
        COUNT(DISTINCT s.o07) AS store_count_distinct
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
    GROUP BY
        c.h01,
        c.h03,
        c.h04,
        cn.c02,
        ct.d02,
        date(p.p06, 'start of month')
),
with_history AS (
    SELECT
        mp.*,
        AVG(mp.monthly_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_avg_prev_months
    FROM monthly_payments AS mp
),
qualified AS (
    SELECT
        wh.*
    FROM with_history AS wh
    WHERE wh.personal_avg_prev_months IS NOT NULL
      AND wh.monthly_amount >= 3 * wh.personal_avg_prev_months
      AND wh.distinct_payment_days >= 3
      AND (wh.staff_count_distinct >= 2 OR wh.store_count_distinct >= 2)
),
ranked AS (
    SELECT
        q.*,
        RANK() OVER (
            PARTITION BY q.country_name, q.month_start
            ORDER BY q.monthly_amount DESC
        ) AS customer_country_month_rank
    FROM qualified AS q
)
SELECT
    strftime('%Y-%m', r.month_start) AS month,
    r.customer_name,
    r.country_name AS country,
    r.city_name AS city,
    r.payment_count,
    ROUND(r.monthly_amount, 2) AS monthly_amount,
    ROUND(r.max_payment, 2) AS max_payment,
    ROUND(r.max_payment * 1.0 / NULLIF(r.monthly_amount, 0), 4) AS max_payment_share,
    r.staff_count_distinct AS distinct_staff_count,
    r.store_count_distinct AS distinct_store_count,
    r.customer_country_month_rank AS country_month_rank
FROM ranked AS r
ORDER BY
    r.country_name,
    r.month_start,
    r.customer_country_month_rank,
    r.customer_id;