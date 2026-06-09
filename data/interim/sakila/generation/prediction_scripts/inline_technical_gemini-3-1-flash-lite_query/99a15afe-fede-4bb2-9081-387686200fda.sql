WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > date(r.q02, '+' || f.i07 || ' days') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS late_return_share
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flm f ON i.n02 = f.i01
    GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.month_start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        c.h02 AS store_id,
        ct.d03 AS country_id
    FROM monthly_customer_stats mcs
    JOIN cus c ON mcs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
),
store_country_percentiles AS (
    SELECT
        store_id,
        country_id,
        month_start,
        monthly_amount,
        PERCENT_RANK() OVER (
            PARTITION BY store_id, country_id, month_start 
            ORDER BY monthly_amount
        ) AS p_rank
    FROM customer_history
),
p95_thresholds AS (
    SELECT
        store_id,
        country_id,
        month_start,
        MAX(monthly_amount) AS p95_val
    FROM store_country_percentiles
    WHERE p_rank <= 0.95
    GROUP BY store_id, country_id, month_start
),
final_ranking AS (
    SELECT
        ch.*,
        RANK() OVER (
            PARTITION BY ch.store_id, ch.month_start 
            ORDER BY ch.monthly_amount DESC
        ) AS store_rank
    FROM customer_history ch
    JOIN p95_thresholds p95 
      ON ch.store_id = p95.store_id 
      AND ch.country_id = p95.country_id 
      AND ch.month_start = p95.month_start
    WHERE ch.prev_avg_amount IS NOT NULL
      AND ch.monthly_amount >= 3 * ch.prev_avg_amount
      AND ch.monthly_amount > p95.p95_val
)
SELECT
    fr.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country,
    ct.d02 AS city,
    fr.store_id,
    strftime('%Y-%m', fr.month_start) AS month,
    ROUND(fr.monthly_amount, 2) AS total_amount,
    fr.payment_count,
    fr.staff_count,
    ROUND(fr.late_return_share, 4) AS late_return_share,
    fr.store_rank
FROM final_ranking fr
JOIN cus c ON fr.customer_id = c.h01
JOIN adr a ON c.h06 = a.e01
JOIN cty ct ON a.e05 = ct.d01
JOIN cnt co ON ct.d03 = co.c01
ORDER BY fr.month_start, fr.store_id, fr.store_rank;