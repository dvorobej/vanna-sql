WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_fio,
        cn.c02 AS country,
        ct.d02 AS city,
        c.h06 AS address_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
),
monthly_base AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS monthly_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT COALESCE(s.o07, -1)) AS distinct_store_count,
        COUNT(DISTINCT date(p.p06)) AS distinct_days_count
    FROM pay AS p
    LEFT JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p04 IS NOT NULL
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
with_personal_history AS (
    SELECT
        mb.*,
        (
            SELECT AVG(mb2.monthly_amount)
            FROM monthly_base AS mb2
            WHERE mb2.customer_id = mb.customer_id
              AND mb2.month_start < mb.month_start
        ) AS prev_months_avg_amount
    FROM monthly_base AS mb
),
qualified_months AS (
    SELECT
        wph.*
    FROM with_personal_history AS wph
    WHERE wph.prev_months_avg_amount IS NOT NULL
      AND wph.prev_months_avg_amount > 0
      AND wph.monthly_amount >= 3.0 * wph.prev_months_avg_amount
      AND wph.payment_count >= 1
      AND wph.distinct_days_count >= 3
      AND wph.distinct_staff_count >= 2
)
SELECT
    qm.customer_id,
    cg.customer_fio,
    strftime('%Y-%m', qm.month_start) AS payment_month,
    cg.country,
    cg.city,
    qm.payment_count,
    ROUND(qm.monthly_amount, 2) AS monthly_amount,
    ROUND(qm.max_payment, 2) AS max_payment,
    ROUND(qm.max_payment * 1.0 / NULLIF(qm.monthly_amount, 0), 4) AS max_payment_share,
    qm.distinct_staff_count AS distinct_staff_count,
    qm.distinct_store_count AS distinct_store_count,
    RANK() OVER (
        PARTITION BY cg.country, qm.month_start
        ORDER BY qm.monthly_amount DESC
    ) AS country_month_amount_rank
FROM qualified_months AS qm
JOIN customer_geo AS cg
  ON cg.customer_id = qm.customer_id
ORDER BY
    cg.country,
    payment_month,
    monthly_amount DESC,
    qm.customer_id;