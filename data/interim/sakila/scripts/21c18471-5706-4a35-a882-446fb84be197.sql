WITH payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        a.e01 AS address_id,
        ct.d01 AS city_id,
        ct.d02 AS city_name,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        p.p03 AS staff_id,
        s.o02 AS staff_first_name,
        s.o03 AS staff_last_name,
        s.o07 AS store_id,
        p.p05 AS amount,
        p.p06 AS payment_ts,
        date(p.p06) AS payment_date
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
),
daily_customer AS (
    SELECT
        customer_id,
        customer_first_name,
        customer_last_name,
        city_id,
        city_name,
        country_id,
        country_name,
        payment_date,
        COUNT(*) AS payment_count,
        SUM(amount) AS day_amount,
        MAX(amount) AS max_payment_amount
    FROM payments_2005
    GROUP BY
        customer_id,
        customer_first_name,
        customer_last_name,
        city_id,
        city_name,
        country_id,
        country_name,
        payment_date
),
daily_ranked AS (
    SELECT
        dc.*,
        AVG(day_amount) OVER (PARTITION BY customer_id) AS customer_avg_daily_amount,
        AVG(day_amount) OVER (PARTITION BY country_id) AS country_avg_daily_amount,
        RANK() OVER (
            PARTITION BY customer_id
            ORDER BY day_amount DESC
        ) AS day_amount_rank
    FROM daily_customer AS dc
),
largest_payment AS (
    SELECT
        customer_id,
        payment_date,
        payment_id,
        amount,
        staff_id,
        staff_first_name,
        staff_last_name,
        store_id,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, payment_date
            ORDER BY amount DESC, payment_ts DESC, payment_id DESC
        ) AS rn
    FROM payments_2005
)
SELECT
    dr.customer_id,
    dr.customer_first_name || ' ' || dr.customer_last_name AS customer_name,
    dr.city_name,
    dr.country_name,
    dr.payment_date,
    dr.payment_count,
    ROUND(dr.day_amount, 2) AS day_amount,
    ROUND(dr.max_payment_amount, 2) AS max_payment_amount,
    lp.staff_id,
    lp.staff_first_name || ' ' || lp.staff_last_name AS staff_name,
    lp.store_id,
    dr.day_amount_rank
FROM daily_ranked AS dr
JOIN largest_payment AS lp
  ON lp.customer_id = dr.customer_id
 AND lp.payment_date = dr.payment_date
 AND lp.rn = 1
WHERE dr.payment_count >= 3
  AND dr.day_amount >= 2 * dr.customer_avg_daily_amount
  AND dr.day_amount > dr.country_avg_daily_amount
ORDER BY
    dr.day_amount DESC,
    dr.customer_id,
    dr.payment_date;