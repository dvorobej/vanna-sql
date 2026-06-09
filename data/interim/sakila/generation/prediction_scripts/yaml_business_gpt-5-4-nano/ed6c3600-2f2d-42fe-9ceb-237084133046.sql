WITH daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_sum,
        COUNT(*) AS day_payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT stf.o07) AS store_count
    FROM pay AS p
    JOIN stf ON stf.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
customer_home AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS home_store_id
    FROM cus AS c
),
daily_risk_base AS (
    SELECT
        d.*,
        ch.home_store_id,
        -- доля платежей, принятых сотрудниками из НЕ домашнего магазина клиента
        (
            SELECT
                CASE WHEN COUNT(*) = 0 THEN 0
                     ELSE SUM(CASE WHEN s2.o07 = ch.home_store_id THEN 0 ELSE 1 END) * 1.0 / COUNT(*)
                END
            FROM pay AS p2
            JOIN stf AS s2 ON s2.o01 = p2.p03
            WHERE p2.p02 = d.customer_id
              AND date(p2.p06) = d.payment_date
        ) AS share_payments_not_home_store
    FROM daily AS d
    JOIN customer_home AS ch ON ch.customer_id = d.customer_id
),
with_stats AS (
    SELECT
        drb.*,
        -- историческая статистика по сумме за предыдущие 30 дней
        (
            SELECT AVG(d2.day_sum)
            FROM daily AS d2
            WHERE d2.customer_id = drb.customer_id
              AND d2.payment_date >= date(drb.payment_date, '-30 day')
              AND d2.payment_date < drb.payment_date
        ) AS avg_day_sum_prev30,
        (
            SELECT
                CASE
                    WHEN COUNT(*) <= 1 THEN NULL
                    ELSE
                        -- стандартное отклонение (популяционная/ выборочная не принципиально для сигнализации;