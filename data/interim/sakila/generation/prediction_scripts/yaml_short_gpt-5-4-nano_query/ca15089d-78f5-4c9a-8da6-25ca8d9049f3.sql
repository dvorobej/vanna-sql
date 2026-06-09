WITH monthly_base AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS monthly_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT COALESCE(i.n03, s.o07)) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS i
        ON i.n01 = r.q03
    WHERE p.p06 IS NOT NULL
    GROUP BY
        c.h01,
        c.h03,
        c.h04,
        co.c02,
        ci.d02,
        strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        mb.*,
        AVG(mb.monthly_amount) OVER (
            PARTITION BY mb.customer_id
            ORDER BY mb.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_monthly_amount
    FROM monthly_base AS mb
),
qualified_months AS (
    SELECT
        mwh.*,
        CASE WHEN mwh.monthly_amount <> 0 THEN mwh.max_payment * 1.0 / mwh.monthly_amount ELSE NULL END AS max_payment_share,
        ROW_NUMBER() OVER (
            PARTITION BY mwh.customer_id, mwh.payment_month
            ORDER BY mwh.monthly_amount DESC
        ) AS rn
    FROM monthly_with_history AS mwh
    WHERE mwh.prev_avg_monthly_amount IS NOT NULL
      AND mwh.prev_avg_monthly_amount > 0
      AND mwh.monthly_amount >= 3.0 * mwh.prev_avg_monthly_amount
      AND EXISTS (
          SELECT 1
          FROM pay AS p2
          WHERE p2.p02 = mwh.customer_id
            AND strftime('%Y-%m', p2.p06) = mwh.payment_month
          GROUP BY p2.p02, strftime('%Y-%m', p2.p06)
          HAVING
            COUNT(*) >= 3
            AND COUNT(DISTINCT p2.p06) >= 3
            AND (COUNT(DISTINCT p2.p03) >= 2 OR COUNT(DISTINCT COALESCE(i2.n03, s2.o07)) >= 2)
      )
)
SELECT
    qm.payment_month AS month,
    qm.customer_name AS fio,
    qm.country_name AS country,
    qm.city_name AS city,
    qm.payment_count,
    ROUND(qm.monthly_amount, 2) AS total_amount,
    ROUND(qm.max_payment, 2) AS max_payment,
    ROUND(qm.max_payment_share, 4) AS max_payment_share_in_month,
    qm.distinct_staff_count AS different_staff_count,
    qm.distinct_store_count AS different_store_count,
    RANK() OVER (
        PARTITION BY qm.country_name, qm.payment_month
        ORDER BY qm.monthly_amount DESC
    ) AS country_monthly_amount_rank
FROM qualified_months AS qm
WHERE qm.rn = 1
ORDER BY
    qm.country_name,
    qm.payment_month,
    country_monthly_amount_rank,
    qm.customer_id;