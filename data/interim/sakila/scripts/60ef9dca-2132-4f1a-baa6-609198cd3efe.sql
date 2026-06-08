WITH payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p05 AS amount,
        p.p06 AS payment_date,
        strftime('%Y-%m', p.p06) AS payment_month
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
),
customer_monthly AS (
    SELECT
        customer_id,
        payment_month,
        SUM(amount) AS monthly_amount,
        COUNT(*) AS payment_count
    FROM payments_2005
    GROUP BY
        customer_id,
        payment_month
),
customer_year_avg AS (
    SELECT
        customer_id,
        SUM(monthly_amount) / 12.0 AS avg_monthly_amount_2005
    FROM customer_monthly
    GROUP BY customer_id
),
store_month_ranked AS (
    SELECT
        cm.customer_id,
        c.h02 AS store_id,
        cm.payment_month,
        cm.monthly_amount,
        cm.payment_count,
        cya.avg_monthly_amount_2005,
        cm.monthly_amount - cya.avg_monthly_amount_2005 AS deviation_from_avg,
        RANK() OVER (
            PARTITION BY c.h02, cm.payment_month
            ORDER BY cm.monthly_amount DESC
        ) AS store_month_rank,
        COUNT(*) OVER (
            PARTITION BY c.h02, cm.payment_month
        ) AS store_month_customer_count
    FROM customer_monthly AS cm
    JOIN cus AS c
        ON c.h01 = cm.customer_id
    JOIN customer_year_avg AS cya
        ON cya.customer_id = cm.customer_id
),
last_staff_payment AS (
    SELECT
        customer_id,
        payment_month,
        staff_id,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, payment_month
            ORDER BY payment_date DESC, payment_id DESC
        ) AS rn
    FROM payments_2005
)
SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    smr.store_id,
    city.d02 AS city,
    country.c02 AS country,
    smr.payment_month,
    ROUND(smr.monthly_amount, 2) AS monthly_amount,
    smr.payment_count,
    ROUND(smr.avg_monthly_amount_2005, 2) AS avg_monthly_amount_2005,
    ROUND(smr.deviation_from_avg, 2) AS deviation_from_avg,
    smr.store_month_rank,
    smr.store_month_customer_count,
    stf.o01 AS last_staff_id,
    stf.o02 || ' ' || stf.o03 AS last_staff_name
FROM store_month_ranked AS smr
JOIN cus AS c
    ON c.h01 = smr.customer_id
JOIN adr AS a
    ON a.e01 = c.h06
JOIN cty AS city
    ON city.d01 = a.e05
JOIN cnt AS country
    ON country.c01 = city.d03
JOIN last_staff_payment AS lsp
    ON lsp.customer_id = smr.customer_id
   AND lsp.payment_month = smr.payment_month
   AND lsp.rn = 1
JOIN stf
    ON stf.o01 = lsp.staff_id
WHERE smr.monthly_amount > 2.0 * smr.avg_monthly_amount_2005
  AND smr.store_month_rank <= (
        CAST(smr.store_month_customer_count * 0.05 AS INTEGER)
        + CASE
            WHEN smr.store_month_customer_count * 0.05 > CAST(smr.store_month_customer_count * 0.05 AS INTEGER)
            THEN 1
            ELSE 0
          END
      )
ORDER BY
    smr.payment_month,
    smr.store_id,
    smr.store_month_rank,
    smr.monthly_amount DESC,
    customer_id;