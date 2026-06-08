WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        DATE(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS amount
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
),
daily_payments AS (
    SELECT
        customer_id,
        payment_day,
        COUNT(*) AS payment_count,
        SUM(amount) AS total_amount,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT store_id) AS distinct_store_count
    FROM payment_enriched
    GROUP BY
        customer_id,
        payment_day
),
daily_ranked AS (
    SELECT
        dp.*,
        RANK() OVER (
            PARTITION BY dp.customer_id
            ORDER BY dp.total_amount DESC
        ) AS day_amount_rank
    FROM daily_payments AS dp
),
daily_with_previous AS (
    SELECT
        dr.*,
        COALESCE((
            SELECT SUM(dp2.total_amount)
            FROM daily_payments AS dp2
            WHERE dp2.customer_id = dr.customer_id
              AND dp2.payment_day >= DATE(dr.payment_day, '-30 days')
              AND dp2.payment_day < dr.payment_day
        ), 0) / 30.0 AS avg_amount_prev_30_days
    FROM daily_ranked AS dr
)
SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    dwp.payment_day AS payment_date,
    dwp.payment_count,
    ROUND(dwp.total_amount, 2) AS total_amount,
    ROUND(dwp.avg_amount_prev_30_days, 2) AS avg_amount_prev_30_days,
    ROUND(dwp.total_amount / NULLIF(dwp.avg_amount_prev_30_days, 0), 2) AS exceed_ratio,
    dwp.day_amount_rank
FROM daily_with_previous AS dwp
JOIN cus AS c
    ON c.h01 = dwp.customer_id
JOIN adr AS a
    ON a.e01 = c.h06
JOIN cty
    ON cty.d01 = a.e05
JOIN cnt
    ON cnt.c01 = cty.d03
WHERE dwp.avg_amount_prev_30_days > 0
  AND dwp.total_amount >= dwp.avg_amount_prev_30_days * 3
  AND dwp.payment_count >= 3
  AND (
      dwp.distinct_staff_count >= 2
      OR dwp.distinct_store_count >= 2
  )
ORDER BY
    exceed_ratio DESC,
    dwp.total_amount DESC,
    dwp.payment_day,
    customer_id;