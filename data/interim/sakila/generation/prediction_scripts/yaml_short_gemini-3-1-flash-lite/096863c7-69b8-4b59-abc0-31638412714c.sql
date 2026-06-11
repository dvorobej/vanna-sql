WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_history AS (
    SELECT
        dcs.*,
        (
            SELECT AVG(h.daily_amount)
            FROM daily_customer_stats AS h
            WHERE h.customer_id = dcs.customer_id
              AND h.payment_day >= DATE(dcs.payment_day, '-30 days')
              AND h.payment_day < dcs.payment_day
        ) AS avg_30d_amount
    FROM daily_customer_stats AS dcs
),
country_stats AS (
    SELECT
        c.c01 AS country_id,
        AVG(dcs.daily_amount) AS avg_country_daily_amount
    FROM daily_customer_stats AS dcs
    JOIN cus ON cus.h01 = dcs.customer_id
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt AS c ON c.c01 = cty.d03
    GROUP BY c.c01
),
suspicious_activity AS (
    SELECT
        ch.*,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cnt.c02 AS country_name,
        cnt.c01 AS country_id,
        cs.avg_country_daily_amount
    FROM customer_history AS ch
    JOIN cus ON cus.h01 = ch.customer_id
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    JOIN country_stats AS cs ON cs.country_id = cnt.c01
    WHERE ch.avg_30d_amount > 0
      AND ch.daily_amount > (3 * ch.avg_30d_amount)
      AND ch.daily_amount > cs.avg_country_daily_amount
      AND (ch.staff_count > 1 OR ch.store_count > 1)
)
SELECT
    customer_name,
    country_name,
    payment_day,
    daily_amount,
    avg_30d_amount,
    avg_country_daily_amount,
    RANK() OVER (PARTITION BY country_id ORDER BY daily_amount DESC) AS country_rank
FROM suspicious_activity
ORDER BY country_name, country_rank;