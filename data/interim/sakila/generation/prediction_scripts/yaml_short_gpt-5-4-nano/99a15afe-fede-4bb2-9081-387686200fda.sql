SELECT COUNT(DISTINCT p.p03)
      FROM pay p
      WHERE p.p02 IN (
        SELECT c1.h01
        FROM cus c1
        WHERE c1.h02 = j.store_id
      )
        AND date(p.p06, 'start of month') = (
          SELECT MIN(date(pp.p06, 'start of month'))
          FROM pay pp
          WHERE pp.p02 IN (
            SELECT c1.h01
            FROM cus c1
            WHERE c1.h02 = j.store_id
          )
            AND strftime('%Y-%m', pp.p06) = j.month
          )
    ) AS staff_count_placeholder
  FROM joined j
)
SELECT
  country_name AS country,
  city_name AS city,
  store_id AS store,
  month,
  ROUND(month_payment_amount, 2) AS month_payment_amount,
  payment_count,
  (
    SELECT COUNT(DISTINCT p.p03)
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    WHERE c.h02 = ranked.store_id
      AND c.h01 IN (
        SELECT c2.h01
        FROM cus c2
        WHERE c2.h02 = ranked.store_id
      )
      AND date(p.p06, 'start of month') = date(substr(ranked.month || '-01', 1, 10))
  ) AS staff_count,
  ROUND(late_return_share, 4) AS late_return_share,
  payment_amount_rank
FROM ranked
ORDER BY
  month,
  country,
  city,
  store,
  payment_amount_rank;