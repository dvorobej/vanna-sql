WITH
payment_ops AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        CAST(p.p05 AS REAL) AS amount,
        DATE(p.p06) AS payment_date,
        inv.n02 AS film_id
    FROM pay AS p
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv
        ON inv.n01 = r.q03
),
customer_daily AS (
    SELECT
        customer_id,
        payment_date,
        SUM(amount) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT film_id) AS unique_rented_films
    FROM payment_ops
    GROUP BY
        customer_id,
        payment_date
),
customer_daily_scored AS (
    SELECT
        cd.*,
        AVG(day_amount) OVER (
            PARTITION BY customer_id
        ) AS avg_daily_amount,
        RANK() OVER (
            PARTITION BY customer_id
            ORDER BY day_amount DESC
        ) AS day_amount_rank
    FROM customer_daily AS cd
),
staff_daily_totals AS (
    SELECT
        customer_id,
        payment_date,
        staff_id,
        SUM(amount) AS staff_day_amount,
        COUNT(*) AS staff_payment_count
    FROM payment_ops
    GROUP BY
        customer_id,
        payment_date,
        staff_id
),
staff_daily_ranked AS (
    SELECT
        sdt.*,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, payment_date
            ORDER BY staff_day_amount DESC, staff_payment_count DESC, staff_id
        ) AS rn
    FROM staff_daily_totals AS sdt
),
dominant_staff AS (
    SELECT
        sdr.customer_id,
        sdr.payment_date,
        sdr.staff_id,
        sdr.staff_day_amount,
        sdr.staff_payment_count
    FROM staff_daily_ranked AS sdr
    JOIN customer_daily AS cd
        ON cd.customer_id = sdr.customer_id
       AND cd.payment_date = sdr.payment_date
    WHERE sdr.rn = 1
      AND sdr.staff_day_amount >= cd.day_amount * 0.70
),
category_daily_totals AS (
    SELECT
        po.customer_id,
        po.payment_date,
        cat.g01 AS category_id,
        cat.g02 AS category_name,
        COUNT(*) AS category_count,
        SUM(po.amount) AS category_amount
    FROM payment_ops AS po
    JOIN flc
        ON flc.l01 = po.film_id
    JOIN cat
        ON cat.g01 = flc.l02
    GROUP BY
        po.customer_id,
        po.payment_date,
        cat.g01,
        cat.g02
),
category_daily_ranked AS (
    SELECT
        cdt.*,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, payment_date
            ORDER BY category_count DESC, category_amount DESC, category_name
        ) AS rn
    FROM category_daily_totals AS cdt
),
top_category AS (
    SELECT
        customer_id,
        payment_date,
        category_name,
        category_count
    FROM category_daily_ranked
    WHERE rn = 1
)
SELECT
    cus.h01 AS customer_id,
    cus.h03 || ' ' || cus.h04 AS customer_name,
    cus.h05 AS email,
    cty.d02 AS city,
    cnt.c02 AS country,
    cds.payment_date AS payment_date,
    ROUND(cds.day_amount, 2) AS day_amount,
    cds.payment_count AS payment_count,
    cds.unique_rented_films AS unique_rented_films,
    stf.o01 AS dominant_staff_id,
    stf.o02 || ' ' || stf.o03 AS dominant_staff_name,
    sto.j01 AS store_id,
    tc.category_name AS top_category,
    cds.day_amount_rank AS customer_day_amount_rank
FROM customer_daily_scored AS cds
JOIN dominant_staff AS ds
    ON ds.customer_id = cds.customer_id
   AND ds.payment_date = cds.payment_date
JOIN cus
    ON cus.h01 = cds.customer_id
JOIN adr
    ON adr.e01 = cus.h06
JOIN cty
    ON cty.d01 = adr.e05
JOIN cnt
    ON cnt.c01 = cty.d03
JOIN stf
    ON stf.o01 = ds.staff_id
JOIN sto
    ON sto.j01 = stf.o07
LEFT JOIN top_category AS tc
    ON tc.customer_id = cds.customer_id
   AND tc.payment_date = cds.payment_date
WHERE cds.payment_count >= 3
  AND cds.day_amount > cds.avg_daily_amount * 3
ORDER BY
    cds.day_amount DESC,
    cus.h01,
    cds.payment_date;