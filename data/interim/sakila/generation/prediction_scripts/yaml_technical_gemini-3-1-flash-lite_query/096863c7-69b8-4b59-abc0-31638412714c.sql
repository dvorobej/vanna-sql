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
country_daily_avg AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
country_avg_stats AS (
    SELECT
        cg.country_id,
        dca.payment_date,
        AVG(dca.daily_amount) AS country_avg_daily_amount
    FROM daily_customer_activity AS dca
    JOIN country_geo AS cg ON cg.customer_id = dca.customer_id
    GROUP BY cg.country_id, dca.payment_date
),
suspicious_cases AS (
    SELECT
        cs.*,
        cg.country_name,
        cg.city_name,
        cas.country_avg_daily_amount,
        cs.daily_amount - cs.personal_avg_30d AS deviation_personal,
        cs.daily_amount - cas.country_avg_daily_amount AS deviation_country
    FROM customer_stats AS cs
    JOIN country_geo AS cg ON cg.customer_id = cs.customer_id
    JOIN country_avg_stats AS cas ON cas.country_id = cg.country_id AND cas.payment_date = cs.payment_date
    WHERE cs.personal_avg_30d > 0
      AND cs.daily_amount > 3 * cs.personal_avg_30d
      AND cs.daily_amount > cas.country_avg_daily_amount
      AND (cs.staff_count > 1 OR cs.store_count > 1)
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    sc.country_name,
    sc.city_name,
    sc.payment_date,
    sc.daily_amount,
    sc.payment_count,
    ROUND(sc.deviation_personal, 2) AS deviation_from_personal_avg,
    ROUND(sc.deviation_country, 2) AS deviation_from_country_avg,
    sc.staff_count,
    sc.store_count,
    RANK() OVER (PARTITION BY sc.country_id ORDER BY sc.daily_amount DESC) AS suspicion_rank_in_country
FROM suspicious_cases AS sc
JOIN cus AS c ON c.h01 = sc.customer_id
ORDER BY sc.country_name, suspicion_rank_in_country;