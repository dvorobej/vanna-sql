WITH daily_customer_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
daily_with_personal_avg AS (
    SELECT
        dca.*,
        (
            SELECT AVG(prev.daily_amount)
            FROM daily_customer_activity AS prev
            WHERE prev.customer_id = dca.customer_id
              AND prev.payment_date >= DATE(dca.payment_date, '-30 days')
              AND prev.payment_date < dca.payment_date
        ) AS personal_avg_30d
    FROM daily_customer_activity AS dca
),
country_daily_avg AS (
    SELECT
        c.c01 AS country_id,
        dca.payment_date,
        AVG(dca.daily_amount) AS country_avg_daily
    FROM daily_customer_activity AS dca
    JOIN cus AS cu ON cu.h01 = dca.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS c ON c.c01 = ci.d03
    GROUP BY c.c01, dca.payment_date
),
suspicious_spikes AS (
    SELECT
        dpa.*,
        cu.h03 || ' ' || cu.h04 AS customer_name,
        c.c02 AS country_name,
        ci.d02 AS city_name,
        c.c01 AS country_id,
        cda.country_avg_daily
    FROM daily_with_personal_avg AS dpa
    JOIN cus AS cu ON cu.h01 = dpa.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS c ON c.c01 = ci.d03
    JOIN country_daily_avg AS cda ON cda.country_id = c.c01 AND cda.payment_date = dpa.payment_date
    WHERE dpa.personal_avg_30d > 0
      AND dpa.daily_amount > 3 * dpa.personal_avg_30d
      AND dpa.daily_amount > cda.country_avg_daily
      AND (dpa.staff_count > 1 OR dpa.store_count > 1)
)
SELECT
    customer_name,
    country_name,
    city_name,
    payment_date,
    daily_amount,
    payment_count,
    ROUND(daily_amount - personal_avg_30d, 2) AS deviation_from_personal_avg,
    ROUND(daily_amount - country_avg_daily, 2) AS deviation_from_country_avg,
    staff_count,
    store_count,
    RANK() OVER (PARTITION BY country_id ORDER BY daily_amount DESC) AS country_suspicion_rank
FROM suspicious_spikes
ORDER BY country_name, country_suspicion_rank;