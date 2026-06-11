SELECT h06 FROM cus WHERE h01 = sm.customer_id)
JOIN cty
  ON cty.d01 = a.e05
JOIN sto AS s
  ON s.j01 = sm.store_id
JOIN rental_overdue_share AS ros
  ON ros.customer_id = sm.customer_id
 AND ros.store_id = sm.store_id
 AND ros.country = sm.country
 AND ros.month_start = sm.month_start
JOIN store_month_rank AS smr
  ON smr.customer_id = sm.customer_id
 AND smr.store_id = sm.store_id
 AND smr.country = sm.country
 AND smr.month_start = sm.month_start
ORDER BY
  sm.month_start,
  sm.store_id,
  sm.country,
  overdue_share_payment_sum DESC;