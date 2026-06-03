-- Bank Transaction Monitoring opaque schema template
-- Source: Bank_Transaction_Monitoring_System.ipynb
-- Placeholders use Russian descriptions from data/external/bank_transaction_monitoring/comments_*.json

-- BEGIN COMMENT_STYLE:inline
CREATE TABLE btm_cst ( -- {{btm_cst}}
    c01 INTEGER, -- {{btm_cst.c01}}
    c02 TEXT   , -- {{btm_cst.c02}}
    c03 TEXT   , -- {{btm_cst.c03}}
    c04 TEXT   , -- {{btm_cst.c04}}
    c05 TEXT     -- {{btm_cst.c05}}
);

CREATE TABLE btm_cex ( -- {{btm_cex}}
    x01 TEXT   , -- {{btm_cex.x01}}
    x02 TEXT   , -- {{btm_cex.x02}}
    x03 TEXT   , -- {{btm_cex.x03}}
    x04 TEXT   , -- {{btm_cex.x04}}
    x05 TEXT     -- {{btm_cex.x05}}
);

CREATE TABLE btm_accd ( -- {{btm_accd}}
    a01 INTEGER, -- {{btm_accd.a01}}
    a02 TEXT   , -- {{btm_accd.a02}}
    a03 TEXT   , -- {{btm_accd.a03}}
    a04 INTEGER, -- {{btm_accd.a04}}
    a05 TEXT   , -- {{btm_accd.a05}}
    a06 TEXT     -- {{btm_accd.a06}}
);

CREATE TABLE btm_accs ( -- {{btm_accs}}
    s01 INTEGER, -- {{btm_accs.s01}}
    s02 TEXT   , -- {{btm_accs.s02}}
    s03 TEXT   , -- {{btm_accs.s03}}
    s04 INTEGER, -- {{btm_accs.s04}}
    s05 TEXT   , -- {{btm_accs.s05}}
    s06 TEXT     -- {{btm_accs.s06}}
);

CREATE TABLE btm_rel ( -- {{btm_rel}}
    r01 INTEGER, -- {{btm_rel.r01}}
    r02 TEXT   , -- {{btm_rel.r02}}
    r03 TEXT   , -- {{btm_rel.r03}}
    r04 TEXT     -- {{btm_rel.r04}}
);

CREATE TABLE btm_trn ( -- {{btm_trn}}
    t01 TEXT   , -- {{btm_trn.t01}}
    t02 REAL   , -- {{btm_trn.t02}}
    t03 TEXT   , -- {{btm_trn.t03}}
    t04 TEXT   , -- {{btm_trn.t04}}
    t05 TEXT     -- {{btm_trn.t05}}
);

CREATE TABLE btm_msg ( -- {{btm_msg}}
    m01 TEXT   , -- {{btm_msg.m01}}
    m02 TEXT   , -- {{btm_msg.m02}}
    m03 TEXT     -- {{btm_msg.m03}}
);

CREATE TABLE btm_rate ( -- {{btm_rate}}
    i01 TEXT   , -- {{btm_rate.i01}}
    i02 REAL   , -- {{btm_rate.i02}}
    i03 TEXT   , -- {{btm_rate.i03}}
    i04 TEXT     -- {{btm_rate.i04}}
);

-- END COMMENT_STYLE:inline

-- BEGIN COMMENT_STYLE:yaml

-- table: btm_cst
-- source_table: BANK_CUST
-- description: {{btm_cst}}
-- columns:
--   c01: {{btm_cst.c01}}  # source: customer_id
--   c02: {{btm_cst.c02}}  # source: customer_name
--   c03: {{btm_cst.c03}}  # source: Address
--   c04: {{btm_cst.c04}}  # source: state_code
--   c05: {{btm_cst.c05}}  # source: Telephone
CREATE TABLE btm_cst (
    c01 INTEGER,
    c02 TEXT,
    c03 TEXT,
    c04 TEXT,
    c05 TEXT
);

-- table: btm_cex
-- source_table: BANK_CUSTOMER_EXPORT
-- description: {{btm_cex}}
-- columns:
--   x01: {{btm_cex.x01}}  # source: customer_id
--   x02: {{btm_cex.x02}}  # source: customer_name
--   x03: {{btm_cex.x03}}  # source: Address
--   x04: {{btm_cex.x04}}  # source: state_code
--   x05: {{btm_cex.x05}}  # source: Telephone
CREATE TABLE btm_cex (
    x01 TEXT,
    x02 TEXT,
    x03 TEXT,
    x04 TEXT,
    x05 TEXT
);

-- table: btm_accd
-- source_table: BANK_ACC_DELS
-- description: {{btm_accd}}
-- columns:
--   a01: {{btm_accd.a01}}  # source: customer_id
--   a02: {{btm_accd.a02}}  # source: Account_number
--   a03: {{btm_accd.a03}}  # source: Account_type
--   a04: {{btm_accd.a04}}  # source: Balance_amount
--   a05: {{btm_accd.a05}}  # source: Account_status
--   a06: {{btm_accd.a06}}  # source: Relationship_type
CREATE TABLE btm_accd (
    a01 INTEGER,
    a02 TEXT,
    a03 TEXT,
    a04 INTEGER,
    a05 TEXT,
    a06 TEXT
);

-- table: btm_accs
-- source_table: BANK_ACCOU
-- description: {{btm_accs}}
-- columns:
--   s01: {{btm_accs.s01}}  # source: Customer_id
--   s02: {{btm_accs.s02}}  # source: Account_Number
--   s03: {{btm_accs.s03}}  # source: Account_type
--   s04: {{btm_accs.s04}}  # source: Balance_amount
--   s05: {{btm_accs.s05}}  # source: Account_status
--   s06: {{btm_accs.s06}}  # source: Relation_ship
CREATE TABLE btm_accs (
    s01 INTEGER,
    s02 TEXT,
    s03 TEXT,
    s04 INTEGER,
    s05 TEXT,
    s06 TEXT
);

-- table: btm_rel
-- source_table: Bank_Account_Relationship_Details
-- description: {{btm_rel}}
-- columns:
--   r01: {{btm_rel.r01}}  # source: Customer_id
--   r02: {{btm_rel.r02}}  # source: Account_Number
--   r03: {{btm_rel.r03}}  # source: Account_type
--   r04: {{btm_rel.r04}}  # source: Linking_Account_Number
CREATE TABLE btm_rel (
    r01 INTEGER,
    r02 TEXT,
    r03 TEXT,
    r04 TEXT
);

-- table: btm_trn
-- source_table: BANK_ACC_TRAN
-- description: {{btm_trn}}
-- columns:
--   t01: {{btm_trn.t01}}  # source: Account_Number
--   t02: {{btm_trn.t02}}  # source: Transaction_amount
--   t03: {{btm_trn.t03}}  # source: Transaction_channel
--   t04: {{btm_trn.t04}}  # source: Province
--   t05: {{btm_trn.t05}}  # source: Transaction_Date
CREATE TABLE btm_trn (
    t01 TEXT,
    t02 REAL,
    t03 TEXT,
    t04 TEXT,
    t05 TEXT
);

-- table: btm_msg
-- source_table: BANK_CUSTOMER_MSG
-- description: {{btm_msg}}
-- columns:
--   m01: {{btm_msg.m01}}  # source: Event
--   m02: {{btm_msg.m02}}  # source: Customer_message
--   m03: {{btm_msg.m03}}  # source: Notice_delivery_mode
CREATE TABLE btm_msg (
    m01 TEXT,
    m02 TEXT,
    m03 TEXT
);

-- table: btm_rate
-- source_table: BANK_INTEREST_RATE
-- description: {{btm_rate}}
-- columns:
--   i01: {{btm_rate.i01}}  # source: account_type
--   i02: {{btm_rate.i02}}  # source: interest_rate
--   i03: {{btm_rate.i03}}  # source: month
--   i04: {{btm_rate.i04}}  # source: year
CREATE TABLE btm_rate (
    i01 TEXT,
    i02 REAL,
    i03 TEXT,
    i04 TEXT
);

-- END COMMENT_STYLE:yaml
