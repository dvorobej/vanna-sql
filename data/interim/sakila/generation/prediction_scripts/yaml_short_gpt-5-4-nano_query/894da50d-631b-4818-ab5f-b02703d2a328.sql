WITH payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,

    -- customer geo
    c.h02 AS customer_home_store_id,
    ct_c.d02 AS customer_city,
    ct_c.d03 AS customer_country_id,

    -- staff store geo
    s.o02 AS staff_store_id,
    ct_s.d01 AS staff_city_id,
    ct_s.d02 AS staff_city,
    ct_s.d03 AS staff_country_id,

    -- film category (for later aggregation)
    fc.l02 AS category_id
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a_c
    ON a_c.e01 = c.h06
  JOIN cty AS ct_c
    ON ct_c.d01 = a_c.e05

  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN adr AS a_s
    ON a_s.e01 = s.o06
  JOIN cty AS ct_s
    ON ct_s.d01 = a_s.e05

  JOIN inv AS i
    ON i.n01 = r.q03

  JOIN flm AS f
    ON f.i01 = i.n02
  JOIN flc AS fc
    ON fc.l01 = f.i01
  WHERE p.p06 IS NOT NULL
),
monthly_base AS (
  SELECT
    customer_id,
    month_start,

    COUNT(*) AS payment_count,
    SUM(payment_amount) AS month_total_amount,
    MAX(payment_amount) AS max_payment,

    -- “foreign store” share:
    -- customer city/country differs from store issuing the rental copy
    SUM(
      CASE
        WHEN customer_city_id IS NULL OR staff_country_id IS NULL THEN 0
        WHEN staff_store_id <> customer_home_store_id THEN 1
        ELSE 0
      END
    ) AS foreign_store_payment_count,

    COUNT(DISTINCT staff_id) AS distinct_staff_count
  FROM (
    SELECT
      pe.*,
      -- customer_city_id not explicitly selected above;