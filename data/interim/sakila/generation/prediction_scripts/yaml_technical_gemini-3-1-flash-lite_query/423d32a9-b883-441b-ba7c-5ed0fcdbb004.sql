WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_history AS (
    SELECT
        mp.*,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_payments AS mp
),
qualifying_months AS (
    SELECT
        ch.*,
        (ch.total_amount - ch.prev_avg_amount) AS deviation
    FROM customer_history AS ch
    WHERE ch.prev_avg_amount IS NOT NULL
      AND ch.total_amount >= 2 * ch.prev_avg_amount
      AND ch.payment_count >= 5
      AND (ch.staff_count > 1 OR ch.store_count > 1)
),
customer_monthly_counts AS (
    SELECT customer_id, COUNT(*) AS months_qualified
    FROM qualifying_months
    GROUP BY customer_id
),
final_report AS (
    SELECT
        qm.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        ct.d02 AS city,
        cnt.c01 AS country_id,
        RANK() OVER (
            PARTITION BY cnt.c01, qm.month_start
            ORDER BY qm.deviation DESC
        ) AS country_rank
    FROM qualifying_months AS qm
    JOIN customer_monthly_counts AS cmc ON qm.customer_id = cmc.customer_id
    JOIN cus AS c ON c.h01 = qm.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt ON cnt.c01 = ct.d03
    WHERE cmc.months_qualified = 12
)
SELECT
    strftime('%Y-%m', month_start) AS month,
    country,
    city,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    ROUND(deviation, 2) AS deviation_from_prev_avg,
    country_rank
FROM final_report
ORDER BY month, country, country_rank;