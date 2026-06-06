WITH
daily_customer AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s
      ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
customer_history AS (
    SELECT
        dc.*,
        AVG(dc.day_amount) OVER (
            PARTITION BY dc.customer_id
            ORDER BY dc.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_30d_amount,
        AVG(dc.payment_count) OVER (
            PARTITION BY dc.customer_id
            ORDER BY dc.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_30d_count
    FROM daily_customer AS dc
),
customer_geo AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        adr.e05 AS city_id,
        cty.d02 AS city_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM cus
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
daily_country_stats AS (
    SELECT
        ch.*,
        cg.customer_name,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        RANK() OVER (
            PARTITION BY cg.country_id, ch.payment_day
            ORDER BY ch.day_amount DESC
        ) AS country_day_rank,
        COUNT(*) OVER (
            PARTITION BY cg.country_id, ch.payment_day
        ) AS country_day_customer_count
    FROM customer_history AS ch
    JOIN customer_geo AS cg
      ON cg.customer_id = ch.customer_id
),
rental_counts AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        COUNT(DISTINCT r.q01) AS linked_rental_count
    FROM pay AS p
    JOIN ren AS r
      ON r.q01 = p.p04
    GROUP BY
        p.p02,
        date(p.p06)
)
SELECT
    dcs.customer_id,
    dcs.customer_name,
    dcs.city_name,
    dcs.country_name,
    dcs.payment_day,
    ROUND(dcs.day_amount, 2) AS day_amount,
    dcs.payment_count,
    ROUND(dcs.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
    ROUND(dcs.avg_prev_30d_count, 2) AS avg_prev_30d_count,
    dcs.staff_count,
    dcs.store_count,
    COALESCE(rc.linked_rental_count, 0) AS linked_rental_count,
    dcs.country_day_rank,
    CASE
        WHEN dcs.staff_count > 1 OR dcs.store_count > 1 THEN 1
        ELSE 0
    END AS multi_staff_or_store_flag
FROM daily_country_stats AS dcs
LEFT JOIN rental_counts AS rc
  ON rc.customer_id = dcs.customer_id
 AND rc.payment_day = dcs.payment_day
WHERE dcs.avg_prev_30d_amount IS NOT NULL
  AND dcs.avg_prev_30d_count IS NOT NULL
  AND dcs.day_amount >= 3.0 * dcs.avg_prev_30d_amount
  AND dcs.payment_count >= 3.0 * dcs.avg_prev_30d_count
  AND dcs.country_day_rank <= CAST((dcs.country_day_customer_count + 19) / 20 AS INTEGER)
ORDER BY
    dcs.country_name,
    dcs.payment_day,
    dcs.country_day_rank,
    dcs.day_amount DESC;