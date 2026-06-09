WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(p.p01) AS daily_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
customer_history AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (
            PARTITION BY ds.customer_id 
            ORDER BY ds.payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_daily_sum_30d,
        AVG(ds.daily_count) OVER (
            PARTITION BY ds.customer_id 
            ORDER BY ds.payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_daily_count_30d
    FROM daily_stats AS ds
),
suspicious_cases AS (
    SELECT
        ch.*,
        (ch.daily_sum / NULLIF(ch.avg_daily_sum_30d, 0)) AS sum_spike_ratio,
        (ch.daily_count / NULLIF(ch.avg_daily_count_30d, 0)) AS count_spike_ratio
    FROM customer_history AS ch
    WHERE ch.avg_daily_sum_30d IS NOT NULL
      AND (ch.daily_sum > 3 * ch.avg_daily_sum_30d OR ch.daily_count > 3 * ch.avg_daily_count_30d)
      AND (ch.staff_count > 1 OR ch.store_count > 1)
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    sc.payment_date,
    sc.daily_sum,
    sc.daily_count,
    sc.staff_count,
    sc.store_count,
    ROUND(sc.sum_spike_ratio, 2) AS sum_spike_ratio,
    RANK() OVER (ORDER BY sc.sum_spike_ratio DESC, sc.daily_sum DESC) AS risk_rank
FROM suspicious_cases AS sc
JOIN cus AS c ON c.h01 = sc.customer_id
ORDER BY risk_rank ASC;