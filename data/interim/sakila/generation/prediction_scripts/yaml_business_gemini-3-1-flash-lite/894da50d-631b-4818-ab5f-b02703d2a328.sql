WITH payment_details AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.p05 AS amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        c.h02 AS customer_store_id,
        c.h06 AS customer_address_id,
        i.n03 AS inventory_store_id,
        fc.l02 AS category_id,
        cat.g02 AS category_name
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf s ON s.o01 = p.p03
    LEFT JOIN ren r ON r.q01 = p.p04
    LEFT JOIN inv i ON i.n01 = r.q03
    LEFT JOIN flc fc ON fc.l01 = i.n02
    LEFT JOIN cat ON cat.g01 = fc.l02
),
monthly_stats AS (
    SELECT
        customer_id,
        month_start,
        SUM(amount) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(amount) AS max_payment,
        SUM(CASE WHEN staff_store_id <> customer_store_id THEN 1.0 ELSE 0.0 END) / COUNT(*) AS off_store_share,
        GROUP_CONCAT(DISTINCT category_name) AS categories
    FROM payment_details
    GROUP BY customer_id, month_start
),
monthly_with_history AS (
    SELECT
        ms.*,
        AVG(total_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        RANK() OVER (
            PARTITION BY customer_id
            ORDER BY total_amount DESC
        ) AS month_rank_by_amount
    FROM monthly_stats ms
)
SELECT
    strftime('%Y-%m', mwh.month_start) AS payment_month,
    mwh.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    ROUND(mwh.total_amount, 2) AS total_amount,
    mwh.payment_count,
    ROUND(mwh.off_store_share, 4) AS off_store_payment_share,
    ROUND(mwh.max_payment, 2) AS max_payment,
    mwh.month_rank_by_amount,
    mwh.categories AS top_categories
FROM monthly_with_history mwh
JOIN cus c ON c.h01 = mwh.customer_id
WHERE mwh.prev_avg_amount IS NOT NULL
  AND mwh.total_amount > 3.0 * mwh.prev_avg_amount
  AND mwh.payment_count >= 5
ORDER BY mwh.month_start, mwh.total_amount DESC;