WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS month_amount,
        MAX(CAST(p.p05 AS REAL)) AS max_payment
    FROM pay AS p
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
monthly_with_history AS (
    SELECT
        mp.*,
        AVG(mp.month_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_hist_avg_amount,
        COUNT(*) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS hist_months_count
    FROM monthly_payments AS mp
),
country_month_payment_counts AS (
    SELECT
        customer_id,
        month_start,
        payment_count,
        AVG(payment_count) OVER (
            PARTITION BY
                customer_id
        ) AS dummy
    FROM monthly_with_history
),
country_month_median_payments AS (
    SELECT
        mh.country_id,
        mh.month_start,
        mh.payment_count
    FROM (
        SELECT
            c.h01 AS customer_id,
            ctry.c01 AS country_id,
            mwh.month_start,
            mwh.payment_count,
            ROW_NUMBER() OVER (
                PARTITION BY ctry.c01, mwh.month_start
                ORDER BY mwh.payment_count
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY ctry.c01, mwh.month_start
            ) AS cnt
        FROM monthly_with_history AS mwh
        JOIN cus AS c
            ON c.h01 = mwh.customer_id
        JOIN adr AS a
            ON a.e01 = c.h06
        JOIN cty AS ct
            ON ct.d01 = a.e05
        JOIN cnt AS ctry
            ON ctry.c01 = ct.d03
        WHERE mwh.hist_months_count > 0
    ) AS mh
    WHERE mh.rn IN (CAST((mh.cnt + 1) / 2 AS INTEGER), CAST((mh.cnt + 2) / 2 AS INTEGER))
),
country_month_median_value AS (
    SELECT
        country_id,
        month_start,
        AVG(payment_count) AS median_payment_count
    FROM country_month_median_payments
    GROUP BY country_id, month_start
),
suspicious_months AS (
    SELECT
        mwh.customer_id,
        ctry.c01 AS country_id,
        ctry.c02 AS country_name,
        city.d02 AS city_name,
        c.h02 AS store_id,
        mwh.month_start,
        mwh.payment_count,
        mwh.month_amount,
        mwh.max_payment,
        mwh.personal_hist_avg_amount,
        cm_med.median_payment_count,
        (mwh.month_amount > 3.0 * mwh.personal_hist_avg_amount) AS is_amount_spike,
        (mwh.payment_count > cm_med.median_payment_count) AS is_count_above_median
    FROM monthly_with_history AS mwh
    JOIN cus AS c
        ON c.h01 = mwh.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS ctry
        ON ctry.c01 = city.d03
    JOIN country_month_median_value AS cm_med
        ON cm_med.country_id = ctry.c01
       AND cm_med.month_start = mwh.month_start
    WHERE mwh.hist_months_count > 0
),
suspicious_filtered AS (
    SELECT *
    FROM suspicious_months
    WHERE is_amount_spike = 1
      AND is_count_above_median = 1
),
store_customer_payments_by_category AS (
    SELECT
        sf.customer_id,
        sf.month_start,
        SUM(CAST(p.p05 AS REAL)) AS suspicious_month_amount,
        SUM(
            CASE
                WHEN cat.g02 IN ('Action','New') THEN CAST(p.p05 AS REAL)
                ELSE 0
            END
        ) AS action_new_amount
    FROM suspicious_filtered AS sf
    JOIN pay AS p
        ON p.p02 = sf.customer_id
       AND date(p.p06, 'start of month') = sf.month_start
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN flc AS fc
        ON fc.l01 = i.n02
    JOIN cat AS cat
        ON cat.g01 = fc.l02
    GROUP BY
        sf.customer_id,
        sf.month_start
),
customer_country_month_ranks AS (
    SELECT
        sf.customer_id,
        sf.month_start,
        DENSE_RANK() OVER (
            PARTITION BY sf.country_id, sf.month_start
            ORDER BY sf.month_amount DESC
        ) AS country_customer_month_rank
    FROM suspicious_filtered AS sf
)
SELECT
    sf.country_name AS country,
    sf.city_name AS city,
    sf.store_id AS store_id,
    sf.customer_id,
    sf.month_start AS month,
    sf.payment_count AS payment_count,
    ROUND(sf.month_amount, 2) AS total_amount,
    ROUND(sf.max_payment, 2) AS max_payment,
    ROUND(
        1.0 * sca.action_new_amount / NULLIF(sca.suspicious_month_amount, 0),
        4
    ) AS action_new_share,
    rnk.country_customer_month_rank AS suspicious_rank_in_country
FROM suspicious_filtered AS sf
JOIN store_customer_payments_by_category AS sca
    ON sca.customer_id = sf.customer_id
   AND sca.month_start = sf.month_start
JOIN customer_country_month_ranks AS rnk
    ON rnk.customer_id = sf.customer_id
   AND rnk.month_start = sf.month_start
ORDER BY
    sf.month_start,
    sf.country_name,
    sf.month_amount DESC,
    sf.customer_id;