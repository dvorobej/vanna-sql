-- Sakila opaque schema template
-- Source: MySQL Sakila sample (opaque column names)
-- Placeholders use Russian descriptions from data/external/sakila/comments_*.json

-- BEGIN COMMENT_STYLE:inline
CREATE TABLE act ( -- {{act}}
  a01 numeric NOT NULL, -- {{act.a01}}
  a02 VARCHAR(45) NOT NULL, -- {{act.a02}}
  a03 VARCHAR(45) NOT NULL, -- {{act.a03}}
  a04 TIMESTAMP NOT NULL, -- {{act.a04}}
  PRIMARY KEY (a01)
);

CREATE INDEX idx_act_a03 ON act(a03);

CREATE TRIGGER act_trigger_ai AFTER INSERT ON act
BEGIN
  UPDATE act SET a04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER act_trigger_au AFTER UPDATE ON act
BEGIN
  UPDATE act SET a04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE cnt ( -- {{cnt}}
  c01 SMALLINT NOT NULL, -- {{cnt.c01}}
  c02 VARCHAR(50) NOT NULL, -- {{cnt.c02}}
  c03 TIMESTAMP, -- {{cnt.c03}}
  PRIMARY KEY (c01)
);

CREATE TRIGGER cnt_trigger_ai AFTER INSERT ON cnt
BEGIN
  UPDATE cnt SET c03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER cnt_trigger_au AFTER UPDATE ON cnt
BEGIN
  UPDATE cnt SET c03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE cty ( -- {{cty}}
  d01 int NOT NULL, -- {{cty.d01}}
  d02 VARCHAR(50) NOT NULL, -- {{cty.d02}}
  d03 SMALLINT NOT NULL, -- {{cty.d03}}
  d04 TIMESTAMP NOT NULL, -- {{cty.d04}}
  PRIMARY KEY (d01),
  CONSTRAINT fk_cty_cnt FOREIGN KEY (d03) REFERENCES cnt (c01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_d03 ON cty(d03);

CREATE TRIGGER cty_trigger_ai AFTER INSERT ON cty
BEGIN
  UPDATE cty SET d04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER cty_trigger_au AFTER UPDATE ON cty
BEGIN
  UPDATE cty SET d04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE adr ( -- {{adr}}
  e01 int NOT NULL, -- {{adr.e01}}
  e02 VARCHAR(50) NOT NULL, -- {{adr.e02}}
  e03 VARCHAR(50) DEFAULT NULL, -- {{adr.e03}}
  e04 VARCHAR(20) NOT NULL, -- {{adr.e04}}
  e05 INT NOT NULL, -- {{adr.e05}}
  e06 VARCHAR(10) DEFAULT NULL, -- {{adr.e06}}
  e07 VARCHAR(20) NOT NULL, -- {{adr.e07}}
  e08 TIMESTAMP NOT NULL, -- {{adr.e08}}
  PRIMARY KEY (e01),
  CONSTRAINT fk_adr_cty FOREIGN KEY (e05) REFERENCES cty (d01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_e05 ON adr(e05);

CREATE TRIGGER adr_trigger_ai AFTER INSERT ON adr
BEGIN
  UPDATE adr SET e08 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER adr_trigger_au AFTER UPDATE ON adr
BEGIN
  UPDATE adr SET e08 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE lng ( -- {{lng}}
  f01 SMALLINT NOT NULL, -- {{lng.f01}}
  f02 CHAR(20) NOT NULL, -- {{lng.f02}}
  f03 TIMESTAMP NOT NULL, -- {{lng.f03}}
  PRIMARY KEY (f01)
);

CREATE TRIGGER lng_trigger_ai AFTER INSERT ON lng
BEGIN
  UPDATE lng SET f03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER lng_trigger_au AFTER UPDATE ON lng
BEGIN
  UPDATE lng SET f03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE cat ( -- {{cat}}
  g01 SMALLINT NOT NULL, -- {{cat.g01}}
  g02 VARCHAR(25) NOT NULL, -- {{cat.g02}}
  g03 TIMESTAMP NOT NULL, -- {{cat.g03}}
  PRIMARY KEY (g01)
);

CREATE TRIGGER cat_trigger_ai AFTER INSERT ON cat
BEGIN
  UPDATE cat SET g03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER cat_trigger_au AFTER UPDATE ON cat
BEGIN
  UPDATE cat SET g03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE cus ( -- {{cus}}
  h01 INT NOT NULL, -- {{cus.h01}}
  h02 INT NOT NULL, -- {{cus.h02}}
  h03 VARCHAR(45) NOT NULL, -- {{cus.h03}}
  h04 VARCHAR(45) NOT NULL, -- {{cus.h04}}
  h05 VARCHAR(50) DEFAULT NULL, -- {{cus.h05}}
  h06 INT NOT NULL, -- {{cus.h06}}
  h07 CHAR(1) DEFAULT 'Y' NOT NULL, -- {{cus.h07}}
  h08 TIMESTAMP NOT NULL, -- {{cus.h08}}
  h09 TIMESTAMP NOT NULL, -- {{cus.h09}}
  PRIMARY KEY (h01),
  CONSTRAINT fk_cus_sto FOREIGN KEY (h02) REFERENCES sto (j01) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT fk_cus_adr FOREIGN KEY (h06) REFERENCES adr (e01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_cus_fk_h02 ON cus(h02);
CREATE INDEX idx_cus_fk_h06 ON cus(h06);
CREATE INDEX idx_cus_h04 ON cus(h04);

CREATE TRIGGER cus_trigger_ai AFTER INSERT ON cus
BEGIN
  UPDATE cus SET h09 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER cus_trigger_au AFTER UPDATE ON cus
BEGIN
  UPDATE cus SET h09 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE flm ( -- {{flm}}
  i01 int NOT NULL, -- {{flm.i01}}
  i02 VARCHAR(255) NOT NULL, -- {{flm.i02}}
  i03 BLOB SUB_TYPE TEXT DEFAULT NULL, -- {{flm.i03}}
  i04 VARCHAR(4) DEFAULT NULL, -- {{flm.i04}}
  i05 SMALLINT NOT NULL, -- {{flm.i05}}
  i06 SMALLINT DEFAULT NULL, -- {{flm.i06}}
  i07 SMALLINT DEFAULT 3 NOT NULL, -- {{flm.i07}}
  i08 DECIMAL(4,2) DEFAULT 4.99 NOT NULL, -- {{flm.i08}}
  i09 SMALLINT DEFAULT NULL, -- {{flm.i09}}
  i10 DECIMAL(5,2) DEFAULT 19.99 NOT NULL, -- {{flm.i10}}
  i11 VARCHAR(10) DEFAULT 'G', -- {{flm.i11}}
  i12 VARCHAR(100) DEFAULT NULL, -- {{flm.i12}}
  i13 TIMESTAMP NOT NULL, -- {{flm.i13}}
  PRIMARY KEY (i01),
  CONSTRAINT CHECK_flm_i12 CHECK(i12 is null OR i12 LIKE '%Trailers%' OR i12 LIKE '%Commentaries%' OR i12 LIKE '%Deleted Scenes%' OR i12 LIKE '%Behind the Scenes%'),
  CONSTRAINT CHECK_flm_i11 CHECK(i11 IN ('G','PG','PG-13','R','NC-17')),
  CONSTRAINT fk_flm_lng FOREIGN KEY (i05) REFERENCES lng (f01),
  CONSTRAINT fk_flm_lng_original FOREIGN KEY (i06) REFERENCES lng (f01)
);

CREATE INDEX idx_fk_i05 ON flm(i05);
CREATE INDEX idx_fk_i06 ON flm(i06);

CREATE TRIGGER flm_trigger_ai AFTER INSERT ON flm
BEGIN
  UPDATE flm SET i13 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER flm_trigger_au AFTER UPDATE ON flm
BEGIN
  UPDATE flm SET i13 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE fla ( -- {{fla}}
  k01 INT NOT NULL, -- {{fla.k01}}
  k02 INT NOT NULL, -- {{fla.k02}}
  k03 TIMESTAMP NOT NULL, -- {{fla.k03}}
  PRIMARY KEY (k01, k02),
  CONSTRAINT fk_fla_act FOREIGN KEY (k01) REFERENCES act (a01) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT fk_fla_flm FOREIGN KEY (k02) REFERENCES flm (i01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_fla_k02 ON fla(k02);
CREATE INDEX idx_fk_fla_k01 ON fla(k01);

CREATE TRIGGER fla_trigger_ai AFTER INSERT ON fla
BEGIN
  UPDATE fla SET k03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER fla_trigger_au AFTER UPDATE ON fla
BEGIN
  UPDATE fla SET k03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE flc ( -- {{flc}}
  l01 INT NOT NULL, -- {{flc.l01}}
  l02 SMALLINT NOT NULL, -- {{flc.l02}}
  l03 TIMESTAMP NOT NULL, -- {{flc.l03}}
  PRIMARY KEY (l01, l02),
  CONSTRAINT fk_flc_flm FOREIGN KEY (l01) REFERENCES flm (i01) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT fk_flc_cat FOREIGN KEY (l02) REFERENCES cat (g01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_flc_l01 ON flc(l01);
CREATE INDEX idx_fk_flc_l02 ON flc(l02);

CREATE TRIGGER flc_trigger_ai AFTER INSERT ON flc
BEGIN
  UPDATE flc SET l03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER flc_trigger_au AFTER UPDATE ON flc
BEGIN
  UPDATE flc SET l03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE flt ( -- {{flt}}
  m01 SMALLINT NOT NULL, -- {{flt.m01}}
  m02 VARCHAR(255) NOT NULL, -- {{flt.m02}}
  m03 BLOB SUB_TYPE TEXT, -- {{flt.m03}}
  PRIMARY KEY (m01)
);

CREATE TABLE inv ( -- {{inv}}
  n01 INT NOT NULL, -- {{inv.n01}}
  n02 INT NOT NULL, -- {{inv.n02}}
  n03 INT NOT NULL, -- {{inv.n03}}
  n04 TIMESTAMP NOT NULL, -- {{inv.n04}}
  PRIMARY KEY (n01),
  CONSTRAINT fk_inv_sto FOREIGN KEY (n03) REFERENCES sto (j01) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT fk_inv_flm FOREIGN KEY (n02) REFERENCES flm (i01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_n02 ON inv(n02);
CREATE INDEX idx_fk_n03_n02 ON inv(n03, n02);

CREATE TRIGGER inv_trigger_ai AFTER INSERT ON inv
BEGIN
  UPDATE inv SET n04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER inv_trigger_au AFTER UPDATE ON inv
BEGIN
  UPDATE inv SET n04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE stf ( -- {{stf}}
  o01 SMALLINT NOT NULL, -- {{stf.o01}}
  o02 VARCHAR(45) NOT NULL, -- {{stf.o02}}
  o03 VARCHAR(45) NOT NULL, -- {{stf.o03}}
  o04 INT NOT NULL, -- {{stf.o04}}
  o05 BLOB DEFAULT NULL, -- {{stf.o05}}
  o06 VARCHAR(50) DEFAULT NULL, -- {{stf.o06}}
  o07 INT NOT NULL, -- {{stf.o07}}
  o08 SMALLINT DEFAULT 1 NOT NULL, -- {{stf.o08}}
  o09 VARCHAR(16) NOT NULL, -- {{stf.o09}}
  o10 VARCHAR(40) DEFAULT NULL, -- {{stf.o10}}
  o11 TIMESTAMP NOT NULL, -- {{stf.o11}}
  PRIMARY KEY (o01),
  CONSTRAINT fk_stf_sto FOREIGN KEY (o07) REFERENCES sto (j01) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT fk_stf_adr FOREIGN KEY (o04) REFERENCES adr (e01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_stf_o07 ON stf(o07);
CREATE INDEX idx_fk_stf_o04 ON stf(o04);

CREATE TRIGGER stf_trigger_ai AFTER INSERT ON stf
BEGIN
  UPDATE stf SET o11 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER stf_trigger_au AFTER UPDATE ON stf
BEGIN
  UPDATE stf SET o11 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE sto ( -- {{sto}}
  j01 INT NOT NULL, -- {{sto.j01}}
  j02 SMALLINT NOT NULL, -- {{sto.j02}}
  j03 INT NOT NULL, -- {{sto.j03}}
  j04 TIMESTAMP NOT NULL, -- {{sto.j04}}
  PRIMARY KEY (j01),
  CONSTRAINT fk_sto_stf FOREIGN KEY (j02) REFERENCES stf (o01),
  CONSTRAINT fk_sto_adr FOREIGN KEY (j03) REFERENCES adr (e01)
);

CREATE INDEX idx_sto_fk_j02 ON sto(j02);
CREATE INDEX idx_fk_sto_j03 ON sto(j03);

CREATE TRIGGER sto_trigger_ai AFTER INSERT ON sto
BEGIN
  UPDATE sto SET j04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER sto_trigger_au AFTER UPDATE ON sto
BEGIN
  UPDATE sto SET j04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE pay ( -- {{pay}}
  p01 int NOT NULL, -- {{pay.p01}}
  p02 INT NOT NULL, -- {{pay.p02}}
  p03 SMALLINT NOT NULL, -- {{pay.p03}}
  p04 INT DEFAULT NULL, -- {{pay.p04}}
  p05 DECIMAL(5,2) NOT NULL, -- {{pay.p05}}
  p06 TIMESTAMP NOT NULL, -- {{pay.p06}}
  p07 TIMESTAMP NOT NULL, -- {{pay.p07}}
  PRIMARY KEY (p01),
  CONSTRAINT fk_pay_ren FOREIGN KEY (p04) REFERENCES ren (q01) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_pay_cus FOREIGN KEY (p02) REFERENCES cus (h01),
  CONSTRAINT fk_pay_stf FOREIGN KEY (p03) REFERENCES stf (o01)
);

CREATE INDEX idx_fk_p03 ON pay(p03);
CREATE INDEX idx_fk_p02 ON pay(p02);

CREATE TRIGGER pay_trigger_ai AFTER INSERT ON pay
BEGIN
  UPDATE pay SET p07 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER pay_trigger_au AFTER UPDATE ON pay
BEGIN
  UPDATE pay SET p07 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TABLE ren ( -- {{ren}}
  q01 INT NOT NULL, -- {{ren.q01}}
  q02 TIMESTAMP NOT NULL, -- {{ren.q02}}
  q03 INT NOT NULL, -- {{ren.q03}}
  q04 INT NOT NULL, -- {{ren.q04}}
  q05 TIMESTAMP DEFAULT NULL, -- {{ren.q05}}
  q06 SMALLINT NOT NULL, -- {{ren.q06}}
  q07 TIMESTAMP NOT NULL, -- {{ren.q07}}
  PRIMARY KEY (q01),
  CONSTRAINT fk_ren_stf FOREIGN KEY (q06) REFERENCES stf (o01),
  CONSTRAINT fk_ren_inv FOREIGN KEY (q03) REFERENCES inv (n01),
  CONSTRAINT fk_ren_cus FOREIGN KEY (q04) REFERENCES cus (h01)
);

CREATE INDEX idx_ren_fk_q03 ON ren(q03);
CREATE INDEX idx_ren_fk_q04 ON ren(q04);
CREATE INDEX idx_ren_fk_q06 ON ren(q06);
CREATE UNIQUE INDEX idx_ren_uq ON ren (q02, q03, q04);

CREATE TRIGGER ren_trigger_ai AFTER INSERT ON ren
BEGIN
  UPDATE ren SET q07 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER ren_trigger_au AFTER UPDATE ON ren
BEGIN
  UPDATE ren SET q07 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- END COMMENT_STYLE:inline

-- BEGIN COMMENT_STYLE:yaml

-- table: act
-- source_table: actor
-- description: {{act}}
-- columns:
--   a01: {{act.a01}}  # source: actor_id
--   a02: {{act.a02}}  # source: first_name
--   a03: {{act.a03}}  # source: last_name
--   a04: {{act.a04}}  # source: last_update
CREATE TABLE act (
  a01 numeric NOT NULL,
  a02 VARCHAR(45) NOT NULL,
  a03 VARCHAR(45) NOT NULL,
  a04 TIMESTAMP NOT NULL,
  PRIMARY KEY (a01)
);

CREATE INDEX idx_act_a03 ON act(a03);

CREATE TRIGGER act_trigger_ai AFTER INSERT ON act
BEGIN
  UPDATE act SET a04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER act_trigger_au AFTER UPDATE ON act
BEGIN
  UPDATE act SET a04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: cnt
-- source_table: country
-- description: {{cnt}}
-- columns:
--   c01: {{cnt.c01}}  # source: country_id
--   c02: {{cnt.c02}}  # source: country
--   c03: {{cnt.c03}}  # source: last_update
CREATE TABLE cnt (
  c01 SMALLINT NOT NULL,
  c02 VARCHAR(50) NOT NULL,
  c03 TIMESTAMP,
  PRIMARY KEY (c01)
);

CREATE TRIGGER cnt_trigger_ai AFTER INSERT ON cnt
BEGIN
  UPDATE cnt SET c03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER cnt_trigger_au AFTER UPDATE ON cnt
BEGIN
  UPDATE cnt SET c03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: cty
-- source_table: city
-- description: {{cty}}
-- columns:
--   d01: {{cty.d01}}  # source: city_id
--   d02: {{cty.d02}}  # source: city
--   d03: {{cty.d03}}  # source: country_id
--   d04: {{cty.d04}}  # source: last_update
CREATE TABLE cty (
  d01 int NOT NULL,
  d02 VARCHAR(50) NOT NULL,
  d03 SMALLINT NOT NULL,
  d04 TIMESTAMP NOT NULL,
  PRIMARY KEY (d01),
  CONSTRAINT fk_cty_cnt FOREIGN KEY (d03) REFERENCES cnt (c01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_d03 ON cty(d03);

CREATE TRIGGER cty_trigger_ai AFTER INSERT ON cty
BEGIN
  UPDATE cty SET d04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER cty_trigger_au AFTER UPDATE ON cty
BEGIN
  UPDATE cty SET d04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: adr
-- source_table: address
-- description: {{adr}}
-- columns:
--   e01: {{adr.e01}}  # source: address_id
--   e02: {{adr.e02}}  # source: address
--   e03: {{adr.e03}}  # source: address2
--   e04: {{adr.e04}}  # source: district
--   e05: {{adr.e05}}  # source: city_id
--   e06: {{adr.e06}}  # source: postal_code
--   e07: {{adr.e07}}  # source: phone
--   e08: {{adr.e08}}  # source: last_update
CREATE TABLE adr (
  e01 int NOT NULL,
  e02 VARCHAR(50) NOT NULL,
  e03 VARCHAR(50) DEFAULT NULL,
  e04 VARCHAR(20) NOT NULL,
  e05 INT NOT NULL,
  e06 VARCHAR(10) DEFAULT NULL,
  e07 VARCHAR(20) NOT NULL,
  e08 TIMESTAMP NOT NULL,
  PRIMARY KEY (e01),
  CONSTRAINT fk_adr_cty FOREIGN KEY (e05) REFERENCES cty (d01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_e05 ON adr(e05);

CREATE TRIGGER adr_trigger_ai AFTER INSERT ON adr
BEGIN
  UPDATE adr SET e08 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER adr_trigger_au AFTER UPDATE ON adr
BEGIN
  UPDATE adr SET e08 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: lng
-- source_table: language
-- description: {{lng}}
-- columns:
--   f01: {{lng.f01}}  # source: language_id
--   f02: {{lng.f02}}  # source: name
--   f03: {{lng.f03}}  # source: last_update
CREATE TABLE lng (
  f01 SMALLINT NOT NULL,
  f02 CHAR(20) NOT NULL,
  f03 TIMESTAMP NOT NULL,
  PRIMARY KEY (f01)
);

CREATE TRIGGER lng_trigger_ai AFTER INSERT ON lng
BEGIN
  UPDATE lng SET f03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER lng_trigger_au AFTER UPDATE ON lng
BEGIN
  UPDATE lng SET f03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: cat
-- source_table: category
-- description: {{cat}}
-- columns:
--   g01: {{cat.g01}}  # source: category_id
--   g02: {{cat.g02}}  # source: name
--   g03: {{cat.g03}}  # source: last_update
CREATE TABLE cat (
  g01 SMALLINT NOT NULL,
  g02 VARCHAR(25) NOT NULL,
  g03 TIMESTAMP NOT NULL,
  PRIMARY KEY (g01)
);

CREATE TRIGGER cat_trigger_ai AFTER INSERT ON cat
BEGIN
  UPDATE cat SET g03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER cat_trigger_au AFTER UPDATE ON cat
BEGIN
  UPDATE cat SET g03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: cus
-- source_table: customer
-- description: {{cus}}
-- columns:
--   h01: {{cus.h01}}  # source: customer_id
--   h02: {{cus.h02}}  # source: store_id
--   h03: {{cus.h03}}  # source: first_name
--   h04: {{cus.h04}}  # source: last_name
--   h05: {{cus.h05}}  # source: email
--   h06: {{cus.h06}}  # source: address_id
--   h07: {{cus.h07}}  # source: active
--   h08: {{cus.h08}}  # source: create_date
--   h09: {{cus.h09}}  # source: last_update
CREATE TABLE cus (
  h01 INT NOT NULL,
  h02 INT NOT NULL,
  h03 VARCHAR(45) NOT NULL,
  h04 VARCHAR(45) NOT NULL,
  h05 VARCHAR(50) DEFAULT NULL,
  h06 INT NOT NULL,
  h07 CHAR(1) DEFAULT 'Y' NOT NULL,
  h08 TIMESTAMP NOT NULL,
  h09 TIMESTAMP NOT NULL,
  PRIMARY KEY (h01),
  CONSTRAINT fk_cus_sto FOREIGN KEY (h02) REFERENCES sto (j01) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT fk_cus_adr FOREIGN KEY (h06) REFERENCES adr (e01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_cus_fk_h02 ON cus(h02);
CREATE INDEX idx_cus_fk_h06 ON cus(h06);
CREATE INDEX idx_cus_h04 ON cus(h04);

CREATE TRIGGER cus_trigger_ai AFTER INSERT ON cus
BEGIN
  UPDATE cus SET h09 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER cus_trigger_au AFTER UPDATE ON cus
BEGIN
  UPDATE cus SET h09 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: flm
-- source_table: film
-- description: {{flm}}
-- columns:
--   i01: {{flm.i01}}  # source: film_id
--   i02: {{flm.i02}}  # source: title
--   i03: {{flm.i03}}  # source: description
--   i04: {{flm.i04}}  # source: release_year
--   i05: {{flm.i05}}  # source: language_id
--   i06: {{flm.i06}}  # source: original_language_id
--   i07: {{flm.i07}}  # source: rental_duration
--   i08: {{flm.i08}}  # source: rental_rate
--   i09: {{flm.i09}}  # source: length
--   i10: {{flm.i10}}  # source: replacement_cost
--   i11: {{flm.i11}}  # source: rating
--   i12: {{flm.i12}}  # source: special_features
--   i13: {{flm.i13}}  # source: last_update
CREATE TABLE flm (
  i01 int NOT NULL,
  i02 VARCHAR(255) NOT NULL,
  i03 BLOB SUB_TYPE TEXT DEFAULT NULL,
  i04 VARCHAR(4) DEFAULT NULL,
  i05 SMALLINT NOT NULL,
  i06 SMALLINT DEFAULT NULL,
  i07 SMALLINT DEFAULT 3 NOT NULL,
  i08 DECIMAL(4,2) DEFAULT 4.99 NOT NULL,
  i09 SMALLINT DEFAULT NULL,
  i10 DECIMAL(5,2) DEFAULT 19.99 NOT NULL,
  i11 VARCHAR(10) DEFAULT 'G',
  i12 VARCHAR(100) DEFAULT NULL,
  i13 TIMESTAMP NOT NULL,
  PRIMARY KEY (i01),
  CONSTRAINT CHECK_flm_i12 CHECK(i12 is null OR i12 LIKE '%Trailers%' OR i12 LIKE '%Commentaries%' OR i12 LIKE '%Deleted Scenes%' OR i12 LIKE '%Behind the Scenes%'),
  CONSTRAINT CHECK_flm_i11 CHECK(i11 IN ('G','PG','PG-13','R','NC-17')),
  CONSTRAINT fk_flm_lng FOREIGN KEY (i05) REFERENCES lng (f01),
  CONSTRAINT fk_flm_lng_original FOREIGN KEY (i06) REFERENCES lng (f01)
);

CREATE INDEX idx_fk_i05 ON flm(i05);
CREATE INDEX idx_fk_i06 ON flm(i06);

CREATE TRIGGER flm_trigger_ai AFTER INSERT ON flm
BEGIN
  UPDATE flm SET i13 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER flm_trigger_au AFTER UPDATE ON flm
BEGIN
  UPDATE flm SET i13 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: fla
-- source_table: film_actor
-- description: {{fla}}
-- columns:
--   k01: {{fla.k01}}  # source: actor_id
--   k02: {{fla.k02}}  # source: film_id
--   k03: {{fla.k03}}  # source: last_update
CREATE TABLE fla (
  k01 INT NOT NULL,
  k02 INT NOT NULL,
  k03 TIMESTAMP NOT NULL,
  PRIMARY KEY (k01, k02),
  CONSTRAINT fk_fla_act FOREIGN KEY (k01) REFERENCES act (a01) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT fk_fla_flm FOREIGN KEY (k02) REFERENCES flm (i01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_fla_k02 ON fla(k02);
CREATE INDEX idx_fk_fla_k01 ON fla(k01);

CREATE TRIGGER fla_trigger_ai AFTER INSERT ON fla
BEGIN
  UPDATE fla SET k03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER fla_trigger_au AFTER UPDATE ON fla
BEGIN
  UPDATE fla SET k03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: flc
-- source_table: film_category
-- description: {{flc}}
-- columns:
--   l01: {{flc.l01}}  # source: film_id
--   l02: {{flc.l02}}  # source: category_id
--   l03: {{flc.l03}}  # source: last_update
CREATE TABLE flc (
  l01 INT NOT NULL,
  l02 SMALLINT NOT NULL,
  l03 TIMESTAMP NOT NULL,
  PRIMARY KEY (l01, l02),
  CONSTRAINT fk_flc_flm FOREIGN KEY (l01) REFERENCES flm (i01) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT fk_flc_cat FOREIGN KEY (l02) REFERENCES cat (g01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_flc_l01 ON flc(l01);
CREATE INDEX idx_fk_flc_l02 ON flc(l02);

CREATE TRIGGER flc_trigger_ai AFTER INSERT ON flc
BEGIN
  UPDATE flc SET l03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER flc_trigger_au AFTER UPDATE ON flc
BEGIN
  UPDATE flc SET l03 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: flt
-- source_table: film_text
-- description: {{flt}}
-- columns:
--   m01: {{flt.m01}}  # source: film_id
--   m02: {{flt.m02}}  # source: title
--   m03: {{flt.m03}}  # source: description
CREATE TABLE flt (
  m01 SMALLINT NOT NULL,
  m02 VARCHAR(255) NOT NULL,
  m03 BLOB SUB_TYPE TEXT,
  PRIMARY KEY (m01)
);

-- table: inv
-- source_table: inventory
-- description: {{inv}}
-- columns:
--   n01: {{inv.n01}}  # source: inventory_id
--   n02: {{inv.n02}}  # source: film_id
--   n03: {{inv.n03}}  # source: store_id
--   n04: {{inv.n04}}  # source: last_update
CREATE TABLE inv (
  n01 INT NOT NULL,
  n02 INT NOT NULL,
  n03 INT NOT NULL,
  n04 TIMESTAMP NOT NULL,
  PRIMARY KEY (n01),
  CONSTRAINT fk_inv_sto FOREIGN KEY (n03) REFERENCES sto (j01) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT fk_inv_flm FOREIGN KEY (n02) REFERENCES flm (i01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_n02 ON inv(n02);
CREATE INDEX idx_fk_n03_n02 ON inv(n03, n02);

CREATE TRIGGER inv_trigger_ai AFTER INSERT ON inv
BEGIN
  UPDATE inv SET n04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER inv_trigger_au AFTER UPDATE ON inv
BEGIN
  UPDATE inv SET n04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: stf
-- source_table: staff
-- description: {{stf}}
-- columns:
--   o01: {{stf.o01}}  # source: staff_id
--   o02: {{stf.o02}}  # source: first_name
--   o03: {{stf.o03}}  # source: last_name
--   o04: {{stf.o04}}  # source: address_id
--   o05: {{stf.o05}}  # source: picture
--   o06: {{stf.o06}}  # source: email
--   o07: {{stf.o07}}  # source: store_id
--   o08: {{stf.o08}}  # source: active
--   o09: {{stf.o09}}  # source: username
--   o10: {{stf.o10}}  # source: password
--   o11: {{stf.o11}}  # source: last_update
CREATE TABLE stf (
  o01 SMALLINT NOT NULL,
  o02 VARCHAR(45) NOT NULL,
  o03 VARCHAR(45) NOT NULL,
  o04 INT NOT NULL,
  o05 BLOB DEFAULT NULL,
  o06 VARCHAR(50) DEFAULT NULL,
  o07 INT NOT NULL,
  o08 SMALLINT DEFAULT 1 NOT NULL,
  o09 VARCHAR(16) NOT NULL,
  o10 VARCHAR(40) DEFAULT NULL,
  o11 TIMESTAMP NOT NULL,
  PRIMARY KEY (o01),
  CONSTRAINT fk_stf_sto FOREIGN KEY (o07) REFERENCES sto (j01) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT fk_stf_adr FOREIGN KEY (o04) REFERENCES adr (e01) ON DELETE NO ACTION ON UPDATE CASCADE
);

CREATE INDEX idx_fk_stf_o07 ON stf(o07);
CREATE INDEX idx_fk_stf_o04 ON stf(o04);

CREATE TRIGGER stf_trigger_ai AFTER INSERT ON stf
BEGIN
  UPDATE stf SET o11 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER stf_trigger_au AFTER UPDATE ON stf
BEGIN
  UPDATE stf SET o11 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: sto
-- source_table: store
-- description: {{sto}}
-- columns:
--   j01: {{sto.j01}}  # source: store_id
--   j02: {{sto.j02}}  # source: manager_staff_id
--   j03: {{sto.j03}}  # source: address_id
--   j04: {{sto.j04}}  # source: last_update
CREATE TABLE sto (
  j01 INT NOT NULL,
  j02 SMALLINT NOT NULL,
  j03 INT NOT NULL,
  j04 TIMESTAMP NOT NULL,
  PRIMARY KEY (j01),
  CONSTRAINT fk_sto_stf FOREIGN KEY (j02) REFERENCES stf (o01),
  CONSTRAINT fk_sto_adr FOREIGN KEY (j03) REFERENCES adr (e01)
);

CREATE INDEX idx_sto_fk_j02 ON sto(j02);
CREATE INDEX idx_fk_sto_j03 ON sto(j03);

CREATE TRIGGER sto_trigger_ai AFTER INSERT ON sto
BEGIN
  UPDATE sto SET j04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER sto_trigger_au AFTER UPDATE ON sto
BEGIN
  UPDATE sto SET j04 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: pay
-- source_table: payment
-- description: {{pay}}
-- columns:
--   p01: {{pay.p01}}  # source: payment_id
--   p02: {{pay.p02}}  # source: customer_id
--   p03: {{pay.p03}}  # source: staff_id
--   p04: {{pay.p04}}  # source: rental_id
--   p05: {{pay.p05}}  # source: amount
--   p06: {{pay.p06}}  # source: payment_date
--   p07: {{pay.p07}}  # source: last_update
CREATE TABLE pay (
  p01 int NOT NULL,
  p02 INT NOT NULL,
  p03 SMALLINT NOT NULL,
  p04 INT DEFAULT NULL,
  p05 DECIMAL(5,2) NOT NULL,
  p06 TIMESTAMP NOT NULL,
  p07 TIMESTAMP NOT NULL,
  PRIMARY KEY (p01),
  CONSTRAINT fk_pay_ren FOREIGN KEY (p04) REFERENCES ren (q01) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_pay_cus FOREIGN KEY (p02) REFERENCES cus (h01),
  CONSTRAINT fk_pay_stf FOREIGN KEY (p03) REFERENCES stf (o01)
);

CREATE INDEX idx_fk_p03 ON pay(p03);
CREATE INDEX idx_fk_p02 ON pay(p02);

CREATE TRIGGER pay_trigger_ai AFTER INSERT ON pay
BEGIN
  UPDATE pay SET p07 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER pay_trigger_au AFTER UPDATE ON pay
BEGIN
  UPDATE pay SET p07 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- table: ren
-- source_table: rental
-- description: {{ren}}
-- columns:
--   q01: {{ren.q01}}  # source: rental_id
--   q02: {{ren.q02}}  # source: rental_date
--   q03: {{ren.q03}}  # source: inventory_id
--   q04: {{ren.q04}}  # source: customer_id
--   q05: {{ren.q05}}  # source: return_date
--   q06: {{ren.q06}}  # source: staff_id
--   q07: {{ren.q07}}  # source: last_update
CREATE TABLE ren (
  q01 INT NOT NULL,
  q02 TIMESTAMP NOT NULL,
  q03 INT NOT NULL,
  q04 INT NOT NULL,
  q05 TIMESTAMP DEFAULT NULL,
  q06 SMALLINT NOT NULL,
  q07 TIMESTAMP NOT NULL,
  PRIMARY KEY (q01),
  CONSTRAINT fk_ren_stf FOREIGN KEY (q06) REFERENCES stf (o01),
  CONSTRAINT fk_ren_inv FOREIGN KEY (q03) REFERENCES inv (n01),
  CONSTRAINT fk_ren_cus FOREIGN KEY (q04) REFERENCES cus (h01)
);

CREATE INDEX idx_ren_fk_q03 ON ren(q03);
CREATE INDEX idx_ren_fk_q04 ON ren(q04);
CREATE INDEX idx_ren_fk_q06 ON ren(q06);
CREATE UNIQUE INDEX idx_ren_uq ON ren (q02, q03, q04);

CREATE TRIGGER ren_trigger_ai AFTER INSERT ON ren
BEGIN
  UPDATE ren SET q07 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

CREATE TRIGGER ren_trigger_au AFTER UPDATE ON ren
BEGIN
  UPDATE ren SET q07 = DATETIME('NOW') WHERE rowid = new.rowid;
END;

-- END COMMENT_STYLE:yaml
