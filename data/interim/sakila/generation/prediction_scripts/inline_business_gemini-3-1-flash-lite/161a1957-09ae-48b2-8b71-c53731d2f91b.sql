WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT stf.o07) AS store_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_list
    FROM pay AS p
    JOIN stf ON stf.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
customer_history AS (
    SELECT
        dcs.*,
        (
            SELECT AVG(h.day_amount)
            FROM daily_customer_stats AS h
            WHERE h.customer_id = dcs.customer_id
              AND h.payment_date >= date(dcs.payment_date, '-30 days')
              AND h.payment_date < dcs.payment_date
        ) AS avg_30d
    FROM daily_customer_stats AS dcs
),
country_percentiles AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY dcs.day_amount) OVER (PARTITION BY cnt.c01) AS p95_country
    FROM daily_customer_stats AS dcs
    JOIN cus AS c ON c.h01 = dcs.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
suspicious_days AS (
    SELECT
        ch.*,
        cp.country_name,
        cp.city_name,
        cp.country_id,
        (ch.day_amount - ch.avg_30d) AS deviation
    FROM customer_history AS ch
    JOIN country_percentiles AS cp ON cp.customer_id = ch.customer_id
    WHERE ch.payment_count >= 3
      AND (ch.staff_count >= 2 OR ch.store_count >= 2)
      AND ch.day_amount > (2 * ch.avg_30d)
      AND ch.day_amount > cp.p95_country
)
SELECT
    customer_id,
    country_name,
    city_name,
    payment_date,
    payment_count,
    day_amount,
    staff_list,
    avg_30d,
    RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS suspicion_rank
FROM suspicious_days
ORDER BY country_name, suspicion_rank;