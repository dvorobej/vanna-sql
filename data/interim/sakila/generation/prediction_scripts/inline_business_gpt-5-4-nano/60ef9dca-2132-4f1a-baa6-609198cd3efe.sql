WITH monthly_customer_store AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        c.h02 AS store_id,
        p.p06 AS payment_datetime,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count,
        MAX(p.p03) AS last_staff_id_in_month
    FROM pay AS p
    JOIN cus AS c
      ON c.h01 = p.p02
    GROUP BY
        c.h01, c.h03, c.h04, c.h02,
        date(p.p06, 'start of month')
),
monthly_with_personal_avg AS (
    SELECT
        m.*,
        AVG(m.monthly_amount) OVER (
            PARTITION BY m.customer_id
        ) AS personal_avg_monthly_amount
    FROM monthly_customer_store AS m
),
ranked_in_store AS (
    SELECT
        mwp.*,
        PERCENT_RANK() OVER (
            PARTITION BY mwp.store_id, mwp.month_start
            ORDER BY mwp.monthly_amount DESC
        ) AS store_month_percent_rank
    FROM monthly_with_personal_avg AS mwp
)
SELECT
    mwp.customer_id,
    mwp.customer_first_name,
    mwp.customer_last_name,
    sto.j01 AS store_id,
    adr_store.e01 AS store_address_id,
    cty_store.d02 AS store_city,
    cnt_store.c02 AS store_country,
    adr_c.e02 AS customer_address_line,
    cty_c.d02 AS customer_city,
    cnt_c.c02 AS customer_country,
    mwp.month_start AS payment_month,
    mwp.monthly_amount,
    mwp.payment_count,
    (mwp.monthly_amount - mwp.personal_avg_monthly_amount) AS deviation_from_personal_avg,
    RANK() OVER (
        PARTITION BY mwp.store_id, mwp.month_start
        ORDER BY mwp.monthly_amount DESC
    ) AS position_in_store_by_month,
    mwp.last_staff_id_in_month AS last_staff_id
FROM ranked_in_store AS mwp
JOIN sto AS sto
  ON sto.j01 = mwp.store_id
JOIN adr AS adr_store
  ON adr_store.e01 = sto.j03
JOIN cty AS cty_store
  ON cty_store.d01 = adr_store.e05
JOIN cnt AS cnt_store
  ON cnt_store.c01 = cty_store.d03
JOIN cus AS c
  ON c.h01 = mwp.customer_id
JOIN adr AS adr_c
  ON adr_c.e01 = c.h06
JOIN cty AS cty_c
  ON cty_c.d01 = adr_c.e05
JOIN cnt AS cnt_c
  ON cnt_c.c01 = cty_c.d03
WHERE
    mwp.month_start >= '2005-01-01'
    AND mwp.month_start < '2006-01-01'
    AND mwp.monthly_amount > mwp.personal_avg_monthly_amount * 1.5
    AND mwp.store_month_percent_rank <= 0.05
ORDER BY
    mwp.month_start,
    mwp.store_id,
    mwp.monthly_amount DESC,
    mwp.customer_id;