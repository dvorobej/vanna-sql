WITH base_payments AS (
    SELECT
        p.p02 AS customer_id,
        p.p04 AS rental_id,
        p.p06 AS payment_ts,
        date(p.p06, 'start of month') AS month_start,
        p.p05 AS payment_amount,
        p.p03 AS staff_id,
        cu.h02 AS store_id,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        ct.d02 AS city_name
    FROM pay p
    JOIN cus cu
      ON cu.h01 = p.p02
    JOIN adr a
      ON a.e01 = cu.h06
    JOIN cty ct
      ON ct.d01 = a.e05
    JOIN cnt cn
      ON cn.c01 = ct.d03
),
category_actions_new AS (
    SELECT
        b.customer_id,
        b.month_start,
        b.country_id,
        b.country_name,
        b.city_name,
        b.store_id,
        cat.g02 AS category_name,
        COUNT(*) AS category_payment_count,
        SUM(b.payment_amount) AS category_payment_amount
    FROM base_payments b
    JOIN ren r
      ON r.q01 = b.rental_id
    JOIN inv i
      ON i.n01 = r.q03
    JOIN flc fc
      ON fc.l01 = i.n02
    JOIN cat
      ON cat.g01 = fc.l02
    WHERE cat.g02 IN ('Action', 'New')
    GROUP BY
        b.customer_id,
        b.month_start,
        b.country_id,
        b.country_name,
        b.city_name,
        b.store_id,
        cat.g02
),
monthly_customer_totals AS (
    SELECT
        b.customer_id,
        b.month_start,
        b.country_id,
        b.country_name,
        b.city_name,
        b.store_id,
        COUNT(*) AS payment_count,
        SUM(b.payment_amount) AS total_payment_amount,
        MAX(b.payment_amount) AS max_payment_amount
    FROM base_payments b
    GROUP BY
        b.customer_id,
        b.month_start,
        b.country_id,
        b.country_name,
        b.city_name,
        b.store_id
),
monthly_customer_categories AS (
    SELECT
        mct.*,
        COALESCE(SUM(CASE WHEN c.an.category_name = 'Action' THEN c.an.category_payment_amount END), 0) AS action_amount,
        COALESCE(SUM(CASE WHEN c.an.category_name = 'New' THEN c.an.category_payment_amount END), 0) AS new_amount,
        COALESCE(SUM(CASE WHEN c.an.category_name = 'Action' THEN c.an.category_payment_count END), 0) AS action_count,
        COALESCE(SUM(CASE WHEN c.an.category_name = 'New' THEN c.an.category_payment_count END), 0) AS new_count
    FROM monthly_customer_totals mct
    LEFT JOIN category_actions_new c.an
      ON c.an.customer_id = mct.customer_id
     AND c.an.month_start = mct.month_start
     AND c.an.country_id = mct.country_id
     AND c.an.city_name = mct.city_name
     AND c.an.store_id = mct.store_id
    GROUP BY
        mct.customer_id,
        mct.month_start,
        mct.country_id,
        mct.country_name,
        mct.city_name,
        mct.store_id,
        mct.payment_count,
        mct.total_payment_amount,
        mct.max_payment_amount
),
final_ranked AS (
    SELECT
        mcc.*,
        ROUND(mcc.action_amount / NULLIF(mcc.total_payment_amount, 0), 4) AS action_amount_share,
        ROUND(mcc.new_amount / NULLIF(mcc.total_payment_amount, 0), 4) AS new_amount_share,
        RANK() OVER (
            PARTITION BY mcc.country_id, mcc.month_start
            ORDER BY mcc.total_payment_amount DESC
        ) AS country_month_rank
    FROM monthly_customer_categories mcc
)
SELECT
    month_start AS month,
    customer_id,
    country_name,
    city_name,
    store_id,
    payment_count,
    ROUND(total_payment_amount, 2) AS total_payment_amount,
    ROUND(max_payment_amount, 2) AS max_payment_amount,
    action_count,
    ROUND(action_amount, 2) AS action_amount,
    ROUND(action_amount_share, 4) AS action_amount_share,
    new_count,
    ROUND(new_amount, 2) AS new_amount,
    ROUND(new_amount_share, 4) AS new_amount_share,
    country_month_rank
FROM final_ranked
ORDER BY
    country_name,
    month_start,
    country_month_rank,
    total_payment_amount DESC,
    customer_id;