WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS monthly_amount
    FROM pay AS p
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        ct.d01 AS city_id,
        ct.d02 AS city_name,
        c.h02 AS store_id,
        sto.j01 AS store_dummy_id
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    JOIN sto
        ON sto.j01 = c.h02
),
monthly_with_history AS (
    SELECT
        mp.customer_id,
        mp.month_start,
        mp.payment_count,
        mp.monthly_amount,
        AVG(mp.monthly_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_avg_prev_amount,
        MEDIAN(mp.payment_count) OVER (
            PARTITION BY cg.country_id, mp.month_start
        ) AS country_median_payment_count
    FROM monthly_payments AS mp
    JOIN customer_geo AS cg
        ON cg.customer_id = mp.customer_id
),
selected_months AS (
    SELECT
        mwh.*
    FROM monthly_with_history AS mwh
    WHERE mwh.personal_avg_prev_amount IS NOT NULL
      AND mwh.monthly_amount > 3.0 * mwh.personal_avg_prev_amount
      AND mwh.payment_count > mwh.country_median_payment_count
),
rental_facts AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.p01 AS payment_id,
        p.p05 AS payment_amount,
        p.p04 AS rental_id,
        r.q01 AS rental_pk,
        i.n02 AS film_id,
        fc.l02 AS category_id,
        cat.g02 AS category_name,
        p.p04 AS rental_id_fk
    FROM pay AS p
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN flc AS fc
        ON fc.l01 = i.n02
    JOIN cat
        ON cat.g01 = fc.l02
),
category_payments AS (
    SELECT
        rf.customer_id,
        rf.month_start,
        SUM(rf.payment_amount) AS total_payment_amount,
        MAX(rf.payment_amount) AS max_single_payment,
        SUM(CASE
              WHEN rf.category_name IN ('Action', 'New') THEN 1.0 * rf.payment_amount
              ELSE 0.0
            END) AS action_new_payment_amount
    FROM rental_facts AS rf
    GROUP BY
        rf.customer_id,
        rf.month_start
),
ranked_customers AS (
    SELECT
        sm.customer_id,
        sm.month_start,
        RANK() OVER (
            PARTITION BY cg.city_id, cg.city_name, sm.month_start
            ORDER BY sm.monthly_amount DESC
        ) AS city_customer_rank
    FROM selected_months AS sm
    JOIN customer_geo AS cg
        ON cg.customer_id = sm.customer_id
),
final_agg AS (
    SELECT
        sm.customer_id,
        cg.country_name,
        cg.city_name,
        cg.store_id,
        sm.month_start,
        sm.payment_count,
        sm.monthly_amount,
        cp.max_single_payment,
        CASE
            WHEN cp.total_payment_amount = 0 THEN 0.0
            ELSE cp.action_new_payment_amount / cp.total_payment_amount
        END AS action_new_payment_share_amount
    FROM selected_months sm
    JOIN customer_geo cg
        ON cg.customer_id = sm.customer_id
    LEFT JOIN category_payments cp
        ON cp.customer_id = sm.customer_id
       AND cp.month_start = sm.month_start
)
SELECT
    fa.customer_id AS h01,
    fa.country_name,
    fa.city_name,
    fa.store_id AS j01,
    strftime('%Y-%m', fa.month_start) AS month,
    fa.payment_count,
    ROUND(fa.monthly_amount, 2) AS total_payment_amount,
    ROUND(fa.max_single_payment, 2) AS max_single_payment,
    ROUND(fa.action_new_payment_share_amount, 4) AS action_new_payment_share,
    rc.city_customer_rank AS city_customer_rank
FROM final_agg fa
JOIN ranked_customers rc
  ON rc.customer_id = fa.customer_id
 AND rc.month_start = fa.month_start
ORDER BY
    fa.country_name,
    fa.city_name,
    fa.month_start,
    fa.monthly_amount DESC,
    fa.customer_id;