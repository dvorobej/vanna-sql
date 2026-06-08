WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS store_id,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        ct.d01 AS city_id,
        ct.d02 AS city_name,
        date(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        CASE
            WHEN r.q01 IS NOT NULL
             AND r.q05 IS NOT NULL
             AND f.i07 IS NOT NULL
             AND r.q05 > datetime(r.q02, '+' || f.i07 || ' days')
            THEN 1.0
            ELSE 0.0
        END AS is_late_return
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS i
        ON i.n01 = r.q03
    LEFT JOIN flm AS f
        ON f.i01 = i.n02
),
monthly_customer AS (
    SELECT
        customer_id,
        customer_name,
        store_id,
        country_id,
        country_name,
        city_id,
        city_name,
        month_start,
        SUM(payment_amount) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        AVG(is_late_return) AS late_return_share
    FROM payment_base
    GROUP BY
        customer_id,
        customer_name,
        store_id,
        country_id,
        country_name,
        city_id,
        city_name,
        month_start
),
monthly_with_history AS (
    SELECT
        mc.*,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_avg_monthly_amount
    FROM monthly_customer AS mc
),
monthly_ranked AS (
    SELECT
        mwh.*,
        RANK() OVER (
            PARTITION BY store_id, month_start
            ORDER BY monthly_amount DESC
        ) AS store_month_amount_rank
    FROM monthly_with_history AS mwh
),
percentile_ordered AS (
    SELECT
        mc.*,
        COUNT(*) OVER (
            PARTITION BY store_id, country_id, month_start
        ) AS group_count,
        ROW_NUMBER() OVER (
            PARTITION BY store_id, country_id, month_start
            ORDER BY monthly_amount ASC, customer_id ASC
        ) AS amount_row
    FROM monthly_customer AS mc
),
percentile_positioned AS (
    SELECT
        po.*,
        CAST((95 * group_count + 5) / 100 AS INTEGER) AS lower_row,
        CAST((95 * group_count + 5 + 99) / 100 AS INTEGER) AS upper_row,
        ((95 * group_count + 5) % 100) / 100.0 AS fraction
    FROM percentile_ordered AS po
),
percentile_95 AS (
    SELECT
        store_id,
        country_id,
        month_start,
        MAX(CASE WHEN amount_row = lower_row THEN monthly_amount END)
        +
        MAX(fraction) * (
            MAX(CASE WHEN amount_row = upper_row THEN monthly_amount END)
            -
            MAX(CASE WHEN amount_row = lower_row THEN monthly_amount END)
        ) AS p95_monthly_amount
    FROM percentile_positioned
    GROUP BY
        store_id,
        country_id,
        month_start
)
SELECT
    mr.customer_id,
    mr.customer_name,
    mr.country_name AS country,
    mr.city_name AS city,
    mr.store_id,
    mr.month_start AS month,
    ROUND(mr.monthly_amount, 2) AS payment_sum,
    mr.payment_count,
    mr.distinct_staff_count,
    ROUND(mr.late_return_share, 4) AS late_return_payment_share,
    mr.store_month_amount_rank
FROM monthly_ranked AS mr
JOIN percentile_95 AS p95
    ON p95.store_id = mr.store_id
   AND p95.country_id = mr.country_id
   AND p95.month_start = mr.month_start
WHERE mr.previous_avg_monthly_amount IS NOT NULL
  AND mr.monthly_amount >= 3.0 * mr.previous_avg_monthly_amount
  AND mr.monthly_amount > p95.p95_monthly_amount
ORDER BY
    mr.month_start,
    mr.store_id,
    mr.store_month_amount_rank,
    mr.customer_id;