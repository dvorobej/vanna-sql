WITH payments_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p06 AS payment_ts,
    date(p.p06, 'start of month') AS month_start,

    s.o07 AS staff_store_id,
    stg.c01 AS staff_country_id,
    stg.c02 AS staff_country_name,
    ctg.d02 AS staff_city_name,

    c.h02 AS home_store_id,
    ch.c01 AS customer_country_id,
    ch.c02 AS customer_country_name,
    ct.c02 AS customer_city_name
  FROM pay p
  JOIN ren r
    ON r.q01 = p.p04
  JOIN stf s
    ON s.o01 = p.p03
  JOIN inv i
    ON i.n01 = r.q03
  JOIN sto st
    ON st.j01 = i.n03
  JOIN adr as_ad
    ON as_ad.e01 = st.j01 /* fallback join target;