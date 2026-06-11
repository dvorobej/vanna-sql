WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        date(p.p06) AS payment_day
    FROM pay p
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        c.h02 AS home_store_id
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
daily_agg AS (
    SELECT
        pb.customer_id,
        pb.payment_day,
        COUNT(*) AS payment_count,
        SUM(pb.payment_amount) AS daily_sum,
        SUM(CASE WHEN pb.staff_id IS NOT NULL AND st.o07 <> cg.home_store_id THEN 1 ELSE 0 END) * 1.0
            / COUNT(*) AS share_off_home_staff_payments,
        COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
        MAX(pb.staff_id) AS any_staff_id
    FROM payment_base pb
    JOIN customer_geo cg ON cg.customer_id = pb.customer_id
    LEFT JOIN stf st ON st.o01 = pb.staff_id
    GROUP BY
        pb.customer_id,
        pb.payment_day
),
daily_with_stats AS (
    SELECT
        da.*,
        /* rolling sum stats over previous 30 days (exclude current day) */
        (
            SELECT AVG(d2.daily_sum)
            FROM daily_agg d2
            WHERE d2.customer_id = da.customer_id
              AND d2.payment_day >= date(da.payment_day, '-30 days')
              AND d2.payment_day <  date(da.payment_day, '+0 days')
        ) AS rolling_avg_30d_sum,
        (
            SELECT
                CASE
                    WHEN COUNT(*) <= 1 THEN NULL
                    ELSE
                        sqrt(
                            AVG(d2.daily_sum * d2.daily_sum) - (AVG(d2.daily_sum) * AVG(d2.daily_sum))
                        )
                END
            FROM daily_agg d2
            WHERE d2.customer_id = da.customer_id
              AND d2.payment_day >= date(da.payment_day, '-30 days')
              AND d2.payment_day <  date(da.payment_day, '+0 days')
        ) AS rolling_stddev_30d_sum,
        (
            SELECT AVG(d2.payment_count * 1.0)
            FROM daily_agg d2
            WHERE d2.customer_id = da.customer_id
              AND d2.payment_day >= date(da.payment_day, '-30 days')
              AND d2.payment_day <  date(da.payment_day, '+0 days')
        ) AS rolling_avg_30d_count,
        (
            SELECT
                CASE
                    WHEN COUNT(*) <= 1 THEN NULL
                    ELSE
                        sqrt(
                            AVG(d2.payment_count * d2.payment_count * 1.0) - (AVG(d2.payment_count * 1.0) * AVG(d2.payment_count * 1.0))
                        )
                END
            FROM daily_agg d2
            WHERE d2.customer_id = da.customer_id
              AND d2.payment_day >= date(da.payment_day, '-30 days')
              AND d2.payment_day <  date(da.payment_day, '+0 days')
        ) AS rolling_stddev_30d_count
    FROM daily_agg da
),
qualified AS (
    SELECT
        dws.*,
        cg.country_name,
        cg.city_name,
        cg.home_store_id
    FROM daily_with_stats dws
    JOIN customer_geo cg ON cg.customer_id = dws.customer_id
    WHERE dws.rolling_avg_30d_sum IS NOT NULL
      AND dws.rolling_stddev_30d_sum IS NOT NULL
      AND dws.rolling_avg_30d_count IS NOT NULL
      AND dws.rolling_stddev_30d_count IS NOT NULL
),
flags AS (
    SELECT
        q.*,
        CASE
            WHEN q.rolling_stddev_30d_sum > 0 AND q.daily_sum > q.rolling_avg_30d_sum + 3.0 * q.rolling_stddev_30d_sum
            THEN 1 ELSE 0
        END AS flag_sum_spike,
        CASE
            WHEN q.rolling_stddev_30d_count > 0 AND q.payment_count > q.rolling_avg_30d_count + 3.0 * q.rolling_stddev_30d_count
            THEN 1 ELSE 0
        END AS flag_count_spike,
        (CASE
            WHEN q.rolling_stddev_30d_sum > 0 AND q.daily_sum > q.rolling_avg_30d_sum + 3.0 * q.rolling_stddev_30d_sum THEN 2 ELSE 0
         END
         +
         CASE
            WHEN q.rolling_stddev_30d_count > 0 AND q.payment_count > q.rolling_avg_30d_count + 3.0 * q.rolling_stddev_30d_count THEN 1 ELSE 0
         END) AS risk_score
    FROM qualified q
),
top_staff_day AS (
    SELECT
        pb.customer_id,
        pb.payment_day,
        pb.staff_id,
        COUNT(*) AS staff_payment_count
    FROM payment_base pb
    GROUP BY pb.customer_id, pb.payment_day, pb.staff_id
),
top_staff_ranked AS (
    SELECT
        tsd.*,
        RANK() OVER (
            PARTITION BY tsd.customer_id, tsd.payment_day
            ORDER BY tsd.staff_payment_count DESC, tsd.staff_id
        ) AS rn
    FROM top_staff_day tsd
),
top_category_day AS (
    SELECT
        pb.customer_id,
        date(p.p06) AS payment_day,
        ca.g02 AS category_name,
        COUNT(*) AS cat_payment_count
    FROM payment_base pb
    JOIN pay p ON p.p01 = pb.payment_id
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flc fc ON fc.l01 = i.n02
    JOIN cat ca ON ca.g01 = fc.l02
    GROUP BY pb.customer_id, date(p.p06), ca.g02
),
top_category_ranked AS (
    SELECT
        tcd.*,
        RANK() OVER (
            PARTITION BY tcd.customer_id, tcd.payment_day
            ORDER BY tcd.cat_payment_count DESC, tcd.category_name
        ) AS rn
    FROM top_category_day tcd
)
SELECT
    f.customer_id,
    f.payment_day,
    f.payment_count,
    ROUND(f.daily_sum, 2) AS daily_payment_sum,
    ROUND(f.rolling_avg_30d_sum, 2) AS rolling_avg_30d_sum,
    ROUND(f.rolling_stddev_30d_sum, 2) AS rolling_stddev_30d_sum,
    f.flag_sum_spike,
    f.flag_count_spike,
    f.risk_score,
    cg.country_name,
    cg.city_name,
    ROUND(f.share_off_home_staff_payments, 4) AS share_off_home_staff_payments,
    ts.staff_id AS top_staff_id,
    s.o02 || ' ' || s.o03 AS top_staff_name,
    tc.category_name AS top_rented_category,
    RANK() OVER (
        ORDER BY f.risk_score DESC, f.daily_sum DESC, f.payment_count DESC
    ) AS overall_risk_rank_in_result
FROM flags f
JOIN customer_geo cg ON cg.customer_id = f.customer_id
LEFT JOIN top_staff_ranked ts
    ON ts.customer_id = f.customer_id
   AND ts.payment_day = f.payment_day
   AND ts.rn = 1
LEFT JOIN stf s ON s.o01 = ts.staff_id
LEFT JOIN top_category_ranked tc
    ON tc.customer_id = f.customer_id
   AND tc.payment_day = f.payment_day
   AND tc.rn = 1
WHERE f.flag_sum_spike = 1 OR f.flag_count_spike = 1
ORDER BY
    f.risk_score DESC,
    f.daily_sum DESC,
    f.payment_count DESC,
    f.customer_id,
    f.payment_day;