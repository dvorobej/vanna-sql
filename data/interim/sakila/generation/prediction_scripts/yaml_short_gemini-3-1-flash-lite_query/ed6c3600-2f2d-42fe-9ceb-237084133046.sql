WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        COUNT(DISTINCT CASE WHEN s.o07 <> c.h02 THEN p.p03 END) * 1.0 / NULLIF(COUNT(*), 0) AS off_home_store_share
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
rolling_stats AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        (SELECT STDEV(d.daily_sum) FROM daily_stats d WHERE d.customer_id = ds.customer_id AND d.payment_date >= date(ds.payment_date, '-30 days') AND d.payment_date < ds.payment_date) AS stddev_sum_30d,
        AVG(ds.daily_count) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_count_30d
    FROM daily_stats ds
),
suspicious_days AS (
    SELECT
        rs.*,
        (rs.daily_sum - rs.avg_sum_30d) / NULLIF(rs.stddev_sum_30d, 0) AS z_score_sum
    FROM rolling_stats rs
    WHERE rs.avg_sum_30d IS NOT NULL
      AND (rs.daily_sum > rs.avg_sum_30d + 3 * rs.stddev_sum_30d OR rs.daily_count > rs.avg_count_30d * 3)
),
top_staff AS (
    SELECT customer_id, payment_date, staff_id
    FROM (
        SELECT p.p02 AS customer_id, date(p.p06) AS payment_date, p.p03 AS staff_id, COUNT(*) as cnt,
               ROW_NUMBER() OVER (PARTITION BY p.p02, date(p.p06) ORDER BY COUNT(*) DESC) as rn
        FROM pay p GROUP BY 1, 2, 3
    ) WHERE rn = 1
),
top_category AS (
    SELECT customer_id, payment_date, category_name
    FROM (
        SELECT p.p02 AS customer_id, date(p.p06) AS payment_date, cat.g02 AS category_name, COUNT(*) as cnt,
               ROW_NUMBER() OVER (PARTITION BY p.p02, date(p.p06) ORDER BY COUNT(*) DESC) as rn
        FROM pay p
        JOIN ren r ON r.q01 = p.p04
        JOIN inv i ON i.n01 = r.q03
        JOIN flc f ON f.l01 = i.n02
        JOIN cat ON cat.g01 = f.l02
        GROUP BY 1, 2, 3
    ) WHERE rn = 1
)
SELECT
    sd.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.payment_date,
    sd.daily_sum,
    sd.daily_count,
    sd.off_home_store_share,
    ts.staff_id AS most_frequent_staff,
    tc.category_name AS main_category,
    RANK() OVER (ORDER BY sd.z_score_sum DESC) AS risk_rank
FROM suspicious_days sd
JOIN cus c ON c.h01 = sd.customer_id
JOIN adr a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
JOIN top_staff ts ON ts.customer_id = sd.customer_id AND ts.payment_date = sd.payment_date
JOIN top_category tc ON tc.customer_id = sd.customer_id AND tc.payment_date = sd.payment_date
ORDER BY risk_rank;