WITH customer_monthly AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS month_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        AVG(p.p05) AS avg_payment_amount
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        strftime('%Y-%m', p.p06)
),
customer_monthly_with_history AS (
    SELECT
        cm.*,
        (
            SELECT AVG(prev.month_amount)
            FROM customer_monthly AS prev
            WHERE prev.customer_id = cm.customer_id
              AND prev.month < cm.month
        ) AS historical_avg_month_amount
    FROM customer_monthly AS cm
),
customer_country AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cnt.c02 AS customer_country_name,
        cnt.c01 AS customer_country_id
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = ct.d03
),
store_country AS (
    SELECT
        s.o01 AS staff_id,
        s.o07 AS store_id,
        cnt.c01 AS store_country_id
    FROM stf AS s
    JOIN sto AS st
        ON st.j01 = s.o07
    JOIN adr AS a
        ON a.e01 = st.j03
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = ct.d03
),
cross_country_payments AS (
    SELECT DISTINCT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    JOIN sto AS st
        ON st.j01 = s.o07
    JOIN adr AS sa
        ON sa.e01 = st.j03
    JOIN cty AS sct
        ON sct.d01 = sa.e05
    JOIN cnt AS scn
        ON scn.c01 = sct.d03
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS ca
        ON ca.e01 = c.h06
    JOIN cty AS cct
        ON cct.d01 = ca.e05
    JOIN cnt AS ccn
        ON ccn.c01 = cct.d03
    WHERE scn.c01 <> ccn.c01
)
SELECT
    cmh.month,
    cc.first_name || ' ' || cc.last_name AS customer_name,
    cc.customer_country_name AS country,
    cmh.payment_count,
    ROUND(cmh.month_amount, 2) AS month_amount,
    ROUND(cmh.historical_avg_month_amount, 2) AS historical_avg_month_amount,
    ROUND(cmh.month_amount - cmh.historical_avg_month_amount, 2) AS deviation_from_history,
    cmh.distinct_staff_count,
    cmh.distinct_store_count,
    RANK() OVER (
        PARTITION BY cmh.month
        ORDER BY (cmh.month_amount - cmh.historical_avg_month_amount) DESC
    ) AS month_deviation_rank
FROM customer_monthly_with_history AS cmh
JOIN customer_country AS cc
    ON cc.customer_id = cmh.customer_id
WHERE cmh.payment_count >= 5
  AND cmh.historical_avg_month_amount IS NOT NULL
  AND cmh.month_amount > 2.0 * cmh.historical_avg_month_amount
  AND EXISTS (
      SELECT 1
      FROM pay AS p
      JOIN stf AS s
          ON s.o01 = p.p03
      JOIN sto AS st
          ON st.j01 = s.o07
      JOIN adr AS sa
          ON sa.e01 = st.j03
      JOIN cty AS sct
          ON sct.d01 = sa.e05
      JOIN cnt AS scn
          ON scn.c01 = sct.d03
      JOIN cus AS c
          ON c.h01 = p.p02
      JOIN adr AS ca
          ON ca.e01 = c.h06
      JOIN cty AS cct
          ON cct.d01 = ca.e05
      JOIN cnt AS ccn
          ON ccn.c01 = cct.d03
      WHERE p.p02 = cmh.customer_id
        AND strftime('%Y-%m', p.p06) = cmh.month
        AND scn.c01 <> ccn.c01
  )
ORDER BY
    cmh.month,
    month_deviation_rank,
    cmh.customer_id;