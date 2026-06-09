WITH payment_details AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.p05 AS amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        c.h02 AS customer_store_id,
        c.h06 AS customer_address_id,
        r.q03 AS inventory_id,
        i.n03 AS inventory_store_id,
        cat.g02 AS category_name
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    LEFT JOIN flc AS fc ON fc.l01 = i.n02
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
        ) AS month_rank
    FROM monthly_stats AS ms
)
SELECT
    customer_id,
    strftime('%Y-%m', month_start) AS month,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    ROUND(off_store_share, 4) AS off_store_share,
    ROUND(max_payment, 2) AS max_payment,
    month_rank,
    categories
FROM monthly_with_history
WHERE prev_avg_amount IS NOT NULL
  AND total_amount > 3.0 * prev_avg_amount
  AND payment_count >= 5
ORDER BY month_start, total_amount DESC;