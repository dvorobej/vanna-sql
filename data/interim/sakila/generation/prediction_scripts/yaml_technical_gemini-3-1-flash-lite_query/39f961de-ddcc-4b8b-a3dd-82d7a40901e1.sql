WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count,
        MAX(CAST(p.p05 AS REAL)) AS max_payment,
        SUM(CASE WHEN f.i11 IN ('R', 'NC-17') THEN 1.0 ELSE 0.0 END) / COUNT(*) AS r_nc17_share
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flm AS f ON f.i01 = i.n02
    GROUP BY p.p02, date(p.p06)
),
daily_with_history AS (
    SELECT
        da.*,
        (
            SELECT AVG(h.daily_sum)
            FROM daily_activity AS h
            WHERE h.customer_id = da.customer_id
              AND h.pay_date >= date(da.pay_date, '-30 days')
              AND h.pay_date < da.pay_date
        ) AS avg_prev_30
    FROM daily_activity AS da
),
suspicious_days AS (
    SELECT
        dwh.*,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cty.d02 AS city,
        cnt.c02 AS country,
        cnt.c01 AS country_id
    FROM daily_with_history AS dwh
    JOIN cus AS c ON c.h01 = dwh.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE dwh.avg_prev_30 > 0
      AND dwh.daily_sum >= 3 * dwh.avg_prev_30
      AND dwh.payment_count >= 3
      AND (dwh.staff_count > 1 OR dwh.store_count > 1)
)
SELECT
    sd.first_name || ' ' || sd.last_name AS customer_name,
    sd.city,
    sd.country,
    sd.pay_date,
    sd.payment_count,
    ROUND(sd.daily_sum, 2) AS daily_sum,
    ROUND(sd.max_payment, 2) AS max_payment,
    ROUND(sd.r_nc17_share, 4) AS r_nc17_share,
    RANK() OVER (
        PARTITION BY sd.country_id
        ORDER BY sd.daily_sum DESC
    ) AS country_rank
FROM suspicious_days AS sd
ORDER BY
    sd.country,
    country_rank,
    sd.pay_date;