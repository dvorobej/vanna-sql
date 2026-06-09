WITH payment_details AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.p05 AS amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        c.h02 AS home_store_id,
        c.h06 AS customer_address_id,
        i.n03 AS film_store_id,
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
        SUM(CASE WHEN staff_store_id <> home_store_id THEN 1.0 ELSE 0.0 END) / COUNT(*) AS foreign_store_share,
        AVG(monthly_amount_prev) OVER (PARTITION BY customer_id ORDER BY month_start) AS avg_prev_amount
    FROM (
        SELECT *,
            LAG(SUM(amount)) OVER (PARTITION BY customer_id ORDER BY month_start) as monthly_amount_prev
        FROM payment_details
        GROUP BY customer_id, month_start
    )
    GROUP BY customer_id, month_start
),
category_spending AS (
    SELECT
        customer_id,
        month_start,
        category_name,
        SUM(amount) as cat_amount,
        RANK() OVER (PARTITION BY customer_id, month_start ORDER BY SUM(amount) DESC) as cat_rank
    FROM payment_details
    GROUP BY customer_id, month_start, category_name
)
SELECT
    ms.month_start,
    ms.customer_id,
    ms.total_amount,
    ms.payment_count,
    ms.foreign_store_share,
    ms.max_payment,
    RANK() OVER (PARTITION BY ms.customer_id ORDER BY ms.total_amount DESC) as month_rank,
    GROUP_CONCAT(cs.category_name) as top_categories
FROM monthly_stats ms
JOIN category_spending cs ON cs.customer_id = ms.customer_id AND cs.month_start = ms.month_start AND cs.cat_rank <= 3
WHERE ms.total_amount > 3 * ms.avg_prev_amount
  AND ms.payment_count >= 5
GROUP BY ms.month_start, ms.customer_id
ORDER BY ms.month_start, ms.total_amount DESC;