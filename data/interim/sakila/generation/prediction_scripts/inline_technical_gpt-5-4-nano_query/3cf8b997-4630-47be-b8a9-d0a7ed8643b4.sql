WITH
-- помесячная агрегация платежей по клиенту (включая гео и магазин клиента)
monthly_pay AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS month_amount
    FROM pay p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
customer_base AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS store_id,
        ct.d02 AS city_name,
        cn.c02 AS country_name
    FROM cus c
    JOIN adr a   ON a.e01 = c.h06
    JOIN cty ct  ON ct.d01 = a.e05
    JOIN cnt cn  ON cn.c01 = ct.d03
),
monthly_enriched AS (
    SELECT
        cb.store_id,
        cb.city_name,
        cb.country_name,
        mp.customer_id,
        mp.month_start,
        mp.payment_count,
        mp.month_amount
    FROM monthly_pay mp
    JOIN customer_base cb
      ON cb.customer_id = mp.customer_id
),
monthly_history AS (
    SELECT
        me.*,
        AVG(me.month_amount) OVER (
            PARTITION BY me.customer_id
            ORDER BY me.month_start
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev2_month_avg_amount
    FROM monthly_enriched me
),
suspicious_months AS (
    SELECT
        mh.*
    FROM monthly_history mh
    WHERE mh.prev2_month_avg_amount IS NOT NULL
      AND mh.payment_count >= 3
      AND mh.month_amount >= 2.0 * mh.prev2_month_avg_amount
),
store_top10_threshold AS (
    -- порог топ-10% по клиентам внутри магазина: 90-й перцентиль по месячной сумме
    -- (аппроксимация через позицию в ранжировании внутри магазина и месяца)
    SELECT
        sm.store_id,
        sm.month_start,
        sm.customer_id,
        sm.month_amount,
        RANK() OVER (
            PARTITION BY sm.store_id, sm.month_start
            ORDER BY sm.month_amount DESC
        ) AS store_month_amount_rank,
        COUNT(*) OVER (
            PARTITION BY sm.store_id, sm.month_start
        ) AS store_month_customer_count
    FROM suspicious_months sm
),
suspicious_months_top10 AS (
    SELECT
        *
    FROM store_top10_threshold
    WHERE store_month_amount_rank <= CAST(CEIL(store_month_customer_count * 0.10) AS INTEGER)
),
customer_months_all_year AS (
    -- оставляем только тех клиентов, для которых каждый месяц 2005 года является "подозрительным"
    -- (то есть есть запись и выполняются условия)
    SELECT
        smt10.store_id,
        smt10.customer_id,
        COUNT(*) AS suspicious_months_cnt
    FROM suspicious_months_top10 smt10
    GROUP BY smt10.store_id, smt10.customer_id
    HAVING suspicious_months_cnt = 12
),
month_top_staff AS (
    -- для каждого клиента/месяца/магазина: сотрудник с максимальной суммой платежей клиента
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        stf.o07 AS top_staff_store_id,
        p.p03 AS top_staff_id,
        SUM(CAST(p.p05 AS REAL)) AS staff_amount,
        ROW_NUMBER() OVER (
            PARTITION BY p.p02, date(p.p06, 'start of month')
            ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.p03
        ) AS rn
    FROM pay p
    JOIN stf ON stf.o01 = p.p03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
    GROUP BY
        p.p02,
        date(p.p06, 'start of month'),
        stf.o07,
        p.p03
),
month_top_staff_pick AS (
    SELECT
        customer_id,
        month_start,
        top_staff_id
    FROM month_top_staff
    WHERE rn = 1
),
staff_names AS (
    SELECT
        o01 AS staff_id,
        o02 || ' ' || o03 AS staff_full_name
    FROM stf
)
SELECT
    smt10.store_id AS store_id,
    cb.city_name AS customer_city,
    cb.country_name AS customer_country,
    smt10.customer_id,
    strftime('%Y-%m', smt10.month_start) AS payment_month,
    ROUND(smt10.month_amount, 2) AS month_amount,
    smt10.payment_count,
    ROUND(smt10.prev2_month_avg_amount, 2) AS rolling_prev2_month_avg,
    ROUND(smt10.month_amount - smt10.prev2_month_avg_amount, 2) AS deviation_from_rolling_avg,
    RANK() OVER (
        PARTITION BY smt10.store_id, smt10.month_start
        ORDER BY smt10.month_amount DESC
    ) AS store_month_customer_rank,
    st.staff_full_name AS top_staff_full_name,
    stp.top_staff_id AS top_staff_id
FROM suspicious_months_top10 smt10
JOIN customer_months_all_year cmy
  ON cmy.store_id = smt10.store_id
 AND cmy.customer_id = smt10.customer_id
JOIN customer_base cb
  ON cb.customer_id = smt10.customer_id
LEFT JOIN month_top_staff_pick stp
  ON stp.customer_id = smt10.customer_id
 AND stp.month_start = smt10.month_start
LEFT JOIN staff_names st
  ON st.staff_id = stp.top_staff_id
ORDER BY
    smt10.store_id,
    smt10.customer_id,
    smt10.month_start;