WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT cnt_store.c02) AS store_countries
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN sto ON sto.j01 = s.o07
    JOIN adr AS adr_store ON adr_store.e01 = sto.j03
    JOIN cty AS cty_store ON cty_store.d01 = adr_store.e05
    JOIN cnt AS cnt_store ON cnt_store.c01 = cty_store.d03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, DATE(p.p06)
),
customer_history AS (
    SELECT
        dp.*,
        (
            SELECT SUM(prev.day_amount) / 30.0
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= DATE(dp.payment_date, '-30 days')
              AND prev.payment_date < dp.payment_date
        ) AS avg_30d
    FROM daily_payments AS dp
),
suspicious_days AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt_cust.c02 AS customer_country,
        (ch.day_amount / NULLIF(ch.avg_30d, 0)) AS exceed_ratio
    FROM customer_history AS ch
    JOIN cus AS c ON c.h01 = ch.customer_id
    JOIN adr AS adr_cust ON adr_cust.e01 = c.h06
    JOIN cty AS cty_cust ON cty_cust.d01 = adr_cust.e05
    JOIN cnt AS cnt_cust ON cnt_cust.c01 = cty_cust.d03
    WHERE ch.payment_count >= 3
      AND ch.day_amount >= 2 * ch.avg_30d
      AND ch.store_count > 1
      AND ch.store_countries LIKE '%' || cnt_cust.c02 || '%' -- Проверка на наличие страны магазина, отличной от страны клиента
)
SELECT
    customer_id,
    customer_country,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(avg_30d, 2) AS avg_30d,
    staff_count,
    store_count,
    store_countries,
    RANK() OVER (PARTITION BY customer_country ORDER BY exceed_ratio DESC) AS suspicion_rank
FROM suspicious_days
ORDER BY customer_country, suspicion_rank;