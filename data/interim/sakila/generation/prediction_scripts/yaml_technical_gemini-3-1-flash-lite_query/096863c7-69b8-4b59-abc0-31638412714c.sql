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
customer_stats AS (
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
country_stats AS (
    SELECT
        c.c01 AS country_id,
        AVG(dca.daily_amount) AS country_avg_daily_amount
    FROM daily_customer_activity AS dca
    JOIN cus AS cu ON cu.h01 = dca.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS c ON c.c01 = ct.d03
    GROUP BY c.c01
),
suspicious_days AS (
    SELECT
        cs.*,
        cu.h03 || ' ' || cu.h04 AS customer_name,
        ct.d02 AS city_name,
        cn.c02 AS country_name,
        cn.c01 AS country_id,
        cs.daily_amount - cs.personal_avg_30d AS deviation_personal,
        cs.daily_amount - cst.country_avg_daily_amount AS deviation_country
    FROM customer_stats AS cs
    JOIN cus AS cu ON cu.h01 = cs.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN country_stats AS cst ON cst.country_id = cn.c01
    WHERE cs.personal_avg_30d > 0
      AND cs.daily_amount > 3 * cs.personal_avg_30d
      AND cs.daily_amount > cst.country_avg_daily_amount
      AND (cs.staff_count > 1 OR cs.store_count > 1)
)
SELECT
    customer_name,
    country_name,
    city_name,
    payment_date,
    ROUND(daily_amount, 2) AS daily_amount,
    payment_count,
    ROUND(deviation_personal, 2) AS deviation_from_personal_avg,
    ROUND(deviation_country, 2) AS deviation_from_country_avg,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY daily_amount DESC
    ) AS country_suspicion_rank
FROM suspicious_days
ORDER BY country_name, country_suspicion_rank;