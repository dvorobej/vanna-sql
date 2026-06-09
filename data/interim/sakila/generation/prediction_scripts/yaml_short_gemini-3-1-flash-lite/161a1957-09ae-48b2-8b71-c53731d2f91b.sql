WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
daily_with_history AS (
    SELECT
        ds.*,
        (
            SELECT AVG(prev.daily_amount)
            FROM daily_stats AS prev
            WHERE prev.customer_id = ds.customer_id
              AND prev.payment_date >= date(ds.payment_date, '-30 days')
              AND prev.payment_date < ds.payment_date
        ) AS avg_prev_30d
    FROM daily_stats AS ds
    WHERE ds.payment_count >= 3
      AND (ds.staff_count > 1 OR ds.store_count > 1)
),
country_p95 AS (
    SELECT
        cty.d03 AS country_id,
        (SELECT val FROM (
            SELECT daily_amount AS val, PERCENT_RANK() OVER (ORDER BY daily_amount) as pr
            FROM daily_stats ds2
            JOIN cus c ON c.h01 = ds2.customer_id
            JOIN adr a ON a.e01 = c.h06
            JOIN cty ON cty.d01 = a.e05
            WHERE cty.d03 = cnt.c01
        ) WHERE pr >= 0.95 LIMIT 1) AS p95_val
    FROM cnt
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    dwh.payment_date,
    dwh.payment_count,
    ROUND(dwh.daily_amount, 2) AS daily_amount,
    dwh.staff_count,
    ROUND(dwh.daily_amount - dwh.avg_prev_30d, 2) AS deviation,
    RANK() OVER (PARTITION BY cnt.c01 ORDER BY (dwh.daily_amount - dwh.avg_prev_30d) DESC) AS suspicion_rank
FROM daily_with_history AS dwh
JOIN cus AS c ON c.h01 = dwh.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
JOIN country_p95 cp ON cp.country_id = cnt.c01
WHERE dwh.avg_prev_30d IS NOT NULL
  AND dwh.daily_amount >= 2 * dwh.avg_prev_30d
  AND dwh.daily_amount > cp.p95_val
ORDER BY suspicion_rank;