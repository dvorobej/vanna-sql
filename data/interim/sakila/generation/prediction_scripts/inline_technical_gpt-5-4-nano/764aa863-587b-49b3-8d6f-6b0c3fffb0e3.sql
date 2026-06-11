WITH payment_base AS (
    SELECT
        cu.h01 AS customer_id,
        cu.h02 AS customer_home_store_id,
        cu.h06 AS customer_address_id,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        ct.d01 AS city_id,
        ct.d02 AS city_name,
        date(p.p06, 'start of month') AS month_start,
        p.p01 AS payment_id,
        p.p03 AS staff_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        stj.j01 AS payment_store_id,
        flc.l02 AS category_id
    FROM pay AS p
    JOIN cus AS cu
        ON cu.h01 = p.p02
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS inv
        ON inv.n01 = r.q03
    JOIN flm AS fl
        ON fl.i01 = inv.n02
    JOIN flc
        ON flc.l01 = fl.i01
    JOIN sto AS stj
        ON stj.j01 = cu.h02
    JOIN adr AS ad
        ON ad.e01 = cu.h06
    JOIN cty AS ct
        ON ct.d01 = ad.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    -- магазин, через который прошла аренда (магазин инвентарной копии)
    JOIN sto AS inv_sto
        ON inv_sto.j01 = inv.n03
    -- признак "не в магазине регистрации клиента"
    CROSS JOIN (SELECT 1 AS dummy)
),
monthly_customer AS (
    SELECT
        customer_id,
        country_id,
        country_name,
        city_id,
        city_name,
        month_start,
        customer_home_store_id,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS month_payment_sum,
        MAX(payment_amount) AS max_payment,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        SUM(CASE WHEN payment_store_id <> customer_home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_store_share,
        COUNT(DISTINCT category_id) AS distinct_category_count
    FROM (
        SELECT
            pb.*,
            pb.payment_amount,
            inv_sto.j01 AS payment_store_id
        FROM payment_base AS pb
        JOIN ren AS r
            ON r.q01 = pb.payment_id  -- ошибка: p.p01 != ren.q01;