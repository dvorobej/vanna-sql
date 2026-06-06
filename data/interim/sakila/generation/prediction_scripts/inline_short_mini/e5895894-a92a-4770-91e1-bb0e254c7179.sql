WITH payment_details AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        c.h05 AS email,
        city.d02 AS city_name,
        country.c02 AS country_name,
        DATE(p.p06) AS payment_day,
        p.p01 AS payment_id,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        s.o02 || ' ' || s.o03 AS staff_name,
        s.o07 AS store_id,
        r.q01 AS rental_id,
        f.i01 AS film_id,
        f.i02 AS film_title,
        cat.g01 AS category_id,
        cat.g02 AS category_name
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS country
        ON country.c01 = city.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS inv
        ON inv.n01 = r.q03
    LEFT JOIN flm AS f
        ON f.i01 = inv.n02
    LEFT JOIN flc AS fc
        ON fc.l01 = f.i01
    LEFT JOIN cat AS cat
        ON cat.g01 = fc.l02
),
daily_agg AS (
    SELECT
        customer_id,
        first_name,
        last_name,
        email,
        city_name,
        country_name,
        payment_day,
        COUNT(*) AS payment_count,
        SUM(amount) AS daily_amount,
        COUNT(DISTINCT rental_id) AS unique_rentals,
        COUNT(DISTINCT staff_id) AS unique_staff,
        COUNT(DISTINCT store_id) AS unique_stores
    FROM payment_details
    GROUP BY
        customer_id,
        first_name,
        last_name,
        email,
        city_name,
        country_name,
        payment_day
),
daily_staff AS (
    SELECT
        customer_id,
        payment_day,
        staff_id,
        staff_name,
        SUM(amount) AS staff_amount
    FROM payment_details
    GROUP BY customer_id, payment_day, staff_id, staff_name
),
dominant_staff AS (
    SELECT
        customer_id,
        payment_day,
        staff_name AS dominant_staff_name,
        staff_amount AS dominant_staff_amount,
        SUM(staff_amount) OVER (PARTITION BY customer_id, payment_day) AS day_amount,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, payment_day
            ORDER BY staff_amount DESC, staff_name
        ) AS rn
    FROM daily_staff
),
dominant_store AS (
    SELECT
        customer_id,
        payment_day,
        store_id AS dominant_store_id,
        store_amount,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, payment_day
            ORDER BY store_amount DESC, store_id
        ) AS rn
    FROM (
        SELECT
            customer_id,
            payment_day,
            store_id,
            SUM(amount) AS store_amount
        FROM payment_details
        GROUP BY customer_id, payment_day, store_id
    )
),
dominant_category AS (
    SELECT
        customer_id,
        payment_day,
        category_name AS top_category_name,
        category_amount,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, payment_day
            ORDER BY category_amount DESC, category_name
        ) AS rn
    FROM (
        SELECT
            customer_id,
            payment_day,
            category_name,
            SUM(amount) AS category_amount
        FROM payment_details
        WHERE category_name IS NOT NULL
        GROUP BY customer_id, payment_day, category_name
    )
),
customer_baseline AS (
    SELECT
        da.*,
        AVG(daily_amount) OVER (
            PARTITION BY customer_id
            ORDER BY julianday(payment_day)
            RANGE BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_daily_amount_30d
    FROM daily_agg AS da
),
ranked_days AS (
    SELECT
        cb.*,
        RANK() OVER (
            PARTITION BY customer_id
            ORDER BY daily_amount DESC, payment_day
        ) AS day_amount_rank
    FROM customer_baseline AS cb
)
SELECT
    rd.customer_id,
    rd.first_name,
    rd.last_name,
    rd.email,
    rd.city_name,
    rd.country_name,
    rd.payment_day,
    ROUND(rd.daily_amount, 2) AS daily_amount,
    rd.payment_count,
    rd.unique_rentals,
    ROUND(rd.avg_daily_amount_30d, 2) AS avg_daily_amount_30d,
    ROUND(rd.daily_amount - rd.avg_daily_amount_30d, 2) AS deviation_from_avg,
    ds.dominant_staff_name,
    ds.dominant_staff_amount,
    dst.dominant_store_id,
    dc.top_category_name,
    rd.day_amount_rank
FROM ranked_days AS rd
JOIN dominant_staff AS ds
    ON ds.customer_id = rd.customer_id
   AND ds.payment_day = rd.payment_day
   AND ds.rn = 1
LEFT JOIN dominant_store AS dst
    ON dst.customer_id = rd.customer_id
   AND dst.payment_day = rd.payment_day
   AND dst.rn = 1
LEFT JOIN dominant_category AS dc
    ON dc.customer_id = rd.customer_id
   AND dc.payment_day = rd.payment_day
   AND dc.rn = 1
WHERE rd.payment_count >= 3
  AND rd.avg_daily_amount_30d IS NOT NULL
  AND rd.avg_daily_amount_30d > 0
  AND rd.daily_amount > rd.avg_daily_amount_30d * 3
  AND EXISTS (
      SELECT 1
      FROM daily_staff AS x
      WHERE x.customer_id = rd.customer_id
        AND x.payment_day = rd.payment_day
      GROUP BY x.customer_id, x.payment_day
      HAVING MAX(x.staff_amount) * 1.0 / SUM(x.staff_amount) >= 0.70
  )
ORDER BY
    rd.day_amount_rank,
    rd.daily_amount DESC,
    rd.customer_id,
    rd.payment_day;