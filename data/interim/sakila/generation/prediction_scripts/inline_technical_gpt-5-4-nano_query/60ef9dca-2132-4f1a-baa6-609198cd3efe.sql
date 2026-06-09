WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS store_id,
        c.h06 AS address_id,
        ct.country_name,
        ci.city_name
    FROM cus AS c
    JOIN adr AS a
      ON a.e01 = c.h06
    JOIN cty AS ci
      ON ci.d01 = a.e05
    JOIN cnt AS ct
      ON ct.c01 = ci.d03
),
payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p05 AS payment_amount,
        date(p.p06, 'start of month') AS month_start,
        strftime('%Y-%m', p.p06) AS month_label
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
),
monthly_client AS (
    SELECT
        pw.customer_id,
        pw.month_start,
        COUNT(*) AS payment_count,
        SUM(pw.payment_amount) AS month_amount
    FROM payments_2005 AS pw
    GROUP BY
        pw.customer_id,
        pw.month_start
),
client_year_avg AS (
    SELECT
        customer_id,
        AVG(month_amount) AS personal_avg_month_amount
    FROM monthly_client
    GROUP BY customer_id
),
last_staff_per_month AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month_label,
        p.p03 AS staff_id,
        ROW_NUMBER() OVER (
            PARTITION BY p.p02, strftime('%Y-%m', p.p06)
            ORDER BY p.p06 DESC, p.p01 DESC
        ) AS rn
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
),
monthly_rank_in_store AS (
    SELECT
        mc.customer_id,
        mc.month_start,
        mc.payment_count,
        mc.month_amount,
        RANK() OVER (
            PARTITION BY c.store_id, mc.month_start
            ORDER BY mc.month_amount DESC
        ) AS store_month_rank,
        COUNT(*) OVER (
            PARTITION BY c.store_id, mc.month_start
        ) AS store_month_customers_count
    FROM monthly_client AS mc
    JOIN cus AS c
      ON c.h01 = mc.customer_id
),
joined AS (
    SELECT
        c.customer_id,
        c.store_id,
        c.city_name,
        c.country_name,
        mr.month_start,
        mr.payment_count,
        mr.month_amount,
        cya.personal_avg_month_amount,
        (mr.month_amount - cya.personal_avg_month_amount) AS deviation_from_personal_avg,
        mr.store_month_rank,
        mr.store_month_customers_count
    FROM monthly_rank_in_store AS mr
    JOIN customer_geo AS c
      ON c.customer_id = mr.customer_id
    JOIN client_year_avg AS cya
      ON cya.customer_id = mr.customer_id
),
qualifying_monthly AS (
    SELECT *
    FROM joined
    WHERE personal_avg_month_amount > 0
      AND month_amount > personal_avg_month_amount * 2
      AND store_month_rank <= CAST(CEIL(store_month_customers_count * 0.05) AS INT)
),
clients_all_12_months AS (
    SELECT
        customer_id
    FROM qualifying_monthly
    GROUP BY customer_id
    HAVING COUNT(*) = 12
)
SELECT
    qm.customer_id,
    qm.store_id,
    qm.city_name,
    qm.country_name,
    strftime('%Y-%m', qm.month_start) AS month,
    ROUND(qm.month_amount, 2) AS month_sum,
    qm.payment_count,
    ROUND(qm.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    qm.store_month_rank AS rank_within_store_for_month,
    ls.staff_id AS last_staff_id
FROM qualifying_monthly AS qm
JOIN clients_all_12_months AS cal
  ON cal.customer_id = qm.customer_id
LEFT JOIN last_staff_per_month AS ls
  ON ls.customer_id = qm.customer_id
 AND ls.month_label = strftime('%Y-%m', qm.month_start)
 AND ls.rn = 1
ORDER BY
  qm.customer_id,
  qm.month_start;