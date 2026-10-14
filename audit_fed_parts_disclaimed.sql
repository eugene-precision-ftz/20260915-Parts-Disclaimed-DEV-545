DROP PROCEDURE IF EXISTS preftz.audit_fed_parts_disclaimed();

CREATE OR REPLACE PROCEDURE preftz.audit_fed_parts_disclaimed ()
LANGUAGE plpgsql
AS $BODY$


-- Change Log:
--EG 09/15/2026 - Initial creation of the table to store raw data.

DECLARE
  v_table_name         VARCHAR(50) = 'fed_parts_disclaimed';
  v_total_count        BIGINT;
  crs                  RECORD;
  v_role_counts        RECORD;
 

BEGIN
    INSERT INTO preftz.system_log (procedure_name,log_message)
        VALUES ('audit_fed_parts_disclaimed','started');

    SELECT COUNT(*) INTO v_total_count 
    FROM preftz.fed_parts_disclaimed
    WHERE fed_status = 'NEW';

    INSERT INTO preftz.system_log (procedure_name, log_message)
    VALUES ('audit_fed_parts_disclaimed', 'RECORD COUNT TO PROCESS ' || TO_CHAR(v_total_count,'999999'));

     DELETE FROM preftz.feed_errors fe
     USING preftz.fed_parts_disclaimed tar
     WHERE fe.table_name = v_table_name
       AND fe.tableid = tar.parts_disclaimed_id
       AND tar.fed_status = 'NEW';


    UPDATE preftz.fed_parts_disclaimed fe
    SET fed_status = 'AUDITING'
    WHERE fed_status = 'NEW';

    -- AUDIT SECTION

    --------------------------------------------------------------------------------------------------------
    --Check for nulls
/*
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type ) 
    SELECT v_table_name, fr.parts_disclaimed_id, 'part_number', 'part_number is missing'
    FROM preftz.fed_parts_disclaimed fr  WHERE fr.fed_status = 'AUDITING'  AND fr.part_number IS NULL;

    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )
    SELECT v_table_name, fr.parts_disclaimed_id, 'pga_code_array', 'pga_code_array is missing'
    FROM preftz.fed_parts_disclaimed fr  WHERE fr.fed_status = 'AUDITING'  AND fr.pga_code_array IS NULL;

    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )
    SELECT v_table_name, fr.parts_disclaimed_id, 'hts', 'hts is missing'
    FROM preftz.fed_parts_disclaimed fr  WHERE fr.fed_status = 'AUDITING'  AND fr.hts IS NULL;

    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )
    SELECT v_table_name, fr.parts_disclaimed_id, 'mid_key', 'mid_key is missing'
    FROM preftz.fed_parts_disclaimed fr  WHERE fr.fed_status = 'AUDITING'  AND fr.mid_key IS NULL;

    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )
    SELECT v_table_name, fr.parts_disclaimed_id, 'coo_iso', 'coo_iso is missing'
    FROM preftz.fed_parts_disclaimed fr  WHERE fr.fed_status = 'AUDITING'  AND fr.coo_iso IS NULL;

    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )
    SELECT v_table_name, fr.parts_disclaimed_id, 'government_agency_code', 'government_agency_code is missing'
    FROM preftz.fed_parts_disclaimed fr  WHERE fr.fed_status = 'AUDITING'  AND fr.government_agency_code IS NULL;

    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )
    SELECT v_table_name, fr.parts_disclaimed_id, 'government_agency_program_code', 'government_agency_program_code is missing'
    FROM preftz.fed_parts_disclaimed fr  WHERE fr.fed_status = 'AUDITING'  AND fr.government_agency_program_code IS NULL;

    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )
    SELECT v_table_name, fr.parts_disclaimed_id, 'government_agency_processing_code', 'government_agency_processing_code is missing'
    FROM preftz.fed_parts_disclaimed fr  WHERE fr.fed_status = 'AUDITING'  AND fr.government_agency_processing_code IS NULL;

    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'intended_use_code', 'intended_use_code is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.intended_use_code IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'item_type', 'item_type is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.item_type IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'product_code_qualifier', 'product_code_qualifier is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.product_code_qualifier IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'product_code_number', 'product_code_number is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.product_code_number IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'source_type_code', 'source_type_code is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.source_type_code IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'commodity_characteristic_description', 'commodity_characteristic_description is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.commodity_characteristic_description IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'entity_role_code', 'entity_role_code is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.entity_role_code IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'entity_name', 'entity_name is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.entity_name IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'entity_address_1', 'entity_address_1 is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.entity_address_1 IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'entity_city', 'entity_city is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.entity_city IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'entity_country', 'entity_country is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.entity_country IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'affirmation_of_compliance_code', 'affirmation_of_compliance_code is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.affirmation_of_compliance_code IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'affirmation_of_compliance_qualifier', 'affirmation_of_compliance_qualifier is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.affirmation_of_compliance_qualifier IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'anticipated_arrival_information', 'anticipated_arrival_information is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.anticipated_arrival_information IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'inspection_or_arrival_location_code', 'inspection_or_arrival_location_code is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.inspection_or_arrival_location_code IS NULL;
    INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  SELECT v_table_name, fr.parts_disclaimed_id, 'insection_or_arival_location', 'insection_or_arival_location is missing' FROM preftz.fed_parts_disclaimed fr WHERE fr.fed_status = 'AUDITING' AND fr.insection_or_arival_location IS NULL;

	INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  
	SELECT v_table_name, fr.parts_disclaimed_id, 'individual_name', 'individual_name is missing' 
	FROM preftz.fed_parts_disclaimed fr 
	WHERE fr.fed_status = 'AUDITING' AND fr.individual_name IS NULL AND fr.entity_role_code = 'PK';

	INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  
	SELECT v_table_name, fr.parts_disclaimed_id, 'telephone_number_of_the_individual', 'telephone_number_of_the_individual is missing' 
	FROM preftz.fed_parts_disclaimed fr 
	WHERE fr.fed_status = 'AUDITING' AND fr.telephone_number_of_the_individual IS NULL AND fr.entity_role_code = 'PK';

	INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  
	SELECT v_table_name, fr.parts_disclaimed_id, 'email_address_for_the_individual', 'email_address_for_the_individual is missing' 
	FROM preftz.fed_parts_disclaimed fr 
	WHERE fr.fed_status = 'AUDITING' AND fr.email_address_for_the_individual IS NULL AND fr.entity_role_code = 'PK';

*/

-- Check required fields for NULL or empty values.

INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'part_number',
    'part_number is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.part_number::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'pga_code_array',
    'pga_code_array is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.pga_code_array::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'hts',
    'hts is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.hts::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'mid_key',
    'mid_key is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.mid_key::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'coo_iso',
    'coo_iso is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.coo_iso::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'government_agency_code',
    'government_agency_code is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.government_agency_code::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'government_agency_program_code',
    'government_agency_program_code is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(
          BTRIM(fr.government_agency_program_code::text),
          ''
      ) IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'government_agency_processing_code',
    'government_agency_processing_code is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(
          BTRIM(fr.government_agency_processing_code::text),
          ''
      ) IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'intended_use_code',
    'intended_use_code is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.intended_use_code::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'item_type',
    'item_type is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.item_type::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'product_code_qualifier',
    'product_code_qualifier is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(
          BTRIM(fr.product_code_qualifier::text),
          ''
      ) IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'product_code_number',
    'product_code_number is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.product_code_number::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'source_type_code',
    'source_type_code is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.source_type_code::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'commodity_characteristic_description',
    'commodity_characteristic_description is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(
          BTRIM(fr.commodity_characteristic_description::text),
          ''
      ) IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'entity_role_code',
    'entity_role_code is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.entity_role_code::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'entity_name',
    'entity_name is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.entity_name::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'entity_address_1',
    'entity_address_1 is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.entity_address_1::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'entity_city',
    'entity_city is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.entity_city::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'entity_country',
    'entity_country is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(BTRIM(fr.entity_country::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'affirmation_of_compliance_code',
    'affirmation_of_compliance_code is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(
          BTRIM(fr.affirmation_of_compliance_code::text),
          ''
      ) IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'affirmation_of_compliance_qualifier',
    'affirmation_of_compliance_qualifier is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(
          BTRIM(fr.affirmation_of_compliance_qualifier::text),
          ''
      ) IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'anticipated_arrival_information',
    'anticipated_arrival_information is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(
          BTRIM(fr.anticipated_arrival_information::text),
          ''
      ) IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'inspection_or_arrival_location_code',
    'inspection_or_arrival_location_code is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(
          BTRIM(fr.inspection_or_arrival_location_code::text),
          ''
      ) IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'insection_or_arival_location',
    'insection_or_arival_location is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND NULLIF(
          BTRIM(fr.insection_or_arival_location::text),
          ''
      ) IS NULL;


/*
 * These fields are required only for entity_role_code = 'PK'.
 */
INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'individual_name',
    'individual_name is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND fr.entity_role_code = 'PK'
  AND NULLIF(BTRIM(fr.individual_name::text), '') IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'telephone_number_of_the_individual',
    'telephone_number_of_the_individual is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND fr.entity_role_code = 'PK'
  AND NULLIF(
          BTRIM(fr.telephone_number_of_the_individual::text),
          ''
      ) IS NULL;


INSERT INTO preftz.feed_errors
(
    table_name,
    tableid,
    field_name,
    error_type
)
SELECT
    v_table_name,
    fr.parts_disclaimed_id,
    'email_address_for_the_individual',
    'email_address_for_the_individual is missing'
FROM preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'
  AND fr.entity_role_code = 'PK'
  AND NULLIF(
          BTRIM(fr.email_address_for_the_individual::text),
          ''
      ) IS NULL;

    --------------------------------------------------------------------------------------------------------
    --Check for FD2

	INSERT INTO preftz.feed_errors  (table_name, tableid, field_name, error_type )  
	SELECT v_table_name, fr.parts_disclaimed_id, 'pga_code_array', 'pga_code_array must have values of FD2' 
	FROM preftz.fed_parts_disclaimed fr 
	WHERE fr.fed_status = 'AUDITING' AND fr.pga_code_array NOT LIKE '%FD2%';

    UPDATE preftz.fed_parts_disclaimed 
    SET pga_code_array = 'FD2'
    WHERE fed_status = 'AUDITING'
    AND pga_code_array LIKE '%FD2%';

    --------------------------------------------------------------------------------------------------------
    -- find records where key is pointing to multiple records in the table.  
    -- This is a data integrity issue and will be flagged as an error.
    INSERT INTO preftz.feed_errors
    (
        table_name,
        tableid,
        field_name,
        error_type
    )
    SELECT
        v_table_name,
        d.parts_disclaimed_id,
        'duplicate_key',
        'duplicate disclaimed-part key'
    FROM
    (
        SELECT
            fr.parts_disclaimed_id,
            COUNT(*) OVER
            (
                PARTITION BY
                    fr.part_number,
                    REPLACE(fr.hts, '.', ''),
                    fr.mid_key,
                    fr.coo_iso,
                    fr.government_agency_code,
                    fr.government_agency_processing_code,
                    fr.government_agency_program_code,
                    fr.intended_use_code,
                    fr.entity_role_code
            ) AS duplicate_count
        FROM preftz.fed_parts_disclaimed fr
        WHERE fr.fed_status = 'AUDITING'
          AND fr.pga_code_array = 'FD2'
    ) d
    WHERE d.duplicate_count > 1;

    --------------------------------------------------------------------------------------------------------
    --set fed_status to ERROR
     UPDATE preftz.fed_parts_disclaimed fr
     SET fed_status = 'ERROR'
     FROM preftz.feed_errors fe
     WHERE fe.table_name = v_table_name
       AND fe.tableid = fr.parts_disclaimed_id
       AND fr.fed_status = 'AUDITING';


--------------------------------------------------------------------------------------------
/*
 * Reject an update when the existing target field contains
 * a value but the incoming feed field is NULL or empty.
 */
FOR crs IN
    SELECT fr.*
    FROM preftz.fed_parts_disclaimed fr
    WHERE fr.fed_status = 'AUDITING'
LOOP
    INSERT INTO preftz.feed_errors
    (
        table_name,
        tableid,
        field_name,
        error_type
    )
    SELECT DISTINCT
        v_table_name,
        crs.parts_disclaimed_id,
        fld.field_name,
        'Existing parts_disclaimed.'
            || fld.field_name
            || ' contains a value, but the feed value is NULL or empty'
    FROM preftz.parts_disclaimed pd

    CROSS JOIN LATERAL
    (
        VALUES
            ('pga_code_array',
             pd.pga_code_array::text,
             crs.pga_code_array::text),

            ('vendor_id',
             pd.vendor_id::text,
             crs.vendor_id::text),

            ('disclaimer',
             pd.disclaimer::text,
             crs.disclaimer::text),

            ('item_type',
             pd.item_type::text,
             crs.item_type::text),

            ('product_code_qualifier',
             pd.product_code_qualifier::text,
             crs.product_code_qualifier::text),

            ('product_code_number',
             pd.product_code_number::text,
             crs.product_code_number::text),

            ('source_type_code',
             pd.source_type_code::text,
             crs.source_type_code::text),

            ('country_code',
             pd.country_code::text,
             crs.country_code::text),

            ('trade_name_brand_name',
             pd.trade_name_brand_name::text,
             crs.trade_name_brand_name::text),

            ('commodity_characteristic_description',
             pd.commodity_characteristic_description::text,
             crs.commodity_characteristic_description::text),

            ('entity_identification_code',
             pd.entity_identification_code::text,
             crs.entity_identification_code::text),

            ('enitity_number',
             pd.enitity_number::text,
             crs.enitity_number::text),

            ('entity_name',
             pd.entity_name::text,
             crs.entity_name::text),

            ('entity_address_1',
             pd.entity_address_1::text,
             crs.entity_address_1::text),

            ('entity_address_2',
             pd.entity_address_2::text,
             crs.entity_address_2::text),

            ('entity_apartment_number_suite_number',
             pd.entity_apartment_number_suite_number::text,
             crs.entity_apartment_number_suite_number::text),

            ('entity_city',
             pd.entity_city::text,
             crs.entity_city::text),

            ('entity_state_province',
             pd.entity_state_province::text,
             crs.entity_state_province::text),

            ('entity_country',
             pd.entity_country::text,
             crs.entity_country::text),

            ('entity_zip_postal_code',
             pd.entity_zip_postal_code::text,
             crs.entity_zip_postal_code::text),

            ('individual_qualifier',
             pd.individual_qualifier::text,
             crs.individual_qualifier::text),

            ('individual_name',
             pd.individual_name::text,
             crs.individual_name::text),

            ('telephone_number_of_the_individual',
             pd.telephone_number_of_the_individual::text,
             crs.telephone_number_of_the_individual::text),

            ('email_address_for_the_individual',
             pd.email_address_for_the_individual::text,
             crs.email_address_for_the_individual::text),

            ('affirmation_of_compliance_code',
             pd.affirmation_of_compliance_code::text,
             crs.affirmation_of_compliance_code::text),

            ('affirmation_of_compliance_qualifier',
             pd.affirmation_of_compliance_qualifier::text,
             crs.affirmation_of_compliance_qualifier::text),

            ('remarks_type_code',
             pd.remarks_type_code::text,
             crs.remarks_type_code::text),

            ('remarks_text',
             pd.remarks_text::text,
             crs.remarks_text::text),

            ('temperature_qualifier',
             pd.temperature_qualifier::text,
             crs.temperature_qualifier::text),

            ('lot_number_qualifier',
             pd.lot_number_qualifier::text,
             crs.lot_number_qualifier::text),

            ('lot_number',
             pd.lot_number::text,
             crs.lot_number::text),

            ('pga_line_value',
             pd.pga_line_value::text,
             crs.pga_line_value::text),

            ('packaging_qualifier',
             pd.packaging_qualifier::text,
             crs.packaging_qualifier::text),

            ('quatity',
             pd.quatity::text,
             crs.quatity::text),

            ('unit_of_measure',
             pd.unit_of_measure::text,
             crs.unit_of_measure::text),

            ('container_number1',
             pd.container_number1::text,
             crs.container_number1::text),

            ('container_number2',
             pd.container_number2::text,
             crs.container_number2::text),

            ('container_number3',
             pd.container_number3::text,
             crs.container_number3::text),

            ('anticipated_arrival_information',
             pd.anticipated_arrival_information::text,
             crs.anticipated_arrival_information::text),

            ('anticipated_arrival_date_at_port_of_entry',
             pd.anticipated_arrival_date_at_port_of_entry::text,
             crs.anticipated_arrival_date_at_port_of_entry::text),

            ('anticipated_arrival_time_at_port_of_entry',
             pd.anticipated_arrival_time_at_port_of_entry::text,
             crs.anticipated_arrival_time_at_port_of_entry::text),

            ('inspection_or_arrival_location_code',
             pd.inspection_or_arrival_location_code::text,
             crs.inspection_or_arrival_location_code::text),

            ('insection_or_arival_location',
             pd.insection_or_arival_location::text,
             crs.insection_or_arival_location::text),

            ('additional_information_qualifier_code',
             pd.additional_information_qualifier_code::text,
             crs.additional_information_qualifier_code::text),

            ('additional_information',
             pd.additional_information::text,
             crs.additional_information::text)
    ) AS fld
    (
        field_name,
        existing_value,
        feed_value
    )

    WHERE pd.part_number IS NOT DISTINCT FROM
          crs.part_number

      AND REPLACE(pd.hts, '.', '') IS NOT DISTINCT FROM
          REPLACE(crs.hts, '.', '')

      AND pd.mid_key IS NOT DISTINCT FROM
          crs.mid_key

      AND pd.coo_iso IS NOT DISTINCT FROM
          crs.coo_iso

      AND pd.government_agency_code IS NOT DISTINCT FROM
          crs.government_agency_code

      AND pd.government_agency_processing_code IS NOT DISTINCT FROM
          crs.government_agency_processing_code

      AND pd.government_agency_program_code IS NOT DISTINCT FROM
          crs.government_agency_program_code

      AND pd.intended_use_code IS NOT DISTINCT FROM
          crs.intended_use_code

      AND pd.entity_role_code IS NOT DISTINCT FROM
          crs.entity_role_code

      /*
       * Existing value must contain non-blank data.
       */
      AND NULLIF(
              BTRIM(fld.existing_value),
              ''
          ) IS NOT NULL

      /*
       * Feed value is NULL, empty, or contains only spaces.
       */
      AND NULLIF(
              BTRIM(fld.feed_value),
              ''
          ) IS NULL;
END LOOP;

/*
 * Change feed records containing errors to ERROR.
 */
UPDATE preftz.fed_parts_disclaimed fr
SET fed_status = 'ERROR'
FROM preftz.feed_errors fe
WHERE fe.table_name = v_table_name
  AND fe.tableid = fr.parts_disclaimed_id
  AND fr.fed_status = 'AUDITING';

    --------------------------------------------------------------------------------------------------------

/*
 * Each matching key must contain exactly five records:
 * one MF, one DEQ, one FD1, one DP, and one PK.
 */
FOR crs IN
    SELECT fr.*
    FROM preftz.fed_parts_disclaimed fr
    WHERE fr.fed_status = 'AUDITING'
LOOP
    SELECT
        COUNT(*) AS total_count,

        COUNT
        (
            CASE
                WHEN fr.entity_role_code = 'MF' THEN 1
            END
        ) AS mf_count,

        COUNT
        (
            CASE
                WHEN fr.entity_role_code = 'DEQ' THEN 1
            END
        ) AS deq_count,

        COUNT
        (
            CASE
                WHEN fr.entity_role_code = 'FD1' THEN 1
            END
        ) AS fd1_count,

        COUNT
        (
            CASE
                WHEN fr.entity_role_code = 'DP' THEN 1
            END
        ) AS dp_count,

        COUNT
        (
            CASE
                WHEN fr.entity_role_code = 'PK' THEN 1
            END
        ) AS pk_count

    INTO v_role_counts
    FROM preftz.fed_parts_disclaimed fr
    WHERE fr.fed_status = 'AUDITING'

      AND fr.part_number IS NOT DISTINCT FROM
          crs.part_number

      AND REPLACE(fr.hts, '.', '') IS NOT DISTINCT FROM
          REPLACE(crs.hts, '.', '')          

      AND fr.mid_key IS NOT DISTINCT FROM
          crs.mid_key

      AND fr.coo_iso IS NOT DISTINCT FROM
          crs.coo_iso

      AND fr.government_agency_code IS NOT DISTINCT FROM
          crs.government_agency_code

      AND fr.government_agency_processing_code IS NOT DISTINCT FROM
          crs.government_agency_processing_code

      AND fr.government_agency_program_code IS NOT DISTINCT FROM
          crs.government_agency_program_code

      AND fr.intended_use_code IS NOT DISTINCT FROM
          crs.intended_use_code;

    IF v_role_counts.total_count <> 5
       OR v_role_counts.mf_count  <> 1
       OR v_role_counts.deq_count <> 1
       OR v_role_counts.fd1_count <> 1
       OR v_role_counts.dp_count  <> 1
       OR v_role_counts.pk_count  <> 1
    THEN
        INSERT INTO preftz.feed_errors
        (
            table_name,
            tableid,
            field_name,
            error_type
        )
        VALUES
        (
            v_table_name,
            crs.parts_disclaimed_id,
            'entity_role_code',
            FORMAT(
                'Expected exactly 5 records. '
                --|| 'MF=1, DEQ=1, FD1=1, DP=1, PK=1. '
                || 'Found total=%s, MF=%s, DEQ=%s, '
                || 'FD1=%s, DP=%s, PK=%s',
                v_role_counts.total_count,
                v_role_counts.mf_count,
                v_role_counts.deq_count,
                v_role_counts.fd1_count,
                v_role_counts.dp_count,
                v_role_counts.pk_count
            )
        );
    END IF;
END LOOP;

    --set fed_status to ERROR
     UPDATE preftz.fed_parts_disclaimed fr
     SET fed_status = 'ERROR'
     FROM preftz.feed_errors fe
     WHERE fe.table_name = v_table_name
       AND fe.tableid = fr.parts_disclaimed_id
       AND fr.fed_status = 'AUDITING';


/*
 * Delete the existing target record only for valid
 * non-error feed records. The replacement record will
 * be inserted afterward.
 */
DELETE FROM preftz.parts_disclaimed pd
USING preftz.fed_parts_disclaimed fr
WHERE fr.fed_status = 'AUDITING'

  AND pd.part_number IS NOT DISTINCT FROM
      fr.part_number

  AND REPLACE(pd.hts, '.', '') IS NOT DISTINCT FROM
      REPLACE(fr.hts, '.', '')

  AND pd.mid_key IS NOT DISTINCT FROM
      fr.mid_key

  AND pd.coo_iso IS NOT DISTINCT FROM
      fr.coo_iso

  AND pd.government_agency_code IS NOT DISTINCT FROM
      fr.government_agency_code

  AND pd.government_agency_processing_code IS NOT DISTINCT FROM
      fr.government_agency_processing_code

  AND pd.government_agency_program_code IS NOT DISTINCT FROM
      fr.government_agency_program_code

  AND pd.intended_use_code IS NOT DISTINCT FROM
      fr.intended_use_code

  AND pd.entity_role_code IS NOT DISTINCT FROM
      fr.entity_role_code;


-- Insert disclaimed
    INSERT INTO preftz.parts_disclaimed
    (
     parts_disclaimed_id,   
     part_number, pga_code_array, hts, mid_key, vendor_id, coo_iso, government_agency_code, government_agency_program_code, government_agency_processing_code,
     intended_use_code, disclaimer, item_type, product_code_qualifier, product_code_number, source_type_code, country_code, trade_name_brand_name, 
     commodity_characteristic_description, entity_role_code, entity_identification_code, enitity_number, entity_name, entity_address_1, entity_address_2,
     entity_apartment_number_suite_number, entity_city, entity_state_province, entity_country, entity_zip_postal_code, individual_qualifier, individual_name, 
     telephone_number_of_the_individual, email_address_for_the_individual, affirmation_of_compliance_code, affirmation_of_compliance_qualifier, remarks_type_code, 
     remarks_text, temperature_qualifier, lot_number_qualifier, lot_number, pga_line_value, packaging_qualifier, quatity, unit_of_measure, container_number1, 
     container_number2, container_number3, anticipated_arrival_information, anticipated_arrival_date_at_port_of_entry, anticipated_arrival_time_at_port_of_entry,
    inspection_or_arrival_location_code, insection_or_arival_location, additional_information_qualifier_code, additional_information
    )
    SELECT 
    parts_disclaimed_id,
    part_number, pga_code_array, replace(hts, '.', '') as hts , mid_key, vendor_id, coo_iso, government_agency_code, government_agency_program_code, 
    government_agency_processing_code, intended_use_code, disclaimer, item_type, product_code_qualifier, product_code_number, source_type_code, country_code, 
    trade_name_brand_name, commodity_characteristic_description, entity_role_code, entity_identification_code, enitity_number, entity_name, entity_address_1, 
    entity_address_2, entity_apartment_number_suite_number, entity_city, entity_state_province, entity_country, entity_zip_postal_code, individual_qualifier, 
    individual_name, telephone_number_of_the_individual, email_address_for_the_individual, affirmation_of_compliance_code, affirmation_of_compliance_qualifier, 
    remarks_type_code, remarks_text, temperature_qualifier, NULLIF(lot_number_qualifier,''), NULLIF(lot_number,''), pga_line_value, packaging_qualifier, quatity,  
    unit_of_measure, container_number1, container_number2, container_number3, anticipated_arrival_information, anticipated_arrival_date_at_port_of_entry, 
    anticipated_arrival_time_at_port_of_entry, inspection_or_arrival_location_code, insection_or_arival_location, additional_information_qualifier_code, 
    additional_information
    FROM preftz.fed_parts_disclaimed
    WHERE fed_status = 'AUDITING';

    --record statistics
     INSERT INTO preftz.system_log
     (
         procedure_name,
         log_message
     )
     SELECT
         'audit_fed_parts_disclaimed',
         CASE fed_status
             WHEN 'AUDITING'  THEN 'IMPORTED'
             WHEN 'PROCESSED' THEN 'REVERSAL'
             ELSE fed_status
         END
         || ': '
         || COUNT(*)::text
     FROM preftz.fed_parts_disclaimed
     GROUP BY fed_status;

    --delete all non-ERROR records 	
    DELETE FROM preftz.fed_parts_disclaimed fr 	 WHERE fr.fed_status = 'AUDITING';


    INSERT INTO preftz.system_log (procedure_name, log_message)
    VALUES ('audit_fed_parts_disclaimed', 'finished');
END;
$BODY$;




