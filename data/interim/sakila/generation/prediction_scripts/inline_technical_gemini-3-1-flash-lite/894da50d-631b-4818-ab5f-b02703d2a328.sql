WITH monthly_base AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p01 AS payment_id,
        p.p05 AS amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        c.h02 AS customer_store_id,
        c.h06 AS customer_address_id,
        a.e05 AS customer_city_id,
        ci.d03 AS customer_country_id,
        r.q03 AS inventory_id,
        i.n03 AS inventory_store_id,
        st.j03 AS store_address_id,
        st_a.e05 AS store_city_id,
        st_ci.d03 AS store_country_id
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN stf s ON s.o01 = p.p03
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN sto st ON st.j01 = i.n03
    JOIN adr st_a ON st_a.e01 = st.j03
    JOIN cty st_ci ON st_ci.d01 = st_a.e05
),
monthly_stats AS (
    SELECT
        customer_id,
        payment_month,
        SUM(amount) AS total_amount,
        COUNT(payment_id) AS payment_count,
        MAX(amount) AS max_amount,
        AVG(SUM(amount)) OVER (PARTITION BY customer_id ORDER BY payment_month ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prev_avg_amount,
        SUM(CASE WHEN staff_store_id <> customer_store_id OR customer_city_id <> store_city_id OR customer_country_id <> store_country_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS foreign_store_share
    FROM monthly_base
    GROUP BY customer_id, payment_month
),
filtered_months AS (
    SELECT * FROM monthly_stats
    WHERE total_amount > 3 * prev_avg_amount AND payment_count >= 5
),
category_agg AS (
    SELECT
        mb.customer_id,
        mb.payment_month,
        GROUP_CONCAT(DISTINCT cat.g02) AS categories
    FROM monthly_base mb
    JOIN inv i ON i.n01 = mb.inventory_id
    JOIN flc ON flc.l01 = i.n02
    JOIN cat ON cat.g01 = flc.l02
    GROUP BY mb.customer_id, mb.payment_month
)
SELECT
    fm.customer_id,
    fm.payment_month,
    fm.total_amount,
    fm.payment_count,
    fm.foreign_store_share,
    fm.max_amount,
    RANK() OVER (PARTITION BY fm.customer_id ORDER BY fm.total_amount DESC) AS month_rank,
    ca.categories
FROM filtered_months fm
JOIN category_agg ca ON ca.customer_id = fm.customer_id AND ca.payment_month = fm.payment_month
ORDER BY fm.customer_id, fm.payment_month;