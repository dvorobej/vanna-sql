WITH
daily_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS customer_home_store_id,
        co.c02 AS customer_country,
        ci.d02 AS customer_city,
        DATE(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS payment_amount,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) AS off_home_staff_payment_count,
        1.0 * SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) / COUNT(*) AS off_home_staff_payment_share
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        c.h01,
        c.h03,
        c.h04,
        c.h02,
        co.c02,
        ci.d02,
        DATE(p.p06)
),
history_raw AS (
    SELECT
        d.customer_id,
        d.customer_name,
        d.customer_home_store_id,
        d.customer_country,
        d.customer_city,
        d.payment_day,
        d.payment_count,
        d.payment_amount,
        d.off_home_staff_payment_count,
        d.off_home_staff_payment_share,
        COUNT(h.payment_day) AS history_days,
        COALESCE(SUM(h.payment_count), 0) AS history_payment_count,
        AVG(h.payment_amount) AS avg_payment_amount_30d,
        AVG(h.payment_count) AS avg_payment_count_30d,
        CASE
            WHEN COUNT(h.payment_day) > 1 THEN
                (
                    SUM(h.payment_amount * h.payment_amount)
                    - SUM(h.payment_amount) * SUM(h.payment_amount) / COUNT(h.payment_day)
                ) / (COUNT(h.payment_day) - 1)
            ELSE 0
        END AS var_payment_amount_30d,
        CASE
            WHEN COUNT(h.payment_day) > 1 THEN
                (
                    SUM(1.0 * h.payment_count * h.payment_count)
                    - SUM(h.payment_count) * SUM(h.payment_count) / COUNT(h.payment_day)
                ) / (COUNT(h.payment_day) - 1)
            ELSE 0
        END AS var_payment_count_30d
    FROM daily_payments AS d
    LEFT JOIN daily_payments AS h
        ON h.customer_id = d.customer_id
       AND JULIANDAY(h.payment_day) >= JULIANDAY(d.payment_day) - 30
       AND JULIANDAY(h.payment_day) < JULIANDAY(d.payment_day)
    GROUP BY
        d.customer_id,
        d.customer_name,
        d.customer_home_store_id,
        d.customer_country,
        d.customer_city,
        d.payment_day,
        d.payment_count,
        d.payment_amount,
        d.off_home_staff_payment_count,
        d.off_home_staff_payment_share
),
history_stats AS (
    SELECT
        *,
        SQRT(CASE WHEN var_payment_amount_30d < 0 THEN 0 ELSE var_payment_amount_30d END) AS stddev_payment_amount_30d,
        SQRT(CASE WHEN var_payment_count_30d < 0 THEN 0 ELSE var_payment_count_30d END) AS stddev_payment_count_30d
    FROM history_raw
),
staff_day_counts AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        p.p03 AS staff_id,
        s.o02 || ' ' || s.o03 AS staff_name,
        COUNT(*) AS staff_payment_count,
        SUM(p.p05) AS staff_payment_amount
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        DATE(p.p06),
        p.p03,
        s.o02,
        s.o03
),
staff_day_ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, payment_day
            ORDER BY staff_payment_count DESC, staff_payment_amount DESC, staff_id
        ) AS rn
    FROM staff_day_counts
),
category_day_counts AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        ca.g01 AS category_id,
        ca.g02 AS category_name,
        COUNT(*) AS category_payment_count,
        SUM(p.p05) AS category_payment_amount
    FROM pay AS p
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN flc AS fc
        ON fc.l01 = i.n02
    JOIN cat AS ca
        ON ca.g01 = fc.l02
    GROUP BY
        p.p02,
        DATE(p.p06),
        ca.g01,
        ca.g02
),
category_day_ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, payment_day
            ORDER BY category_payment_count DESC, category_payment_amount DESC, category_id
        ) AS rn
    FROM category_day_counts
),
scored AS (
    SELECT
        hs.customer_id,
        hs.customer_name,
        hs.customer_country,
        hs.customer_city,
        hs.customer_home_store_id,
        hs.payment_day,
        hs.payment_count,
        ROUND(hs.payment_amount, 2) AS payment_amount,
        hs.history_days,
        hs.history_payment_count,
        ROUND(hs.avg_payment_amount_30d, 2) AS avg_payment_amount_30d,
        ROUND(hs.stddev_payment_amount_30d, 4) AS stddev_payment_amount_30d,
        ROUND(hs.avg_payment_count_30d, 2) AS avg_payment_count_30d,
        ROUND(hs.stddev_payment_count_30d, 4) AS stddev_payment_count_30d,
        hs.off_home_staff_payment_count,
        ROUND(hs.off_home_staff_payment_share, 4) AS off_home_staff_payment_share,
        sd.staff_id AS most_frequent_staff_id,
        sd.staff_name AS most_frequent_staff_name,
        sd.staff_payment_count AS most_frequent_staff_payment_count,
        cd.category_id AS main_category_id,
        cd.category_name AS main_category_name,
        cd.category_payment_count AS main_category_payment_count,
        CASE
            WHEN hs.stddev_payment_amount_30d > 0 THEN
                (hs.payment_amount - hs.avg_payment_amount_30d) / hs.stddev_payment_amount_30d
            WHEN hs.payment_amount > hs.avg_payment_amount_30d THEN 10.0
            ELSE 0.0
        END AS amount_z_score,
        CASE
            WHEN hs.stddev_payment_count_30d > 0 THEN
                (hs.payment_count - hs.avg_payment_count_30d) / hs.stddev_payment_count_30d
            WHEN hs.payment_count > hs.avg_payment_count_30d THEN 10.0
            ELSE 0.0
        END AS count_z_score
    FROM history_stats AS hs
    LEFT JOIN staff_day_ranked AS sd
        ON sd.customer_id = hs.customer_id
       AND sd.payment_day = hs.payment_day
       AND sd.rn = 1
    LEFT JOIN category_day_ranked AS cd
        ON cd.customer_id = hs.customer_id
       AND cd.payment_day = hs.payment_day
       AND cd.rn = 1
    WHERE
        hs.history_days >= 3
        AND hs.history_payment_count >= 5
        AND (
            (
                hs.stddev_payment_amount_30d > 0
                AND hs.payment_amount > hs.avg_payment_amount_30d + 3 * hs.stddev_payment_amount_30d
            )
            OR (
                hs.stddev_payment_amount_30d = 0
                AND hs.payment_amount > hs.avg_payment_amount_30d
            )
            OR (
                hs.stddev_payment_count_30d > 0
                AND hs.payment_count > hs.avg_payment_count_30d + 3 * hs.stddev_payment_count_30d
            )
            OR (
                hs.payment_count >= CASE
                    WHEN 2 * hs.avg_payment_count_30d > 3 THEN 2 * hs.avg_payment_count_30d
                    ELSE 3
                END
            )
        )
),
risk AS (
    SELECT
        *,
        ROUND(
            CASE WHEN amount_z_score > 0 THEN amount_z_score ELSE 0 END * 40
            + CASE WHEN count_z_score > 0 THEN count_z_score ELSE 0 END * 30
            + off_home_staff_payment_share * 20
            + CASE WHEN payment_count >= 5 THEN 10 ELSE 0 END,
            2
        ) AS risk_score
    FROM scored
)
SELECT
    RANK() OVER (ORDER BY risk_score DESC, payment_amount DESC, payment_count DESC) AS risk_rank,
    customer_id,
    customer_name,
    customer_country,
    customer_city,
    customer_home_store_id,
    payment_day,
    payment_count,
    payment_amount,
    history_days,
    history_payment_count,
    avg_payment_amount_30d,
    stddev_payment_amount_30d,
    ROUND(amount_z_score, 4) AS amount_z_score,
    avg_payment_count_30d,
    stddev_payment_count_30d,
    ROUND(count_z_score, 4) AS count_z_score,
    off_home_staff_payment_count,
    off_home_staff_payment_share,
    most_frequent_staff_id,
    most_frequent_staff_name,
    most_frequent_staff_payment_count,
    main_category_id,
    main_category_name,
    main_category_payment_count,
    risk_score
FROM risk
ORDER BY
    risk_score DESC,
    payment_amount DESC,
    payment_count DESC,
    customer_id,
    payment_day;