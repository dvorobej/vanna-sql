WITH payment_details AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.p01 AS payment_id,
        p.p05 AS amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        c.h02 AS customer_store_id,
        c.h06 AS customer_address_id,
        i.n03 AS film_store_id,
        fc.l02 AS category_id,
        cat.g02 AS category_name
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf s ON s.o01 = p.p03
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flc fc ON fc.l01 = i.n02
    JOIN cat ON cat.g01 = fc.l02
),
geo_mismatch AS (
    SELECT
        pd.*,
        a.e05 AS customer_city_id,
        ct.d03 AS customer_country_id,
        sto.j03 AS store_address_id,
        sa.e05 AS store_city_id,
        sct.d03 AS store_country_id
    FROM payment_details pd
    JOIN adr a ON a.e01 = pd.customer_address_id
    JOIN cty ct ON ct.d01 = a.e05
    JOIN sto ON sto.j01 = pd.film_store_id
    JOIN adr sa ON sa.e01 = sto.j03
    JOIN cty sct ON sct.d01 = sa.e05
    WHERE pd.customer_city_id <> pd.store_city_id OR pd.customer_country_id <> pd.store_country_id
),
monthly_stats AS (
    SELECT
        customer_id,
        month_start,
        SUM(amount) AS total_amount,
        COUNT(payment_id) AS payment_count,
        MAX(amount) AS max_payment,
        COUNT(DISTINCT staff_store_id) AS distinct_staff_stores,
        SUM(CASE WHEN staff_store_id <> customer_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(payment_id) AS off_store_share
    FROM payment_details
    GROUP BY customer_id, month_start
),
history_avg AS (
    SELECT
        customer_id,
        month_start,
        total_amount,
        payment_count,
        max_payment,
        off_store_share,
        AVG(total_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_stats
    WHERE payment_count >= 5
      AND distinct_staff_stores > 1
),
category_spending AS (
    SELECT
        customer_id,
        month_start,
        category_name,
        SUM(amount) AS cat_amount
    FROM payment_details
    GROUP BY customer_id, month_start, category_name
),
top_categories AS (
    SELECT
        customer_id,
        month_start,
        GROUP_CONCAT(category_name, ', ') AS main_categories
    FROM (
        SELECT customer_id, month_start, category_name,
               RANK() OVER (PARTITION BY customer_id, month_start ORDER BY cat_amount DESC) as rnk
        FROM category_spending
    )
    WHERE rnk <= 2
    GROUP BY customer_id, month_start
)
SELECT
    strftime('%Y-%m', h.month_start) AS month,
    h.total_amount,
    h.payment_count,
    ROUND(h.off_store_share, 4) AS off_store_share,
    h.max_payment,
    RANK() OVER (PARTITION BY h.customer_id ORDER BY h.total_amount DESC) AS month_rank,
    tc.main_categories
FROM history_avg h
JOIN top_categories tc ON tc.customer_id = h.customer_id AND tc.month_start = h.month_start
WHERE h.prev_avg_amount > 0
  AND h.total_amount > 3 * h.prev_avg_amount
  AND EXISTS (SELECT 1 FROM geo_mismatch gm WHERE gm.customer_id = h.customer_id AND gm.month_start = h.month_start)
ORDER BY h.customer_id, h.month_start;