SELECT qm.*
  FROM qualified_months AS qm
)
SELECT
  cmm.month_start AS month,
  cg.country_name AS country,
  cg.city_name AS city,
  cmm.payment_sum,
  cmm.payment_count,
  cmm.deviation_from_prev_avg AS deviation_from_prev_avg_sum,
  RANK() OVER (
    PARTITION BY cg.country_name
    ORDER BY cmm.deviation_from_prev_avg DESC
  ) AS client_rank_in_country_by_deviation
FROM client_months_in_2005 AS cmm
JOIN cust_geo AS cg
  ON cg.customer_id = cmm.customer_id
ORDER BY
  cmm.customer_id,
  cmm.month_start;