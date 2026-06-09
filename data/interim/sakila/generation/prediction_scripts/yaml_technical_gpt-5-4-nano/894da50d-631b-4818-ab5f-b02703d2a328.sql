SELECT DISTINCT
    qm.customer_id,
    date(p.p06, 'start of month') AS month_start,
    ca.g01 AS category_id,
    ca.g02 AS category_name
  FROM qualified_months qm
  JOIN cus c
    ON c.h01 = qm.customer_id
  JOIN pay p
    ON p.p02 = c.h01
  JOIN ren r
    ON r.q01 = p.p04
  JOIN inv i
    ON i.n01 = r.q03
  JOIN flc
    ON flc.l01 = i.n02
  JOIN cat ca
    ON ca.g01 = flc.l02
),
categories_concat AS (
  SELECT
    fcb.customer_id,
    fcb.month_start,
    group_concat(DISTINCT fcb.category_name, ', ') AS categories_g02
  FROM film_categories_by_rental_month fcb
  GROUP BY
    fcb.customer_id,
    fcb.month_start
)
SELECT
  ma.customer_id AS h01,
  ma.month_start AS month,
  ma.month_total_amount,
  ma.payment_count,
  ROUND(ma.foreign_staff_store_payment_share, 4) AS foreign_staff_store_payment_share,
  ma.max_single_payment,
  ma.month_amount_rank_within_customer,
  cc.categories_g02 AS categories_g02
FROM month_agg ma
LEFT JOIN categories_concat cc
  ON cc.customer_id = ma.customer_id
 AND cc.month_start = ma.month_start
ORDER BY
  ma.customer_id,
  ma.month_start;