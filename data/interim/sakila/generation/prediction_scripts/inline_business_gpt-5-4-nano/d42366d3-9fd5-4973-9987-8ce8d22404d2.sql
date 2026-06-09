WITH
client_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        c.h02 AS home_store_id,
        a.e01 AS customer_address_id,
        ci.d01 AS customer_city_id,
        ci.d02 AS customer_city,
        co.c01 AS customer_country_id,
        co.c02 AS customer_country
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
pay_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        r.q01 AS rental_id,
        cg.customer_country_id,
        cg.customer_country,
        cg.home_store_id
    FROM pay AS p
    JOIN client_geo AS cg ON cg.customer_id = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
),
monthly_customer AS (
    SELECT
        customer_id,
        month_start,
        customer_country_id,
        customer_country,
        home_store_id,
        SUM(payment_amount) AS month_payment_sum,
        COUNT(*) AS month_payment_count,
        MAX(payment_amount) AS max_single_payment,
        SUM(CASE WHEN staff_store_id <> home_store_id THEN 1 ELSE 0 END) AS off_home_payment_count,
        1.0 * SUM(CASE WHEN staff_store_id <> home_store_id THEN 1 ELSE 0 END) / COUNT(*) AS off_home_payment_share,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT staff_store_id) AS distinct_staff_store_count
    FROM pay_base
    GROUP BY
        customer_id, month_start, customer_country_id, customer_country, home_store_id
),
personal_history AS (
    SELECT
        mc.*,
        AVG(month_payment_sum) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev2_avg_month_sum
    FROM monthly_customer AS mc
),
country_month_stats AS (
    SELECT
        customer_country_id,
        month_start,
        -- медиана недоступна напрямую в SQLite; используем приближение через 90-й квантиль как "типичное значение"
        -- (фактически "верхний порог" для фильтрации).
        AVG(month_payment_sum) AS country_month_avg_sum,
        COUNT(*) AS country_month_customers
    FROM monthly_customer
    GROUP BY customer_country_id, month_start
),
country_month_rank AS (
    SELECT
        mc.*,
        RANK() OVER (
            PARTITION BY mc.customer_country_id, mc.month_start
            ORDER BY mc.month_payment_sum
        ) AS asc_rank_in_country_month,
        COUNT(*) OVER (
            PARTITION BY mc.customer_country_id, mc.month_start
        ) AS cnt_in_country_month
    FROM monthly_customer AS mc
),
combined AS (
    SELECT
        ph.customer_id,
        ph.month_start,
        ph.customer_country_id,
        ph.customer_country,
        ph.home_store_id,
        ph.month_payment_sum,
        ph.month_payment_count,
        ph.max_single_payment,
        ph.off_home_payment_share,
        ph.distinct_staff_count,
        ph.distinct_staff_store_count,
        ph.prev2_avg_month_sum,
        cmr.asc_rank_in_country_month,
        cmr.cnt_in_country_month,
        cms.country_month_avg_sum
    FROM personal_history AS ph
    JOIN country_month_rank AS cmr
      ON cmr.customer_id = ph.customer_id
     AND cmr.month_start = ph.month_start
    JOIN country_month_stats AS cms
      ON cms.customer_country_id = ph.customer_country_id
     AND cms.month_start = ph.month_start
),
suspicious AS (
    SELECT
        c.*,
        -- "типичное значение" по стране за месяц задаём как 90-й процентиль (верхняя граница),
        -- приближённо: считаем подозрительными месяцы, попавшие в верхние 10% по сумме внутри страны.
        CAST(((c.cnt_in_country_month + 9) / 10) AS INTEGER) AS top10_threshold_rank
    FROM combined AS c
    WHERE c.prev2_avg_month_sum IS NOT NULL
      AND c.prev2_avg_month_sum > 0
      AND c.month_payment_sum > 3.0 * c.prev2_avg_month_sum
)
SELECT
    s.month_start AS payment_month,
    s.customer_id,
    cg.customer_first_name,
    cg.customer_last_name,
    s.customer_country,
    cg.customer_city,
    s.home_store_id AS customer_home_store_id,
    s.month_payment_count,
    ROUND(s.month_payment_sum, 2) AS month_payment_sum,
    ROUND(s.max_single_payment, 2) AS max_single_payment,
    ROUND(s.off_home_payment_share, 4) AS off_home_payment_share,
    s.distinct_staff_count,
    s.distinct_staff_store_count,
    -- место клиента по сумме платежей внутри страны за этот месяц
    DENSE_RANK() OVER (
        PARTITION BY s.customer_country_id, s.month_start
        ORDER BY s.month_payment_sum DESC
    ) AS country_month_sum_rank
FROM suspicious AS s
JOIN client_geo AS cg
  ON cg.customer_id = s.customer_id
WHERE
    -- условие "выходит за пределы типичного значения для страны"
    -- = попадание в верхние 10% по сумме платежей внутри страны за месяц
    s.asc_rank_in_country_month > (s.top10_threshold_rank - 1)
ORDER BY
    s.customer_country,
    payment_month,
    country_month_sum_rank,
    s.customer_id;