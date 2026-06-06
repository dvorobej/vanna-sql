WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    s.o02 || ' ' || s.o03 AS staff_name,
    s.o07 AS store_id,
    DATE(p.p06) AS payment_day,
    CAST(p.p05 AS REAL) AS amount,
    f.i01 AS film_id
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN flm AS f
    ON f.i01 = i.n02
),
daily_customer AS (
  SELECT
    customer_id,
    payment_day,
    COUNT(*) AS payment_count,
    SUM(amount) AS daily_amount,
    COUNT(DISTINCT film_id) AS unique_rented_films
  FROM payment_base
  GROUP BY
    customer_id,
    payment_day
),
daily_scored AS (
  SELECT
    d.*,
    AVG(d.daily_amount) OVER (
      PARTITION BY d.customer_id
    ) AS customer_avg_daily_amount,
    RANK() OVER (
      PARTITION BY d.customer_id
      ORDER BY d.daily_amount DESC
    ) AS customer_day_amount_rank
  FROM daily_customer AS d
),
staff_daily AS (
  SELECT
    customer_id,
    payment_day,
    staff_id,
    staff_name,
    store_id,
    COUNT(*) AS staff_payment_count,
    SUM(amount) AS staff_amount
  FROM payment_base
  GROUP BY
    customer_id,
    payment_day,
    staff_id,
    staff_name,
    store_id
),
dominant_staff AS (
  SELECT
    sd.*,
    ds.daily_amount,
    sd.staff_amount / NULLIF(ds.daily_amount, 0) AS staff_amount_share,
    ROW_NUMBER() OVER (
      PARTITION BY sd.customer_id, sd.payment_day
      ORDER BY sd.staff_amount DESC, sd.staff_payment_count DESC, sd.staff_id
    ) AS rn
  FROM staff_daily AS sd
  JOIN daily_scored AS ds
    ON ds.customer_id = sd.customer_id
   AND ds.payment_day = sd.payment_day
),
category_counts AS (
  SELECT
    pb.customer_id,
    pb.payment_day,
    cat.g02 AS category_name,
    COUNT(*) AS category_operation_count
  FROM payment_base AS pb
  JOIN flc AS fc
    ON fc.l01 = pb.film_id
  JOIN cat AS cat
    ON cat.g01 = fc.l02
  GROUP BY
    pb.customer_id,
    pb.payment_day,
    cat.g02
),
top_category AS (
  SELECT
    customer_id,
    payment_day,
    category_name,
    category_operation_count,
    ROW_NUMBER() OVER (
      PARTITION BY customer_id, payment_day
      ORDER BY category_operation_count DESC, category_name
    ) AS rn
  FROM category_counts
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  c.h05 AS email,
  city.d02 AS city,
  country.c02 AS country,
  ds.payment_day,
  ds.payment_count,
  ROUND(ds.daily_amount, 2) AS daily_amount,
  ROUND(ds.customer_avg_daily_amount, 2) AS customer_avg_daily_amount,
  ROUND(ds.daily_amount - ds.customer_avg_daily_amount, 2) AS deviation_from_avg,
  ds.unique_rented_films,
  dom.staff_id AS dominant_staff_id,
  dom.staff_name AS dominant_staff_name,
  dom.store_id AS dominant_store_id,
  ROUND(dom.staff_amount, 2) AS dominant_staff_amount,
  ROUND(dom.staff_amount_share, 4) AS dominant_staff_amount_share,
  tc.category_name AS most_frequent_category,
  ds.customer_day_amount_rank
FROM daily_scored AS ds
JOIN dominant_staff AS dom
  ON dom.customer_id = ds.customer_id
 AND dom.payment_day = ds.payment_day
 AND dom.rn = 1
JOIN cus AS c
  ON c.h01 = ds.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty AS city
  ON city.d01 = a.e05
JOIN cnt AS country
  ON country.c01 = city.d03
LEFT JOIN top_category AS tc
  ON tc.customer_id = ds.customer_id
 AND tc.payment_day = ds.payment_day
 AND tc.rn = 1
WHERE ds.payment_count >= 3
  AND ds.customer_avg_daily_amount > 0
  AND ds.daily_amount > ds.customer_avg_daily_amount * 3
  AND dom.staff_amount_share >= 0.70
ORDER BY
  ds.daily_amount DESC,
  ds.payment_day,
  c.h01;