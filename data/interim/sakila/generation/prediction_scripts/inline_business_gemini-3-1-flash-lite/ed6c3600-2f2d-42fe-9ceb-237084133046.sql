WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        GROUP_CONCAT(p.p03) AS staff_ids,
        GROUP_CONCAT(p.p04) AS rental_ids
    FROM pay p
    GROUP BY p.p02, date(p.p06)
),
customer_history AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        AVG(ds.daily_count) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_count_30d,
        (SELECT COUNT(*) FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.payment_date < ds.payment_date) AS history_len
    FROM daily_stats ds
),
suspicious_days AS (
    SELECT
        ch.*
    FROM customer_history ch
    WHERE ch.history_len >= 30
      AND (ch.daily_sum > (ch.avg_sum_30d + 3 * (SELECT STDEV(daily_sum) FROM daily_stats WHERE customer_id = ch.customer_id AND payment_date >= date(ch.payment_date, '-30 days')))
           OR ch.daily_count > (ch.avg_count_30d * 3))
),
risk_metrics AS (
    SELECT
        sd.*,
        (SELECT COUNT(*) FROM pay p WHERE p.p02 = sd.customer_id AND date(p.p06) = sd.payment_date AND p.p03 NOT IN (SELECT o01 FROM stf WHERE o07 = (SELECT h02 FROM cus WHERE h01 = sd.customer_id))) * 1.0 / sd.daily_count AS foreign_staff_ratio,
        (SELECT g02 FROM cat WHERE g01 = (SELECT l02 FROM flc WHERE l01 = (SELECT q03 FROM ren WHERE q01 = (SELECT p04 FROM pay WHERE p02 = sd.customer_id AND date(p.p06) = sd.payment_date LIMIT 1)) LIMIT 1) LIMIT 1) AS top_category
    FROM suspicious_days sd
)
SELECT
    rm.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    rm.payment_date,
    rm.daily_sum,
    rm.daily_count,
    rm.foreign_staff_ratio,
    rm.top_category,
    RANK() OVER (ORDER BY rm.daily_sum DESC) AS suspicion_rank
FROM risk_metrics rm
JOIN cus c ON c.h01 = rm.customer_id
JOIN adr a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY suspicion_rank;