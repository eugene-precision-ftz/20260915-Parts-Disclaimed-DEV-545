-- DROP FUNCTION preftz.audit_e214_data(varchar);

CREATE OR REPLACE FUNCTION preftz.audit_e214_data(p_admission_number character varying)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$  	
   	
--Change Log: 
--MH 7/29/2026 changed pre-receipt message NONMATCHINGPREREC
--EG 7/13/2026 message changed
--EG 4/7/2026 auto delete pre-receipts DEV-257
--MH 10/9/2025 not include adjustments in conveyance not found
--MH 6/24/2025B removed pre-receipts criteria
--MH 6/24/2025 audit conveyance id exists	
--MH 7/9/2024 added BOL to audit message for no carriers present 	
--MH 7/8/2024 added audits if there are no carriers present  	
--MH 1/3/2024 new code to show fed receipts  	
--MH 9/28/2023 ADD EDITWN1 action code to update wn1 table   	
--NKM 06/20/2023 Changed hts_units to a materialized view   	
--NKM 02/10/2023 revised audit for conveyance records with the same vehicle but mismatched dates   	
--NKM 11/17/2022 added audit for conveyance records with the same vehicle but mismatched dates   	
--NKM 05/18/2022 added audit for port of unlading   	
--NKM 05/03/2022 added audit to prevent mix of pre_receipt and regular receipts on the same admission   	
--JMM 04/06/2022 added COALESCE for port code audit   	
--NKM 03/31/2022 now uses location_port_code for arriving in-bonds   	
--NKM 03/28/2022 conveyance not required for receipts with bol proxy = 'ADJUSTMENT'   	
--NKM 03/24/2022 add audit to prevent mixed ZTZ/non-ZTZ receipts on same conveyance   	
--NKM 03/24/2022 bugfix: add audit for assigned receipts without a valid conveyance   	
--RTJ 11/08/2021 refine audit for unprocessed receipt data   	
--NKM 09/14/2021 add audit for unprocessed receipt edits   	
--RTJ 08/11/2021 add action_code to data_audit_messages   	
--RTJ 08/08/2021 automatically add reason code '10' if replacing temporary deposit   	
--               add audit for missing E214 contact record   	
--               add audit for records in fed_receipts table   	
   	
--RTJ 06/30/2021 account for  vessel departure port, country of export, import date   	
--               and export date on conveyances record   	
--NKM 06/24/2021 Added validation of inbond_number   	
--RTJ 06/21/2021 check for reason code / remarks for replacement 214   	
--RTJ 05/06/2021 audit for depart date not prior to arrival date   	
--RTJ 03/23/2021 account for '' in HTS UOM   	
--RTJ 03/05/2021 add receipt/classification data for foreign up adjusts   	
--               add airport code updates from master table   	
--RTJ 01/06/2021 include truck conveyances in carrier country audit   	
--NKM 01/05/2021 added audit for ocean depart_date   	
--RTJ 10/17/2020 removed audit for arrival_date_offset;    	
--               using arrival date for export date for air shipments   	
--RTJ 11/15/2020 add port code updates from master table   	
--               account for zero quantity receipts   	
   	
DECLARE   	
  audit_result       VARCHAR(10);  --FAIL or PASS   	
  ars                RECORD;   	
  rcpt_e214_status   VARCHAR(1);   	
  adj_e214_status    VARCHAR(1);   	
  classif_audit      VARCHAR(10);   	
  messageid_count    INTEGER;   	
  v_location_port_code VARCHAR(4); --NKM 06/24/2021   	

BEGIN   	
  INSERT INTO preftz.system_log (procedure_name, log_message)    	
  VALUES ('audit_e214_data', 'started: ' || p_admission_number);   	
   	
  REFRESH MATERIALIZED VIEW preftz.hts_units; --NKM 06/20/2023   	
  
 --EG 4/7/2026 use loacal view so no need to use selected_bols_for_214 
  
  DROP TABLE IF EXISTS selected_bols_for_214_tmp CASCADE;

  CREATE TEMPORARY TABLE selected_bols_for_214_tmp AS
  SELECT DISTINCT c.bill_of_lading_airwaybill
  FROM preftz.conveyances c
  WHERE c.zone_admission_no = p_admission_number;

  
  CREATE OR REPLACE TEMPORARY VIEW ams_response_union_tmp_view AS
  SELECT wr1.carrier_code, wr1.voyage_flight_trip_number, wsc.air_waybill_number bill_of_lading, 
         wsc.house_air_waybill_number house_bill, TO_DATE(wr1.date_of_arrival,'mmddyy') arrival_date,
         TO_DATE(wsc.scheduled_arrival_date,'mmddyy') scheduled_arrival_date, 
         TO_NUMBER(CASE
                   WHEN wsc.house_air_waybill_number = '' THEN COALESCE(NULLIF(wsc.boarded_quantity_master, ''), wsc.manifest_quantity_master)
                   ELSE
                        CASE wsc.part_indicator_house
                        WHEN '' THEN wsc.manifest_quantity_house
                        ELSE wsc.boarded_quantity_house
                        END
                   END, '99999999') AS manifest_quantity,
         '40' mode_of_transportation, 
         COALESCE(NULLIF(wnib1.actual_port_of_unlading,''), 
                  NULLIF(wnib1.manifested_port_of_unlading,'')) port_of_unlading,        
         wsc.part_indicator_house, NULL importing_vessel_code,
         NULL vessel_departure_port, NULL depart_date, wr1.wr1id
    FROM preftz.wr1 wr1 INNER JOIN preftz.wsc wsc ON wr1.wr1id = wsc.wr1id 
                        INNER JOIN selected_bols_for_214_tmp b 
                                ON b.bill_of_lading_airwaybill = wsc.air_waybill_number
                         LEFT JOIN (SELECT wn1.* FROM (SELECT wr1id, min(wn1id) wn1id 
                                                         FROM preftz.wn1 
                                                        GROUP BY wr1id) AS ib1 --First WN1 record is most recent in-bond
                                                 JOIN preftz.wn1 ON wn1.wn1id=ib1.wn1id) AS wnib1
                                ON wr1.wr1id = wnib1.wr1id
  UNION ALL
  SELECT wr1.carrier_code, wr1.voyage_flight_trip_number, 
         wr4.issuer_code_of_master_bill_number || wr4.master_bill_number bill_of_lading, NULL house_bill, --NKM 04/28/2023
         TO_DATE(wr1.date_of_arrival,'mmddyy') arrival_date, NULL scheduled_arrival_date,
         TO_NUMBER(wr4.manifest_quantity,'99999999') manifest_quantity, 
         wr4.mode_of_transportation_code || '1' mode_of_transportation, 
         COALESCE(NULLIF(wnib1.ocean_vessel_diversion_port,''), 
                  NULLIF(wnib1.actual_port_of_unlading,''), 
                  NULLIF(wnib1.manifested_port_of_unlading,'')) port_of_unlading,
         NULL part_indicator_house, wr1.importing_vessel_code,  wnib1.vessel_departure_port, 
         CASE WHEN wnib1.vessel_departure_date = ''
              THEN NULL ELSE TO_DATE(wnib1.vessel_departure_date,'mmddyy') END depart_date, 
         wr1.wr1id
    FROM preftz.wr1 wr1 INNER JOIN preftz.wr4 wr4 ON wr1.wr1id = wr4.wr1id
                        INNER JOIN selected_bols_for_214_tmp b
                        ON b.bill_of_lading_airwaybill = wr4.issuer_code_of_master_bill_number || wr4.master_bill_number --NKM 04/28/2023
                         LEFT JOIN (SELECT wn1.* FROM (SELECT wr1id, min(wn1id) wn1id 
                                                         FROM preftz.wn1 
                                                        GROUP BY wr1id) AS ib1 --First WN1 record is most recent in-bond
                                                 JOIN preftz.wn1 ON wn1.wn1id=ib1.wn1id) AS wnib1
                                ON wr1.wr1id = wnib1.wr1id;
--EG 4/7/2026


  DELETE FROM preftz.data_audit_messages d   	
   WHERE d.audit_document = p_admission_number;   	
      	
  audit_result = 'PASS';   	
     	
  SELECT MAX(r.zone_status)   	
    INTO rcpt_e214_status   	
    FROM preftz.receipts r   	
   WHERE r.zone_admission_no = p_admission_number   	
     AND r.quantity > 0;  --RTJ 11/15/2020   	
      	
  SELECT MAX(r.zone_status)   	
    INTO adj_e214_status   	
    FROM preftz.inventory_items ii   	
         INNER JOIN preftz.adjustment_zone_admission_nos a   	
                 ON ii.itemid = a.itemid   	
         INNER JOIN preftz.receipts r   	
                 ON ii.receiptid = r.receiptid   	
   WHERE ii.adjustid > 0   	
     AND a.zone_admission_no = p_admission_number;   	
      	
  IF COALESCE(rcpt_e214_status,'D') = 'D' AND COALESCE(adj_e214_status,'D') = 'D' THEN   	
      INSERT INTO preftz.data_audit_messages   	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
          VALUES (p_admission_number,    	
                 'No foreign status inventory on 214 ' || p_admission_number,'');  --RTJ 08/11/2021   	
      audit_result = 'DOMESTIC';   	
   	
  ELSE   	
      --NKM 03/24/2022 assure conveyance does not have both ztz and standard receipts   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)   	
      SELECT DISTINCT p_admission_number,    	
             'A conveyance can not have both zone-to-zone transfer and regular receipts',   	
             'CONTSUPRT'   	
        FROM (SELECT r.conveyanceid   	
                FROM preftz.receipts r   	
               INNER JOIN preftz.conveyances c   	
                       ON c.conveyanceid = r.conveyanceid   	
               WHERE COALESCE(r.zone_admission_no,'') = p_admission_number   	
               GROUP BY r.conveyanceid   	
              HAVING COUNT(DISTINCT COALESCE(r.zone_to_zone_transfer,'N')) > 1) mixed;   	
      --NKM 03/24/2022 assure conveyance does not have both ztz and standard receipts  	
   	
   	
     -- MH 6/24/2025 BEGIN not allow receipts that are linked to conveyance that not longer exists	
   IF EXISTS(	
   select DISTINCT rec.conveyanceid from preftz.receipts rec	
   where rec.conveyanceid not in(select cn.conveyanceid from preftz.conveyances cn)	
   and COALESCE(rec.conveyanceid,0) <> 0	
   and rec.zone_admission_no =  p_admission_number	
   and rec.zone_status <> 'D'
   and rec.cloned_from_receiptid is null) THEN	 --MH 10/9/2025 not include adjustments
   	
         INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)	
     VALUES(p_admission_number,	
        'Conveyance cannot be found',	
        'CONTSUPRT');	
   	
   	
   END IF;	
    -- MH 6/24/2025 END not allow receipts that are linked to conveyance that not longer exists	
   	
   	
      --NKM 09/14/2021/RTJ 11/08/2021 check for assigned receipts that have not been processed   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)   	
      SELECT DISTINCT p_admission_number,    	
             'There are unprocessed receipts affecting this zone admission number',   	
             'EDITFEDRCPT' --MH 1/3/2024 new code to show fed receipts  	
        FROM preftz.fed_receipts fr   	
             LEFT JOIN preftz.receipts r ON fr.receiptid = r.receiptid   	
       WHERE COALESCE(fr.zone_admission_no,'') = p_admission_number   	
          OR COALESCE(r.zone_admission_no,'') = p_admission_number;   	
      --NKM 09/14/2021/RTJ 11/08/2021   	
      
      --EG 4/7/2026      
      --NKM 05/03/2022 check for mix of regular and pre_receipts   	
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'NO') 
    THEN 
      
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)   	
      SELECT p_admission_number,    	
             'This admission can not be filed because it contains both regular receipts and pre_receipts',   	
             'EDITRCPT'   	
        FROM preftz.receipts r   	
       WHERE r.zone_admission_no = p_admission_number
      HAVING COUNT(DISTINCT COALESCE(r.pre_receipt,FALSE)) > 1;
      
    END IF;
      --NKM 05/03/2022
      
   	
     --EG 4/7/2026
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK_CONCUR')
    THEN 
       IF  (preftz.check_prereceipt_zone_admission_no(p_admission_number) <> 'NA')
       AND (preftz.check_prereceipt_zone_admission_no(p_admission_number) <> 'PASS')
       THEN
        INSERT INTO preftz.data_audit_messages
                   (audit_document, audit_message, action_code)
        SELECT p_admission_number,
               'Pre-receipts are authorized; however, the corresponding actual receipts have not been fully received.',--EG 7/13/2026
               'NONMATCHINGPREREC';
       END IF;
    END IF;     
     

      --NKM 03/24/2022 check for receipts with no valid conveyance (e.g. conveyance in fed table)   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)   	
      SELECT DISTINCT p_admission_number,    	
             'This admission has receipts using BOL Proxy: ' || COALESCE(r.bill_of_lading_proxy,'NO PROXY') ||     	
             ' which are not linked to a validated conveyance', 'CONTSUPRT'   	
        FROM preftz.fed_receipts r   	
             LEFT JOIN preftz.conveyances c ON c.conveyanceid = r.conveyanceid   	
       WHERE c.conveyanceid IS NULL   	
         AND r.zone_admission_no = p_admission_number   	
         AND r.bill_of_lading_proxy <> 'ADJUSTMENT'; --NKM 03/28/2022   	
      --NKM 03/24/2022   	
   	
      --no ams response data   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,    	
             'No AMS response for BOL: ' || c.bill_of_lading_airwaybill ||   	
             ' HBOL: ' || COALESCE(c.house_bill,'NONE'),'CONTSUPRT'  --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             LEFT JOIN ams_response_union_tmp_view au   	
                    ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
                   AND COALESCE(c.house_bill,'') = COALESCE(au.house_bill,'')   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
         AND au.bill_of_lading IS NULL;   	
                           	
       --the following in-bond audits are redundant with audits performed in audit_fed_conveyances   	
       --AMS response exists, but inbond number is not associated with BOL in AMS --NKM 06/24/2021   	
       INSERT INTO preftz.data_audit_messages    	
                  (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
       SELECT DISTINCT p_admission_number,    	
              CASE WHEN c.house_bill IS NULL   	
              THEN 'AMS does not report BOL ' || c.bill_of_lading_airwaybill ||    	
                   ' is covered by inbond ' || c.inbond_number   	
              ELSE   	
                   'AMS does not report BOL/HBOL ' || c.bill_of_lading_airwaybill || '/' || c.house_bill ||   	
                   ' is covered by inbond ' || c.inbond_number   	
              END, 'CONTSUPRT'  --RTJ 08/11/2021   	
         FROM preftz.conveyances c   	
              INNER JOIN preftz.receipts r   	
                      ON c.conveyanceid = r.conveyanceid   	
              INNER JOIN ams_response_union_tmp_view au   	
                      ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
                     AND COALESCE(c.house_bill,'') = COALESCE(au.house_bill,'')   	
                     AND COALESCE(c.house_bill_partial_indicator,'') = COALESCE(au.part_indicator_house,'')   	
               LEFT JOIN preftz.wn1   	
                      ON wn1.wr1id = au.wr1id   	
                     AND wn1.inbond_entry_number = c.inbond_number   	
        WHERE c.zone_admission_no = p_admission_number   	
          AND r.zone_status <>'D'   	
          AND r.quantity > 0  --RTJ 11/15/2020   	
          AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
          AND COALESCE(c.inbond_number,'NONE')<>'NONE' --do not perform if inbond is NULL OR 'NONE'   	
          AND wn1.inbond_entry_number IS NULL;   	
    	
       --Get FTZ port --NKM 06/24/2021   	
       SELECT location_port_code   	
         INTO v_location_port_code   	
         FROM preftz.ftz_reference;   	
         
--EG 4/7/2026
/*
       --inbond is associated with BOL, but inbond is not bound for FTZ port --NKM 06/24/2021   	
       INSERT INTO preftz.data_audit_messages    	
                  (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
       SELECT DISTINCT p_admission_number,    	
              'AMS reports inbond ' || c.inbond_number || ' is not bound for port ' || v_location_port_code,   	
              'CONTSUPRT'  --RTJ 08/11/2021   	
         FROM preftz.conveyances c   	
              INNER JOIN preftz.receipts r   	
                      ON c.conveyanceid = r.conveyanceid   	
              INNER JOIN ams_response_union_tmp_view au   	
                      ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
                     AND COALESCE(c.house_bill,'') = COALESCE(au.house_bill,'')   	
                     AND COALESCE(c.house_bill_partial_indicator,'') = COALESCE(au.part_indicator_house,'')   	
              INNER JOIN preftz.wn1   	
                      ON wn1.wr1id = au.wr1id   	
                     AND wn1.inbond_entry_number = c.inbond_number   	
               LEFT JOIN preftz.inbond_status ibs ON ibs.bill_of_lading_airwaybill = c.bill_of_lading_airwaybill   	
                     AND ibs.house_bill = COALESCE(c.house_bill,'')   	
                     AND ibs.house_bill_partial_indicator = COALESCE(c.house_bill_partial_indicator,'')   	
                     AND ibs.inbond_number = c.inbond_number   	
        WHERE c.zone_admission_no = p_admission_number   	
          AND r.zone_status <>'D'   	
          AND r.quantity > 0  --RTJ 11/15/2020   	
          AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
          AND COALESCE(c.inbond_number,'NONE')<>'NONE' --do not perform if inbond is NULL OR 'NONE'   	
          AND wn1.inbond_entry_number IS NOT NULL   	
          AND COALESCE(ibs.inbond_arrival_port,'') <> v_location_port_code;   	
*/
   	
      --RTJ 11/15/2020   	
      --pull new port codes from master data   	
      INSERT INTO preftz.port_codes   	
            (port_code, port_name, port_country, harbor_maintenance_fee_required)   	
      SELECT DISTINCT pcm.port_code, pcm.port_name, pcm.port_country, pcm.harbor_maintenance_fee_required   	
        FROM prehts.port_codes_master pcm   	
             INNER JOIN ams_response_union_tmp_view au   	
                     ON au.vessel_departure_port = pcm.port_code   	
              LEFT JOIN preftz.port_codes pc   	
                     ON au.vessel_departure_port = pc.port_code   	
       WHERE pc.port_code IS NULL;   	
           	
      INSERT INTO preftz.port_codes   	
            (port_code, port_name, port_country, harbor_maintenance_fee_required)   	
      SELECT DISTINCT pcm.port_code, pcm.port_name, pcm.port_country, pcm.harbor_maintenance_fee_required   	
        FROM prehts.port_codes_master pcm   	
             INNER JOIN ams_response_union_tmp_view au   	
                     ON au.port_of_unlading = pcm.port_code   	
              LEFT JOIN preftz.port_codes pc   	
                     ON au.port_of_unlading = pc.port_code   	
       WHERE pc.port_code IS NULL;   	
      --RTJ 11/15/2020     	
       	
      --RTJ 03/05/2021 pull new airport codes from master data   	
      INSERT INTO preftz.port_codes   	
            (port_code, port_name, port_country, harbor_maintenance_fee_required)   	
      SELECT DISTINCT pcm.port_code, pcm.port_name, pcm.port_country, pcm.harbor_maintenance_fee_required   	
        FROM ams_response_union_tmp_view au   	
             INNER JOIN preftz.flight_reference f   	
                     ON au.carrier_code = f.carrier_code   	
                    AND au.voyage_flight_trip_number = f.flight_number   	
             INNER JOIN prehts.port_codes_master pcm   	
                     ON f.departure_port_code = pcm.port_code   	
              LEFT JOIN preftz.port_codes pc   	
                     ON f.departure_port_code = pc.port_code   	
       WHERE pc.port_code IS NULL;   	
      	
  	
	
      	
    -- MH 7/9/2024 added to allow for no carriers and not just null fields   	
   	
       	
   INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message,action_code) 	
      	
 select DISTINCT p_admission_number ,'Required Carriers are missing for BOL ' ||  COALESCE(c.bill_of_lading_airwaybill,'None Listed'), 'EDADCAR'   	
       FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             LEFT JOIN ams_response_union_tmp_view au   	
                     ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
                    AND COALESCE(c.house_bill,'') = COALESCE(au.house_bill,'')   	
    LEFT JOIN preftz.carriers cr   	
                     ON au.carrier_code = cr.carrier_code   	
     WHERE c.zone_admission_no = p_admission_number  	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
        -- AND LEFT(au.mode_of_transportation,1) IN ('1','2','3','4')  	
   AND cr.carrier_code is null; 	
  	
       	
   	
      	
      	
      	
      --RTJ 03/05/2021     	
      --ocean departure port code   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,    	
             'Country data missing or invalid for Port Code: ' || COALESCE(au.vessel_departure_port,'None listed in AMS'),   	
             'EDADPORT'  --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN ams_response_union_tmp_view  au   	
                     ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
              LEFT JOIN preftz.port_codes pc   	
                     ON au.vessel_departure_port = pc.port_code   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
         AND au.mode_of_transportation LIKE '1%'   	
         AND COALESCE(pc.port_country,'US') = 'US'   	
         AND COALESCE(c.country_of_export,'') = '';  --RTJ 06/30/2021   	
   	
      --ocean departure depart_date --NKM 01/05/2021   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,    	
             'Missing vessel departure date for ocean BOL: ' || au.bill_of_lading,   	
             'RESETCONV'  --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN ams_response_union_tmp_view  au   	
                     ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
         AND au.mode_of_transportation LIKE '1%'   	
         AND au.depart_date IS NULL   	
         AND c.export_date IS NULL;  --RTJ 06/30/2021   	
                           	
      --ocean arrival_date prior to depart_date --RTJ 05/06/2021   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,    	
             'Arrival date prior to departure date for BOL: ' || au.bill_of_lading,   	
             'RESETCONV'  --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN ams_response_union_tmp_view  au   	
                     ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
         AND au.mode_of_transportation LIKE '1%'   	
         AND au.arrival_date < au.depart_date   	
         AND c.export_date IS NULL    	
         AND c.import_date IS NULL;  --RTJ 06/30/2021   	
                           	
      --ocean arrival port code   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,    	
             'Port data missing for Port Code: ' || COALESCE(au.port_of_unlading, 'None listed in AMS'),   	
             'EDADPORT'  --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN ams_response_union_tmp_view  au   	
                     ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
              LEFT JOIN preftz.port_codes pc   	
                     ON au.port_of_unlading = pc.port_code   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
         AND au.mode_of_transportation LIKE '1%'   	
         AND pc.port_code IS NULL;   	
   	
      --port of unlading --NKM 05/18/2022   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code,audit_reference)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,    	
             'Port of unlading missing for Conveyance: ' || CONCAT_WS('/',au.bill_of_lading,au.house_bill),   	
             'EDITWN1',  --RTJ 08/11/2021 --- MH 9/28/2023  changed action code from contact support ot EDITWN1   	
 au.wr1id -- MH 9/28/2023 added to update manifest import port code   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN ams_response_union_tmp_view  au   	
                     ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
         AND COALESCE(au.port_of_unlading,'') = '';   	
                           	
      --carrier name (non-ocean)   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,    	
             'Carrier Name missing for Carrier Code: ' || au.carrier_code,'EDADCAR'  --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN ams_response_union_tmp_view au   	
                     ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
                    AND COALESCE(c.house_bill,'') = COALESCE(au.house_bill,'')   	
              LEFT JOIN preftz.carriers cr   	
                     ON au.carrier_code = cr.carrier_code   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
         AND au.mode_of_transportation NOT LIKE '1%'   	
         AND cr.carrier_name IS NULL;   	
             	
      --carrier country (rail/truck)   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,    	
             'Carrier Country missing for Carrier Code: ' || au.carrier_code,'EDADCAR' --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN ams_response_union_tmp_view au   	
                     ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
                    AND COALESCE(c.house_bill,'') = COALESCE(au.house_bill,'')   	
              LEFT JOIN preftz.carriers cr   	
                     ON au.carrier_code = cr.carrier_code   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
         AND LEFT(au.mode_of_transportation,1) IN ('2','3')  --RTJ 01/06/2021   	
         AND cr.carrier_country IS NULL   	
         AND COALESCE(c.country_of_export,'') = '';  --RTJ 06/30/2021   	
             	
      --flight reference data   	
      --NOTE: flight reference data is not used when the CoE is on the conveyance record     	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,    	
             'Flight data missing for Carrier Code: ' || au.carrier_code ||   	
             ' Flight Number: ' || au.voyage_flight_trip_number,'ADDFLIG'  --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN ams_response_union_tmp_view au   	
                     ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
                    AND c.house_bill = au.house_bill   	
              LEFT JOIN preftz.flight_reference f   	
                     ON au.carrier_code = f.carrier_code   	
                    AND au.voyage_flight_trip_number = f.flight_number   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
         AND au.mode_of_transportation LIKE '4%'   	
         AND f.departure_port_code IS NULL   	
         AND COALESCE(c.country_of_export,'') = '';  --RTJ 06/30/2021   	
      --        OR f.arrival_date_offset IS NULL); --RTJ 10/17/2020   	
               	
      --airport code   	
      --NOTE: flight reference data is not used when the CoE is on the conveyance record     	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,    	
             'Country data missing or invalid for Airport Code: ' || f.departure_port_code,   	
             'EDITFLIG'  --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN ams_response_union_tmp_view au   	
                     ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
                    AND c.house_bill = au.house_bill   	
             INNER JOIN preftz.flight_reference f   	
                     ON au.carrier_code = f.carrier_code   	
                    AND au.voyage_flight_trip_number = f.flight_number   	
              LEFT JOIN preftz.port_codes pc   	
                     ON f.departure_port_code = pc.port_code   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
         AND au.mode_of_transportation LIKE '4%'   	
         AND COALESCE(pc.port_country,'US') = 'US'   	
         AND COALESCE(c.country_of_export,'') = '';  --RTJ 06/30/2021   	
         	
      --classify receipts   	
      classif_audit = preftz.classify_receipts(p_admission_number);   	
         	
      IF classif_audit = 'FAIL' THEN audit_result = 'FAIL'; END IF;   	
         	
      --statistical quantity 1   	
      INSERT INTO preftz.data_audit_messages   	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,   	
             'UOM 1 conversion missing for: ' || p.unit_of_measure || ' to: ' ||    	
             h.unit_1 || ' part: ' || r.part_number,'EDITPART'  --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN preftz.receipt_classifications rc   	
                     ON r.receiptid = rc.receiptid   	
             INNER JOIN preftz.hts_units h    	
                     ON rc.harmonized_tariff_schedule_number = h.tariff_number   	
             INNER JOIN preftz.parts p   	
                     ON r.part_number = p.part_number    	
             INNER JOIN preftz.part_classifications pc   	
                     ON p.part_number = pc.part_number   	
                    AND rc.harmonized_tariff_schedule_number = pc.harmonized_tariff_schedule_number   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(h.unit_1,'X') NOT IN ('X','')  --RTJ 03/23/2021   	
         AND COALESCE(pc.quantity1_conversion_rate,0) = 0   	
       GROUP BY p.unit_of_measure, h.unit_1, r.part_number;   	
                    	
      --statistical quantity 2   	
      INSERT INTO preftz.data_audit_messages   	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT DISTINCT p_admission_number,   	
             'UOM 2 conversion missing for: ' || p.unit_of_measure || ' to: ' ||    	
             h.unit_2 || ' part: ' || r.part_number,'EDITPART'  --RTJ 08/11/2021   	
        FROM preftz.conveyances c   	
             INNER JOIN preftz.receipts r   	
                     ON c.conveyanceid = r.conveyanceid   	
             INNER JOIN preftz.receipt_classifications rc   	
                     ON r.receiptid = rc.receiptid   	
             INNER JOIN preftz.hts_units h    	
                     ON rc.harmonized_tariff_schedule_number = h.tariff_number   	
             INNER JOIN preftz.parts p   	
                     ON r.part_number = p.part_number    	
             INNER JOIN preftz.part_classifications pc   	
                     ON p.part_number = pc.part_number   	
                    AND rc.harmonized_tariff_schedule_number = pc.harmonized_tariff_schedule_number   	
       WHERE c.zone_admission_no = p_admission_number   	
         AND r.zone_status <>'D'   	
         AND r.quantity > 0  --RTJ 11/15/2020   	
         AND COALESCE(h.unit_2,'X') NOT IN ('X','')  --RTJ 03/23/2021   	
         AND COALESCE(pc.quantity2_conversion_rate,0) = 0   	
       GROUP BY p.unit_of_measure, h.unit_2, r.part_number;   	
   	
   	
      --NKM 02/10/2023 NKM 11/17/2022 BOLs on the same physical conveyance with mismatched import or export date   	
      WITH dprs AS(--dprs are any duplicate conveyance records that might be created (usually due to inconsistent dates)   	
                   WITH crs AS (--crs is the query used by create_e214 to find conveyances   	
                                SELECT au.carrier_code, au.voyage_flight_trip_number, au.arrival_date,    	
                                       au.mode_of_transportation, au.port_of_unlading, au.depart_date,   	
                                       au.importing_vessel_code, au.scheduled_arrival_date, cr.carrier_name,   	
                                       c.export_date, c.import_date  --RTJ 06/30/2021 / RTJ 07/08/2021 / NKM 03/21/2022   	
                                  FROM preftz.conveyances c   	
                                       INNER JOIN preftz.receipts r    	
                                               ON c.conveyanceid = r.conveyanceid   	
                                       INNER JOIN ams_response_union_tmp_view au    	
                                               ON c.bill_of_lading_airwaybill = au.bill_of_lading   	
                                              AND COALESCE(c.house_bill,'') = COALESCE(au.house_bill,'')   	
                                              AND (   c.house_bill_partial_indicator IS NULL   	
                                                   OR c.house_bill_partial_indicator = au.part_indicator_house)   	
                                        LEFT JOIN preftz.carriers cr   	
                                               ON au.carrier_code = cr.carrier_code   	
                                 WHERE c.zone_admission_no = p_admission_number   	
                                   AND r.zone_status <>'D'   	
                                   AND r.quantity > 0  --RTJ 11/15/2020   	
                                   AND COALESCE(r.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/21/2022   	
                                   AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021   	
                                 GROUP BY au.carrier_code, au.voyage_flight_trip_number, au.arrival_date,    	
                                          au.mode_of_transportation, au.port_of_unlading, au.depart_date,   	
                                          au.importing_vessel_code, au.scheduled_arrival_date, cr.carrier_name,   	
                                          c.export_date, c.import_date)   	
                   SELECT crs.carrier_code,    	
                          CASE WHEN crs.mode_of_transportation LIKE '1%'THEN crs.importing_vessel_code ELSE LEFT(crs.carrier_name,23) END AS conveyance_name,   	
                          crs.voyage_flight_trip_number, crs.export_date, crs.port_of_unlading   	
                     FROM crs   	
                    GROUP BY crs.carrier_code,    	
                          CASE WHEN crs.mode_of_transportation LIKE '1%'THEN crs.importing_vessel_code ELSE LEFT(crs.carrier_name,23) END,   	
                          crs.voyage_flight_trip_number, crs.export_date, crs.port_of_unlading   	
                    HAVING COUNT(*) > 1)   	
      INSERT INTO preftz.data_audit_messages    	
                 (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
      SELECT p_admission_number,    	
             CONCAT('BOL ',au.bill_of_lading,' shares the same physical conveyance (vessel) as another BOL on this admission, ',   	
                    'but the export or import dates on the conveyance records do not match.  ',   	
                    'Enter the date of vessel departure from and arrival at port for the export and import date respectively.'),   	
             'RESETCONV'   	
        --Bills of lading with conveyances with inconsistent dates   	
        FROM dprs, ams_response_union_tmp_view au   	
        LEFT JOIN preftz.carriers cr ON cr.carrier_code = au.carrier_code   	
        WHERE au.carrier_code = dprs.carrier_code   	
          AND (CASE WHEN au.mode_of_transportation LIKE '1%' THEN au.importing_vessel_code ELSE cr.carrier_name END) = dprs.conveyance_name   	
          AND au.voyage_flight_trip_number = dprs.voyage_flight_trip_number   	
          AND au.port_of_unlading = dprs.port_of_unlading;   	
   	
      --EG 4/7/2026   	
      --RTJ 06/21/2021 check for reason code / contact data if 214 has already been filed   	
      IF (SELECT efs.currently_filed FROM preftz.e214_filing_statuses efs   	
           WHERE efs.zone_admission_no = p_admission_number) = 'Y' 
      AND (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') <> 'AUTO_LINK_CONCUR')           
      AND (preftz.check_prereceipt_zone_admission_no(p_admission_number) <> 'PASS')
    
      THEN   	
   	
          --RTJ 08/04/2021 add reason code '10' for replacement of temporary deposit   	
          IF  (SELECT efs.temporary_deposit FROM preftz.e214_filing_statuses efs   	
                WHERE efs.zone_admission_no = p_admission_number) = 'Y'   	
          AND (SELECT COUNT(*) FROM preftz.e214_replace_reasons r   	
                    WHERE r.zone_admission_no = p_admission_number   	
                      AND r.reason_code = '10') = 0  THEN   	
             	
              INSERT INTO preftz.e214_replace_reasons (zone_admission_no, reason_code)   	
              VALUES (p_admission_number, '10');   	
                 	
          END IF;   	
   	
          IF NOT EXISTS (SELECT 'x' FROM preftz.contacts c   	
               WHERE c.contact_type = 'E214') THEN   	
              INSERT INTO preftz.data_audit_messages   	
                     (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
              VALUES (p_admission_number, 'Contact information missing for replacement e214',   	
                      'EDADR214CNTAC');  --RTJ 08/11/2021   	
          END IF;   	
          --RTJ 08/04/2021   	
   	
          IF (SELECT COALESCE(c.contact_name,'') FROM preftz.contacts c   	
               WHERE c.contact_type = 'E214') = '' THEN   	
              INSERT INTO preftz.data_audit_messages   	
                     (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
              VALUES (p_admission_number, 'Contact name missing for replacement e214',   	
                      'EDADR214CNTAC');  --RTJ 08/11/2021   	
          END IF;   	
                  	
          IF (SELECT COALESCE(c.contact_phone,'') FROM preftz.contacts c   	
               WHERE c.contact_type = 'E214') = '' THEN   	
              INSERT INTO preftz.data_audit_messages   	
                     (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
              VALUES (p_admission_number, 'Contact phone number missing for replacement e214',   	
                      'EDADR214CNTAC');  --RTJ 08/11/2021   	
          END IF;   	
   	
          IF (SELECT COUNT(*) FROM preftz.e214_replace_reasons r   	
               WHERE r.zone_admission_no = p_admission_number) = 0 THEN   	
              INSERT INTO preftz.data_audit_messages   	
                     (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
              VALUES (p_admission_number, 'Reason code missing for replacement e214',   	
                      'ADDREPREA');  --RTJ 08/11/2021   	
             	
          ELSE   	
             	
              IF  (SELECT COUNT(*) FROM preftz.e214_replace_reasons r   	
                    WHERE r.zone_admission_no = p_admission_number   	
                      AND r.reason_code = '08') > 0   	
              AND (SELECT COUNT(*) FROM preftz.e214_replace_reasons r   	
                    WHERE r.zone_admission_no = p_admission_number   	
                      AND COALESCE(r.remarks,'') <> '') = 0 THEN   	
                         	
                  INSERT INTO preftz.data_audit_messages   	
                         (audit_document, audit_message, action_code)  --RTJ 08/11/2021   	
                  VALUES (p_admission_number, 'Remarks missing for replace reason code 08',   	
                      'ADDREPREA');  --RTJ 08/11/2021   	
   	
              END IF;  --replace remarks missing   	
          END IF;  --replace reason code missing   	
      END IF;  --e214 previously filed   	
      --RTJ 06/21/2021    	
     	
      SELECT COUNT(*) INTO messageid_count FROM preftz.data_audit_messages d   	
       WHERE d.audit_document = p_admission_number;   	
      IF messageid_count > 0 THEN audit_result = 'FAIL'; END IF;   	
         	
  END IF;  --domestic only   	
     	
  INSERT INTO preftz.system_log (procedure_name, log_message)    	
  VALUES ('audit_e214_data', 'ended: ' || p_admission_number || ' ' || audit_result);   	
     	
  RETURN audit_result;   	
   	
END;    	
$function$
;
-- DROP PROCEDURE preftz.audit_fed_receipts(bool);

CREATE OR REPLACE PROCEDURE preftz.audit_fed_receipts(IN p_use_selected_receipts boolean DEFAULT false)
 LANGUAGE plpgsql
AS $procedure$ 	
 	
--Change Log:
-- EG 08/23/2026 do not call update_e214_after_create if AUTO CONCUR is set to AUTO_LINK_CONCUR and pre-receipts exists
-- EG 08/11/2026 add submit job call
-- EG 08/07/2026 remove using temp_audit_receipts table in the main code
-- KK 08/05/2026 just in case a previous audit ended in error, change status back to NEW
-- EG 07/23/2026 do not reset e214 status for edited receipts if pre-receipt was AUTHORIZED and AUTO CONCUR is set to AUTO_LINK_CONCUR
-- EG 07/16/2026 Compare fed_receipts columns with all other tables to know if anything chaged during front end UPDATE 
-- KK 07/03/2026 add USMCA special treatments, allow capture of percentage of value is US content.
-- EG 07/06/2026 some issues fixed
-- MH 07/02/2026 allow UN (Unknown) for country of cast	
-- EG 6/10/2026 auto delete pre-receipts DEV-257 	
-- EG 4/7/2026 auto delete pre-receipts DEV-257 	
-- KK 05/11/2026 Fix cast and smelt reporting to reflect new Section232 prefixes. 	
-- KK 04/23/2026 Account for duplicate key receipt in receipt_derivative_content with upsert. 	
-- CL 04/22/2026 Allow defaults by part for melt/pour and cast/smelt. 	
-- KK 04/14/2026 Allow defaults by part for Aluminum, Steel, and Copper content weights. 	
-- KK 04/06/2026 CSMS # 68253075 - GUIDANCE: Section 232 Duties on Imports of Aluminum, Steel, and Copper 	
-- KK 01/13/2026 Add ability to process a batch of receipts from fed_receipts. 	
-- NO 12/03/2025 Added optional param to audit single receipt by receiptid, guard clause to exit if not found and checks throughout to support 	
-- KK 08/01/2025 Logic for SECTION232 Copper derivatives zone entry. 	
-- KK 07/18/2025 Create new part_number(s) where we have a new lot in fed_receipts. 	
-- KK 05/23/2025 create temp views for cast/smelt and melt/pour reporting and don't flag 0% derivatives. 	
-- KK 05/09/2025 Cast/Smelt and Melt/Pour reporting should NOT include derivatives that have zero percent aluminum or steel. 	
-- KK 05/02/2025 Fix derivative percentage audit; allow temp deposit, domestic, z2z, pre-receipt to process. 	
-- KK 04/23/2025 SECTION232 Steel and aluminum derivatives. Derivative percentage changes. 	
-- KK 04/22/2025 SECTION232 Steel and aluminum derivatives. Changes to fix cast and smelt for new derivatives. 	
-- KK 04/17/2025 SECTION232 Steel and aluminum derivatives 	
-- KK 11/19/2024 - remove audits for countervailing and antidumping 	
-- KK 11/14/2024 allow user to input license number and country of cast, even if not required 	
-- MH 10/22/2024 delete currently present user references 	
-- KK 08/20/2024 Changes to allow Kit conversion to part and versioning of Kit BOM. 	
--NKM 05/21/2024 Added missing criteria to check for duplicate transaction_reference (previous receipts) 	
--Mh 5/2/2024 added kitting receipt missing code ( copied from test environments that had the complete code) 	
--NKM 04/08/2024 Added receipt_date as build_date to kit_builds 	
--NKM 03/25/2024 Added domestic kit receipts 	
--               Added fed_status of 'AUDITING' to distinguish between unprocessed records and records currently being processed 	
--NKM 02/12/2024 Added kit logic - kits not eligible for receipts 	
--NKM 12/18/2023 Corrected criterion for requiring a proxy on ZTZ receipts 	
--NKM 11/07/2023 Added COALESCE to country_of_origin in reversal logic 	
--NKM 09/18/2023 Changed privileged_date to match receipt_date 	
--JMM 07/11/2023 Fixed unknow pre_receipt and changed to fr.pre_receipt at line 660 	
--NKM 06/28/2023 Allow for zone-to-zone pre-receipts 	
--MH 5/4/2023 type on secondary 	
--NKM 04/21/2023 Added aluminum cast & smelt fields 	
--               Fixed loophole for domestic goods in MID code audit 	
--RTJ 01/19/2023 Added unit_assist 	
--NKM 10/03/2022 Standardized criteria for editing 214 data and added use of update_e214_after_create 	
--NKM 08/25/2022 Added UPPER conversion to inbonds 	
--NKM 07/12/2022 Added roundoff error protections using v_tol 	
--NKM 05/31/2022 Link conveyance to current admission if it has receipts but no admission number 	
--NKM 05/04/2022 Bugfix - copy pre_receipt field to receipts table 	
--NKM 05/03/2022 Added phase 1 of pre_receipt logic - pre_receipts do not create inventory_items 	
--NKM 04/27/2022 Bugfix - fixed re-enabled AD/CVD error logic 	
--NKM 04/10/2022 BOL proxy required on ZTZ receipts when option 'ZTZ MATCH ON PROXY' is 'YES' 	
--NKM 03/30/2022 Removed MID code audit for zone-to-zone 	
--NKM 03/18/2022 Reworked zone-to-zone handling 	
--               Moved query that strips conveyanceid and admission_no from all domestic receipts from process_receipt_updates to audit_fed_receipts 	
--               Added invalid MID code audit 	
--               Moved audit of AD/CV numbers to function audit_case_number 	
--               and added call to query_case_numbers 	
--NKM 02/17/2022 Added clearing import_license_type at start of procedure 	
--NKM 02/02/2022 Added import license logic 	
--RTJ 11/08/2021 add zone_to_zone_transfer field to fed_receipts to handle edits to ZTZ transfers 	
--               and simple ZTZ receipts from non-PREFTZ systems 	
 	
--RTJ 11/01/2021 add checks and updates of e214 statuses 	
--NKM 10/20/2021 corrected typo in error message 	
--NKM 09/01/2021 revised process for receipt updates 	
--RTJ 08/12/2021 update inbond number from ZTZ log for ZTZ transfers 	
--NKM 08/09/2021 now removes non-alphanumeric characters from fed BOL, HBOL, and in-bond numbers 	
--RTJ 08/08/2021 Use inbond as BOL proxy for ZTZ transfers 	
--               Add country of export for ZTZ transfers 	
--               Add audit for missing receipt date 	
 	
--RTJ 08/08/2021 add handling for temporary deposits 	
--               + move temporary deposit errors to temporary_deposit_feed_errors table 	
--               + do not allow temporary deposit receipts to create inventory 	
 	
--RTJ 07/29/2021 add transferid to ztz_feed_errors table 	
 	
--RTJ 07/19/2021 include changes for zone-to-zone transfers 	
--               + errors are reported in ztz_feed_errors table 	
--               + records are added to the appropriate tables in the audit_ztz_feeds procedure 	
--               + records are deleted from the fed_receipts table in the audit_ztz_feeds procedure 	
--               + part numbers are found in the fed_parts table 	
--               + receipt quantities must be > zero; zone status must be provided 	
 	
--NKM 06/24/2021 Added inbond_number to receipts feed 	
--RTJ 05/05/2021 Pull audits for legitimacy of receipt corrections to separate procedure 	
--RTJ 04/10/2021 Audit for correct case number prefix 	
--RTJ 04/05/2021 Query new case numbers in ACE 	
--RTJ 04/03/2021 Add rate end date for AD/CVD case numbers 	
--RTJ 03/31/2021 Add handling for AD/CVD case numbers 	
--RTJ 03/31/2021 Add ftz_setting RECEIPT LINKING to handle automatic/manual linking of 	
--               receipts to conveyances 	
 	
--RTJ 03/11/2021 Insert missing MID codes into fed_vendors 	
--RTJ 03/03/2021 Removed audit for US country of origin on foreign receipt 	
--RTJ 02/16/2021 Add function to verify_country_code (and pull from master table) 	
--RTJ 02/15/2021 Removed 30 day receipt date audit 	
 	
--RTJ 01/24/2021 Do not default zone status to domestic 	
--               Refined error messages 	
--               added fed_record_identifier to feed_errors table 	
 	
--NKM 12/16/2020 Consolidated and expanded cleanup of varchar fields 	
--RTJ 11/18/2020 Query master manufacturer data for missing MID codes 	
 	
--RTJ 11/13/2020 Add logic for handling receipt corrections 	
--               Use variables for audit messages for ease of reference 	
--               Set empty user reference fields to null 	
 	
DECLARE 	
  rvrs                       RECORD; 	
  v_min_rcpt_id              INTEGER; 	
  v_min_rvrs_id              INTEGER; 	
  v_receipt_qty              NUMERIC; 	
  v_reversal_qty             NUMERIC; 	
  dprs                       RECORD; 	
  ccrs                       RECORD; --NKM 04/21/2023 	
 	
  --RTJ 11/13/2020 	
  v_table_name               VARCHAR(50) = 'fed_receipts'; 	
  v_update_count             INTEGER; 	
  v_kit_update_count         INTEGER; 	
  v_duplicate_msg            VARCHAR = 'Bypassed due to duplicate Transaction Reference'; 	
  v_missing_part_msg         VARCHAR = 'Part Number is missing'; 	
  v_invalid_part_msg         VARCHAR = 'Part Number is not in parts list'; 	
  v_foreign_kit_msg          VARCHAR = 'Kits may only be received as domestic - to receive kits in foreign status enter receipts for each component and then build the kit'; 	
  v_ztz_kit_msg              VARCHAR = 'Kits may not be received in a zone-to-zone transfer - to receive these goods enter receipts for each component and then build the kit'; 	
  v_td_kit_msg               VARCHAR = 'Kits may not be received as a temporary deposit - to receive these goods as a temporary deposit enter receipts for each component'; 	
  v_missing_qty_msg          VARCHAR = 'Receipt quantity is missing'; 	
  v_negative_qty_msg         VARCHAR = 'Correction receipt cannot have negative quantity'; 	
  v_invalid_kit_qty_msg      VARCHAR = 'Kits may only be received in positive integer quantities'; --NKM 03/25/2024 	
  v_invalid_status_msg       VARCHAR = 'Zone Status must be D, N, P or Z'; 	
  v_invalid_coo_msg          VARCHAR = 'Missing or invalid Country Of Origin'; 	
  --v_coo_mismatch_msg       VARCHAR = 'US country of origin on foreign status receipt';  --RTJ 03/03/2021 	
  v_missing_mid_msg          VARCHAR = 'Manufacturer is missing or not in vendor list'; 	
  v_invalid_mid_msg          VARCHAR = 'Manufacturer is neither a known vendor nor a valid MID code'; --NKM 03/18/2022 	
  v_receipt_date_audit       NUMERIC = 30; 	
  --v_invalid_rcpt_dt_msg      VARCHAR = 'Receipt Date is missing or older than 30 days'; 	
  v_invalid_rcpt_dt_msg      VARCHAR = 'Receipt Date is missing'; 	
  v_invalid_price_msg        VARCHAR = 'Unit Price is missing, zero or negative'; 	
  v_missing_proxy_msg        VARCHAR = 'Missing conveyance information (BOL/HBOL or proxy)'; 	
  v_missing_inbond_msg       VARCHAR = 'Missing in-bond number - enter NONE for no in-bond'; 	
  v_invalid_inbond_msg       VARCHAR = 'Invalid in-bond number format'; 	
  urs                        RECORD; 	
  --RTJ 11/13/2020 	
 	
  crs                        RECORD;  --RTJ 03/31/2021 	
  v_case_msg                 VARCHAR;  --RTJ 04/05/2021 	
  -- KK 11/19/2024 - remove audits for countervailing and antidumping 	
  --  v_domestic_ad_case_msg     VARCHAR = 'Domestic goods do not require antidumping case numbers';  --NKM 03/25/2024 	
  --  v_domestic_cv_case_msg     VARCHAR = 'Domestic goods do not require countervailing case numbers';  --NKM 03/25/2024 	
  v_case_error               BOOLEAN;  --RTJ 04/05/2021 	
--NKM 02/25/2022  v_case_suffix_needed       VARCHAR = 'Case Number suffix required';  --RTJ 04/05/2021 	
--NKM 02/25/2022  v_inactive_case            VARCHAR = 'Case Number is not currently active';  --RTJ 04/05/2021 	
--NKM 02/25/2022  v_invalid_case             VARCHAR = 'Case Number is invalid';  --RTJ 04/05/2021 	
--NKM 02/25/2022  v_waiting_case             VARCHAR = 'Waiting for Case Number response from ABI';  --RTJ 04/05/2021 	
--NKM 02/25/2022  v_invalid_case_prefix_a    VARCHAR = 'Antidumping Case Number must begin with A';  --RTJ 04/10/2021 	
--NKM 02/25/2022  v_invalid_case_prefix_c    VARCHAR = 'Countervailing Case Number must begin with C';  --RTJ 04/10/2021 	
  v_ztz_require_proxy        BOOLEAN; --NKM 04/10/2022 	
  v_require_inbonds          BOOLEAN; --NKM 06/24/2021 	
 	
  --RTJ 07/19/2021 	
  v_ztz_negative_qty_msg     VARCHAR = 'ZTZ transfer quantity must be greater than zero'; 	
  v_ztz_missing_part_msg     VARCHAR = 'Part Number is missing from the ZTZ transfer data'; 	
  v_ztz_invalid_coe_msg      VARCHAR = 'Invalid Country Of Export';  --RTJ 08/06/2021 	
  v_ztz_missing_proxy_msg    VARCHAR = 'A BOL proxy is required to match this receipt to a transfer record'; --NKM 04/10/2022 	
  --RTJ 07/19/2021 	
 	
  v_pre_negative_qty_msg     VARCHAR = 'Pre-receipt quantity must be greater than zero'; --NKM 05/03/2022 	
 	
  v_temporary_deposit_msg    VARCHAR = 'Temporary Deposit receipt held since: ';  --RTJ 08/04/2021 	
  v_concurred_e214_msg       VARCHAR = 'Zone Admission Number is for a concurred e214';  --RTJ 11/01/2021 	
  v_missing_ztz_inbond_msg   VARCHAR = 'Missing in-bond number for zone-to-zone transfer';  --RTJ 11/08/2021 	
  v_missing_alu_license_msg  VARCHAR = 'An aluminum import license is required for these goods'; --NKM 02/02/2022 	
  v_missing_stl_license_msg  VARCHAR = 'A steel import license is required for these goods'; --NKM 02/02/2022 	
  v_unknown_license_msg      VARCHAR = 'A license is not expected for this receipt - contact support if a license is required'; --NKM 03/18/2022 	
 	
  conrs                      RECORD;  --NKM 05/31/2022 	
  v_current_admission_no     VARCHAR(10) DEFAULT NULL; 	
  v_update_admission_no      VARCHAR(10) DEFAULT NULL; 	
 	
  v_tol                      DOUBLE PRECISION DEFAULT preftz.get_ftz_setting('ROUNDOFF TOLERANCE'); --NKM 07/12/2022 	
  v_invalid_assist_msg       VARCHAR = 'Unit Assist is negative';  --RTJ 01/19/2023 	
  v_domestic_assist_msg      VARCHAR = 'Domestic goods may not have a unit assist';  --NKM 03/25/2024 	
 	
  v_valid_country            VARCHAR(5); --NKM 04/21/2023 consolidated auditing of all country code fields 	
 	
  v_unexpected_cast_and_smelt_msg  VARCHAR = 'Cast and Smelt data is not required for this part'; 	
  v_missing_cast_msg         VARCHAR = 'Missing Country of Cast'; 	
  v_missing_1smelt_msg       VARCHAR = 'Missing Primary Country of Smelt (Enter a valid 2-character ISO country code or N/A)'; 	
  v_missing_2smelt_msg       VARCHAR = 'Missing Secondary Country of Smelt (Enter a valid 2-character ISO country code or N/A)'; 	
  v_incomplete_smelt_msg     VARCHAR = 'The Primary and Secondary Countres of Smelt are required when the Country of Cast is entered'; 	
  v_invalid_cast_msg         VARCHAR = 'Invalid Country of Cast'; 	
  v_invalid_1smelt_msg       VARCHAR = 'Invalid Primary Country of Smelt (Enter a valid 2-character ISO country code or N/A)'; 	
  v_invalid_2smelt_msg       VARCHAR = 'Invalid Secondary Country of Smelt (Enter a valid 2-character ISO country code or N/A)'; 	
  v_invalid_na_1smelt_msg    VARCHAR = 'The Primary Country of Smelt may not be N/A unless the Secondary Country of Smelt is also N/A'; 	
 	
  v_invalid_kit_date_msg     VARCHAR = 'The receipt date is greater than the date this Kit Part was removed.'; 	
  v_steel_percent_msg        VARCHAR = 'Steel percentage is required for SECTION232 derivatives'; 	
  v_alu_percent_msg          VARCHAR = 'Aluminum percentage is required for SECTION232 derivatives'; 	
  v_copper_percent_msg       VARCHAR = 'Copper percentage is required for SECTION232 derivatives'; 	
  v_missing_melt_msg         VARCHAR = 'Missing Country of Melt.'; 	
  v_missing_pour_msg         VARCHAR = 'Missing Country of Pour'; 	
  v_invalid_melt_msg         VARCHAR = 'Invalid Country of Melt.'; 	
  v_invalid_pour_msg         VARCHAR = 'Invalid Country of Pour'; 	
   	
  v_e214status_msg           VARCHAR = 'Actual receipt could not be linked because pre-receipts exist on an unauthorized admission'; 	
  v_pre_receipt_msg          VARCHAR = 'PRE-receipts already were removed for this BOL_proxy'; 	
  v_pre_receipt_mix_msg      VARCHAR = 'PRE-receipts mixed with receipts on the same feed'; 	
  v_pre_receipt_mix_msg_2    VARCHAR = 'Not proccessed PRE-receipts exist for incoming receipts'; 	
  v_pre_receipt_mix_msg_3    VARCHAR = 'Receipts exist for incoming PRE-receipts'; 	
  v_pre_receipt_filed_msg    VARCHAR = 'Cannot add pre-receipt for already FILED/AUTHORIZED e214 with same BOL_proxy #'; 	

  v_usmca_percent_us_value_msg VARCHAR = 'USMCA Percent U.S. Value must be between 0 - 100; Enter in whole number percentage.';
   	
 	
  v_total_count              INTEGER; -- NO 12/04/2025 	
   	
  v_concur_status     VARCHAR(26); 	
  v_count             INTEGER; 	
  v_conveyanceid      INTEGER; 	
  v_e214_status       VARCHAR(26); 	
  v_zone_admission_no VARCHAR(10); 	
  v_inbond_number     VARCHAR(12);  	
   	
   	
 	
BEGIN 	
    INSERT INTO preftz.system_log (procedure_name,log_message) 	
        VALUES ('audit_fed_receipts','started'); 	

 -- KK 08/05/2026 just in case a previous audit ended in error, change status back to NEW
    UPDATE preftz.fed_receipts fr     
    SET fed_status = 'NEW'
    WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE');
 	
-- EG 4/7/2026 	
    IF 
    (
    (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK_CONCUR')  	
    OR (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK') 
    )
    THEN  	
        CALL preftz.link_receipts_to_conveyances_by_inbond(); 	
        CALL preftz.assign_zone_admission(); 	
        --CALL preftz.pre_receipts_filing(); 	
    END IF; 	
-- EG 4/7/2026 	
 	
    -- NO 12/03/2025 Create temp table to limit processing to single receipt if param provided, 	
    -- use temp table count as guard clause (specific id passed in, not found in fed_receipts) 	
    DROP TABLE IF EXISTS temp_audit_receipts; 	
 	
    CREATE TEMPORARY TABLE temp_audit_receipts(receiptid INTEGER PRIMARY KEY); 	
 	
    -- KK 01/13/2026 Add ability to process a batch of receipts from fed_receipts. 	
    IF p_use_selected_receipts IS TRUE THEN 	
      INSERT INTO temp_audit_receipts(receiptid) 	
      SELECT receiptid FROM preftz.selected_fed_receipts; 	
 	
      DELETE FROM preftz.selected_fed_receipts 	
      WHERE receiptid IN (SELECT receiptid FROM temp_audit_receipts); 	
 	
      IF (SELECT COUNT(fr.receiptid) 	
          FROM preftz.fed_receipts fr 	
          JOIN temp_audit_receipts tar ON tar.receiptid = fr.receiptid) = 0 THEN 	
        RAISE NOTICE 'Nothing to process from selected_fed_receipts, exiting.'; 	
        INSERT INTO preftz.system_log (procedure_name,log_message) 	
        VALUES ('audit_fed_receipts', 'Nothing to process from selected_fed_receipts, exiting.'); 	
        RETURN; 	
      END IF; 	
      RAISE NOTICE 'Processing receipts in selected_fed_receipts...'; 	
    ELSE 	
      INSERT INTO temp_audit_receipts 	
        SELECT receiptid FROM preftz.fed_receipts; 	
      RAISE NOTICE 'Processing all receipts in fed_receipts...'; 	
    END IF; 	
 	
    SELECT COUNT(*) INTO v_total_count FROM temp_audit_receipts; 	
 	
    IF v_total_count = 0 THEN 	
      INSERT INTO preftz.system_log (procedure_name,log_message) 	
        VALUES ('audit_fed_receipts', 'Nothing to do, exiting.'); 	
      RETURN; 	
    END IF; 	
 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    SELECT 'audit_fed_receipts', 'RECORD COUNT TO PROCESS ' || TO_CHAR(COUNT(*),'999999') 	
      FROM temp_audit_receipts; 	
 	
    -- ONLY DELETE ERRORS FOR RECORDS BEING PROCESSED 	
    DELETE FROM preftz.feed_errors fe 	
      USING temp_audit_receipts tar 	
      WHERE fe.table_name = v_table_name 	
        AND fe.tableid = tar.receiptid; 	
 	
    DELETE FROM preftz.ztz_feed_errors zfe 	
      USING temp_audit_receipts tar 	
      WHERE zfe.table_name = v_table_name 	
        AND zfe.tableid = tar.receiptid; 	
 	
    DELETE FROM preftz.temporary_deposit_feed_errors te 	
      USING temp_audit_receipts tar 	
      WHERE te.table_name = v_table_name 	
        AND te.tableid = tar.receiptid; 	
 	
    DELETE FROM preftz.fed_receipts 	
      WHERE fed_status = 'DUPLICATE'; 	
    GET DIAGNOSTICS v_update_count = ROW_COUNT; 	
 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    VALUES ('audit_fed_receipts', 'PREVIOUS DUPLICATES ' || TO_CHAR(v_update_count,'999999')); 	
 	
    UPDATE preftz.fed_receipts fe 	
      SET fed_status = 'AUDITING', 	
          import_license_type = NULL 	
      FROM temp_audit_receipts tar 	
      WHERE fe.receiptid = tar.receiptid; 	
 	
    --COMMIT; 	
 	
    --NKM 12/16/2020 Consolidated and expanded cleanup varchar fields 	
    --Capitalize, remove spaces, and/or set '' to NULL as appropriate 	
    UPDATE preftz.fed_receipts fr 	
       SET part_number = NULLIF(TRIM(UPPER(part_number)),''), 	
           quantity = preftz.roundto(quantity, 0., v_tol), --NKM 07/12/2022 	
           unit_price = preftz.roundto(unit_price, 0., v_tol), --NKM 07/12/2022 	
           unit_assist = preftz.roundto(unit_assist, 0., v_tol),  --RTJ 01/19/2023 	
           manufacturer_mid_code = NULLIF(TRIM(UPPER(manufacturer_mid_code)),''), 	
           country_of_origin = NULLIF(TRIM(UPPER(country_of_origin)),''), 	
           bill_of_lading_airwaybill = NULLIF(UPPER(regexp_replace(bill_of_lading_airwaybill,'[^A-Za-z0-9]','','g')),''), 	
           house_bill = NULLIF(UPPER(regexp_replace(house_bill,'[^A-Za-z0-9]','','g')),''), 	
           house_bill_partial_indicator = NULLIF(TRIM(UPPER(house_bill_partial_indicator)),''), 	
           bill_of_lading_proxy = NULLIF(TRIM(UPPER(bill_of_lading_proxy)),''), 	
           transaction_reference = NULLIF(TRIM(UPPER(transaction_reference)),''), 	
           zone_status = NULLIF(TRIM(UPPER(zone_status)),''), 	
           foreign_unit_price = preftz.roundto(foreign_unit_price, 0., v_tol), --NKM 07/12/2022 	
           currency_code = NULLIF(TRIM(UPPER(currency_code)),''), 	
           currency_exchange_rate = preftz.roundto(currency_exchange_rate, 0., v_tol), --NKM 07/12/2022 	
           user_reference1 = NULLIF(TRIM(user_reference1),''), 	
           user_reference2 = NULLIF(TRIM(user_reference2),''), 	
           user_reference3 = NULLIF(TRIM(user_reference3),''), 	
           user_reference4 = NULLIF(TRIM(user_reference4),''), 	
           user_reference5 = NULLIF(TRIM(user_reference5),''), 	
           antidumping_case_number = NULLIF(TRIM(UPPER(antidumping_case_number)),''),  --RTJ 03/31/2021 	
           countervailing_case_number = NULLIF(TRIM(UPPER(countervailing_case_number)),''),  --RTJ 03/31/2021 	
           inbond_number = NULLIF(TRIM(UPPER(regexp_replace(inbond_number,'[^A-Za-z0-9]','','g'))),''),  --NKM 06/24/2021 --08/25/2022 	
           temporary_deposit = NULLIF(TRIM(UPPER(temporary_deposit)),''),  --RTJ 08/04/2021 	
           zone_to_zone_transfer = NULLIF(TRIM(UPPER(zone_to_zone_transfer)),''),  --RTJ 11/08/2021 	
           import_license_number = NULLIF(TRIM(UPPER(import_license_number)),''), --NKM 02/02/2022 	
           country_of_cast = NULLIF(TRIM(UPPER(country_of_cast)),''),                      --NKM 04/21/2023 	
           primary_country_of_smelt = NULLIF(TRIM(UPPER(primary_country_of_smelt)),''),    --NKM 04/21/2023 	
           secondary_country_of_smelt = NULLIF(TRIM(UPPER(secondary_country_of_smelt)),''), --NKM 04/21/2023 	
           country_of_melt = NULLIF(TRIM(UPPER(country_of_melt)),''), -- KK 04/17/2025 	
           country_of_pour = NULLIF(TRIM(UPPER(country_of_pour)),''), -- KK 04/17/2025 	
           steel_content_weight = preftz.roundto(steel_content_weight, 0., v_tol),       -- KK 04/06/2026 	
           aluminum_content_weight = preftz.roundto(aluminum_content_weight, 0., v_tol), -- KK 04/06/2026 	
           copper_content_weight = preftz.roundto(copper_content_weight, 0., v_tol),     -- KK 04/06/2026 	
           usmca_percent_us_value = preftz.roundto(usmca_percent_us_value, 0., v_tol)     -- KK 07/03/2026 
        WHERE fr.fed_status = 'AUDITING'; 	
 	
    -- update COO, MMC, ZS from parts_defaults if values are null 	
    UPDATE preftz.fed_receipts fr 	
    SET manufacturer_mid_code = pd.mmc, 	
        country_of_origin = pd.coo, 	
        zone_status = pd.zn 	
    FROM ( 	
        SELECT fr.receiptid, COALESCE(fr.country_of_origin, pd.country_of_origin) AS coo, 	
            COALESCE(fr.manufacturer_mid_code, pd.manufacturer_mid_code) AS mmc, 	
            COALESCE(fr.zone_status, pd.zone_status) AS zn 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.parts_defaults pd ON pd.part_number = fr.part_number 	
        WHERE fr.fed_status = 'AUDITING' 	
    ) pd 	
    WHERE pd.receiptid = fr.receiptid; 	
 	
    -- update cast/smelt if values are null 	
    UPDATE preftz.fed_receipts fr 	
    SET country_of_cast = pd.country_of_cast, 	
        primary_country_of_smelt = pd.primary_country_of_smelt, 	
        secondary_country_of_smelt = pd.secondary_country_of_smelt 	
    FROM ( 	
        SELECT fr.receiptid, 	
               COALESCE(fr.country_of_cast, pd.country_of_cast) country_of_cast, 	
               COALESCE(fr.primary_country_of_smelt, pd.primary_country_of_smelt) primary_country_of_smelt, 	
               COALESCE(fr.secondary_country_of_smelt, pd.secondary_country_of_smelt) secondary_country_of_smelt 	
          FROM preftz.fed_receipts fr 	
          JOIN preftz.parts_defaults pd ON pd.part_number = fr.part_number 	
         WHERE fr.fed_status = 'AUDITING' 	
           AND fr.country_of_cast IS NULL 	
           AND fr.primary_country_of_smelt IS NULL 	
           AND fr.secondary_country_of_smelt IS NULL 	
    ) pd 	
    WHERE pd.receiptid = fr.receiptid; 	
 	
    -- update melt/pour if values are null 	
    UPDATE preftz.fed_receipts fr 	
    SET country_of_melt = pd.country_of_melt, 	
        country_of_pour = pd.country_of_pour 	
    FROM ( 	
        SELECT fr.receiptid, 	
               COALESCE(fr.country_of_melt, pd.country_of_melt) country_of_melt, 	
               COALESCE(fr.country_of_pour, pd.country_of_pour) country_of_pour 	
          FROM preftz.fed_receipts fr 	
          JOIN preftz.parts_defaults pd ON pd.part_number = fr.part_number 	
         WHERE fr.fed_status = 'AUDITING' 	
           AND fr.country_of_melt IS NULL 	
           AND fr.country_of_pour IS NULL 	
    ) pd 	
    WHERE pd.receiptid = fr.receiptid; 	
 	
    -- update metal content weights from parts_defaults 	
    -- ONLY if ALL three values are null in fed table AND there are no existing values in receipt_derivative_content 	
    UPDATE preftz.fed_receipts fr 	
    SET steel_content_weight = pd.steel_content_weight, 	
        aluminum_content_weight = pd.aluminum_content_weight, 	
        copper_content_weight = pd.copper_content_weight 	
    FROM ( 	
        SELECT fr.receiptid, COALESCE(pd.steel_content_weight,0) AS steel_content_weight, 	
            COALESCE(pd.aluminum_content_weight,0) AS aluminum_content_weight, 	
            COALESCE(pd.copper_content_weight,0) AS copper_content_weight 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.parts_defaults pd ON pd.part_number = fr.part_number 	
            AND (pd.steel_content_weight IS NOT NULL 	
                OR pd.aluminum_content_weight IS NOT NULL 	
                OR pd.copper_content_weight IS NOT NULL) 	
        LEFT JOIN preftz.receipt_derivative_content rdc ON rdc.receiptid = fr.receiptid 	
        WHERE fr.fed_status = 'AUDITING' 	
            AND fr.steel_content_weight IS NULL  -- no values specified for any weights in fed table 	
            AND fr.aluminum_content_weight IS NULL 	
            AND fr.copper_content_weight IS NULL 	
            AND rdc.receiptid IS NULL  -- no existing row for this receiptid 	
    ) pd 	
    WHERE pd.receiptid = fr.receiptid; 	
 	
    --COMMIT; 	
 	
    UPDATE preftz.fed_receipts 	
      SET temporary_deposit = NULL 	
        WHERE temporary_deposit <> 'Y' -- RTJ 08/04/2021 	
          AND fed_status = 'AUDITING'; -- NO 12/03/2025 	
 	
    UPDATE preftz.fed_receipts 	
      SET zone_to_zone_transfer = NULL 	
      WHERE zone_to_zone_transfer <> 'Y' --RTJ 11/08/2021 	
        AND fed_status = 'AUDITING'; -- NO 12/03/2025 	
 	
    -- KK 07/18/2025 Create new part_number(s) where we have a new lot in fed_receipts. 	
    IF EXISTS ( 	
        SELECT 'x' 	
        FROM preftz.fed_receipts fr 	
          WHERE part_number like '%$%' 	
            AND fr.fed_status = 'AUDITING' -- NO 12/03/2025 	
    ) THEN 	
        CALL preftz.create_part_for_new_lots(); 	
    END IF; 	
 	
    --RTJ 11/13/2020 	
    --check for correction records (regular_receipts) 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'UPDATE' 	
      FROM preftz.receipts r 	
     WHERE fr.receiptid = r.receiptid 	
       AND fr.fed_status = 'AUDITING'; 	
    GET DIAGNOSTICS v_update_count = ROW_COUNT;  --RTJ 05/05/2021 	


/*
-- EG 07/16/2026
    INSERT INTO preftz.system_log (
        procedure_name,
        log_message
    )
    SELECT
        'audit_fed_receipts',
        'DELETED UPDATED RECEIPTS WITH NO CHANGES: ' ||
        COALESCE(
            string_agg(
                fr.receiptid::text,
                ',' ORDER BY fr.receiptid
            ),
            'NONE'
        )
    FROM preftz.fed_receipts fr
    WHERE preftz.compare_fed_receipt(fr.receiptid) = 'PASS'
    AND fr.fed_status = 'UPDATE'
    AND COALESCE(fr.temporary_deposit,'N') = 'N'
    AND COALESCE(fr.zone_to_zone_transfer,'N') = 'N'
    ;
            
    DELETE FROM preftz.fed_receipts fr
    WHERE fr.receiptid IN (
        SELECT fr.receiptid
        FROM preftz.fed_receipts fr
        WHERE preftz.compare_fed_receipt(fr.receiptid) = 'PASS'
        AND fr.fed_status = 'UPDATE'
        AND COALESCE(fr.temporary_deposit,'N') = 'N'
        AND COALESCE(fr.zone_to_zone_transfer,'N') = 'N'    
    );
    */
    
    --NKM 03/25/2024 	
    --check for correction records (kit_receipts) 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'KIT_UPDATE' 	
      FROM preftz.kit_receipts kr 	
     WHERE fr.receiptid = kr.receiptid 	
       AND fr.fed_status = 'AUDITING'; 	
    GET DIAGNOSTICS v_kit_update_count = ROW_COUNT; 	
 	
    --RTJ 05/05/2021 Move audits for legitimacy of correction records to separate procedure 	
    IF v_update_count >= 1 OR v_kit_update_count >= 1 THEN 	
        CALL preftz.audit_receipt_corrections(); 	
    END IF; 	
    --RTJ 05/05/2021 	
 	
    --check for duplicate transaction_reference (previous receipts) 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'transaction_reference', 	
           v_duplicate_msg, fr.transaction_reference, fr.part_number 	
      FROM preftz.fed_receipts fr 	
           LEFT JOIN preftz.receipts r 	
                  ON fr.transaction_reference = r.transaction_reference 	
           LEFT JOIN preftz.kit_receipts kr 	
                  ON fr.transaction_reference = kr.transaction_reference 	
     WHERE fr.transaction_reference IS NOT NULL 	
       AND (   fr.fed_status = 'AUDITING'                                         --RTJ 11/13/2020 	
            OR (fr.fed_status = 'UPDATE' AND r.receiptid <> fr.receiptid)         --NKM 03/25/2024 	
            OR (fr.fed_status = 'KIT_UPDATE' AND kr.receiptid <> fr.receiptid))   --NKM 03/25/2024 	
       AND (r.receiptid IS NOT NULL OR kr.receiptid IS NOT NULL); --NKM 05/21/2024 	
 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'DUPLICATE' 	
      FROM preftz.receipts r 	
     WHERE fr.transaction_reference = r.transaction_reference 	
       AND fr.transaction_reference IS NOT NULL 	
       AND (    fr.fed_status = 'AUDITING'                                 --RTJ 11/13/2020 	
            OR (fr.fed_status = 'UPDATE' AND r.receiptid <> fr.receiptid)); --NKM 03/25/2024 	
 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'DUPLICATE' 	
      FROM preftz.kit_receipts kr 	
     WHERE fr.transaction_reference = kr.transaction_reference 	
       AND fr.transaction_reference IS NOT NULL 	
       AND (    fr.fed_status = 'AUDITING'                                 --RTJ 11/13/2020 	
            OR (fr.fed_status = 'KIT_UPDATE' AND kr.receiptid <> fr.receiptid)); --NKM 03/25/2024 	
 	
    --check for duplicate transaction_reference (same file) 	
    FOR dprs IN SELECT MIN(fr.receiptid) min_receipt_id, fr.transaction_reference 	
                  FROM preftz.fed_receipts fr 	
                 WHERE fr.fed_status = 'AUDITING'  --RTJ 05/11/2020 	
                   AND fr.transaction_reference IS NOT NULL 	
                 GROUP BY fr.transaction_reference 	
                HAVING count(*) > 1 	
    LOOP 	
        INSERT INTO preftz.feed_errors 	
               (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
         SELECT v_table_name, fr.receiptid, 'transaction_reference', 	
                v_duplicate_msg, fr.transaction_reference, fr.part_number 	
           FROM preftz.fed_receipts fr 	
          WHERE fr.transaction_reference = dprs.transaction_reference 	
            AND fr.receiptid > dprs.min_receipt_id 	
            AND fr.fed_status IN ('AUDITING', 'KIT_UPDATE', 'UPDATE');  --NO 12/03/2025 	
 	
        UPDATE preftz.fed_receipts fr 	
           SET fed_status = 'DUPLICATE' 	
         WHERE fr.transaction_reference = dprs.transaction_reference 	
           AND fr.receiptid > dprs.min_receipt_id 	
           AND fr.fed_status IN ('AUDITING', 'KIT_UPDATE', 'UPDATE');  --NO 12/03/2025 	
    END LOOP; 	
 	
    --check for reversals (exclude ztz transfers, temporary deposits, and pre_receipts) 	
    FOR rvrs IN 	
        SELECT DISTINCT fr.part_number, fr.country_of_origin, fr.unit_price, fr.manufacturer_mid_code, 	
               COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') bol, 	
               COALESCE(fr.commercial_invoice_number,'NULL') invoice, COALESCE(fr.inbond_number,'NULL') inbond, 	
               COALESCE(fr.import_license_number,'NULL') import_license, 	
               COALESCE(fr.country_of_cast,'NULL') country_of_cast,           --NKM 04/21/2023 	
               COALESCE(fr.primary_country_of_smelt,'NULL') primary_smelt,    --NKM 04/21/2023 	
               COALESCE(fr.secondary_country_of_smelt,'NULL') secondary_smelt --NKM 04/21/2023 	
          FROM preftz.fed_receipts fr 	
               INNER JOIN preftz.fed_receipts frv 	
                       ON fr.part_number = frv.part_number 	
                      AND COALESCE(fr.country_of_origin,'') = COALESCE(frv.country_of_origin,'') 	
                      AND fr.unit_price = frv.unit_price --NKM 07/12/2022 unit price must be exact for a reversal (no tolerance) 	
                      AND fr.manufacturer_mid_code = frv.manufacturer_mid_code 	
                      AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = 	
                          COALESCE(frv.bill_of_lading_airwaybill,frv.bill_of_lading_proxy,'NULL') 	
                      AND COALESCE(fr.commercial_invoice_number,'NULL') = COALESCE(frv.commercial_invoice_number,'NULL') 	
                      AND COALESCE(fr.inbond_number,'NULL') = COALESCE(frv.inbond_number,'NULL') 	
                      AND COALESCE(fr.import_license_number,'NULL') = COALESCE(frv.import_license_number,'NULL') 	
                      AND COALESCE(fr.country_of_cast,'NULL') = COALESCE(frv.country_of_cast,'NULL') 	
                      AND COALESCE(fr.primary_country_of_smelt,'NULL') = COALESCE(frv.primary_country_of_smelt,'NULL') 	
                      AND COALESCE(fr.secondary_country_of_smelt,'NULL') = COALESCE(frv.secondary_country_of_smelt,'NULL') 	
         WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
           AND frv.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
           AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
           AND COALESCE(frv.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
           AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
           AND frv.temporary_deposit IS NULL  --RTJ 08/04/2021 	
           AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
           AND frv.quantity < 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
           AND fr.pre_receipt IS NOT TRUE     --NKM 05/03/2022 	
           AND frv.pre_receipt IS NOT TRUE    --NKM 05/03/2022 	
    LOOP 	
        SELECT MIN(fr.receiptid), SUM(fr.quantity) 	
          INTO v_min_rcpt_id, v_receipt_qty 	
          FROM preftz.fed_receipts fr 	
         WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
           AND fr.part_number = rvrs.part_number 	
           AND COALESCE(fr.country_of_origin,'') = COALESCE(rvrs.country_of_origin,'') 	
           AND fr.unit_price = rvrs.unit_price 	
           AND fr.manufacturer_mid_code = rvrs.manufacturer_mid_code 	
           AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = rvrs.bol 	
           AND COALESCE(fr.commercial_invoice_number,'NULL') = rvrs.invoice 	
           AND COALESCE(fr.inbond_number,'NULL') = rvrs.inbond 	
           AND COALESCE(fr.import_license_number,'NULL') = rvrs.import_license 	
           AND COALESCE(fr.country_of_cast,'NULL') = rvrs.country_of_cast 	
           AND COALESCE(fr.primary_country_of_smelt,'NULL') = rvrs.primary_smelt 	
           AND COALESCE(fr.secondary_country_of_smelt,'NULL') = rvrs.secondary_smelt 	
           AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
           AND fr.temporary_deposit IS NULL           --NKM 03/18/2022 	
           AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
           AND fr.pre_receipt IS NOT TRUE;    --NKM 05/03/2022 	
 	
        SELECT MIN(fr.receiptid), SUM(fr.quantity) 	
          INTO v_min_rvrs_id, v_reversal_qty 	
          FROM preftz.fed_receipts fr 	
         WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
           AND fr.part_number = rvrs.part_number 	
           AND COALESCE(fr.country_of_origin,'') = COALESCE(rvrs.country_of_origin,'') 	
           AND fr.unit_price = rvrs.unit_price 	
           AND fr.manufacturer_mid_code = rvrs.manufacturer_mid_code 	
           AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = rvrs.bol 	
           AND COALESCE(fr.commercial_invoice_number,'NULL') = rvrs.invoice 	
           AND COALESCE(fr.inbond_number,'NULL') = rvrs.inbond 	
           AND COALESCE(fr.import_license_number,'NULL') = rvrs.import_license 	
           AND COALESCE(fr.country_of_cast,'NULL') = rvrs.country_of_cast 	
           AND COALESCE(fr.primary_country_of_smelt,'NULL') = rvrs.primary_smelt 	
           AND COALESCE(fr.secondary_country_of_smelt,'NULL') = rvrs.secondary_smelt 	
           AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
           AND fr.temporary_deposit IS NULL           --NKM 03/18/2022 	
           AND fr.quantity < 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
           AND fr.pre_receipt IS NOT TRUE;    --NKM 05/03/2022 	
 	
        -- where receipt = reversal, bypass all 	
        IF preftz.isequal(ABS(v_reversal_qty), v_receipt_qty, v_tol) THEN --NKM 07/12/2022 	
            UPDATE preftz.fed_receipts fr 	
               SET fed_status = 'PROCESSED' 	
             WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
               AND fr.part_number = rvrs.part_number 	
               AND COALESCE(fr.country_of_origin,'') = COALESCE(rvrs.country_of_origin,'') 	
               AND fr.unit_price = rvrs.unit_price 	
               AND fr.manufacturer_mid_code = rvrs.manufacturer_mid_code 	
               AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = rvrs.bol 	
               AND COALESCE(fr.commercial_invoice_number,'NULL') = rvrs.invoice 	
               AND COALESCE(fr.inbond_number,'NULL') = rvrs.inbond 	
               AND COALESCE(fr.import_license_number,'NULL') = rvrs.import_license 	
               AND COALESCE(fr.country_of_cast,'NULL') = rvrs.country_of_cast 	
               AND COALESCE(fr.primary_country_of_smelt,'NULL') = rvrs.primary_smelt 	
               AND COALESCE(fr.secondary_country_of_smelt,'NULL') = rvrs.secondary_smelt 	
               AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
               AND fr.temporary_deposit IS NULL           --NKM 03/18/2022 	
               AND fr.pre_receipt IS NOT TRUE;    --NKM 05/03/2022 	
 	
        -- where receipt > reversal, create decreased receipt, bypass all others 	
        ELSIF preftz.isgreater(v_receipt_qty, ABS(v_reversal_qty), v_tol) THEN --NKM 07/12/2022 	
            v_receipt_qty = v_receipt_qty + v_reversal_qty; 	
 	
            UPDATE preftz.fed_receipts fr 	
               SET fed_status = 'PROCESSED' 	
             WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
               AND fr.part_number = rvrs.part_number 	
               AND COALESCE(fr.country_of_origin,'') = COALESCE(rvrs.country_of_origin,'') 	
               AND fr.unit_price = rvrs.unit_price 	
               AND fr.manufacturer_mid_code = rvrs.manufacturer_mid_code 	
               AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = rvrs.bol 	
               AND COALESCE(fr.commercial_invoice_number,'NULL') = rvrs.invoice 	
               AND COALESCE(fr.inbond_number,'NULL') = rvrs.inbond 	
               AND COALESCE(fr.import_license_number,'NULL') = rvrs.import_license 	
               AND COALESCE(fr.country_of_cast,'NULL') = rvrs.country_of_cast 	
               AND COALESCE(fr.primary_country_of_smelt,'NULL') = rvrs.primary_smelt 	
               AND COALESCE(fr.secondary_country_of_smelt,'NULL') = rvrs.secondary_smelt 	
               AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
               AND fr.temporary_deposit IS NULL           --NKM 03/18/2022 	
               AND fr.pre_receipt IS NOT TRUE;    --NKM 05/03/2022 	
 	
            INSERT INTO preftz.fed_receipts 	
                  (part_number, receipt_date, quantity, unit_price, manufacturer_mid_code, 	
                   country_of_origin, bill_of_lading_airwaybill, house_bill, 	
                   house_bill_partial_indicator, bill_of_lading_proxy, commercial_invoice_number, 	
                   transaction_reference, zone_admission_no, zone_status, foreign_unit_price, 	
                   currency_code, currency_exchange_rate, user_reference1, user_reference2, 	
                   user_reference3, user_reference4, user_reference5, conveyanceid, 	
                   antidumping_case_number, countervailing_case_number, inbond_number,  --RTJ 03/31/2021 	
                   import_license_number, unit_assist, --NKM 02/02/2022 / RTJ 01/19/2023 	
                   country_of_cast, primary_country_of_smelt, secondary_country_of_smelt) --NKM 04/21/2023 	
            SELECT fr.part_number, fr.receipt_date, v_receipt_qty, fr.unit_price, fr.manufacturer_mid_code, 	
                   fr.country_of_origin, fr.bill_of_lading_airwaybill, fr.house_bill, 	
                   fr.house_bill_partial_indicator, fr.bill_of_lading_proxy, fr.commercial_invoice_number, 	
                   fr.transaction_reference, fr.zone_admission_no, fr.zone_status, fr.foreign_unit_price, 	
                   fr.currency_code, fr.currency_exchange_rate, fr.user_reference1, fr.user_reference2, 	
                   fr.user_reference3, fr.user_reference4, COALESCE(fr.user_reference5, 'PARTIAL REVERSAL'), 	
                   fr.conveyanceid, fr.antidumping_case_number, fr.countervailing_case_number, fr.inbond_number, --RTJ 03/31/2021 	
                   fr.import_license_number, fr.unit_assist, --NKM 02/02/2022 / RTJ 01/19/2023 	
                   fr.country_of_cast, fr.primary_country_of_smelt, fr.secondary_country_of_smelt  --NKM 04/21/2023 	
              FROM preftz.fed_receipts fr 	
             WHERE fr.receiptid = v_min_rcpt_id; 	
 	
        -- where receipt < reversal, create decreased reversal, bypass all others 	
        ELSIF preftz.isgreater(ABS(v_reversal_qty), v_receipt_qty, v_tol) THEN --NKM 07/12/2022 	
            v_reversal_qty = v_reversal_qty + v_receipt_qty; 	
 	
            UPDATE preftz.fed_receipts fr 	
               SET fed_status = 'PROCESSED' 	
             WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
               AND fr.part_number = rvrs.part_number 	
               AND COALESCE(fr.country_of_origin,'') = COALESCE(rvrs.country_of_origin,'') 	
               AND fr.unit_price = rvrs.unit_price 	
               AND fr.manufacturer_mid_code = rvrs.manufacturer_mid_code 	
               AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = rvrs.bol 	
               AND COALESCE(fr.commercial_invoice_number,'NULL') = rvrs.invoice 	
               AND COALESCE(fr.inbond_number,'NULL') = rvrs.inbond 	
               AND COALESCE(fr.import_license_number,'NULL') = rvrs.import_license 	
               AND COALESCE(fr.country_of_cast,'NULL') = rvrs.country_of_cast 	
               AND COALESCE(fr.primary_country_of_smelt,'NULL') = rvrs.primary_smelt 	
               AND COALESCE(fr.secondary_country_of_smelt,'NULL') = rvrs.secondary_smelt 	
               AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
               AND fr.temporary_deposit IS NULL           --NKM 03/18/2022 	
               AND fr.pre_receipt IS NOT TRUE;    --NKM 05/03/2022 	
 	
            INSERT INTO preftz.fed_receipts 	
                  (part_number, receipt_date, quantity, unit_price, manufacturer_mid_code, 	
                   country_of_origin, bill_of_lading_airwaybill, house_bill, 	
                   house_bill_partial_indicator, bill_of_lading_proxy, commercial_invoice_number, 	
                   transaction_reference, zone_admission_no, zone_status, foreign_unit_price, 	
                   currency_code, currency_exchange_rate, user_reference1, user_reference2, 	
                   user_reference3, user_reference4, user_reference5, conveyanceid, 	
                   antidumping_case_number, countervailing_case_number, inbond_number,  --RTJ 03/31/2021 	
                   import_license_number, unit_assist, --NKM 02/02/2022 / RTJ 01/19/2023 	
                   country_of_cast, primary_country_of_smelt, secondary_country_of_smelt) --NKM 04/21/2023 	
            SELECT fr.part_number, fr.receipt_date, v_reversal_qty, fr.unit_price, fr.manufacturer_mid_code, 	
                   fr.country_of_origin, fr.bill_of_lading_airwaybill, fr.house_bill, 	
                   fr.house_bill_partial_indicator, fr.bill_of_lading_proxy, fr.commercial_invoice_number, 	
                   fr.transaction_reference, fr.zone_admission_no, fr.zone_status, fr.foreign_unit_price, 	
                   fr.currency_code, fr.currency_exchange_rate, fr.user_reference1, fr.user_reference2, 	
                   fr.user_reference3, fr.user_reference4, COALESCE(fr.user_reference5, 'OVER REVERSAL'), 	
                   fr.conveyanceid, fr.antidumping_case_number, fr.countervailing_case_number, fr.inbond_number, --RTJ 03/31/2021 	
                   fr.import_license_number, unit_assist, --NKM 02/02/2022 / RTJ 01/19/2023 	
                   fr.country_of_cast, fr.primary_country_of_smelt, fr.secondary_country_of_smelt  --NKM 04/21/2023 	
              FROM preftz.fed_receipts fr 	
             WHERE fr.receiptid = v_min_rvrs_id; 	
 	
        END IF; 	
    END LOOP; 	
 	
    --RTJ 11/01/2021 check for 214 in concurred status 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'receiptid', v_concurred_e214_msg, fr.zone_admission_no, fr.part_number 	
      FROM preftz.fed_receipts fr 	
           INNER JOIN preftz.e214_filing_statuses efs 	
                   ON fr.zone_admission_no = efs.zone_admission_no 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(efs.concur_status,'') NOT IN ('','REJECTED'); --NKM 10/03/2022 	
 	
  
  -- EG 08/23/2026
    -- ignore edited receipts and do not call update_e214_after_create 
    -- if pre-receit was AUTHORIZED and AUTO CONCUR is set to AUTO_LINK_CONCUR
    IF (
      SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK_CONCUR'
      OR 
      (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK')
      )  	
    THEN  	
       --update e214 filing status for all associated un-concurred 214s 	

       FOR urs IN 	
           SELECT DISTINCT fr.zone_admission_no 	
             FROM preftz.fed_receipts fr 	
                  INNER JOIN preftz.e214_filing_statuses efs 	
                          ON fr.zone_admission_no = efs.zone_admission_no 	
            WHERE fr.fed_status IN ('AUDITING','UPDATE','ERROR') 	
              AND COALESCE(efs.concur_status,'') IN ('','REJECTED') 
              AND COALESCE(efs.e214_status,'') <> '' 	
              AND fr.pre_receipt IS TRUE 
       LOOP 	
           CALL preftz.update_e214_after_create(urs.zone_admission_no); 
       END LOOP; 	

       -- call if actual receipts was edited and pre-receipts does not exist
       -- so if pre-receipt exists do not  call update_e214_after_create for edited actual receipt
       FOR urs IN 	
           SELECT DISTINCT fr.zone_admission_no 	
             FROM preftz.fed_receipts fr 	
                  INNER JOIN preftz.e214_filing_statuses efs 	
                          ON fr.zone_admission_no = efs.zone_admission_no 	
            WHERE fr.fed_status IN ('AUDITING','UPDATE','ERROR')
              AND COALESCE(efs.concur_status,'') IN ('','REJECTED') 
              AND COALESCE(efs.e214_status,'') <> '' 	
              AND fr.pre_receipt IS NOT TRUE 
                      /*    Pre-receipt does not exist.  */
                    AND NOT EXISTS
                    (
                        SELECT 1
                        FROM preftz.receipts pr
                        WHERE pr.zone_admission_no =
                              efs.zone_admission_no
                          AND pr.pre_receipt IS TRUE
                    )

       LOOP 	
           CALL preftz.update_e214_after_create(urs.zone_admission_no); 
       END LOOP; 	


    END IF;


  -- EG 08/23/2026
  --normal process
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'NO') 
    THEN  	
       --update e214 filing status for all associated un-concurred 214s 	
       FOR urs IN 	
           SELECT DISTINCT fr.zone_admission_no 	
             FROM preftz.fed_receipts fr 	
                  INNER JOIN preftz.e214_filing_statuses efs 	
                          ON fr.zone_admission_no = efs.zone_admission_no 	
            WHERE fr.fed_status IN ('AUDITING','UPDATE','ERROR') 	
              AND COALESCE(efs.concur_status,'') IN ('','REJECTED') --NKM 10/03/2022 	
              AND COALESCE(efs.e214_status,'') <> '' 	
       LOOP 	
           CALL preftz.update_e214_after_create(urs.zone_admission_no); --NKM 10/03/2022 	
       END LOOP; 	

    END IF;

    --RTJ 11/01/2021 	
 	
    --part_number 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'part_number', v_missing_part_msg, fr.part_number, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND fr.part_number IS NULL; 	
 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'part_number', 	
           CASE WHEN kp.part_number IS NULL THEN v_invalid_part_msg ELSE v_foreign_kit_msg END, 	
           fr.part_number, fr.part_number 	
      FROM preftz.fed_receipts fr 	
           LEFT JOIN preftz.parts_activation_view p   -- KK converted kits 	
                  ON fr.part_number = p.part_number 	
                 AND fr.receipt_date > p.activation_date   -- KK converted kits 	
           LEFT JOIN preftz.kit_parts kp                   --NKM 02/12/2024 	
                  ON fr.part_number = kp.part_number 	
                 AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND fr.part_number IS NOT NULL 	
       AND p.part_number IS NULL 	
       AND (kp.part_number IS NULL OR fr.zone_status <> 'D'); --NKM 03/25/2024 	
 	
 	
    -- KK 04/17/2025 - steel percentage SECTION232 requirements 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier, action_code) 	
    SELECT DISTINCT v_table_name, fr.receiptid, 'steel derivative percentage', v_steel_percent_msg, null, fr.part_number, 'PARTEXTMISS' 	
    FROM preftz.fed_receipts fr 	
    JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number AND pc.tariff_type = 'BASE' 	
    JOIN preftz.additional_tariff_derivatives a 	
        ON a.tariff_prefix = SUBSTR(pc.harmonized_tariff_schedule_number,1,LENGTH(a.tariff_prefix)) 	
        AND NOT pc.harmonized_tariff_schedule_number LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[])) 	
        AND (a.country_of_origin = fr.country_of_origin OR a.country_of_origin = 'ALL') 	
        AND NOT fr.country_of_origin LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[])) 	
        AND a.tariff_type = 'SECTION232' 	
        AND CURRENT_DATE BETWEEN a.start_date AND a.end_date 	
        AND LOWER(notes) LIKE 'iron_steel%' 	
     LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = fr.part_number 	
        AND CURRENT_TIMESTAMP BETWEEN dpc.start_date AND dpc.end_date 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'  --not required for zone_to_zone_transfer 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND dpc.steel_percentage IS NULL; 	
 	
    -- KK 04/17/2025 - aluminum percentage SECTION232 requirements 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier, action_code) 	
    SELECT DISTINCT v_table_name, fr.receiptid, 'aluminum derivative percentage', v_alu_percent_msg, null, fr.part_number, 'PARTEXTMISS' 	
    FROM preftz.fed_receipts fr 	
    JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number AND pc.tariff_type = 'BASE' 	
    JOIN preftz.additional_tariff_derivatives a 	
        ON a.tariff_prefix = SUBSTR(pc.harmonized_tariff_schedule_number,1,LENGTH(a.tariff_prefix)) 	
        AND NOT pc.harmonized_tariff_schedule_number LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[])) 	
        AND (a.country_of_origin = fr.country_of_origin OR a.country_of_origin = 'ALL') 	
        AND NOT fr.country_of_origin LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[])) 	
        AND a.tariff_type = 'SECTION232' 	
        AND CURRENT_DATE BETWEEN a.start_date AND a.end_date 	
        AND LOWER(notes) LIKE 'aluminum%' 	
     LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = fr.part_number 	
        AND CURRENT_TIMESTAMP BETWEEN dpc.start_date AND dpc.end_date 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'  --not required for zone_to_zone_transfer 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND dpc.aluminum_percentage IS NULL; 	
 	
    -- KK 08/01/2025 - copper percentage SECTION232 requirements 	
    INSERT INTO preftz.feed_errors 	
            (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier, action_code) 	
    SELECT DISTINCT v_table_name, fr.receiptid, 'copper derivative percentage', v_copper_percent_msg, null, fr.part_number, 'PARTEXTMISS' 	
    FROM preftz.fed_receipts fr 	
    JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number AND pc.tariff_type = 'BASE' 	
    JOIN preftz.additional_tariff_derivatives a 	
        ON a.tariff_prefix = SUBSTR(pc.harmonized_tariff_schedule_number,1,LENGTH(a.tariff_prefix)) 	
        AND NOT pc.harmonized_tariff_schedule_number LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[])) 	
        AND (a.country_of_origin = fr.country_of_origin OR a.country_of_origin = 'ALL') 	
        AND NOT fr.country_of_origin LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[])) 	
        AND a.tariff_type = 'SECTION232' 	
        AND CURRENT_DATE BETWEEN a.start_date AND a.end_date 	
        AND LOWER(notes) LIKE 'copper%' 	
        LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = fr.part_number 	
        AND CURRENT_TIMESTAMP BETWEEN dpc.start_date AND dpc.end_date 	
        WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'  --not required for zone_to_zone_transfer 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND dpc.copper_percentage IS NULL; 	
 	
    --ztz kits - forbidden 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'part_number', v_ztz_kit_msg, fr.part_number, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.kit_parts kp ON kp.part_number = fr.part_number 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND fr.zone_to_zone_transfer = 'Y'; 	
 	
    --temporary deposit kits - forbidden 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'part_number', v_td_kit_msg, fr.part_number, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.kit_parts kp ON kp.part_number = fr.part_number 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND fr.temporary_deposit = 'Y'; 	
 	
    --quantity 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'quantity', v_missing_qty_msg, fr.quantity, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NKM 03/25/2024 	
       AND fr.quantity IS NULL; 	
 	
    --RTJ 07/19/2021  ztz quantity cannot be negative or zero 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'quantity', v_ztz_negative_qty_msg, fr.quantity, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND COALESCE(fr.zone_to_zone_transfer,'N') = 'Y'   --NKM 03/18/2022 	
       AND fr.quantity <= 0; --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
    --RTJ 07/19/2021 	
 	
    --NKM 05/03/2022  pre_receipt quantity cannot be negative or zero 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'quantity', v_pre_negative_qty_msg, fr.quantity, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND fr.pre_receipt IS TRUE 	
       AND fr.quantity <= 0; --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
 	
    --RTJ 11/13/2020 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'quantity', v_negative_qty_msg, fr.quantity, fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('UPDATE','KIT_UPDATE') --NKM 03/25/2024 	
       AND fr.quantity < 0; --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
    --RTJ 11/13/2020 	
 	
    --quantity for kits must be a positive integer --NKM 03/25/2024 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'quantity', v_invalid_kit_qty_msg, fr.quantity, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.kit_parts kp ON fr.part_number = kp.part_number 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
     WHERE fr.fed_status IN ('AUDITING','KIT_UPDATE') 	
       AND (fr.quantity <> fr.quantity::INTEGER  --true equals (no roundoff allowed) 	
            OR fr.quantity <= 0); --assumes quantity rounded to 0 at start of procedure 	
 	
    --zone_status 	
    UPDATE preftz.fed_receipts fr 	
       SET zone_status = p.zone_status 	
      FROM preftz.parts_activation_view p   -- KK converted kits 	
     WHERE fr.part_number = p.part_number 	
       AND fr.receipt_date > p.activation_date   -- KK converted kits 	
       AND fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR fr.pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.zone_status IS NULL 	
       AND p.zone_status <> 'D'; 	
 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'zone_status', v_invalid_status_msg, fr.zone_status, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NKM 03/25/2024 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') NOT IN ('D','N','P','Z'); 	
 	
    --country_of_origin 	
    UPDATE preftz.fed_receipts fr 	
       SET country_of_origin = 'US' 	
     WHERE fr.zone_status = 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.country_of_origin IS NULL 	
       AND fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE'); 	
 	
    --US country_of_origin (kits) --NKM 03/25/2024 	
    UPDATE preftz.fed_receipts fr 	
       SET country_of_origin = 'US' 	
      FROM preftz.kit_parts kp 	
     WHERE kp.part_number = fr.part_number 	
       AND fr.zone_status = 'D' 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
       AND fr.fed_status IN ('AUDITING','KIT_UPDATE'); 	
 	
    --Validate all country code fields (assures all valid codes are in the preftz table) NKM 04/21/2023 	
    --Ugly check for status to enable optional single query paramater, might revisit later NO 12/03/2025 	
    FOR ccrs IN SELECT country_of_origin AS country_code 	
                  FROM preftz.fed_receipts 	
                  WHERE fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NO 12/03/2025 	
                 UNION 	
                SELECT country_of_cast AS country_code 	
                  FROM preftz.fed_receipts 	
                  WHERE fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NO 12/03/2025 	
                 UNION 	
                SELECT LEFT(primary_country_of_smelt,2) AS country_code 	
                  FROM preftz.fed_receipts 	
                 WHERE primary_country_of_smelt <> 'N/A' 	
                   AND fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NO 12/03/2025 	
                 UNION 	
                SELECT LEFT(secondary_country_of_smelt,2) AS country_code 	
                  FROM preftz.fed_receipts 	
                 WHERE primary_country_of_smelt <> 'N/A' 	
                   AND fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NO 12/03/2025 	
    LOOP 	
        v_valid_country = preftz.verify_country_code(ccrs.country_code); 	
    END LOOP; 	
 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'country_of_origin', v_invalid_coo_msg, fr.country_of_origin, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
      LEFT JOIN preftz.countries c ON c.iso_country_code = fr.country_of_origin 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND c.iso_country_code IS NULL; --NKM 04/21/2023 Logic above assures all valid country codes are in the preftz table 	
 	
    --RTJ 03/03/2021 There are situations under which a US country of origin is valid for a foreign receipt 	
    --INSERT INTO preftz.feed_errors 	
    --      (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    --SELECT v_table_name, fr.receiptid, 'country_of_origin', v_coo_mismatch_msg, fr.country_of_origin, 	
    --       fr.part_number 	
    --  FROM preftz.fed_receipts fr 	
    -- WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
    --   AND fr.zone_status <> 'D' 	
    --   AND fr.country_of_origin = 'US'; 	
    --RTJ 03/03/2021 	
 	
    --manufacturer_mid_code 	
    UPDATE preftz.fed_receipts fr 	
       SET manufacturer_mid_code = v.manufacturer_id_code 	
      FROM preftz.vendors v 	
     WHERE (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.manufacturer_mid_code = v.vendor_code 	
       AND NOT EXISTS (SELECT 'x' FROM preftz.manufacturer_identification_codes m 	
                        WHERE fr.manufacturer_mid_code = m.manufacturer_id_code) 	
       AND fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE'); --NO 12/03/2025 	
 	
    --RTJ 11/18/2020 	
    --pull MID codes from master table where possible 	
    INSERT INTO preftz.manufacturer_identification_codes 	
          (manufacturer_id_code, firm_name, street, city, iso_country_code, zip_or_postal_code) 	
    SELECT DISTINCT micm.manufacturer_id_code, micm.firm_name, micm.street, micm.city, 	
           micm.iso_country_code, micm.zip_or_postal_code 	
      FROM preftz.fed_receipts fr 	
            LEFT JOIN preftz.manufacturer_identification_codes m 	
                   ON fr.manufacturer_mid_code = m.manufacturer_id_code 	
           INNER JOIN prehts.manufacturer_identification_codes_master micm 	
                   ON fr.manufacturer_mid_code = micm.manufacturer_id_code 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND m.manufacturer_id_code IS NULL; 	
    --RTJ 11/18/2020 	
 	
    --missing MID code 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'manufacturer_mid_code', v_missing_mid_msg, fr.manufacturer_mid_code, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
           LEFT JOIN preftz.manufacturer_identification_codes m 	
                  ON fr.manufacturer_mid_code = m.manufacturer_id_code 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(fr.zone_status,'X') <> 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND m.manufacturer_id_code IS NULL; 	
 	
    --invalid MID code 	
    --NKM 03/18/2022 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'manufacturer_mid_code', v_invalid_mid_msg, fr.manufacturer_mid_code, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
           LEFT JOIN prehts.countries_master c 	
                   ON LEFT(fr.manufacturer_mid_code,2) = c.iso_country_code 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(fr.zone_status,'X') <> 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.manufacturer_mid_code IS NOT NULL 	
       AND (c.iso_country_code IS NULL 	
            OR NOT LENGTH(fr.manufacturer_mid_code) BETWEEN 6 AND 15); 	
    --NKM 03/18/2022 	
 	
    --DOMESTIC MID code --NKM 04/21/2023 	
    UPDATE preftz.fed_receipts fr 	
       SET manufacturer_mid_code = 'DOMESTIC' --overwrite MID code to DOMESTIC if it's not a known MID code 	
      FROM preftz.fed_receipts fr2 	
           LEFT JOIN preftz.manufacturer_identification_codes m 	
                  ON fr2.manufacturer_mid_code = m.manufacturer_id_code 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND fr.zone_status = 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR fr.pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr2.receiptid = fr.receiptid 	
       AND m.manufacturer_id_code IS NULL;    --No match in MID codes table 	
 	
    --DOMESTIC MID code (kits) --NKM 03/25/2024 	
    UPDATE preftz.fed_receipts fr 	
       SET manufacturer_mid_code = 'DOMESTIC' --overwrite MID code to DOMESTIC for kits with 'D' status 	
      FROM preftz.kit_parts kp 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND fr.zone_status = 'D' 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
       AND fr.part_number = kp.part_number; 	
 	
    --RTJ 03/11/2021 add MID to fed_vendors if begins with a valid country code 	
    INSERT INTO preftz.fed_vendors (vendor_code, manufacturer_id_code) 	
    SELECT DISTINCT fr.manufacturer_mid_code, fr.manufacturer_mid_code 	
      FROM preftz.fed_receipts fr 	
            LEFT JOIN preftz.manufacturer_identification_codes m 	
                   ON fr.manufacturer_mid_code = m.manufacturer_id_code 	
            LEFT JOIN preftz.fed_vendors v 	
                   ON fr.manufacturer_mid_code = v.manufacturer_id_code 	
           INNER JOIN prehts.countries_master c 	
                   ON LEFT(fr.manufacturer_mid_code,2) = c.iso_country_code 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(fr.zone_status,'X') <> 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND LENGTH(fr.manufacturer_mid_code) BETWEEN 6 AND 15 --NKM 03/18/2022 	
       AND m.manufacturer_id_code IS NULL 	
       AND v.manufacturer_id_code IS NULL; 	
    --RTJ 03/11/2021 	
 	
    --RTJ 02/15/2021 removed day-count audit until it can be included in ftz_settings 	
    --receipt_date 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'receipt_date', v_invalid_rcpt_dt_msg, fr.receipt_date, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --RTJ 11/13/2020 	
       AND fr.receipt_date IS NULL; 	
       --AND DATE_PART('day',current_date - COALESCE(fr.receipt_date,'01/01/1900')) > v_receipt_date_audit; 	
 	
    -- make sure updated receipt_date isn't after Kit had been removed 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'receipt_date', v_invalid_kit_date_msg, fr.receipt_date, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.kit_parts kp ON kp.part_number = fr.part_number 	
     WHERE fr.fed_status IN ('KIT_UPDATE') 	
       AND fr.receipt_date > kp.removed_date ; 	
 	
    --price 	
    UPDATE preftz.fed_receipts fr 	
       SET unit_price = foreign_unit_price * currency_exchange_rate 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.unit_price,0) <= 0             --NKM 07/12/2022 assumes unit_price was rounded to 0 at start of procedure 	
       AND COALESCE(fr.foreign_unit_price,0) > 0      --NKM 07/12/2022 assumes foreign_unit_price was rounded to 0 at start of procedure 	
       AND COALESCE(fr.currency_exchange_rate,0) > 0; --NKM 07/12/2022 assumes currency_exchange_rate was rounded to 0 at start of procedure 	
 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'unit_price', v_invalid_price_msg, fr.unit_price, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.unit_price,0) <= 0; --NKM 07/12/2022 assumes unit_price was rounded to 0 at start of procedure 	
 	
    --RTJ 01/19/2023  unit assist 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'unit_assist', v_invalid_assist_msg, fr.unit_assist, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.unit_assist,0) < 0; 	
    --RTJ 01/19/2023 	
 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'unit_assist', v_domestic_assist_msg, fr.unit_assist, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND fr.unit_assist IS NOT NULL 	
       AND fr.zone_status = 'D'; 	
 	
    --conveyance 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'bill_of_lading_proxy', v_missing_proxy_msg, fr.bill_of_lading_proxy, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(fr.zone_status,'X') <> 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.bill_of_lading_proxy IS NULL 	
       AND fr.bill_of_lading_airwaybill IS NULL; 	
 	
    --NKM 04/10/2022 Get ztz setting 	
    v_ztz_require_proxy=((preftz.get_ftz_setting('ZTZ MATCH ON PROXY') = 'YES') IS TRUE); 	
 	
    --NKM 04/10/2022 ztz missing required proxy 	
    IF v_ztz_require_proxy THEN 	
      INSERT INTO preftz.feed_errors 	
            (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
      SELECT v_table_name, fr.receiptid, 'bill_of_lading_proxy', v_ztz_missing_proxy_msg, fr.bill_of_lading_proxy, 	
             fr.part_number 	
        FROM preftz.fed_receipts fr 	
       WHERE fr.fed_status  = 'AUDITING' 	
         AND COALESCE(fr.zone_to_zone_transfer,'N') = 'Y'   --NKM 12/18/2023 zone-to-zone receipts 	
         AND pre_receipt IS NOT TRUE                        --NKM 12/18/2023 N/A for pre-receipts 	
         AND COALESCE(fr.bill_of_lading_proxy,'') = '';     --no proxy 	
    END IF; 	
 	
 	
    --NKM 06/24/2021 Get inbond setting 	
    v_require_inbonds=((preftz.get_ftz_setting('REQUIRE INBONDS') = 'REQUIRED') IS NOT FALSE); 	
 	
    --missing in-bond --NKM 06/24/2021 	
    IF v_require_inbonds THEN 	
      INSERT INTO preftz.feed_errors 	
            (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
      SELECT v_table_name, fr.receiptid, 'inbond_number', v_missing_inbond_msg, fr.inbond_number, 	
             fr.part_number 	
        FROM preftz.fed_receipts fr 	
       WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
         AND COALESCE(fr.zone_status,'X') <> 'D' 	
         AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
         AND COALESCE(fr.bill_of_lading_proxy,'') = ''       --not needed if using a proxy NKM 03/18/2022 	
         AND COALESCE(fr.inbond_number,'') = ''; 	
    END IF; 	
 	
    --invalid in-bond format (N/A if inbond_number is NULL) --NKM 06/24/2021 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'inbond_number', v_invalid_inbond_msg, fr.inbond_number, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(fr.zone_status,'X') <> 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND NOT (fr.inbond_number IS NULL 	
            OR COALESCE(fr.inbond_number,'') ~ '^NONE$'    --No In-bond 	
            OR COALESCE(fr.inbond_number,'') ~ '^[0-9]{9}$'      --CBP-assigned In-bond 	
            OR COALESCE(fr.inbond_number,'') ~ '^V[0-9A-Z]{10}$' --AMS Paperless In-bond 	
            OR(COALESCE(fr.inbond_number,'') ~ '^[0-9]{11}$' 	
               AND COALESCE(fr.inbond_number,'') = COALESCE(fr.bill_of_lading_airwaybill,fr.inbond_number,''))); --Air Waybill 	
 	
    --RTJ 03/31/2021 antidumping_case_number/countervailing_case_number 	
    --where possible, add the appropriate suffix to the case number 	
    FOR crs IN 	
        SELECT LEFT(REPLACE(q.case_number,'-',''),7) case_prefix, COUNT(*) suffix_count 	
          FROM (SELECT DISTINCT acr.case_number 	
                  FROM preftz.ad_cvd_case_reference acr 	
                 WHERE CURRENT_DATE >= acr.rate_effective_date 	
                   AND CURRENT_DATE <= acr.rate_end_date  --RTJ 04/03/2021 	
                   AND acr.case_status = 'ACTIVE') q 	
         GROUP BY LEFT(REPLACE(q.case_number,'-',''),7) 	
        HAVING COUNT(*) = 1 	
    LOOP 	
        UPDATE preftz.fed_receipts fr 	
           SET antidumping_case_number = acr.case_number 	
          FROM preftz.ad_cvd_case_reference acr 	
         WHERE (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
           AND REPLACE(fr.antidumping_case_number,'-','') = crs.case_prefix 	
           AND LEFT(REPLACE(acr.case_number,'-',''),7) = crs.case_prefix 	
           AND CURRENT_DATE >= acr.rate_effective_date 	
           AND CURRENT_DATE <= acr.rate_end_date  --RTJ 04/03/2021 	
           AND acr.case_status = 'ACTIVE'
           AND fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE'); -- EG 08/07/2026
           --AND fr.receiptid IN (SELECT receiptid FROM temp_audit_receipts); --NO 12/04/2025 	
 	
 	
        UPDATE preftz.fed_receipts fr 	
           SET countervailing_case_number = acr.case_number 	
          FROM preftz.ad_cvd_case_reference acr 	
         WHERE (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
           AND REPLACE(fr.countervailing_case_number,'-','') = crs.case_prefix 	
           AND LEFT(REPLACE(acr.case_number,'-',''),7) = crs.case_prefix 	
           AND CURRENT_DATE >= acr.rate_effective_date 	
           AND CURRENT_DATE <= acr.rate_end_date  --RTJ 04/03/2021 	
           AND acr.case_status = 'ACTIVE' 	
           AND fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE'); -- EG 08/07/2026
           --AND fr.receiptid IN (SELECT receiptid FROM temp_audit_receipts); --NO 12/04/2025 	
 	
    END LOOP; 	
 	
    --RTJ 04/05/2021 	
    FOR crs IN SELECT DISTINCT q.fed_case_number, q.case_type FROM 	
        (SELECT REPLACE(fr.antidumping_case_number,'-','') fed_case_number, 	
                'A' case_type 	
          FROM preftz.fed_receipts fr 	
         WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
           AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
           AND COALESCE(fr.zone_status,'X') <> 'D' 	
           AND COALESCE(fr.antidumping_case_number,'') <> '' 	
        UNION 	
        SELECT REPLACE(fr.countervailing_case_number,'-','') fed_case_number, 	
               'C' case_type 	
          FROM preftz.fed_receipts fr 	
         WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
           AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
           AND COALESCE(fr.zone_status,'X') <> 'D' 	
           AND COALESCE(fr.countervailing_case_number,'') <> '') q 	
    LOOP 	
 	
        --NKM 03/18/2022 	
        v_case_msg = preftz.audit_case_number(crs.fed_case_number, crs.case_type); --NKM 03/18/2022 	
        v_case_error = (v_case_msg IS NOT NULL);                                   --NKM 03/18/2022 --NKM 04/27/2022 	
 	
        IF v_case_error THEN 	
            INSERT INTO preftz.feed_errors 	
                  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
            SELECT DISTINCT v_table_name, fr.receiptid, 'antidumping_case_number', v_case_msg, 	
                   fr.antidumping_case_number, fr.part_number 	
              FROM preftz.fed_receipts fr 	
             WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
               AND COALESCE(fr.zone_status,'X') <> 'D' 	
               AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
               AND COALESCE(fr.antidumping_case_number,'') <> '' 	
               AND REPLACE(fr.antidumping_case_number,'-','') = crs.fed_case_number; 	
 	
            INSERT INTO preftz.feed_errors 	
                  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
            SELECT DISTINCT v_table_name, fr.receiptid, 'countervailing_case_number', v_case_msg, 	
                   fr.countervailing_case_number, fr.part_number 	
              FROM preftz.fed_receipts fr 	
             WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
               AND COALESCE(fr.zone_status,'X') <> 'D' 	
               AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
               AND COALESCE(fr.countervailing_case_number,'') <> '' 	
               AND REPLACE(fr.countervailing_case_number,'-','') = crs.fed_case_number; 	
        END IF; 	
    END LOOP; 	
 	
    -- KK 11/19/2024 - remove audits for countervailing and antidumping 	
    -- --case numbers for domestic receipts - not allowed --NKM 03/25/2024 	
    -- INSERT INTO preftz.feed_errors 	
    --       (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    -- SELECT DISTINCT v_table_name, fr.receiptid, 'antidumping_case_number', v_domestic_ad_case_msg, 	
    --        fr.antidumping_case_number, fr.part_number 	
    --   FROM preftz.fed_receipts fr 	
    --  WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
    --    AND fr.zone_status = 'D' 	
    --    AND COALESCE(fr.antidumping_case_number,'') <> ''; 	
 	
    -- INSERT INTO preftz.feed_errors 	
    --       (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    -- SELECT DISTINCT v_table_name, fr.receiptid, 'countervailing_case_number', v_domestic_cv_case_msg, 	
    --        fr.countervailing_case_number, fr.part_number 	
    --   FROM preftz.fed_receipts fr 	
    --  WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
    --    AND fr.zone_status = 'D' 	
    --    AND COALESCE(fr.countervailing_case_number,'') <> ''; 	
    -- --RTJ 03/31/2021/RTJ 04/05/2021 	
 	
    CALL preftz.query_case_numbers(); --NKM 03/18/2022 	
 	
    --NKM 02/02/2022 determine import_license_type - overwrites any existing value 	
    UPDATE preftz.fed_receipts fr 	
       SET import_license_type = CASE WHEN htsr.miscellaneous_permit_license_indicator = '01' THEN 'STL' 	
                                      WHEN htsr.miscellaneous_permit_license_indicator = '28' THEN 'ALU' 	
                                      ELSE NULL 	
                                      END 	
      FROM preftz.part_classifications pc, preftz.harmonized_tariff_schedule_reference htsr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND ((COALESCE(fr.zone_status,'X') <> 'D'  --license not required for domestic goods 	
           AND fr.temporary_deposit IS NULL         --license not required for temporary deposit 	
           AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE))  --NKM 03/18/2022 --NKM 06/28/2023 	
           OR fr.import_license_number IS NOT NULL)   -- KK 11/14/2024 	
       AND pc.part_number = fr.part_number 	
       AND htsr.tariff_number = pc.harmonized_tariff_schedule_number 	
       AND pc.tariff_type = 'BASE' 	
       AND fr.receipt_date BETWEEN htsr.record_begin_effective_date AND htsr.record_end_effective_date 	
       AND htsr.miscellaneous_permit_license_indicator IN ('01','28'); 	
 	
    --NKM 02/02/2022 required import license check 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'import_license_number', 	
           CASE WHEN fr.import_license_type = 'STL' THEN v_missing_stl_license_msg 	
                WHEN fr.import_license_type = 'ALU' THEN v_missing_alu_license_msg 	
                ELSE 'license error' END, 	
           fr.import_license_number, fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND fr.import_license_number IS NULL 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --license not required for domestic goods 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL         --license not required for temporary deposit 	
       AND fr.import_license_type IS NOT NULL;  --a requied license type was identified 	
 	
    --NKM 02/02/2022 unexpected import license check 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'import_license_number', 	
           v_unknown_license_msg, fr.import_license_number, fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND fr.import_license_number IS NOT NULL     --a license number is given 	
       AND fr.import_license_type IS NULL; 	
    -- KK 11/14/2024 - allow user to input license number even if not required 	
    --    AND (COALESCE(fr.zone_status,'X') = 'D'               --license not required for domestic goods 	
    --         OR (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE)  --NKM 03/18/2022 zone-to-zone transfer --NKM 06/28/2023 	
    --         OR fr.temporary_deposit IS NOT NULL              --license not required for temporary deposit 	
    --         OR fr.import_license_type IS NULL);              --a requied license type was not identified 	
 	
    --Aluminum cast & smelt reporting START --NKM 04/21/2023 	
    -- KK 05/23/2025 create temp views for cast/smelt and melt/pour reporting and don't flag 0% derivatives. 	
    CREATE OR REPLACE TEMPORARY VIEW cast_and_smelt_reporting_fp_view AS 	
    WITH max_date_content AS ( 	
        SELECT dpc.part_number, MAX(dpc.start_date) as max_start_date 	
        FROM preftz.derivative_parts_content dpc 	
        JOIN preftz.fed_receipts fr ON fr.part_number = dpc.part_number 	
        GROUP BY dpc.part_number 	
    ), most_recent_part_content AS ( 	
        SELECT dpc.part_number, dpc.aluminum_percentage, dpc.start_date 	
        FROM preftz.derivative_parts_content dpc 	
        JOIN max_date_content md ON md.part_number = dpc.part_number 	
            AND md.max_start_date = dpc.start_date 	
    ), parts_needing_cast_smelt AS ( 	
        -- Aluminum Products 	
        SELECT pc.part_number, pc.harmonized_tariff_schedule_number AS tariff_number, rbh.category 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number 	
        JOIN preftz.reporting_by_hts rbh ON pc.harmonized_tariff_schedule_number LIKE rbh.tariff_prefix || '%' 	
            AND rbh.category = 'aluminum_product' 	
            AND fr.receipt_date BETWEEN rbh.start_date AND rbh.end_date 	
        WHERE pc.tariff_type = 'BASE' 	
        UNION 	
        -- Aluminum Derivatives; Exclude those parts that are 0% aluminum 	
        SELECT pc.part_number, pc.harmonized_tariff_schedule_number AS tariff_number, rbh.category 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number 	
        JOIN preftz.reporting_by_hts rbh ON pc.harmonized_tariff_schedule_number LIKE rbh.tariff_prefix || '%' 	
            AND rbh.category = 'aluminum_derivative' 	
            AND fr.receipt_date BETWEEN rbh.start_date AND rbh.end_date 	
        LEFT JOIN most_recent_part_content dpc ON dpc.part_number = pc.part_number 	
        WHERE pc.tariff_type = 'BASE' 	
            AND COALESCE(dpc.aluminum_percentage,1) > 0 	
    ) 	
    SELECT part_number, tariff_number, category 	
    FROM parts_needing_cast_smelt 	
    ORDER BY part_number; 	
 	
    --cast & smelt for US goods - PER CBP filers may report 'US' and 'N/A' for products of the US --NKM 04/21/2023 	
    UPDATE preftz.fed_receipts fr 	
       SET country_of_cast = COALESCE(fr.country_of_cast,'US'), 	
           primary_country_of_smelt = COALESCE(fr.primary_country_of_smelt,'N/A'), 	
           secondary_country_of_smelt = COALESCE(fr.secondary_country_of_smelt,'N/A') 	
      FROM cast_and_smelt_reporting_fp_view csr   -- KK 05/09/2025 	
     WHERE csr.part_number = fr.part_number 	
       AND fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.country_of_origin = 'US'; 	
 	
    --Cast and smelt details provided when they are not required 	
    -- INSERT INTO preftz.feed_errors 	
    --       (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    -- SELECT v_table_name, fr.receiptid, 'country_of_cast/primary_smelt/secondary_smelt', 	
    --        v_unexpected_cast_and_smelt_msg, CONCAT_WS('/',fr.country_of_cast,fr.primary_country_of_smelt,fr.secondary_country_of_smelt), 	
    --        fr.part_number 	
    --   FROM preftz.fed_receipts fr 	
    --   JOIN cast_and_smelt_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
    --  WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
    --    AND (   country_of_cast IS NOT NULL          --country of cast or smelt is given 	
    --         OR NULLIF(primary_country_of_smelt,'N/A') IS NOT NULL 	
    --         OR NULLIF(secondary_country_of_smelt,'N/A') IS NOT NULL) 	
    --    AND (   csr.tariff_number IS NULL               --not required for this HTS 	
    --         OR (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE)  --NKM 03/18/2022 zone-to-zone transfer --NKM 06/28/2023 	
    --         OR COALESCE(fr.zone_status,'X') = 'D'   --not required for domestic goods 	
    --         OR fr.temporary_deposit = 'Y'           --not required for temporary deposit 	
    --         OR fr.pre_receipt IS TRUE);             --not required for a pre-receipt 	
 	
    --Missing country_of_cast 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'country_of_cast', 	
           v_missing_cast_msg, fr.country_of_cast, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN cast_and_smelt_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.country_of_cast IS NULL; 	
 	
    --Missing primary_country_of_smelt 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'primary_country_of_smelt', 	
           v_missing_1smelt_msg, fr.primary_country_of_smelt, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN cast_and_smelt_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.primary_country_of_smelt IS NULL; 	
 	
    --Missing secondary_country_of_smelt 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'secondary_country_of_smelt', 	
           v_missing_2smelt_msg, fr.secondary_country_of_smelt, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN cast_and_smelt_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.secondary_country_of_smelt IS NULL; 	
 	
    --Cast data provided without smelt data 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'countries of primary_smelt/secondary_smelt', 	
           v_incomplete_smelt_msg, CONCAT_WS('/',fr.primary_country_of_smelt, fr.secondary_country_of_smelt), fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN cast_and_smelt_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.country_of_cast IS NOT NULL 	
       AND (fr.primary_country_of_smelt IS NULL OR fr.secondary_country_of_smelt IS NULL); 	
 	
    --Invalid country_of_cast 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'country_of_cast', 	
           v_invalid_cast_msg, fr.country_of_cast, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      LEFT JOIN preftz.countries c ON c.iso_country_code = fr.country_of_cast 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.country_of_cast IS NOT NULL 	
    AND COALESCE(fr.country_of_cast,'') <> 'UN' --UN(unknown) is acceptable 	
       AND c.iso_country_code IS NULL; --not in preftz table (logic above assures all valid countires are in the preftz table) 	
 	
    --Invalid primary_country_of_smelt 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'primary_country_of_smelt', 	
           v_invalid_1smelt_msg, fr.primary_country_of_smelt, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      LEFT JOIN preftz.countries c ON c.iso_country_code = fr.primary_country_of_smelt 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.primary_country_of_smelt IS NOT NULL 	
       AND COALESCE(primary_country_of_smelt,'') <> 'N/A' --N/A is acceptable 	
       AND c.iso_country_code IS NULL; --not in preftz table (logic above assures all valid countires are in the preftz table) 	
 	
    --Invalid secondary_country_of_smelt 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'secondary_country_of_smelt', 	
           v_invalid_2smelt_msg, fr.secondary_country_of_smelt, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      LEFT JOIN preftz.countries c ON c.iso_country_code = fr.secondary_country_of_smelt 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.secondary_country_of_smelt IS NOT NULL 	
       AND COALESCE(secondary_country_of_smelt,'') <> 'N/A' --N/A is acceptable 	
       AND c.iso_country_code IS NULL; --not in preftz table (logic above assures all valid countires are in the preftz table) 	
 	
    --Invalid use of N/A for primary_country_of_smelt 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'primary_country_of_smelt', 	
           v_invalid_na_1smelt_msg, fr.primary_country_of_smelt, fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.primary_country_of_smelt = 'N/A' 	
       AND fr.secondary_country_of_smelt <> 'N/A'; 	
 	
    --Aluminum cast & smelt reporting END --NKM 04/21/2023 	
 	
    -- KK 05/23/2025 create temp views for cast/smelt and melt/pour reporting and don't flag 0% derivatives. 	
    CREATE OR REPLACE TEMPORARY VIEW melt_and_pour_reporting_fp_view AS 	
    WITH max_date_content AS ( 	
        SELECT dpc.part_number, MAX(dpc.start_date) as max_start_date 	
        FROM preftz.derivative_parts_content dpc 	
        JOIN preftz.fed_receipts fr ON fr.part_number = dpc.part_number 	
        GROUP BY dpc.part_number 	
    ), most_recent_part_content AS ( 	
        SELECT dpc.part_number, dpc.steel_percentage, dpc.start_date 	
        FROM preftz.derivative_parts_content dpc 	
        JOIN max_date_content md ON md.part_number = dpc.part_number 	
            AND md.max_start_date = dpc.start_date 	
    ), parts_needing_melt_pour AS ( 	
        -- Iron/Steel Products 	
        SELECT pc.part_number, pc.harmonized_tariff_schedule_number, rbh.category 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number 	
        JOIN preftz.reporting_by_hts rbh ON pc.harmonized_tariff_schedule_number LIKE rbh.tariff_prefix || '%' 	
            AND rbh.category = 'iron_steel_product' 	
            AND fr.receipt_date BETWEEN rbh.start_date AND rbh.end_date 	
        WHERE pc.tariff_type = 'BASE' 	
        UNION 	
        -- Iron/Steel Derivatives; Exclude those parts that are 0% iron or steel 	
        SELECT pc.part_number, pc.harmonized_tariff_schedule_number, rbh.category 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number 	
        JOIN preftz.reporting_by_hts rbh ON pc.harmonized_tariff_schedule_number LIKE rbh.tariff_prefix || '%' 	
            AND rbh.category = 'iron_steel_derivative' 	
            AND fr.receipt_date BETWEEN rbh.start_date AND rbh.end_date 	
        LEFT JOIN most_recent_part_content dpc ON dpc.part_number = pc.part_number 	
        WHERE pc.tariff_type = 'BASE' 	
            AND COALESCE(dpc.steel_percentage,1) > 0 	
    ) 	
    SELECT * FROM parts_needing_melt_pour 	
    ORDER BY part_number; 	
 	
    -- KK 04/17/2025 - Melt and Pour - country_of_melt may be required 	
    INSERT INTO preftz.feed_errors 	
        (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT DISTINCT v_table_name, fr.receiptid, 'country_of_melt', 	
           v_missing_melt_msg, fr.country_of_melt, fr.part_number 	
    FROM preftz.fed_receipts fr 	
    JOIN melt_and_pour_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
    WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND fr.country_of_melt IS NULL; 	
 	
    -- KK 04/17/2025 - Melt and Pour - country_of_pour may be required 	
    INSERT INTO preftz.feed_errors 	
        (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT DISTINCT v_table_name, fr.receiptid, 'country_of_pour', 	
           v_missing_pour_msg, fr.country_of_pour, fr.part_number 	
    FROM preftz.fed_receipts fr 	
    JOIN melt_and_pour_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
    WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND fr.country_of_pour IS NULL; 	
 	
    -- KK 04/17/2025 Invalid country_of_melt 	
    INSERT INTO preftz.feed_errors 	
        (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'country_of_melt', 	
        v_invalid_melt_msg, fr.country_of_melt, fr.part_number 	
    FROM preftz.fed_receipts fr 	
    LEFT JOIN (SELECT * FROM preftz.countries UNION SELECT 'OTH', 'OTHER') c ON c.iso_country_code = fr.country_of_melt 	
    WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND fr.country_of_melt IS NOT NULL 	
        AND c.iso_country_code IS NULL; --not in preftz table (logic above assures all valid countires are in the preftz table) 	
 	
    -- KK 04/17/2025 Invalid country_of_pour 	
    INSERT INTO preftz.feed_errors 	
        (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'country_of_pour', 	
        v_invalid_melt_msg, fr.country_of_pour, fr.part_number 	
    FROM preftz.fed_receipts fr 	
    LEFT JOIN (SELECT * FROM preftz.countries UNION SELECT 'OTH', 'OTHER') c ON c.iso_country_code = fr.country_of_pour 	
    WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND fr.country_of_pour IS NOT NULL 	
        AND c.iso_country_code IS NULL; --not in preftz table (logic above assures all valid countires are in the preftz table) 	
    -- END Melt and Pour 	

    -- KK 07/03/2026 - Invalid Percentage of US value for USMCA column
    INSERT INTO preftz.feed_errors 	
        (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'usmca_percent_us_value', 	
        v_usmca_percent_us_value_msg, fr.usmca_percent_us_value, fr.part_number 	
    FROM preftz.fed_receipts fr
    WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND COALESCE(fr.zone_status,'X') <> 'D'	
        AND fr.usmca_percent_us_value IS NOT NULL
        AND (fr.usmca_percent_us_value < 0.0
          OR fr.usmca_percent_us_value > 100.0);
     	
    -- EG 4/7/2026 auto delete pre-receipts DEV-257 	
 	
            IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N'  	
            THEN 	
               	
              FOR crs IN  	
                 SELECT fr.bill_of_lading_proxy, fr.receiptid, fr.pre_receipt 	
                 FROM preftz.fed_receipts fr 	
                 WHERE  fr.fed_status IN('NEW','AUDITING')  	
                  AND COALESCE(fr.zone_admission_no,'') = '' 	
                  AND fr.conveyanceid IS NULL 	
                  AND fr.quantity > 0 	
                  AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
                  AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
                  ORDER BY fr.receiptid 	
                  LOOP 	
 	
                       -- Reset per-loop variables to avoid accidental reuse 	
                       v_conveyanceid := NULL; 	
                       v_zone_admission_no := NULL; 	
                       v_concur_status := NULL; 	
                        	
                       -- check if already hs a conveyance 	
                       SELECT c.conveyanceid, c.zone_admission_no 	
                       INTO v_conveyanceid,v_zone_admission_no 	
                       FROM preftz.conveyances c 	
                       where c.inbond_number  = crs.bill_of_lading_proxy; 	
                        	
                       -- check filing statuses  	
                       SELECT COALESCE(efs.concur_status,''),COALESCE(efs.e214_status,'') 	
                       INTO v_concur_status, v_e214_status 	
                       FROM preftz.e214_filing_statuses efs 	
                       WHERE efs.zone_admission_no = v_zone_admission_no; 	
                        	
                       -- check if has pre_receipts already deleted (error condition) 	
                       select count(*) 	
                       into v_count 	
                       FROM preftz.deleted_pre_receipts ftf 	
                       where ftf.conveyanceid = v_conveyanceid; 	
                        	
                       -- check if concur status (ERROR condition)  	
                       IF  (v_conveyanceid IS NOT NULL)  	
                           AND (COALESCE(v_concur_status,'') NOT IN ('','REJECTED'))   	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_concurred_e214_msg,   v_zone_admission_no, v_concur_status; 	
                       END IF; 	
 	
                       -- check if v_e214_status status is AUTHORIZED/FILED for existing pre-receipts   	
                       -- and we want to add more pre-receipts (ERROR condition)  	
                       IF   v_conveyanceid IS NOT NULL 	
                           AND crs.pre_receipt IS TRUE 	
                           AND v_e214_status IN ('AUTHORIZED','FILED')   	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,               error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_pre_receipt_filed_msg,  v_zone_admission_no, v_e214_status; 	
                       END IF; 	
 	
                       -- check if v_e214_status status is not AUTHORIZED for existing pre-receipts   	
                       -- and we already received receipts (ERROR condition)  	
                       IF   v_conveyanceid IS NOT NULL 	
                           AND crs.pre_receipt IS NOT TRUE 	
                           AND v_e214_status NOT IN ('AUTHORIZED')   	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_e214status_msg,        v_zone_admission_no, v_e214_status; 	
                       END IF; 	
                        	
                       -- check if pre-receipts were already found  and moved to deleted table  	
                       -- and we already received receipts (ERROR condition)  	
                       IF  v_count > 0 	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_pre_receipt_msg,        v_zone_admission_no, v_count; 	
                       END IF; 	
                        	
                       -- check if pre-receipts and receipts are on the same feed (ERROR condition)  	
                        	
                       WITH t1  	
                       AS ( 	
                       SELECT  	
                       ftf.bill_of_lading_proxy 	
                       ,COALESCE(FTF.PRE_RECEIPT,FALSE) 	
                       FROM preftz.fed_receipts ftf 	
                       WHERE bill_of_lading_proxy = crs.bill_of_lading_proxy 	
                       GROUP BY  	
                       ftf.bill_of_lading_proxy 	
                       ,COALESCE(FTF.PRE_RECEIPT,FALSE) 	
                       ) 	
                       , t2 AS 	
                       ( 	
                       SELECT t1.bill_of_lading_proxy 	
                       ,COUNT(*) 	
                       FROM t1  	
                       GROUP BY  	
                       t1.bill_of_lading_proxy 	
                       HAVING COUNT(*) > 1 	
                       ) 	
                       SELECT COUNT(*)  	
                       INTO v_count 	
                       FROM t2; 	
                        	
                       IF  v_count > 0 	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_pre_receipt_mix_msg,     v_zone_admission_no, v_count; 	
                       END IF; 	
                        	
                       -- check if pre-receipts were received but not processed , so NOT AUTHORIZED  	
                       -- and receipts should not be coming yet  (ERROR condition)  	

                       SELECT COUNT(*)  	
                       INTO v_count 	
                       FROM preftz.receipts ftf 	
                       WHERE ftf.bill_of_lading_proxy = crs.bill_of_lading_proxy 	
                       AND ftf.pre_receipt IS TRUE 
                       AND crs.pre_receipt IS NOT TRUE	
                       AND ftf.conveyanceid IS NULL; 	-- EG 07/06/2026 	
                        	
                       IF  v_count > 0 	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_pre_receipt_mix_msg_2,     v_zone_admission_no, v_count; 	
                       END IF; 	
 	
                       -- 'Receipts exist for incoming PRE-receipts' (ERROR condition)  	
                       SELECT COUNT(*)  	
                       INTO v_count 	
                       FROM preftz.receipts ftf 	
                       WHERE ftf.bill_of_lading_proxy = crs.bill_of_lading_proxy 	
                       AND ftf.pre_receipt IS NOT TRUE 	
                       AND crs.pre_receipt IS TRUE
                       ; 	
                        	
                       IF  v_count > 0 	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_pre_receipt_mix_msg_3,     v_zone_admission_no, v_count; 	
                       END IF; 	
                        	
                        	
                  END LOOP;     	
                  	
            END IF; -- IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N'  	
    -- EG 4/7/2026 auto delete pre-receipts DEV-257 	
     	
     	
     	
     	
     	
 	
    --set fed_status to ERROR 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'ERROR' 	
      FROM preftz.feed_errors fe 	
     WHERE fe.table_name = v_table_name 	
       AND fe.tableid = fr.receiptid 	
       AND fe.error_type <> v_duplicate_msg;  --RTJ 11/13/2020 	

    -- KK 07/03/2026 - Upsert for persisting USMCA percent U.S. value
    -- We make the assumption these are entered as whole percentages (ie: 45.5 = 45.5%) - it is stored as decimal
    -- This part would also have to be flagged in preftz.parts_extension
    MERGE INTO preftz.receipt_percentage_value AS target
    USING (
        SELECT fr.receiptid, fr.usmca_percent_us_value / 100::NUMERIC AS usmca_percent_us_value
        FROM preftz.fed_receipts fr 
        WHERE fr.fed_status IN ('AUDITING','UPDATE')
          AND COALESCE(fr.zone_status,'X') <> 'D'	
          AND fr.usmca_percent_us_value IS NOT NULL
    ) AS source
    ON target.receiptid = source.receiptid
    WHEN MATCHED THEN
        UPDATE SET 
            percent_us_value = source.usmca_percent_us_value
    WHEN NOT MATCHED THEN
        INSERT (receiptid, percent_us_value)
        VALUES (source.receiptid, source.usmca_percent_us_value);
 	
    --RTJ 11/13/2020 reset conveyance link if conveyance or zone admission number data has changed on correction record 	
    UPDATE preftz.fed_receipts fr --NKM 09/01/2021 changed loop with update query into plain update query 	
       SET zone_admission_no = NULL, 	
           conveyanceid = NULL 	
      FROM preftz.receipts r 	
           LEFT JOIN preftz.conveyances c 	
                  ON r.conveyanceid = c.conveyanceid 	
           LEFT JOIN preftz.fed_conveyances fc 	
                  ON r.conveyanceid = fc.conveyanceid 	
         WHERE fr.fed_status IN('UPDATE','KIT_UPDATE') 	
           AND fr.receiptid = r.receiptid 	
           AND (   COALESCE(fr.bill_of_lading_airwaybill,'') <> 	
                   COALESCE(fc.bill_of_lading_airwaybill,c.bill_of_lading_airwaybill,'') 	
                OR COALESCE(fr.house_bill,'') <> COALESCE(fc.house_bill,c.house_bill,'') 	
                OR COALESCE(fr.bill_of_lading_proxy,'') <> COALESCE(r.bill_of_lading_proxy,'') 	
                OR COALESCE(fr.zone_admission_no,'') <> COALESCE(r.zone_admission_no,'') 	
                OR COALESCE(fr.inbond_number,'') <> COALESCE(fc.inbond_number,c.inbond_number,'')); --NKM 09/01/2021 	
 	
    --COMMIT; 	
 	
    --handle conveyance linking for AUDITING record and UPDATE records with null zone_admission_no 	
    --RTJ 03/31/2021 if AUTOMATIC linking is selected assign all fed receipts 	
     	
    --EG 4/7/2026 auto delete pre-receipts DEV-257 	
    --IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) <> 'N'  	
    --THEN  	
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'NO')  	
    THEN  	
     	
    IF preftz.get_ftz_setting('RECEIPT LINKING') = 'AUTOMATIC' THEN 	
        CALL preftz.assign_fed_receipts(); --NKM 06/24/2021 Updates made up to this point 	
    ELSE 	
    --if MANUAL linking is selected, ensure that each record includes a bill of lading proxy 	
        UPDATE preftz.fed_receipts fr 	
           SET bill_of_lading_proxy = COALESCE(fr.bill_of_lading_airwaybill,'NONE') || 	
                                      COALESCE(fr.house_bill,'NONE') || 	
                                      COALESCE('SPLIT'||fr.house_bill_partial_indicator,'') || --NKM 06/24/2021 added 	
                                      COALESCE(fr.inbond_number,'NULL') || --NKM 06/24/2021 'NULL' is different FROM 'NONE' 	
                                      TO_CHAR(current_date,'mmddyy') 	
         WHERE fr.fed_status = 'AUDITING' 	
           AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
           AND COALESCE(fr.bill_of_lading_proxy,'') = '' 	
           AND COALESCE(fr.zone_status,'') <> 'D';             --NKM 03/25/2024 	
    END IF; 	
     	
    END IF; --IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'NO')


    IF 
    (
    (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK')
    AND 
    ((SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N' )
    )
    THEN  	
        UPDATE preftz.fed_receipts fr 	
           SET bill_of_lading_proxy = fr.bill_of_lading_airwaybill
         WHERE fr.fed_status = 'AUDITING' 	
           AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   
           AND COALESCE(fr.bill_of_lading_proxy,'') = '' 	
           AND COALESCE(fr.zone_status,'') <> 'D';             
    END IF; 	
 	
    --NKM 05/31/2022 Link conveyance to current admission if has linked receipts but does not already have an admission number 	
    FOR conrs IN SELECT DISTINCT c.conveyanceid 	
                   FROM preftz.conveyances c 	
                   JOIN preftz.fed_receipts fr ON fr.conveyanceid = c.conveyanceid 	
                  WHERE COALESCE(c.zone_admission_no,'') = '' 	
                  AND fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE')  --NO 12/04/2025 	
    LOOP 	
        IF v_current_admission_no IS NULL THEN 	
           v_current_admission_no = preftz.get_current_zone_admission_number(); 	
        END IF; 	
 	
        SELECT COALESCE(MAX(fr.zone_admission_no),v_current_admission_no) 	
          INTO v_update_admission_no 	
          FROM preftz.fed_receipts fr 	
         WHERE fr.conveyanceid = conrs.conveyanceid 	
           AND COALESCE(fr.zone_admission_no,'') <> '' 	
           AND fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE'); --NO 12/04/2025 	
 	
        CALL preftz.assign_conveyances_to_214(conrs.conveyanceid, v_update_admission_no); 	
    END LOOP; 	
    --NKM 05/31/2022 	
 	
    --RTJ 11/13/2020 handle receipt corrections 	
    IF EXISTS (SELECT FROM preftz.fed_receipts WHERE fed_status = 'UPDATE') THEN --NKM 03/25/2024 	
        CALL preftz.process_receipt_updates(); 	
    END IF; 	
 	
    --NKM 03/25/2024 	
    IF EXISTS (SELECT FROM preftz.fed_receipts WHERE fed_status = 'KIT_UPDATE') THEN 	
        CALL preftz.process_kit_receipt_updates(); 	
    END IF; 	
 	
    --NKM 03/18/2022 	
    --strip 214 number and conveyance link before entering into token table if domestic 	
    UPDATE preftz.fed_receipts fr 	
       SET zone_admission_no = NULL, 	
           conveyanceid = NULL 	
     WHERE fr.zone_status = 'D' 	
       AND fr.fed_status IN('AUDITING','UPDATE','KIT_UPDATE'); --NKM 03/25/2024 	
    --NKM 03/18/2022 	
 	
    --NKM 03/25/2024 change status to KIT for received kit parts (except for pre-receipts) 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'KIT' 	
      FROM preftz.kit_parts kp 	
     WHERE kp.part_number = fr.part_number 	
       AND fr.fed_status = 'AUDITING' 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
       AND fr.pre_receipt IS NOT TRUE; --pre-receipts can be kits (because kits must be domestic) 	
 	
    --insert AUDITING records to receipts table 	
    INSERT INTO preftz.receipts 	
          (receiptid, part_number, receipt_date, quantity, unit_price, manufacturer_mid_code, 	
           country_of_origin, bill_of_lading_proxy, commercial_invoice_number, transaction_reference, 	
           zone_admission_no, zone_status, foreign_unit_price, currency_code, currency_exchange_rate, 	
           privileged_date, conveyanceid, inbond_number, zone_to_zone_transfer, pre_receipt,  --RTJ 11/08/2021 NKM 05/04/2022 	
           unit_assist)  --RTJ 01/19/2023 	
    SELECT fr.receiptid, fr.part_number, fr.receipt_date, fr.quantity, fr.unit_price, fr.manufacturer_mid_code, 	
           fr.country_of_origin, fr.bill_of_lading_proxy, fr.commercial_invoice_number, fr.transaction_reference, 	
           fr.zone_admission_no, fr.zone_status, fr.foreign_unit_price, fr.currency_code, fr.currency_exchange_rate, 	
           CASE WHEN fr.zone_status = 'P' THEN fr.receipt_date ELSE NULL END, --NKM 09/18/2023 	
           fr.conveyanceid, fr.inbond_number, 'N', fr.pre_receipt, fr.unit_assist  --RTJ 11/08/2021 NKM 05/04/2022  RTJ 01/19/2023 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 --includes pre-receipt kits 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0; --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
 	
 	
 -- MH 10/22/2024 delete currently present user references for next step will fail if present 	
 with recs as( 	
   select receiptid FROM preftz.fed_receipts fr 	
   LEFT JOIN preftz.user_references ur on ur.table_name = 'receipts' and ur.tableid = fr.receiptid 	
     WHERE fr.fed_status = 'AUDITING' 	
    AND ur.tableid is not null 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND COALESCE(fr.user_reference1,fr.user_reference2,fr.user_reference3,fr.user_reference4, 	
                    fr.user_reference5,'') <> '') 	
 delete from preftz.user_References where table_name = 'receipts' and tableid in(select receiptid from recs); 	
 	
    --insert AUDITING records to user_references table 	
    INSERT INTO preftz.user_references 	
          (table_name, tableid, user_reference1, user_reference2, user_reference3, user_reference4, 	
           user_reference5) 	
    SELECT 'receipts', fr.receiptid, fr.user_reference1, fr.user_reference2, fr.user_reference3, 	
           fr.user_reference4, fr.user_reference5 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND COALESCE(fr.user_reference1,fr.user_reference2,fr.user_reference3,fr.user_reference4, 	
                    fr.user_reference5,'') <> ''; 	
 	
    --RTJ 03/31/2021 insert AUDITING records to receipt_case_numbers table 	
    INSERT INTO preftz.receipt_case_numbers 	
          (receiptid, antidumping_case_number, countervailing_case_number) 	
    SELECT fr.receiptid, LEFT(REPLACE(fr.antidumping_case_number,'-',''),1) || '-' || 	
           SUBSTR(REPLACE(fr.antidumping_case_number,'-',''),2,3) || '-' || 	
           SUBSTR(REPLACE(fr.antidumping_case_number,'-',''),5,3) || '-' || 	
           SUBSTR(REPLACE(fr.antidumping_case_number,'-',''),8,3), 	
           LEFT(REPLACE(fr.countervailing_case_number,'-',''),1) || '-' || 	
           SUBSTR(REPLACE(fr.countervailing_case_number,'-',''),2,3) || '-' || 	
           SUBSTR(REPLACE(fr.countervailing_case_number,'-',''),5,3) || '-' || 	
           SUBSTR(REPLACE(fr.countervailing_case_number,'-',''),8,3) 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND COALESCE(fr.antidumping_case_number,fr.countervailing_case_number,'') <> ''; 	
    --RTJ 03/31/2021 	
 	
    --NKM 02/02/2022 insert AUDITING records to import_licenses 	
    INSERT INTO preftz.import_licenses (receiptid, import_license_type, import_license_number) 	
    SELECT fr.receiptid, fr.import_license_type, fr.import_license_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND fr.import_license_number IS NOT NULL; 	
 	
    --NKM 04/21/2023 insert AUDITING records to aluminum_cast_and_smelt 	
    INSERT INTO preftz.receipt_cast_and_smelt (receiptid, country_of_cast, primary_country_of_smelt, secondary_country_of_smelt) 	
    SELECT fr.receiptid, fr.country_of_cast, fr.primary_country_of_smelt, fr.secondary_country_of_smelt 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND fr.country_of_cast IS NOT NULL; --Country of cast will be null if no cast or smelt data is provided 	
 	
    -- KK 04/22/2025 insert AUDITING records to receipt_melt_and_pour 	
    INSERT INTO preftz.receipt_melt_and_pour (receiptid, country_of_melt, country_of_pour) 	
    SELECT fr.receiptid, fr.country_of_melt, fr.country_of_pour 	
    FROM preftz.fed_receipts fr 	
    WHERE fr.fed_status = 'AUDITING' 	
        AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
        AND fr.temporary_deposit IS NULL 	
        AND fr.quantity > 0 	
        AND fr.country_of_melt IS NOT NULL; 	
 	
    --insert AUDITING records to inventory_items table 	
    INSERT INTO preftz.inventory_items 	
          (part_number, quantity_received, quantity_on_hand, receipt_date, receiptid, zone_status) 	
    SELECT fr.part_number, fr.quantity, fr.quantity, fr.receipt_date, fr.receiptid, fr.zone_status 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND fr.pre_receipt IS NOT TRUE; 	
 	
    --insert AUDITING records to receipt_derivative_content table 	
    INSERT INTO preftz.receipt_derivative_content 	
        (receiptid, steel_content_weight, aluminum_content_weight, copper_content_weight, unit_net_weight) 	
    SELECT fr.receiptid, COALESCE(fr.steel_content_weight,0.0), 	
        COALESCE(fr.aluminum_content_weight,0.0), 	
        COALESCE(fr.copper_content_weight,0.0), 	
        COALESCE(p.unit_net_weight,0.0) 	
    FROM preftz.fed_receipts fr 	
    JOIN preftz.parts p ON p.part_number = fr.part_number 	
    WHERE fr.fed_status = 'AUDITING' 	
        AND (fr.steel_content_weight IS NOT NULL 	
            OR fr.aluminum_content_weight IS NOT NULL 	
            OR fr.copper_content_weight IS NOT NULL) 	
    ON CONFLICT (receiptid) DO UPDATE                 -- KK 04/23/2026 	
        SET steel_content_weight = EXCLUDED.steel_content_weight,  	
            aluminum_content_weight = EXCLUDED.aluminum_content_weight,  	
            copper_content_weight = EXCLUDED.copper_content_weight,  	
            unit_net_weight = EXCLUDED.unit_net_weight; 	
 	
    --kit parts START --NKM 03/25/2024 	
    --insert kit_receipts record 	
    INSERT INTO preftz.kit_receipts 	
          (receiptid, part_number, receipt_date, quantity, unit_price, commercial_invoice_number, 	
           transaction_reference, foreign_unit_price, currency_code, currency_exchange_rate) 	
    SELECT fr.receiptid, fr.part_number, fr.receipt_date, fr.quantity, fr.unit_price, fr.commercial_invoice_number, 	
           fr.transaction_reference, fr.foreign_unit_price, fr.currency_code, fr.currency_exchange_rate 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'KIT'; 	
 	
    --insert KIT records to user_references table 	
    INSERT INTO preftz.user_references 	
          (table_name, tableid, user_reference1, user_reference2, user_reference3, user_reference4, 	
           user_reference5) 	
    SELECT 'kit_receipts', fr.receiptid, fr.user_reference1, fr.user_reference2, fr.user_reference3, 	
           fr.user_reference4, fr.user_reference5 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'KIT'; 	
 	
    --insert kit_build event 	
    INSERT INTO preftz.kit_builds(kit_buildid, part_number, quantity_built, build_date, receiptid) --NKM 04/08/2024 	
    SELECT nextval('preftz.fed_kit_builds_kit_buildid_seq') AS kit_buildid, 	
           fr.part_number, fr.quantity, fr.receipt_date, fr.receiptid 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'KIT'; 	
 	
    --update kit inventory 	
    UPDATE preftz.kit_inventory ki 	
       SET quantity_on_hand = COALESCE(ki.quantity_on_hand,0) + fr.total_quantity 	
      FROM (SELECT part_number, SUM(quantity) AS total_quantity FROM preftz.fed_receipts WHERE fed_status = 'KIT' GROUP BY part_number) fr 	
     WHERE fr.part_number = ki.part_number; 	
 	
    --insert receipts records for kit components 	
    --REFRESH MATERIALIZED VIEW preftz.exploded_kit_boms; 	
    INSERT INTO preftz.receipts 	
          (receiptid, part_number, receipt_date, quantity, unit_price, 	
           manufacturer_mid_code, country_of_origin, commercial_invoice_number, transaction_reference, 	
           zone_status, kit_receiptid) 	
    SELECT nextval('preftz.fed_receipts_receiptid_seq') AS receiptid, 	
           kb.component_part_number, fr.receipt_date, fr.quantity*kb.quantity_per_kit, 	
           CASE 	
           WHEN tot.all_priced --all components parts have a reference unit price 	
           THEN p.reference_unit_price*(fr.unit_price/tot.total_reference_unit_price) --part unit price scales by kit reference unit price 	
           WHEN tot.total_reference_unit_price = 0 --no component parts has a reference unit price 	
             OR (NOT tot.all_priced AND tot.total_reference_unit_price >= fr.unit_price) --component part reference unit prices exceed total reference unit price 	
           THEN fr.unit_price*(p.unit_net_weight/tot.total_net_weight) --unit price scales by net weight 	
           ELSE --some but not all components have a reference_unit_price (hybrid) 	
                CASE 	
                WHEN p.reference_unit_price > 0 	
                THEN p.reference_unit_price --Use unit price where it exists 	
                ELSE (fr.unit_price-tot.total_reference_unit_price)*(p.unit_net_weight/tot.unpriced_total_net_weight) --scale the balance value by weight 	
                END 	
           END AS unit_price, 	
           'DOMESTIC' AS manufacturer_mid_code, 'US' AS country_of_origin, fr.commercial_invoice_number, 	
           CONCAT('KIT RECEIPT ',fr.receiptid::TEXT,'-',kb.exploded_componentid) AS transaction_reference, 	
           fr.zone_status, fr.receiptid 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.exploded_kit_boms kb ON kb.kit_part_number = fr.part_number 	
       AND fr.receipt_date BETWEEN kb.version_start_date AND kb.version_end_date  -- KK kit versions 	
      JOIN preftz.parts_activation_view p ON p.part_number = kb.component_part_number   -- KK converted kits 	
       AND fr.receipt_date > p.activation_date    -- KK converted kits 	
      JOIN (SELECT bom.kit_part_number, SUM(parts.reference_unit_price*bom.quantity_per_kit) total_reference_unit_price, 	
                   NOT (MIN(parts.reference_unit_price)=0) AS all_priced, SUM(parts.unit_net_weight*bom.quantity_per_kit) AS total_net_weight, 	
                   SUM(parts.unit_net_weight*bom.quantity_per_kit*(parts.reference_unit_price=0)::INT) AS unpriced_total_net_weight 	
              FROM preftz.exploded_kit_boms bom 	
              JOIN preftz.fed_receipts fr1 ON fr1.part_number = bom.kit_part_number          -- KK kit versions 	
            AND fr1.receipt_date BETWEEN bom.version_start_date AND bom.version_end_date  -- KK kit versions 	
              JOIN preftz.parts_activation_view parts ON parts.part_number = bom.component_part_number   -- KK converted kits 	
               AND fr1.receipt_date > parts.activation_date   -- KK converted kits 	
             GROUP BY bom.kit_part_number) tot ON tot.kit_part_number = fr.part_number 	
     WHERE fr.fed_status = 'KIT'; 	
 	
    --insert KIT records to inventory_items table 	
    INSERT INTO preftz.inventory_items 	
          (part_number, quantity_received, quantity_on_hand, receipt_date, receiptid, zone_status) 	
    SELECT r.part_number, r.quantity, r.quantity, r.receipt_date, r.receiptid, r.zone_status 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.receipts r ON r.kit_receiptid = fr.receiptid 	
     WHERE fr.fed_status = 'KIT'; 	
 	
    --kit parts END --NKM 03/25/2024 	
 	
    --insert AUDITING negative records to fed_adjustments table 	
    INSERT INTO preftz.fed_adjustments 	
          (part_number, adjust_date, quantity_adjusted, transaction_reference, user_reference5) 	
    SELECT fr.part_number, fr.receipt_date, fr.quantity, fr.transaction_reference, fr.user_reference5 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity < 0; --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
 	
    --RTJ 07/19/2021 Tranfer feed errors for ztz records 	
    INSERT INTO preftz.ztz_feed_errors 	
               (table_name, tableid, field_name, error_type, error_key_value, 	
                fed_record_identifier, transferid)  --RTJ 07/29/2021 	
         SELECT table_name, tableid, field_name, error_type, error_key_value, 	
                fed_record_identifier, transferid  --RTJ 07/29/2021 	
           FROM preftz.feed_errors fe 	
                INNER JOIN preftz.fed_receipts fr ON fr.receiptid = fe.tableid 	
          WHERE (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
            AND fe.table_name = v_table_name; 	
 	
    DELETE FROM preftz.feed_errors fe 	
     USING preftz.fed_receipts fr 	
     WHERE fr.receiptid = fe.tableid 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fe.table_name = v_table_name; 	
 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    SELECT 'ztz fed_receipts', fed_status || TO_CHAR(COUNT(*),'999999') 	
      FROM preftz.fed_receipts fr 	
     WHERE (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
     GROUP BY fed_status; 	
    --RTJ 07/19/2021 	
 	
    --RTJ 08/04/2021 Tranfer feed errors for temporary deposit records 	
    INSERT INTO preftz.temporary_deposit_feed_errors 	
               (table_name, tableid, field_name, error_type, error_key_value, 	
                fed_record_identifier) 	
         SELECT table_name, tableid, field_name, error_type, error_key_value, 	
                fed_record_identifier 	
           FROM preftz.feed_errors fe 	
                INNER JOIN preftz.fed_receipts fr ON fr.receiptid = fe.tableid 	
          WHERE fr.temporary_deposit IS NOT NULL 	
            AND fe.table_name = v_table_name; 	
 	
    DELETE FROM preftz.feed_errors fe 	
     USING preftz.fed_receipts fr 	
     WHERE fr.receiptid = fe.tableid 	
       AND fr.temporary_deposit IS NOT NULL 	
       AND fe.table_name = v_table_name 	
       AND fr.receiptid IN (SELECT receiptid FROM temp_audit_receipts); 	
 	
    --add non-error temporary deposit records 	
    INSERT INTO preftz.temporary_deposit_feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'temporary_deposit', 	
           v_temporary_deposit_msg || COALESCE(TO_CHAR(fr.receipt_date,'mm/dd/yyyy'),''), 	
           COALESCE(fr.zone_admission_no,'') || ' ' || 	
           CASE WHEN COALESCE(fr.bill_of_lading_airwaybill,'') = '' 	
                THEN COALESCE(fr.bill_of_lading_proxy) 	
                ELSE COALESCE(fr.bill_of_lading_airwaybill,'') || COALESCE(fr.house_bill,'') 	
                END, fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND fr.temporary_deposit IS NOT NULL; 	
 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    SELECT 'temporary deposit fed_receipts', 	
           CASE WHEN fed_status = 'AUDITING' THEN 'HOLDING' 	
                ELSE fed_status END || TO_CHAR(COUNT(*),'999999') 	
      FROM preftz.fed_receipts fr --NO 12/04/2025 	
     WHERE temporary_deposit IS NOT NULL 	
     AND fr.receiptid IN (SELECT receiptid FROM temp_audit_receipts) --NO 12/04/2025 	
     GROUP BY fed_status; 	
    --RTJ 08/04/2021 	
 	
    --record statistics 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    SELECT 'audit_fed_receipts', 	
           (CASE fed_status 	
                 WHEN 'AUDITING' THEN 'IMPORTED' 	
                 WHEN 'PROCESSED' THEN 'REVERSAL' 	
                 ELSE fed_status 	
                 END) || TO_CHAR(COUNT(*),'999999') 	
      FROM preftz.fed_receipts fr 	
     WHERE (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.receiptid IN (SELECT receiptid FROM temp_audit_receipts) --NO 12/04/2025 	
       AND temporary_deposit IS NULL  --RTJ 08/04/2021 	
     GROUP BY fed_status; 	
 	
    --Change status of ZTZ records to indicate they have passed audits (for use by process_fed_transfer_items) 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'ZTZ' 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE); --NKM 03/18/2022 --NKM 06/28/2023 	
 	
    --delete all non-ERROR records 	
    DELETE FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('PROCESSED','UPDATE','KIT','KIT_UPDATE');  --RTJ 11/13/2020 	
 	
    DELETE FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL;  --RTJ 08/04/2021 	
 	
    --The following are retained: 	
      --ZTZ records that have passed the audits (status = 'ZTZ') 	
      --Temporary deposit records (status = 'HOLDING') 	
 	
-- EG 4/7/2026 	
    IF 
    (
    (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK_CONCUR')  	
    OR (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK') 
    )
    THEN  	
        CALL preftz.link_receipts_to_conveyances_by_inbond(); 	
        CALL preftz.assign_zone_admission(); 	
        
        -- EG 08/11/2026
        CALL preftz.submit_job_request('preftz.process_auto_concur',NULL,'MED');

        --CALL preftz.pre_receipts_filing(); 	
    END IF; 	
-- EG 4/7/2026 	
 	
 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    VALUES ('audit_fed_receipts', 'finished'); 	
END; 	
$procedure$
;
-- PROCEDURE: preftz.audit_fed_conveyances()

-- DROP PROCEDURE IF EXISTS preftz.audit_fed_conveyances();

CREATE OR REPLACE PROCEDURE preftz.audit_fed_conveyances(
	)
LANGUAGE 'plpgsql'
AS $BODY$
	
	
--Change Log:	
-- MH 05/20/2026 added more container changes
-- MH 05/19/2026 added container to insert into token table
-- KK 05/15/2026 Try to update house_bill_partial_indicator where required but null	
-- EG 4/7/2026 link and auto delete pre-receipts project DEV-257	
-- MH 05/05/2026 commented out  v_ib_destination_msg audit	
-- MH 8/7/2025 added with ams_air_response and left join to handle scenerio when there is null and A/B	
-- MH 8/5/2025 added coalesce for ams split	
-- KK 2/7/2025 Populate gross_weight, charges, and country_of_export if NULL from conveyances.	
--MH 8/19/2024 added system logs	
--MH 7/23/2024 added call to unlink fed conveyances , add_deleted_record and extra audit for concurred admissions	
--NKM 05/21/2023 Added handling of AWBs w/o house_bills	
--NKM 04/28/2023 Changed carrier_code to issuer_code_of_master_bill_number for ocean/land BOL matching	
--NKM 11/17/2022 Revised loading data for import and export dates from AMS query results	
--NKM 10/03/2022 Standardized criteria for editing 214 data and added use of update_e214_after_create	
--               Added audits to changing the zone_admission_number	
--NKM 08/25/2022 Added UPPER conversion to inbonds	
--NKM 05/31/2022 Assign new conveyances to the current zone admission	
--NKM 05/20/2022 No longer strips leading zeroes from house bills	
--NKM 03/31/2022 now uses location_port_code for arriving in-bonds	
--NKM 08/30/2021 now resets conveyance_status for all records at start of procedure	
--NKM 08/09/2021 now removes non-alphanumeric characters from fed BOL, HBOL, and in-bond numbers	
--RTJ 07/21/2021 reset e214 status if changes are made to assigned conveyance	
	
--RTJ 06/30/2021 added country_of_export (mandatory)	
--               added vessel_departure_port, export_date, import_date (optional)	
--               default export date and import date from AMS data if none provided	
	
--NKM 06/24/2021 Added inbond_number to receipts feed	
--NKM 05/04/2021 add DISTINCT to ams_ocean_land_response query to handle multiple in-bonds	
--RTJ 03/18/2021 add audit for HBOL on non-air shipment	
	
--RTJ 03/17/2021 added update of zone_admission_no if associated receipts already linked	
	
--RTJ 01/30/2021 added call to ams_query_conveyances at the end of this procedure	
	
--RTJ 01/28/2021 added fed_record_identifier to feed_errors table	
--               added data cleanup	
	
--RTJ 01/21/2021 use variables for audit messages for ease of reference	
--               add ALL waiting records to errors table for visibility	
	
--NKM 12/22/2020 Added house_bill_partial_indicator = '' error trapping	
--NKM 12/14/2020 Added house_bill_partial_indicator to fed_conveyances to	
--                 assist in matching fed conveyances to AMS query results.	
   	
DECLARE	
  dprs                    RECORD;	
  crs                     RECORD;	
  ars                     RECORD; --NKM 10/03/2022	
  prev_airwaybill         VARCHAR(16);	
  prev_house_bill         VARCHAR(12);	
  v_conveyanceid          INTEGER;	
  v_update_count          INTEGER;	
  v_table_name            VARCHAR(50) = 'fed_conveyances';	
  v_duplicate_msg1         VARCHAR = 'Duplicate conveyance data 1';	
  v_duplicate_msg2         VARCHAR = 'Duplicate conveyance data 2';	
  v_duplicate_msg3         VARCHAR = 'Duplicate conveyance data 3';	
  v_missing_hbol_msg      VARCHAR = 'House Bill missing from air shipment - enter NONE for an air shipment with no house bills'; --NKM 05/21/2024	
  v_partial_wo_hbol_msg   VARCHAR = 'House Bill Partial Indicator requires a House Bill';	
  v_partial_alpha_msg     VARCHAR = 'House Bill Partial Indicator must be a letter';	
  v_missing_weight_msg    VARCHAR = 'Gross Weight must be greater than zero';	
  v_missing_charges_msg   VARCHAR = 'Charges must be greater than zero';	
  v_negative_pkg_msg      VARCHAR = 'Package Quantity cannot be less than zero';	
  v_no_ams_match_msg      VARCHAR = 'No match on BOL/HBOL in AMS';	
  v_no_partial_needed_msg VARCHAR = 'AMS shipment is not split - House Bill Partial Indicator must be empty';	
  v_partial_required_msg  VARCHAR = 'AMS shipment is split - House Bill Partial Indicator required';	
  v_waiting_for_ams_msg   VARCHAR = 'Waiting for AMS response to query'; --message completed in query	
  v_no_ams_details_msg    VARCHAR = 'No details returned from AMS for BOL/HBOL'; --query returned, with no record for this bill	
  v_no_ams_split_msg      VARCHAR = 'No details returned from AMS for this split';	
  v_ams_has_hbol_msg      VARCHAR = 'A House Bill is required because AMS reports this Airwaybill has House Bills'; --NKM 05/21/2024	
  v_non_air_house_msg     VARCHAR = 'House Bill cannot be entered for a non-air shipment';  --RTJ 03/18/2021	
  v_require_inbonds       BOOLEAN;    --NKM 06/24/2021	
  v_location_port_code    VARCHAR(4); --NKM 06/24/2021 --NKM 03/31/2022	
  v_missing_inbond_msg    VARCHAR = 'Missing in-bond number - enter \\\"NONE\\\" for no in-bond';	
  v_invalid_inbond_msg    VARCHAR = 'Invalid in-bond number format';	
  v_air_inbond_err_msg    VARCHAR = 'An 11 digit in-bond number must match the air waybill number';	
  v_ib_bill_mismatch_msg  VARCHAR = 'Inbond not associated with BOL/HBOL in AMS';	
  v_ib_destination_msg    VARCHAR = 'AMS reports inbond is not bound for FTZ port';	
  v_invalid_port_msg      VARCHAR = 'Vessel Departure Port is invalid';  --RTJ 06/30/2021	
  v_port_country_msg      VARCHAR = 'Vessel Departure Port cannot be a US port';  --RTJ 06/30/2021	
  v_missing_coe_msg       VARCHAR = 'Country of Export is missing or invalid';  --RTJ 06/30/2021	
  v_date_mismatch_msg     VARCHAR = 'The import date needs to be greater than or equal to the export date';  --RTJ 06/30/2021	
  v_missing_ex_date_msg   VARCHAR = 'Export date is required';  --NKM 11/17/2022	
  v_missing_im_date_msg   VARCHAR = 'Import date is required';  --NKM 11/17/2022	
  v_linking_err_msg       VARCHAR = 'This conveyances is already on a concurred 214 and may not be edited';  --NKM 10/03/2022	
  v_duplicate_linking_err_msg VARCHAR = 'This conveyance is a duplicate conveyance but conveyance is already on a concurred 214 and may not be edited';	
  v_current_admission_no  VARCHAR(10) DEFAULT NULL;	
  v_update_admission_no   VARCHAR(10);	
 	
	
BEGIN	
    INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','started');	
       	
    INSERT INTO preftz.system_log (procedure_name, log_message)	
    SELECT 'audit_fed_conveyances', 'RECORD COUNT ' || TO_CHAR(COUNT(*),'999999')	
      FROM preftz.fed_conveyances;	
	
    DELETE FROM preftz.feed_errors WHERE table_name = v_table_name;	
    	
    --delete all duplicate records	
 --MH 7/17/2024 must remove all links	
	
 INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','unlink receipts from duplicate conveyances');	
 -- Unlink receipts from fed_conveyances ( this will update fed_status to ERROR if linked to concurred admission)	
 CALL preftz.unlink_receipts_from_duplicate_conveyances();	
 -- add duplicate records to deleted_conveyances	
 INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','delete duplicates');	
 CALL preftz.add_multiple_deleted_records('fed_conveyances','DUPLICATE','DUPLICATE',0);	
 -- Delete conveyances where still DUPLICATE and now in deleted tables	
 DELETE FROM preftz.fed_conveyances where conveyanceid IN(	
     SELECT fc.conveyanceid FROM	
  preftz.fed_conveyances  fc	
  JOIN preftz.deleted_conveyances dc on fc.conveyanceid = dc.conveyanceid	
  WHERE fc.fed_status = 'DUPLICATE');	
  	
 GET DIAGNOSTICS v_update_count = ROW_COUNT;	
	
   	
    INSERT INTO preftz.system_log (procedure_name, log_message)	
    VALUES ('audit_fed_conveyances', 'PREVIOUS DUPLICATES ' || TO_CHAR(v_update_count,'999999'));	
    	
    --Reset statuses	
    UPDATE preftz.fed_conveyances fc	
       SET fed_status = 'NEW',	
           conveyance_status = 'NEW'; --NKM 08/30/2021	
	
    --Formatting updates 	
	
/*  NKM 05/20/2022	
    --strip leading zeros off house_bills	
    UPDATE preftz.fed_conveyances fc	
       SET house_bill = preftz.trim_leading_zeros(house_bill)	
     WHERE house_bill LIKE '0%';	
*/	
    	
    --Capitalize, remove spaces, and/or set '' to NULL as appropriate	
    UPDATE preftz.fed_conveyances	
       SET bill_of_lading_airwaybill = UPPER(regexp_replace(bill_of_lading_airwaybill,'[^A-Za-z0-9]','','g')),	
           house_bill = NULLIF(UPPER(regexp_replace(house_bill,'[^A-Za-z0-9]','','g')),''),	
           house_bill_partial_indicator = NULLIF(TRIM(UPPER(house_bill_partial_indicator)),''),	
           inbond_number = NULLIF(TRIM(UPPER(regexp_replace(inbond_number,'[^A-Za-z0-9]','','g'))),''),  --NKM 06/24/2021 --08/25/2022	
           country_of_export = NULLIF(TRIM(UPPER(country_of_export)),''),  --RTJ 06/30/2021	
           vessel_departure_port = NULLIF(TRIM(UPPER(vessel_departure_port)),'');  --RTJ 06/30/2021	
	
    --update query status from conveyance_queries table --NKM 06/24/2021	
	
  INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','update fed conveyances with known data');	
    UPDATE preftz.fed_conveyances fc	
       SET conveyance_status = cq.conveyance_status	
      FROM preftz.conveyance_queries cq	
     WHERE fc.bill_of_lading_airwaybill = cq.bill_of_lading_airwaybill	
       AND COALESCE(NULLIF(fc.house_bill,'NONE'),'') = cq.house_bill; --NKM 05/21/2024	
	
    --populate export date (usually available for ocean shipments with in-bonds) NKM 11/17/2022 - preferred	
	
    UPDATE preftz.fed_conveyances fc	
       SET export_date = TO_DATE(wn1.vessel_departure_date,'MMDDYY')	
      FROM (SELECT min(wn1id) AS wn1id FROM preftz.wn1 GROUP BY wr1id) ib1,	
           preftz.wr1	
      JOIN preftz.wr4 ON wr4.wr1id = wr1.wr1id	
      JOIN preftz.wn1 ON wn1.wr1id = wr1.wr1id	
     WHERE fc.bill_of_lading_airwaybill = wr4.issuer_code_of_master_bill_number || wr4.master_bill_number --NKM 04/28/2023	
       AND wn1.wn1id = ib1.wn1id	
       AND wn1.vessel_departure_date <> ''	
       AND fc.export_date IS NULL	
       AND fc.conveyance_status = 'COMPLETE';	
	
    --populate import date from conveyance arrival message (ocean and rail) NKM 11/17/2022 - preferred	
    UPDATE preftz.fed_conveyances fc	
       SET import_date = TO_DATE(wr5.disposition_action_date,'MMDDYY')	
      FROM preftz.wr1	
      JOIN preftz.wr4 ON wr4.wr1id = wr1.wr1id	
      JOIN preftz.wr5 ON wr5.wr1id = wr1.wr1id AND wr5.disposition_action_code = '19'	
     WHERE fc.bill_of_lading_airwaybill = wr4.issuer_code_of_master_bill_number || wr4.master_bill_number --NKM 04/28/2023	
       AND fc.import_date IS NULL	
       AND fc.conveyance_status = 'COMPLETE';	
	
    --RTJ 06/30/2021 populate import date using expected date (ocean, rail and truck) - secondary	
    UPDATE preftz.fed_conveyances fc	
       SET import_date = ao.arrival_date	
      FROM preftz.ams_ocean_land_response ao	
     WHERE fc.bill_of_lading_airwaybill = ao.issuer_code_of_master_bill_number || ao.master_bill_number --NKM 04/28/2023	
       AND fc.conveyance_status = 'COMPLETE'	
       AND fc.import_date IS NULL;	
	
    --RTJ 06/30/2021 populate import date using expected date (air)	
    UPDATE preftz.fed_conveyances fc	
       SET import_date = aa.arrival_date	
      FROM preftz.ams_air_response aa	
     WHERE fc.bill_of_lading_airwaybill = aa.air_waybill_number	
       AND fc.house_bill = aa.house_air_waybill_number	
       AND COALESCE(fc.house_bill_partial_indicator,'') = COALESCE(aa.part_indicator_house,'')	
       AND fc.conveyance_status = 'COMPLETE'	
       AND fc.import_date IS NULL;	
      	
    --RTJ 06/30/2021 populate export date (air)	
    UPDATE preftz.fed_conveyances fc	
       SET export_date = aa.arrival_date	
      FROM preftz.ams_air_response aa	
     WHERE fc.bill_of_lading_airwaybill = aa.air_waybill_number	
       AND (fc.house_bill = aa.house_air_waybill_number OR (fc.house_bill = 'NONE' AND aa.house_air_waybill_number = '')) --NKM 05/21/2024	
       AND COALESCE(fc.house_bill_partial_indicator,'') = COALESCE(aa.part_indicator_house,'')	
       AND fc.conveyance_status = 'COMPLETE'	
       AND fc.export_date IS NULL;	
	
    -- KK 2/7/2025 populate Charges	
    UPDATE preftz.fed_conveyances fc	
    SET charges = c.charges	
    FROM preftz.conveyances c	
    WHERE fc.bill_of_lading_airwaybill = c.bill_of_lading_airwaybill	
        AND fc.inbond_number = c.inbond_number	
        AND fc.charges IS NULL	
        AND fc.fed_status = 'NEW';	
	
    -- KK 2/7/2025 populate Gross Weight	
    UPDATE preftz.fed_conveyances fc	
    SET gross_weight = c.gross_weight	
    FROM preftz.conveyances c	
    WHERE fc.bill_of_lading_airwaybill = c.bill_of_lading_airwaybill	
        AND fc.inbond_number = c.inbond_number	
        AND fc.gross_weight IS NULL	
        AND fc.fed_status = 'NEW';	
	
    -- KK 2/7/2025 populate Country of Export	
    UPDATE preftz.fed_conveyances fc	
    SET country_of_export = c.country_of_export	
    FROM preftz.conveyances c	
    WHERE fc.bill_of_lading_airwaybill = c.bill_of_lading_airwaybill	
        AND fc.inbond_number = c.inbond_number	
        AND fc.country_of_export IS NULL	
        AND fc.fed_status = 'NEW';	
	
      -- KK 05/15/2026 Try to update house_bill_partial_indicator where required but null	
      WITH partial_indicator_missing AS (	
            --AMS shipment is split - House Bill Partial Indicator required'	
            SELECT DISTINCT fc.conveyanceid, fc.bill_of_lading_airwaybill, fc.house_bill, fc.inbond_number	
            FROM preftz.fed_conveyances fc	
                  JOIN preftz.ams_air_response aa	
                        ON fc.bill_of_lading_airwaybill = aa.air_waybill_number	
                  AND (   fc.house_bill = aa.house_air_waybill_number	
                        OR (fc.house_bill = 'NONE' AND aa.house_air_waybill_number = ''))	
      WHERE fc.fed_status <> 'DUPLICATE'	
            AND fc.conveyance_status = 'COMPLETE'	
            AND LEFT(fc.bill_of_lading_airwaybill,1) < 'A'	
            AND COALESCE(fc.house_bill_partial_indicator,'') = ''	
            AND COALESCE(aa.part_indicator_house,'') <> ''	
      ), indicator_updates AS (	
            SELECT pi.conveyanceid, wsc.part_indicator_house	
            FROM partial_indicator_missing pi	
            JOIN preftz.wsc on wsc.inbond_number = pi.inbond_number	
                  AND wsc.air_waybill_number = pi.bill_of_lading_airwaybill	
                  AND wsc.house_air_waybill_number = pi.house_bill	
      )	
      UPDATE preftz.fed_conveyances fc	
      SET house_bill_partial_indicator = iu.part_indicator_house	
      FROM indicator_updates iu	
      WHERE fc.conveyanceid = iu.conveyanceid;	
	
    COMMIT;	
	
    --zero pad airwaybills	
    UPDATE preftz.fed_conveyances fc	
       SET bill_of_lading_airwaybill = RIGHT('00000000000' || bill_of_lading_airwaybill, 11)	
     WHERE LEFT(bill_of_lading_airwaybill,1) BETWEEN '0' AND '9'	
     AND LENGTH(bill_of_lading_airwaybill) < 11;	
	
   INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','mark new duplicates');	
	
--EG 4/7/2026	
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK_CONCUR')	
    THEN	
       --check for duplicate records (previously fed)  inbond  must be unique in case of AUTO concur 	
       INSERT INTO preftz.feed_errors	
             (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
       SELECT v_table_name, fc.conveyanceid, 'bill_of_lading_airwaybill',	
              v_duplicate_msg1, fc.bill_of_lading_airwaybill || '/' ||	
              COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'') || '/' ||	
              COALESCE(fc.house_bill_partial_indicator,'') || '/' ||	
              COALESCE(TO_CHAR(fc.e214_date,'mm/dd/yyyy'),''),	
              fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.house_bill,'')	
         FROM preftz.fed_conveyances fc	
              INNER JOIN preftz.conveyances c	
                     ON COALESCE(fc.inbond_number,'') = COALESCE(c.inbond_number,'')
					 and COALESCE(fc.container,'') = COALESCE(c.container,'');	
	
       UPDATE preftz.fed_conveyances fc	
          SET fed_status = 'DUPLICATE'	
         FROM preftz.conveyances c	
        WHERE COALESCE(fc.inbond_number,'') = COALESCE(c.inbond_number,'');	
    END IF;	
--EG 4/7/2026    	
   	
    --check for duplicate records (previously fed)	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'bill_of_lading_airwaybill',	
           v_duplicate_msg2, fc.bill_of_lading_airwaybill || '/' ||	
           COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'') || '/' ||	
           COALESCE(fc.house_bill_partial_indicator,'') || '/' ||	
           COALESCE(TO_CHAR(fc.e214_date,'mm/dd/yyyy'),''),	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
           INNER JOIN preftz.conveyances c	
                   ON fc.bill_of_lading_airwaybill = c.bill_of_lading_airwaybill	
                  AND COALESCE(NULLIF(fc.house_bill,'NONE'),'') = COALESCE(c.house_bill,'') --NKM 05/21/2024	
                  AND COALESCE(fc.inbond_number,'') = COALESCE(c.inbond_number,'')	
                  AND COALESCE(fc.e214_date,'12/31/9999') = COALESCE(c.e214_date,'12/31/9999')	
                  AND COALESCE(fc.house_bill_partial_indicator,'') = COALESCE(c.house_bill_partial_indicator,'')
				  and COALESCE(fc.container,'') = COALESCE(c.container,'');	
          	
    UPDATE preftz.fed_conveyances fc	
       SET fed_status = 'DUPLICATE'	
      FROM preftz.conveyances c	
     WHERE fc.bill_of_lading_airwaybill = c.bill_of_lading_airwaybill	
       AND COALESCE(fc.house_bill,'') = COALESCE(c.house_bill,'')	
       AND COALESCE(fc.inbond_number,'') = COALESCE(c.inbond_number,'')	
       AND COALESCE(fc.e214_date,'12/31/9999') = COALESCE(c.e214_date,'12/31/9999')	
       AND COALESCE(fc.house_bill_partial_indicator,'') = COALESCE(c.house_bill_partial_indicator,'')
	   and COALESCE(fc.container,'') = COALESCE(c.container,'');	
      	
    --check for duplicate records (same file)	
    FOR dprs IN SELECT MIN(fc.conveyanceid) min_conveyance_id,	
                       fc.bill_of_lading_airwaybill, fc.house_bill,	
                       fc.house_bill_partial_indicator,fc.e214_date, fc.inbond_number,
					   fc.container
                  FROM preftz.fed_conveyances fc	
                 WHERE fc.fed_status <> 'DUPLICATE'	
                 GROUP BY fc.bill_of_lading_airwaybill, fc.inbond_number, fc.house_bill,	
                       fc.house_bill_partial_indicator,fc.e214_date	,fc.container
                HAVING count(*) > 1	
    LOOP	
        INSERT INTO preftz.feed_errors	
               (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
        SELECT v_table_name, fc.conveyanceid, 'bill_of_lading_airwaybill',	
               v_duplicate_msg3, fc.bill_of_lading_airwaybill || '/' ||	
               COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'') || '/' ||	
               COALESCE(fc.house_bill_partial_indicator,'') || '/' ||	
               COALESCE(TO_CHAR(fc.e214_date,'mm/dd/yyyy'),''),	
               fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.house_bill,'')	
          FROM preftz.fed_conveyances fc	
         WHERE fc.bill_of_lading_airwaybill = dprs.bill_of_lading_airwaybill	
           AND COALESCE(fc.inbond_number,'') = COALESCE(dprs.inbond_number,'')	
           AND COALESCE(fc.house_bill,'') = COALESCE(dprs.house_bill,'')	
           AND COALESCE(fc.e214_date,'12/31/9999') = COALESCE(dprs.e214_date,'12/31/9999')	
           AND COALESCE(fc.house_bill_partial_indicator,'') = COALESCE(dprs.house_bill_partial_indicator,'')
		   AND COALESCE(fc.container,'') = COALESCE(dprs.container,'')
           AND fc.conveyanceid > dprs.min_conveyance_id;	
          	
        UPDATE preftz.fed_conveyances fc	
           SET fed_status = 'DUPLICATE'	
         WHERE fc.bill_of_lading_airwaybill = dprs.bill_of_lading_airwaybill	
           AND COALESCE(fc.inbond_number,'') = COALESCE(dprs.inbond_number,'')	
           AND COALESCE(fc.house_bill,'') = COALESCE(dprs.house_bill,'')	
           AND COALESCE(fc.e214_date,'12/31/9999') = COALESCE(dprs.e214_date,'12/31/9999')	
           AND COALESCE(fc.house_bill_partial_indicator,'') = COALESCE(dprs.house_bill_partial_indicator,'')
		   and COALESCE(fc.container,'') = COALESCE(dprs.container,'')
           AND fc.conveyanceid > dprs.min_conveyance_id;	
    END LOOP;	
      	
	
    --Errors that preclude an AMS query	
	
  INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','process errors that preclude an AMS query');	
	
    --RTJ 03/18/2021 house_bill on non-air shipment	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'house_bill', v_non_air_house_msg, fc.house_bill,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.house_bill IS NOT NULL	
       AND LEFT(fc.bill_of_lading_airwaybill,1) NOT BETWEEN '0' AND '9';	
    --RTJ 03/18/2021	
	
    --missing house_bill	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'house_bill', v_missing_hbol_msg, fc.house_bill,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.house_bill IS NULL	
       AND LEFT(fc.bill_of_lading_airwaybill,1) BETWEEN '0' AND '9';	
	
    --house_bill_partial_indicator without house_bill	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'house_bill_partial_indicator',	
           v_partial_wo_hbol_msg, fc.house_bill_partial_indicator,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND NULLIF(fc.house_bill,'NONE') IS NULL --NKM 05/21/2024	
       AND fc.house_bill_partial_indicator IS NOT NULL;	
      	
    --set conveyance_status to NOQUERY - do not query AMS because the BOL/HBOL data is invalid	
    UPDATE preftz.fed_conveyances fc	
       SET conveyance_status = 'NOQUERY'	
      FROM preftz.feed_errors fe	
     WHERE fe.table_name = v_table_name	
       AND fe.tableid = fc.conveyanceid;	
	
	
    --query conveyances	
  INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','populate conveyance_queries to be queried');	
	
    --add new non-error bills to conveyance_queries table	
    INSERT INTO preftz.conveyance_queries (bill_of_lading_airwaybill, house_bill, conveyance_status)	
    SELECT DISTINCT fc.bill_of_lading_airwaybill, COALESCE(NULLIF(fc.house_bill,'NONE'),''), 'NEW'  --RTJ 06/30/2021 --NKM 05/21/2024	
      FROM preftz.fed_conveyances fc	
      LEFT JOIN preftz.conveyance_queries cq	
             ON fc.bill_of_lading_airwaybill = cq.bill_of_lading_airwaybill	
            AND COALESCE(NULLIF(fc.house_bill,'NONE'),'') = cq.house_bill	
          WHERE cq.bill_of_lading_airwaybill IS NULL	
            AND fc.conveyance_status = 'NEW';	
	
    CALL preftz.ams_query_conveyances();	
	
    --update query status from conveyance_status table --NKM 06/24/2021	
    UPDATE preftz.fed_conveyances fc	
       SET conveyance_status = cq.conveyance_status	
      FROM preftz.conveyance_queries cq	
     WHERE fc.bill_of_lading_airwaybill = cq.bill_of_lading_airwaybill	
       AND COALESCE(NULLIF(fc.house_bill,'NONE'),'') = cq.house_bill; --NKM 05/21/2024	
	
    --waiting for AMS query resonse	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'bill_of_lading_airwaybill',	
           v_waiting_for_ams_msg || ' sent at ' || to_char(ar.request_time::timestamptz,'HH24:MI TZ on MM/DD/YY'),	
           fc.bill_of_lading_airwaybill,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
      JOIN preftz.conveyance_queries cq	
        ON fc.bill_of_lading_airwaybill = cq.bill_of_lading_airwaybill	
       AND COALESCE(NULLIF(fc.house_bill,'NONE'),'') = cq.house_bill --NKM 05/21/2024	
      JOIN preftz.abi_requests ar ON ar.batchid = cq.batchid	
     WHERE fc.fed_status <> 'ERROR'	
       AND cq.conveyance_status = 'QUERIED';	
	
	
    --Errors that allow for an AMS query	
	
  INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','process errors that allow for an AMS query');	
	
    --invalid house_bill_partial_indicator	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'house_bill_partial_indicator',	
           v_partial_alpha_msg, fc.house_bill_partial_indicator,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND NOT fc.house_bill_partial_indicator BETWEEN 'A' AND 'Z';	
	
    --NKM 06/24/2021 Get inbond setting	
    v_require_inbonds=((preftz.get_ftz_setting('REQUIRE INBONDS') = 'REQUIRED') IS NOT FALSE);	
	
    --missing in-bond --NKM 06/24/2021	
    IF v_require_inbonds THEN	
       INSERT INTO preftz.feed_errors	
             (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
       SELECT v_table_name, fc.conveyanceid, 'inbond_number', v_missing_inbond_msg, fc.inbond_number,	
              fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.house_bill,'')	
         FROM preftz.fed_conveyances fc	
        WHERE fc.fed_status <> 'DUPLICATE'	
          AND fc.inbond_number IS NULL;	
    END IF;	
	
    --invalid in-bond format (N/A if inbond_number is NULL) --NKM 06/24/2021	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'inbond_number', v_invalid_inbond_msg, fc.inbond_number,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND NOT (fc.inbond_number ~ '^NONE$'    --No In-bond	
            OR  fc.inbond_number ~ '^[0-9]{9}$'      --CBP-assigned In-bond	
            OR  fc.inbond_number ~ '^V[0-9A-Z]{10}$' --AMS Paperless In-bond	
            OR  (fc.inbond_number ~ '^[0-9]{11}$')); --Air Waybill	
	
    --in-bond does not match air waybill (required for 11 digit in-bonds)	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'inbond_number', v_air_inbond_err_msg, fc.inbond_number,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.inbond_number ~ '^[0-9]{11}$' --Air Waybill	
       AND fc.inbond_number != COALESCE(fc.bill_of_lading_airwaybill,'');	
	
    --missing gross_weight	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'gross_weight', v_missing_weight_msg, fc.gross_weight,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND COALESCE(fc.gross_weight,0) <= 0;	
      	
    --missing charges	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'charges', v_missing_charges_msg, fc.charges,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND COALESCE(fc.charges,0) <= 0;	
      	
    --negative package quantity	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'package_quantity', v_negative_pkg_msg, fc.package_quantity,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND COALESCE(fc.package_quantity,0) < 0;	
   	
    --RTJ 06/30/2021 missing or invalid country of export	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'country_of_export', v_missing_coe_msg, fc.country_of_export,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND (   preftz.verify_country_code(fc.country_of_export) = 'FAIL'	
            OR fc.country_of_export = 'US');	
	
	
    --Errors based on AMS query results	
	
  INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','process errors based on AMS query results');	
      	
    --AMS error response	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'bill_of_lading_airwaybill/house_bill',	
           v_no_ams_match_msg, fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.house_bill,''),	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.conveyance_status = 'ERROR';	
      	
    --RTJ 06/30/2021 invalid vessel departure port (ocean)	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'vessel_departure_port', v_invalid_port_msg, fc.vessel_departure_port,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
           INNER JOIN preftz.ams_ocean_land_response ao	
                   ON fc.bill_of_lading_airwaybill = ao.issuer_code_of_master_bill_number || ao.master_bill_number --NKM 04/28/2023	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND (   preftz.verify_port_code(fc.vessel_departure_port) = 'FAIL'	
            OR NOT(fc.vessel_departure_port ~ '^[0-9]{5}$'))	
       AND COALESCE(fc.vessel_departure_port,'') <> ''	
       AND ao.mode_of_transportation LIKE '1%';	
      	
    --RTJ 06/30/2021 US vessel departure port (ocean)	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'vessel_departure_port', v_port_country_msg, fc.vessel_departure_port,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
           INNER JOIN preftz.ams_ocean_land_response ao	
                   ON fc.bill_of_lading_airwaybill = ao.issuer_code_of_master_bill_number || ao.master_bill_number --NKM 04/28/2023	
           INNER JOIN preftz.port_codes pc	
                   ON fc.vessel_departure_port = pc.port_code	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND pc.port_country = 'US'	
       AND ao.mode_of_transportation LIKE '1%';	
      	
    --RTJ 06/30/2021 export/import date mismatch	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'export_date', v_date_mismatch_msg, fc.export_date || ' / ' || fc.import_date,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.import_date < fc.export_date;	
	
    --NKM 11/17/2022 missing export date	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'export_date', v_missing_ex_date_msg, fc.export_date,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.conveyance_status = 'COMPLETE' --only check after query is returned successfully	
       AND fc.export_date IS NULL;	
	
    --NKM 11/17/2022 missing import date	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'import_date', v_missing_im_date_msg, fc.import_date,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.conveyance_status = 'COMPLETE' --only check after query is returned successfully	
       AND fc.import_date IS NULL;	
	
    --house partial indicator fed for non-split shipment	
 --AMS shipment is not split - House Bill Partial Indicator must be empty	
 -- MH 8/7/2025 added with ams_air_response and left join to handle scenerio when there is null and A/B	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
   with ams_air_response as(	
 select aa.air_waybill_number , aa.house_air_waybill_number  , aa.part_indicator_house	
  from preftz.ams_air_response aa where COALESCE(part_indicator_house,'') <> ''	
 )	
     SELECT v_table_name, fc.conveyanceid, 'house_bill_partial_indicator',	
           v_no_partial_needed_msg, fc.house_bill_partial_indicator,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
               LEFT JOIN ams_air_response aa	
                  ON fc.bill_of_lading_airwaybill = aa.air_waybill_number	
                 AND (   fc.house_bill = aa.house_air_waybill_number	
                      OR (fc.house_bill = 'NONE' AND aa.house_air_waybill_number = '')) --NKM 05/21/2024	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.conveyance_status = 'COMPLETE'           --NKM 06/24/2021	
       AND LEFT(fc.bill_of_lading_airwaybill,1) < 'A'	
       AND COALESCE(fc.house_bill_partial_indicator,'') <> ''	
       AND COALESCE(aa.part_indicator_house,'') = '';  -- MH 8/5/2025	
           	
    --no house partial indicator fed for split shipment	
 --'AMS shipment is split - House Bill Partial Indicator required';	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT DISTINCT --AMS can have multiple records for a split shipment	
           v_table_name, fc.conveyanceid, 'house_bill_partial_indicator',	
           v_partial_required_msg, fc.house_bill_partial_indicator,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
                JOIN preftz.ams_air_response aa	
                  ON fc.bill_of_lading_airwaybill = aa.air_waybill_number	
                 AND (   fc.house_bill = aa.house_air_waybill_number	
                      OR (fc.house_bill = 'NONE' AND aa.house_air_waybill_number = '')) --NKM 05/21/2024	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.conveyance_status = 'COMPLETE'           --NKM 06/24/2021	
       AND LEFT(fc.bill_of_lading_airwaybill,1) < 'A'	
       AND COALESCE(fc.house_bill_partial_indicator,'') = ''	
       AND COALESCE(aa.part_indicator_house,'') <> '';   -- MH 8/5/2025	
	
    --Missing or Unknown AMS response for BOL (ocean)	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'bill_of_lading_airwaybill',	
           v_no_ams_details_msg, fc.bill_of_lading_airwaybill,	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
           LEFT JOIN preftz.ams_ocean_land_response ao	
                  ON fc.bill_of_lading_airwaybill = ao.issuer_code_of_master_bill_number || ao.master_bill_number --NKM 04/28/2023	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.conveyance_status = 'COMPLETE'           --NKM 06/24/2021	
       AND LEFT(fc.bill_of_lading_airwaybill,1) >= 'A'	
       AND ao.master_bill_number IS NULL;	
      	
    --Missing or Unknown AMS response for BOL/HBOL (air) - general case	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'bill_of_lading_airwaybill/house_bill',	
           v_no_ams_details_msg, fc.bill_of_lading_airwaybill || '/' ||	
           fc.house_bill || '/' || COALESCE(fc.house_bill_partial_indicator,''),	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
           LEFT JOIN preftz.ams_air_response aa	
                  ON fc.bill_of_lading_airwaybill = aa.air_waybill_number	
                 AND (   fc.house_bill = aa.house_air_waybill_number	
                      OR (fc.house_bill = 'NONE' AND aa.house_air_waybill_number = '')) --NKM 05/21/2024	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.conveyance_status = 'COMPLETE'           --NKM 06/24/2021	
       AND LEFT(fc.bill_of_lading_airwaybill,1) < 'A'	
       AND aa.air_waybill_number IS NULL	
       AND fc.house_bill IS NOT NULL; --NKM 05/21/2024	
     	
    --Missing or Unknown AMS response for BOL/HBOL/split (air) - special case: split indicator not found in AMS	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT DISTINCT	
           v_table_name, fc.conveyanceid, 'bill_of_lading_airwaybill/house_bill',	
           v_no_ams_split_msg, fc.bill_of_lading_airwaybill || '/' ||	
           fc.house_bill || '/' || COALESCE(fc.house_bill_partial_indicator,''),	
           fc.bill_of_lading_airwaybill || '/' || COALESCE(fc.inbond_number,'') || '/' || COALESCE(fc.house_bill,'')	
      FROM preftz.fed_conveyances fc	
           JOIN preftz.ams_air_response aa	
                  ON fc.bill_of_lading_airwaybill = aa.air_waybill_number	
                 AND (   fc.house_bill = aa.house_air_waybill_number	
                      OR (fc.house_bill = 'NONE' AND aa.house_air_waybill_number = '')) --NKM 05/21/2024	
                 AND fc.house_bill_partial_indicator <> aa.part_indicator_house --not matched indicator	
           LEFT JOIN (SELECT fc.conveyanceid	
                        FROM preftz.fed_conveyances fc	
                        JOIN preftz.ams_air_response aa	
                          ON fc.bill_of_lading_airwaybill = aa.air_waybill_number	
                         AND (   fc.house_bill = aa.house_air_waybill_number	
                              OR (fc.house_bill = 'NONE' AND aa.house_air_waybill_number = '')) --NKM 05/21/2024	
                         AND fc.house_bill_partial_indicator = aa.part_indicator_house) x --matched indicator	
                  ON fc.conveyanceid = x.conveyanceid	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.conveyance_status = 'COMPLETE'           --NKM 06/24/2021	
       AND x.conveyanceid IS NULL --only unmatched indicators	
       AND aa.part_indicator_house <> ''  --only split shipments	
       AND fc.house_bill IS NOT NULL; --NKM 05/21/2024	
	
    --AMS shows AWB has HBOL, but fed_conveyances has an HBOL of 'NONE' (air) --NKM 05/21/2024	
    INSERT INTO preftz.feed_errors	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
    SELECT v_table_name, fc.conveyanceid, 'bill_of_lading_airwaybill/house_bill', v_ams_has_hbol_msg,	
           CONCAT_WS('/', fc.bill_of_lading_airwaybill, fc.house_bill, COALESCE(fc.house_bill_partial_indicator,'')),	
           CONCAT_WS('/', fc.bill_of_lading_airwaybill, COALESCE(fc.inbond_number,''), COALESCE(fc.house_bill,''))	
      FROM preftz.fed_conveyances fc	
                JOIN preftz.ams_air_response aa	
                  ON fc.bill_of_lading_airwaybill = aa.air_waybill_number               --conveyance matches a master AWB in AMS	
                 AND (fc.house_bill IN('NONE','') AND aa.house_air_waybill_number = '') --conveyance has no house bill	
                JOIN (SELECT DISTINCT air_waybill_number FROM preftz.ams_air_response WHERE house_air_waybill_number <> '') hb	
                  ON hb.air_waybill_number = fc.bill_of_lading_airwaybill               --AMS has house bills	
     WHERE fc.fed_status <> 'DUPLICATE'	
       AND fc.conveyance_status = 'COMPLETE'	
       AND LEFT(fc.bill_of_lading_airwaybill,1) < 'A';	
	
     --AMS response exists, but inbond number is not associated with BOL in AMS (ocean) --NKM 06/24/2021	
     INSERT INTO preftz.feed_errors	
           (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
     SELECT v_table_name, fc.conveyanceid, 'inbond_number/bill_of_lading_airwaybill',	
            v_ib_bill_mismatch_msg, CONCAT_WS('/',fc.inbond_number,fc.bill_of_lading_airwaybill),	
            CONCAT_WS('/',fc.inbond_number,fc.bill_of_lading_airwaybill)	
       FROM preftz.fed_conveyances fc	
            JOIN preftz.ams_ocean_land_response ao	
              ON fc.bill_of_lading_airwaybill = ao.issuer_code_of_master_bill_number || ao.master_bill_number --NKM 04/28/2023	
       LEFT JOIN preftz.wn1	
              ON wn1.wr1id = ao.wr1id	
             AND wn1.inbond_entry_number = fc.inbond_number	
      WHERE fc.fed_status <> 'DUPLICATE'	
        AND fc.conveyance_status = 'COMPLETE'	
        AND LEFT(fc.bill_of_lading_airwaybill,1) >= 'A'	
        AND wn1.inbond_entry_number IS NULL	
        AND COALESCE(fc.inbond_number,'NONE')<>'NONE'	
        AND (fc.inbond_number ~ '^[0-9]{9}$'    --Valid in-bond format --CBP-assigned In-bond	
             OR  fc.inbond_number ~ '^V[0-9A-Z]{10}$');               --AMS Paperless In-bond	
	
     --AMS response exists, but inbond number is not associated with BOL in AMS (air) --NKM 06/24/2021	
     INSERT INTO preftz.feed_errors	
           (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
     SELECT DISTINCT	
            v_table_name, fc.conveyanceid, 'inbond_number/bill_of_lading_airwaybill/house_bill',	
            v_ib_bill_mismatch_msg, CONCAT_WS('/',fc.inbond_number,fc.bill_of_lading_airwaybill,fc.house_bill),	
            CONCAT_WS('/',fc.inbond_number,fc.bill_of_lading_airwaybill,fc.house_bill)	
       FROM preftz.fed_conveyances fc	
            JOIN preftz.ams_air_response aa	
              ON fc.bill_of_lading_airwaybill = aa.air_waybill_number	
             AND (   fc.house_bill = aa.house_air_waybill_number	
                  OR (fc.house_bill = 'NONE' AND aa.house_air_waybill_number = '')) --NKM 05/21/2024	
             AND COALESCE(fc.house_bill_partial_indicator,'') = aa.part_indicator_house	
       LEFT JOIN preftz.wn1 ON wn1.wr1id = aa.wr1id AND wn1.inbond_entry_number = fc.inbond_number	
      WHERE fc.fed_status <> 'DUPLICATE'	
        AND fc.conveyance_status = 'COMPLETE'	
        AND LEFT(fc.bill_of_lading_airwaybill,1) < 'A'	
        AND wn1.inbond_entry_number IS NULL	
        AND COALESCE(fc.inbond_number,'NONE')<>'NONE'	
        AND (fc.inbond_number ~ '^[0-9]{9}$'    --Valid in-bond format                --CBP-assigned In-bond	
             OR  fc.inbond_number ~ '^V[0-9A-Z]{10}$'                                 --AMS Paperless In-bond	
             OR (fc.inbond_number ~ '^[0-9]{11}$'	
                 AND fc.inbond_number = COALESCE(fc.bill_of_lading_airwaybill,'')));  --Air Waybill	
	
     --Get FTZ port --NKM 06/24/2021	
     SELECT location_port_code	
       INTO v_location_port_code	
       FROM preftz.ftz_reference;	
  /* -- MH 05/05/2026 commented out 	
     --inbond is associated with BOL, but inbond is not bound for FTZ port --NKM 06/24/2021	
     INSERT INTO preftz.feed_errors	
           (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
     SELECT DISTINCT	
            v_table_name, fc.conveyanceid, 'inbond_number',	
            v_ib_destination_msg, fc.inbond_number, fc.inbond_number	
       FROM preftz.fed_conveyances fc	
            JOIN (SELECT ao.issuer_code_of_master_bill_number || ao.master_bill_number AS bill_of_lading_airwaybill, --NKM 04/28/2023	
                         '' AS house_bill, ao.wr1id	
                    FROM preftz.ams_ocean_land_response ao	
                   UNION	
                  SELECT aa.air_waybill_number AS bill_of_lading_airwaybill,	
                         aa.house_air_waybill_number AS house_bill, aa.wr1id	
                    FROM preftz.ams_air_response aa) AS ams	
              ON fc.bill_of_lading_airwaybill = ams.bill_of_lading_airwaybill	
             AND COALESCE(NULLIF(fc.house_bill,'NONE'),'') = ams.house_bill   --valid AMS response exists --NKM 05/21/2024	
            JOIN preftz.wn1 ON wn1.wr1id = ams.wr1id	
                           AND wn1.inbond_entry_number=fc.inbond_number  --fed inbond is associated with fed BOL	
       LEFT JOIN preftz.wn1 n1 ON n1.wr1id = ams.wr1id	
                              AND COALESCE(NULLIF(n1.inbond_manual_diversion_port,''),	
                                           NULLIF(n1.inbond_edi_diversion_port,''),	
                                           NULLIF(n1.manifested_inbond_port,'')) = v_location_port_code --bound for ftz port	
      WHERE fc.fed_status <> 'DUPLICATE'	
        AND fc.conveyance_status = 'COMPLETE'	
        AND n1.inbond_entry_number IS NULL	
        AND COALESCE(fc.inbond_number,'NONE')<>'NONE';	
 */	
     --NKM 10/03/2022 Receipts linked to this conveyance are on a 214 that has been concurred	
     INSERT INTO preftz.feed_errors	
           (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
     SELECT DISTINCT	
            v_table_name, fc.conveyanceid, 'zone_admission_no',	
            v_linking_err_msg, efs.zone_admission_no,	
            CONCAT_WS('/',fc.inbond_number,fc.bill_of_lading_airwaybill,fc.house_bill,fc.house_bill_partial_indicator)	
      FROM preftz.receipts r	
      JOIN preftz.fed_conveyances fc ON fc.conveyanceid = r.conveyanceid	
      JOIN preftz.e214_filing_statuses efs ON efs.zone_admission_no = r.zone_admission_no	
     WHERE COALESCE(efs.concur_status,'') NOT IN ('','REJECTED');	
	
 INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','set ERROR status');	
    --set fed_status to ERROR	
    UPDATE preftz.fed_conveyances fc	
       SET fed_status = 'ERROR'	
      FROM preftz.feed_errors fe	
     WHERE fe.table_name = v_table_name	
       AND fe.tableid = fc.conveyanceid	
       AND fc.fed_status <> 'DUPLICATE';	
  	
	
  INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','check duplicates that have been linked to concurred admission');	
 -- check for all DUPLICATE conveyances that have been linked to concurred admission - should not be deleted	
 UPDATE preftz.fed_conveyances	
 SET fed_status = 'DUPERROR'	
 where conveyanceid IN(	
 SELECT  rec.conveyanceid	
 FROM preftz.fed_receipts rec	
 JOIN preftz.fed_conveyances fc on fc.conveyanceid = rec.conveyanceid	
 LEFT JOIN preftz.e214_filing_statuses es on rec.zone_admission_no = es.zone_admission_no	
 where fc.fed_status = 'DUPLICATE'	
 AND COALESCE(es.concur_status,'') NOT  IN('','REJECTED')	
 );	
	
	
 UPDATE preftz.fed_conveyances	
 SET fed_status = 'DUPERROR'	
 where conveyanceid IN(	
 SELECT  rec.conveyanceid	
 FROM preftz.receipts rec	
 JOIN preftz.fed_conveyances fc on fc.conveyanceid = rec.conveyanceid	
 LEFT JOIN preftz.e214_filing_statuses es on rec.zone_admission_no = es.zone_admission_no	
 where fc.fed_status = 'DUPLICATE'	
 AND COALESCE(es.concur_status,'') NOT IN('','REJECTED')	
 );	
	
 -- insert new feed_error message for conveyances that are linked to admission that has been concurred	
  INSERT INTO preftz.feed_errors	
           (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)	
     SELECT DISTINCT	
           v_table_name,fc.conveyanceid, 'zone_admission_no',v_duplicate_linking_err_msg,	
   COALESCE(rec.zone_admission_no,frec.zone_admission_no),	
            CONCAT_WS('/',fc.inbond_number,fc.bill_of_lading_airwaybill,fc.house_bill,fc.house_bill_partial_indicator)	
      FROM preftz.fed_conveyances fc	
   LEFT JOIN preftz.receipts rec on fc.conveyanceid = rec.conveyanceid	
   LEFT JOIN preftz.fed_receipts frec on fc.conveyanceid = frec.conveyanceid	
   WHERE fc.fed_status = 'DUPERROR';	
 	
 --  UPDATE preftz.fed_conveyances	
 --  SET fed_status = 'ERROR'	
 --  where fed_status = 'DUPERROR';	
 	
	
  INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','add valid records');	
    --insert non-ERROR records with ocean responses to conveyances table	
    INSERT INTO preftz.conveyances	
          (bill_of_lading_airwaybill, house_bill, e214_date, gross_weight, charges, package_quantity,	container,
           conveyanceid, inbond_number, vessel_departure_port, country_of_export, export_date, import_date)  --RTJ 06/30/2021	
    SELECT DISTINCT fc.bill_of_lading_airwaybill, fc.house_bill, fc.e214_date, fc.gross_weight,	
           fc.charges, fc.package_quantity, fc.container, fc.conveyanceid, fc.inbond_number,	
           fc.vessel_departure_port, fc.country_of_export, fc.export_date, fc.import_date  --RTJ 06/30/2021	
      FROM preftz.fed_conveyances fc	
           INNER JOIN preftz.ams_ocean_land_response ao	
                   ON fc.bill_of_lading_airwaybill = ao.issuer_code_of_master_bill_number || ao.master_bill_number --NKM 04/28/2023	
     WHERE fc.fed_status = 'NEW';	
   	
    --insert non-ERROR records with air responses to conveyances table	
    --RTJ 07/01/2021 do not include vessel departure port	
    INSERT INTO preftz.conveyances	
          (bill_of_lading_airwaybill, house_bill, e214_date, gross_weight, charges, package_quantity,	
           house_bill_partial_indicator, conveyanceid, inbond_number, country_of_export, export_date, import_date)  --RTJ 06/30/2021	
    SELECT DISTINCT fc.bill_of_lading_airwaybill, CASE WHEN fc.house_bill = 'NONE' THEN '' ELSE fc.house_bill END, --NKM 05/21/2024	
           fc.e214_date, fc.gross_weight,	
           fc.charges, fc.package_quantity, aa.part_indicator_house, fc.conveyanceid, fc.inbond_number,	
           fc.country_of_export, export_date, import_date  --RTJ 06/30/2021	
      FROM preftz.fed_conveyances fc	
           INNER JOIN preftz.ams_air_response aa	
                   ON fc.bill_of_lading_airwaybill = aa.air_waybill_number	
                  AND (   fc.house_bill = aa.house_air_waybill_number	
                       OR (fc.house_bill = 'NONE' AND aa.house_air_waybill_number = '')) --NKM 05/21/2024	
                  AND COALESCE(fc.house_bill_partial_indicator,'') = COALESCE(aa.part_indicator_house,'')	
     WHERE fc.fed_status = 'NEW';	
    	
    --RTJ 03/17/2021 update zone_admission_no if associated receipts already linked	
    UPDATE preftz.conveyances c	
       SET zone_admission_no = r.zone_admission_no	
      FROM preftz.receipts r	
     WHERE r.conveyanceid = c.conveyanceid	
       AND COALESCE(r.zone_admission_no,'') <> ''	
       AND COALESCE(c.zone_admission_no,'') = '';	
    --RTJ 03/17/2021	
   	
    --RTJ 07/21/2021 update e214 status for updated conveyance records	
    --NKM 10/03/2022 changed to use update_e214_after_create	
    FOR ars IN SELECT c.zone_admission_no	
                FROM preftz.conveyances c	
                JOIN preftz.fed_conveyances fc ON fc.conveyanceid = c.conveyanceid	
    LOOP	
        CALL preftz.update_e214_after_create(ars.zone_admission_no); --NKM 10/03/2022	
    END LOOP;	
    --RTJ 07/21/2021	
	
    --NKM 05/31/2022 --Assign conveyance to current admission if has linked receipts but does not already have an admission number	
  INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','assign conveyances');	
    FOR crs IN SELECT DISTINCT c.conveyanceid	
                 FROM preftz.conveyances c	
                 JOIN preftz.receipts r ON r.conveyanceid = c.conveyanceid	
                WHERE COALESCE(c.zone_admission_no,'') = ''	
    LOOP	
        IF v_current_admission_no IS NULL THEN	
           v_current_admission_no = preftz.get_current_zone_admission_number();	
        END IF;	
	
        CALL preftz.assign_conveyances_to_214(crs.conveyanceid, v_current_admission_no);	
    END LOOP;	
    --NKM 05/31/2022	
   	
    --delete all non-ERROR records with responses	
    DELETE FROM preftz.fed_conveyances fc	
     USING preftz.conveyances c	
     WHERE fc.conveyanceid = c.conveyanceid;	
   	
    GET DIAGNOSTICS v_update_count = ROW_COUNT;	
    COMMIT;	
	
--EG 4/7/2026	
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK_CONCUR') 	
    THEN 	
       CALL preftz.link_receipts_to_conveyances_by_inbond();	
       CALL preftz.assign_zone_admission();	
    END IF;	
--EG 4/7/2026    	
	
	
    --record statistics	
    INSERT INTO preftz.system_log (procedure_name, log_message)	
    SELECT 'audit_fed_conveyances',	
           (CASE fed_status	
                 WHEN 'NEW' THEN 'WAITING'	
                 ELSE fed_status	
                 END) || TO_CHAR(COUNT(*),'999999')	
      FROM preftz.fed_conveyances	
     GROUP BY fed_status ;	
	
    INSERT INTO preftz.system_log(procedure_name, log_message)	
        VALUES ('audit_fed_conveyances', 'IMPORTED' || TO_CHAR(v_update_count,'999999'));	
	
    INSERT INTO preftz.system_log (procedure_name, log_message)	
        VALUES ('audit_fed_conveyances','finished');	
       	
	
END;	
$BODY$;
-- DROP PROCEDURE preftz.create_e214(varchar);

CREATE OR REPLACE PROCEDURE preftz.create_e214(IN p_admission_number character varying)
 LANGUAGE plpgsql
AS $procedure$
	
--Change Log:
-- KK 09/10/2026 Use classification_date in preference to e214_date when creating e214.
-- KK 08/12/2026 refresh view AFTER audit_e214_data because a new tariff may have been inserted into hts ref table.
--NO 07/14/2026 Change condition for ft43 record creation
--EG 4/7/2026 link and auto delete pre-receipts project DEV-257
--NO 2/24/2026 Create hmf from e214, inserts into archive_hmf_details table, added check for function to account for possible version issues
--EG 2/23/2026 fix for multiple ports of unlading for one BOL
--KK 02/16/2026 do not do the charges fix loop if the array v_charges_err is empty or null.
--NO 01/21/2026 added FT43 container records when PROCESS PRE_RECEIPTS setting is CONTAINER
--MH 9/11/2025 added export_date to brs loop(bols) to no duplicate conveyances with same arrival date
--MH 6/24/2025 moved audit for missing conveyance to audit_e214_data to link in receipts
-- KK 06/19/2025 audit for missing conveyance.	
--NKM 03/28/2024 Now reports a minimum HTS quantity of 0.01 on FT50 records	
--NKM 03/14/2024 Excluded domestic goods from total conveyance net weight calculation	
--NKM 10/02/2023 Prevents reporting a separate applicant_for_admission when it is the same as the ftz_irs_number	
--NKM 09/07/2023 Expanded selected_bols_for_214 to include the issuer code on ocean/land bills (this edit was previously listed under 04/28/2023)	
--MH 08/24/2023 added delete from data audit message at  beginning to remove duplicate e214 status messages	
--NKM 06/20/2023 Changed hts_units to a materialized view	
--NKM 03/15/2023 added set_pga_document_status for handling of PGAs	
--NKM 02/01/2023 added abi_an formatting to descriptions from parts table used in FT60 records	
--RTJ 01/19/2023 added unit assist/receipt_dutiable_fees	
--NKM 11/17/2022 import and export dates now always come from conveyance record	
--NKM 10/12/2022 added quantity and units from base HTS to chapter 98 HTSs	
--MH  10/12/2022 changed p_zone_admission_no to p_admission_number	
--MH  10/11/2022 added () to function	
--NKM 10/03/2022 Added has_pre-receipts and physical_arrival_status to e214_filing_statuses	
--               Standardized criteria for editing 214 data	
--RTJ 09/05/2022 Add tariff type sort to HTS listing	
--NKM 05/19/2022 Includes import licenses on adjustments	
--JM  05/05/2022 Added insert for query at line 679, added s to wr1id at line 693	
--NKM 05/05/2022 Now recognizes chapter 99 HTSs with a unit_1 = '' on adjustments	
--NKM 04/29/2022 Now recognizes chapter 99 HTSs with a unit_1 = ''	
--NKM 03/31/2022 Added use of location_port_code	
--NKM 03/21/2022 Restructured handling of zone_to_zone transfers	
--NKM 02/14/2022 Added combined Master AWB/House AWB to FT41 record when House AWB serves as in-bond number	
--NKM 02/03/2022 Added aluminum and steel import licenses	
--NKM 12/16/2021 Allows for 3 character carrier codes on air shipments	
--NKM 09/23/2021 Adjusts for roundoff error in the FT50 line item charges to assure the total charges match the conveyance	
--RTJ 08/08/2021 add temporary_deposit_status to e214_filing_statuses	
--RTJ 07/21/2021 Modify update to country of export on receipts record 	
--RTJ 07/14/2021 Add zone-to-zone_transfers without a carrier BOL 	
--               (receipts.conveyanceid IS NULL)	
--RTJ 07/09/2021 add delete_status to e214_filing_statuses	
--RTJ 07/08/2021 Add zone-to-zone transfers using the carrier's BOL	
--RTJ 07/05/2021 change v_total_weight to double precision to match weight on parts table	
--RTJ 06/30/2021 Pull country of export, vessel departure port, import date	
--               and export date from conveyances record if provided	
	
--RTJ 06/29/2021 Add house bill partial indicator to get_hts_line_number	
--NKM 06/24/2021 Added inbond_number to receipt and conveyance records	
--RTJ 06/21/2021 Handle filing a replacement 214 including:	
--               1) setting action code appropriately	
--               2) tracking HTS line numbers	
--               3) including FT11/FT12 records in replacement file	
--               4) confirming 214 is in unconcurred status	
	
--NKM 06/11/2021 Now only uses AMS manifest quantity when conveyance quantity is zero	
--	
--RTJ 05/21/2021 Make sure 214 is in an un-filed status	
--               Update insert into FT40 for adjustments	
	
--RTJ 05/13/2021 Use a package count of 1 on overage FT40 records to allow for	
--               an overage 214 to be concurred	
	
--NKM 03/29/2021 Now creates an FT41 record for every in-bond using the wn1 table	
--RTJ 03/05/2021 Add receipt/classification data for foreign up adjusts	
	
--RTJ 01/22/2021 truncate part description to 45 characters	
	
--RTJ 10/17/2020 removed reference to arrival_date_offset; 	
--               using arrival date for export date for air shipments	
	
--RTJ 11/15/2020 account for zero quantity receipts	
	
--This procedure requires that all receipts be linked to their corresponding conveyances record	
--through a conveyanceid on both records and that the appropriate zone_admission_no be recorded	
--on both the conveyances record and the receipts record.	
	
DECLARE	
    v_audit_result  VARCHAR(10);	
    v_ft10id        INTEGER;	
    v_firms         VARCHAR(4);	
    crs             RECORD;  --conveyance record	
    v_ft20id        INTEGER;	
    brs             RECORD;  --bill of lading record	
    v_ft40id        INTEGER;	
    v_pkg_count     INTEGER;	
    irs             RECORD;  --inbond record	
    rrs             RECORD;  --receipt record	
    urs             RECORD;  --update receipts record	
    line_count      INTEGER;	
    hts_count       INTEGER;	
    prev_line_group VARCHAR;	
    v_total_weight  DOUBLE PRECISION;  --RTJ 07/05/2021	
    v_gross_weight  INTEGER;	
    v_charges       DOUBLE PRECISION;  --NKM 09/23/2021	
    v_hmf_fee       NUMERIC;	
    v_spi_type      VARCHAR(1);	
    v_ft50id        INTEGER;	
    drs             RECORD;  --description record	
    v_value         NUMERIC;	
    v_qty1_rnd      NUMERIC;	
    v_qty2_rnd      NUMERIC;	
    v_base_uom      VARCHAR(3);	
    v_base_qty      NUMERIC;	
    v_unit_1        VARCHAR(3);	
    v_unit_2        VARCHAR(3);	
    ars             RECORD;  --adjust record	
    v_first_adjust  BOOLEAN;	
    v_weight_rnd    NUMERIC;	
    v_charges_rnd   NUMERIC; 	
    v_create_status VARCHAR(20);  --RTJ 06/21/2021	
    v_action_code   CHAR(1);  --RTJ 06/21/2021	
    prs             RECORD;  --RTJ 06/21/2021replace record	
    v_first_reason  CHAR(2);  --RTJ 06/21/2021	
    v_reason_count  INTEGER;  --RTJ 06/21/2021	
    v_additional_reasons VARCHAR(14);  --RTJ 06/21/2021	
    v_require_inbonds BOOLEAN; --NKM 06/24/2021	
    v_first_ztz     BOOLEAN;  --RTJ 07/08/2021	
    bzrs            RECORD;   --NKM 03/21/2022 ztz bols	
    rzrs            RECORD;   --NKM 03/21/2022 ztz receipts	
    uzrs            RECORD;   --NKM 03/21/2022 update ztz receipts record	
    dzrs            RECORD;   --NKM 03/21/2022 ztz description record	
    v_total_charges INTEGER;  --NKM 09/23/2021 total charges for the current BOL	
    v_charges_err   DOUBLE PRECISION[];  --NKM 09/23/2021 roundoff error of charges by HTS line	
    v_charges_fix   INTEGER;  --NKM 09/23/2021 whole dollar changes needed to correct for roundoff error in total charges	
    v_sign          INTEGER;  --NKM 09/23/2021 sign of v_charges_fix (+/-)	
    v_fix_line      INTEGER;  --NKM 09/23/2021 HTS line number to be changed by one dollar	
    v_concur_status             VARCHAR(10); --NKM 10/03/2022	
    v_option_create             BOOLEAN;     --NKM 10/03/2022	
    v_has_pre_receipts          BOOLEAN;     --NKM 10/03/2022	
    v_physical_arrival_status   VARCHAR(10); --NKM 10/03/2022	
    v_classify_date             DATE DEFAULT CURRENT_DATE;
	
BEGIN	
  INSERT INTO preftz.system_log (procedure_name, log_message) 	
  VALUES ('create_e214', 'started: ' || p_admission_number);	
  DELETE FROM preftz.data_audit_messages where audit_document = p_admission_number;--MH 08/24/2023 	
  	
  --RTJ 06/21/2021 ensure 214 is in an unconcurred status	
  --NKM 10/03/2022 added use option_create	
  SELECT concur_status, option_create	
    INTO v_concur_status, v_option_create	
    FROM preftz.e214_filing_statuses efs, preftz.e214_action_options_function() aof	
   WHERE efs.zone_admission_no = p_admission_number	
     AND aof.zone_admission_no = p_admission_number;	
	
  IF COALESCE(v_option_create,FALSE) IS NOT TRUE THEN  --NKM 10/03/2022	
	
      IF COALESCE(v_concur_status,'') IN('','REJECTED') THEN --NKM 10/03/2022 added details on reason for failure	
	
          INSERT INTO preftz.data_audit_messages (audit_document, audit_message)	
          VALUES (p_admission_number, 'e214 not eligible to be filed');	
          v_audit_result = 'FAIL';	
          v_create_status = 'Not allowed';	
      	
      ELSE	
	
          INSERT INTO preftz.data_audit_messages (audit_document, audit_message)	
          VALUES (p_admission_number, 'e214 already concurred');	
          v_audit_result = 'FAIL';	
          v_create_status = 'Already Concurred';	
	
      END IF;	
	
	
	
  ELSE	
	
      --RTJ 06/21/2021 check if 214 is currently filed with CBP	
      IF (SELECT efs.currently_filed FROM preftz.e214_filing_statuses efs	
           WHERE efs.zone_admission_no = p_admission_number) = 'Y' THEN	
          v_action_code = 'R';	
      ELSE	
          v_action_code = 'A';	
          DELETE FROM preftz.e214_hts_line_numbers 	
           WHERE admission_number = p_admission_number;	
      END IF;	
      --RTJ 06/21/2021	
      	
      DELETE FROM preftz.selected_bols_for_214;	
      	
      INSERT INTO preftz.selected_bols_for_214 (bill_of_lading_airwaybill)	
      SELECT DISTINCT c.bill_of_lading_airwaybill --NKM 09/07/2023	
        FROM preftz.conveyances c	
       WHERE c.zone_admission_no = p_admission_number;	

--EG 4/7/2026 link and auto delete pre-receipts project DEV-257
/*      	
      COMMIT;	-- EG will create an error 
SQL Error [2D000]: ERROR: invalid transaction termination
  Where: PL/pgSQL function create_e214(character varying) line 185 at COMMIT
SQL statement "CALL preftz.create_e214(crs.zone_admission_no)"
*/
--EG 4/7/2026 link and auto delete pre-receipts project DEV-257
	
      SELECT ft10id INTO v_ft10id	
        FROM preftz.ft10	
       WHERE calendar_year = LEFT(p_admission_number,2)	
         AND control_number = SUBSTR(p_admission_number,3,8);	
         	
      IF v_ft10id IS NOT NULL THEN	
          call preftz.remove_previous_e214_data (v_ft10id);	
      END IF;	
          	
      v_audit_result = preftz.audit_e214_data(p_admission_number);

      -- KK 09/10/2026 instead of using materialized view hts_units, use temp table.
      -- this is to allow the classification_date to determine what HTS are in the table; instead of current_date
      DROP TABLE IF EXISTS hts_units_temp;
      CREATE TABLE hts_units_temp (
        tariff_number VARCHAR UNIQUE NOT NULL, 
        unit_1 VARCHAR, 
        unit_2 VARCHAR
      );
      CREATE INDEX IF NOT EXISTS idx_hts_units_temp_tariff_number ON hts_units_temp (tariff_number);

      SELECT COALESCE(classification_date, CURRENT_DATE) AS classify_date
      INTO v_classify_date
      FROM preftz.e214_filing_statuses efs
      WHERE zone_admission_no = p_admission_number
      LIMIT 1;

      INSERT INTO hts_units_temp
      SELECT h.tariff_number, h.unit_1, h.unit_2
      FROM preftz.harmonized_tariff_schedule_reference h
      WHERE h.record_begin_effective_date <= v_classify_date
        AND h.record_end_effective_date >= v_classify_date
        AND COALESCE(h.special_programs_indicator,'') = '';
        
      -- KK 09/10/2026
  	
      IF v_audit_result = 'PASS' THEN	
          --NKM 06/24/2021 Get inbond setting	
          v_require_inbonds=((preftz.get_ftz_setting('REQUIRE INBONDS') = 'REQUIRED') IS NOT FALSE);	
	
          INSERT INTO preftz.ft10 	
                     (action_code, zoneid, calendar_year, control_number, expanded_zoneid_indicator,	
                      port_code, direct_delivery_indicator, abi_filer_code, abi_routing_code,	
                      zone_operator_identifier, firms_identifier, applicant_for_admission)	
               SELECT v_action_code, r.ftz_zoneid, LEFT(p_admission_number,2), SUBSTR(p_admission_number,3,8),  --RTJ 06/20/201	
                      CASE WHEN LENGTH(r.ftz_zoneid) = 9 THEN 'Y' ELSE 'N' END,	
                      r.location_port_code, r.direct_delivery_indicator, r.filer_code, NULL,	
                      r.ftz_irs_number, r.firms_code, 	
                      CASE WHEN COALESCE(NULLIF(TRIM(r.applicant_for_admission),''),r.ftz_irs_number) <> r.ftz_irs_number --NKM 10/02/2023	
                           THEN r.applicant_for_admission	
                           ELSE NULL END	
                 FROM preftz.ftz_reference r;	
        	
          SELECT currval(pg_get_serial_sequence('preftz.ft10','ft10id')) INTO v_ft10id;	
	
          --RTJ 06/21/2021 add FT11/FT12 records for replacement 214	
          IF v_action_code = 'R' THEN	
              v_reason_count = 1;	
              v_additional_reasons = '';	
              	
              FOR prs IN	
                  SELECT DISTINCT r.reason_code	
                    FROM preftz.e214_replace_reasons r	
                   WHERE r.zone_admission_no = p_admission_number	
                   ORDER BY r.reason_code	
                   LIMIT 8	
              LOOP	
                  IF v_reason_count = 1 THEN 	
                      v_first_reason = prs.reason_code; 	
                  ELSE	
                      v_additional_reasons = v_additional_reasons || prs.reason_code;	
                  END IF;	
                  v_reason_count = v_reason_count + 1;	
              END LOOP;	
                   	
              INSERT INTO preftz.ft11	
                    (ft10id, contact_name, contact_phone, reason_code, additional_reason_codes)	
              SELECT v_ft10id, c.contact_name, REGEXP_REPLACE(c.contact_phone,'[^0-9]','','g'), v_first_reason, 	
                     v_additional_reasons	
                FROM preftz.contacts c	
               WHERE c.contact_type = 'E214';	
               	
              INSERT INTO preftz.ft12 (ft10id, remarks)	
              SELECT v_ft10id, r.remarks	
                FROM preftz.e214_replace_reasons r	
               WHERE r.zone_admission_no = p_admission_number	
                 AND COALESCE(NULLIF(TRIM(r.remarks),''),'') <> ''	
               ORDER BY r.e214_replace_reasonid	
               LIMIT 10;	
          END IF;	
          --RTJ 06/21/2021	
          	
          FOR crs IN  --conveyances  	
              SELECT au.carrier_code, au.voyage_flight_trip_number, au.arrival_date, 	
                     au.mode_of_transportation, au.port_of_unlading, au.depart_date,	
                     au.importing_vessel_code, au.scheduled_arrival_date, cr.carrier_name,	
                     c.export_date, c.import_date  --RTJ 06/30/2021 / RTJ 07/08/2021 / NKM 03/21/2022	
                FROM preftz.conveyances c	
                     INNER JOIN preftz.receipts r 	
                             ON c.conveyanceid = r.conveyanceid	
                     INNER JOIN preftz.ams_response_union au 	
                             ON c.bill_of_lading_airwaybill = au.bill_of_lading	
                            AND COALESCE(c.house_bill,'') = COALESCE(au.house_bill,'')	
                            AND (   c.house_bill_partial_indicator IS NULL	
                                 OR c.house_bill_partial_indicator = au.part_indicator_house)	
                      LEFT JOIN preftz.carriers cr	
                             ON au.carrier_code = cr.carrier_code	
               WHERE c.zone_admission_no = p_admission_number	
                 AND r.zone_status <>'D'	
                 AND r.quantity > 0  --RTJ 11/15/2020	
                 AND COALESCE(r.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/21/2022	
                 AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021	
               GROUP BY au.carrier_code, au.voyage_flight_trip_number, au.arrival_date, 	
                        au.mode_of_transportation, au.port_of_unlading, au.depart_date,	
                        au.importing_vessel_code, au.scheduled_arrival_date, cr.carrier_name,	
                        c.export_date, c.import_date	
               ORDER BY MAX(r.zone_to_zone_transfer) DESC, au.mode_of_transportation, au.carrier_code  --RTJ 07/08/2021	
          LOOP	
              	
              INSERT INTO preftz.ft20 	
                         (admission_type, mode_of_transportation, importing_carrier, conveyance_name,	
                          voyage_trip_flight_number, export_date, import_date, port_of_unlading,	
                          scheduled_date_of_arrival, ft10id)	
                  VALUES ('A',crs.mode_of_transportation, 	
                          CASE WHEN crs.mode_of_transportation LIKE '4%'	
                               THEN TRIM(LEFT(crs.carrier_code,3)) ELSE crs.carrier_code END, 	
                          CASE WHEN crs.mode_of_transportation LIKE '1%'	
                               THEN crs.importing_vessel_code ELSE LEFT(crs.carrier_name,23) END, 	
                          crs.voyage_flight_trip_number, crs.export_date, crs.import_date, crs.port_of_unlading, --RTJ 06/30/2021 --NKM 11/17/2022	
                          CASE WHEN crs.mode_of_transportation LIKE '4%'	
                               THEN crs.scheduled_arrival_date ELSE crs.arrival_date END, 	
                          v_ft10id);	
                              	
              SELECT currval(pg_get_serial_sequence('preftz.ft20','ft20id')) INTO v_ft20id;	
              	
              FOR brs IN  --bills of lading	
                  SELECT bol.bill_of_lading, bol.house_bill, bol.part_indicator_house,	
                         bol.manifest_quantity, 	
                         bol.container, -- NO 06/24/2026
                         SUM(bol.package_quantity) AS package_quantity, --NKM 06/24/2021 total quantity admitted on this bill across all in-bonds	
                         SUM(bol.gross_weight) AS gross_weight,         --NKM 06/24/2021 total gross weight admitted on this bill across all in-bonds	
                         SUM(bol.charges) AS charges,                   --NKM 06/24/2021 total charges on this bill across all in-bonds	
                         COALESCE(pc.port_country, pc1.port_country, cr.carrier_country) derived_country_of_export, --RTJ 06/30/2021	
                         bol.country_of_export, bol.ams_departure_port, bol.vessel_departure_port, --RTJ 06/30/2021	
                         wr1id	
                    FROM (SELECT DISTINCT au.bill_of_lading, au.house_bill, au.part_indicator_house,	
                                 au.manifest_quantity, c.package_quantity, c.gross_weight, c.charges,	
                                 au.vessel_departure_port ams_departure_port, au.carrier_code,  --RTJ 06/30/2021	
                                 au.voyage_flight_trip_number, c.inbond_number, au.wr1id, c.country_of_export, --RTJ 06/30/2021	
                                 c.vessel_departure_port,  --RTJ 06/30/2021	
                                 c.container
                            FROM preftz.conveyances c	
                                 INNER JOIN preftz.receipts r	
                                         ON c.conveyanceid = r.conveyanceid	
                                 INNER JOIN preftz.ams_response_union au	
                                         ON c.bill_of_lading_airwaybill = au.bill_of_lading	
                                        AND COALESCE(c.house_bill,'') = COALESCE(au.house_bill,'')	
                                        AND (   c.house_bill_partial_indicator IS NULL	
                                         OR c.house_bill_partial_indicator = au.part_indicator_house)	
                           WHERE c.zone_admission_no = p_admission_number	
                             AND r.zone_status <>'D'	
                             AND r.quantity > 0  --RTJ 11/15/2020	
                             AND COALESCE(r.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/21/2022	
                             AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021	
                             AND au.carrier_code = crs.carrier_code	
                             AND au.voyage_flight_trip_number = crs.voyage_flight_trip_number	
                             AND au.arrival_date = crs.arrival_date
						  	 AND c.export_date = crs.export_date --MH 9/11/2025 
                             AND au.port_of_unlading = crs.port_of_unlading --EG 2/23/2026 fix for multiple ports of unlading for one BOL
                       ) AS bol	
                    LEFT JOIN preftz.port_codes pc	
                           ON bol.ams_departure_port = pc.port_code  --ocean export country  --RTJ 06/30/2021	
                    LEFT JOIN preftz.flight_reference f	
                           ON bol.carrier_code = f.carrier_code	
                          AND bol.voyage_flight_trip_number = f.flight_number	
                    LEFT JOIN preftz.port_codes pc1	
                           ON f.departure_port_code = pc1.port_code  --flight export country	
                    LEFT JOIN preftz.carriers cr	
                           ON bol.carrier_code = cr.carrier_code  --to get rail export country	
                    GROUP BY bol.bill_of_lading, bol.house_bill, bol.part_indicator_house, 	
                             bol.manifest_quantity, derived_country_of_export, bol.country_of_export,  --RTJ 06/30/2021	
                             bol.ams_departure_port, bol.vessel_departure_port, bol.wr1id, bol.container  --RTJ 06/30/2021	
                    ORDER BY bol.bill_of_lading, bol.house_bill	
              LOOP	
                  IF COALESCE(brs.package_quantity,0) = 0 THEN    --NKM 06/11/2021	
                      v_pkg_count = brs.manifest_quantity;  --quantity on this bill from AMS	
                  ELSE	
                      v_pkg_count = brs.package_quantity;   --total quantity admitted on this bill	
                  END IF;	
                  	
                  INSERT INTO preftz.ft40	
                             (bill_of_lading_airwaybill, house_bill, quantity, country_of_export, 	
                              foreign_load_port, ft20id)	
                      VALUES (brs.bill_of_lading, brs.house_bill, v_pkg_count,	
                              COALESCE(brs.country_of_export,brs.derived_country_of_export),  --RTJ 06/30/2021	
                              CASE WHEN crs.mode_of_transportation LIKE '1%'	
                                   THEN brs.vessel_departure_port  --RTJ 06/30/2021 use only the port code provided by the user	
                                   ELSE NULL END, 	
                              v_ft20id);	
                  	
                  SELECT currval(pg_get_serial_sequence('preftz.ft40','ft40id')) INTO v_ft40id;	
                 	
                  IF v_require_inbonds THEN -- NKM 06/24/2021	
                     --inbonds from the conveyance records	
                     INSERT INTO preftz.ft41 (ft40id, it_number)	
                     SELECT DISTINCT v_ft40id, 	
                            CASE                             --NKM 02/14/2022 use Master AWB + House AWB when House AWB serves as in-bond	
                            WHEN COALESCE(brs.house_bill,'') = c.inbond_number THEN COALESCE(brs.bill_of_lading,'') || c.inbond_number	
                            ELSE c.inbond_number	
                            END it_number	
                       FROM preftz.conveyances c	
                      WHERE c.bill_of_lading_airwaybill = brs.bill_of_lading	
                        AND COALESCE(c.house_bill,'') = COALESCE(brs.house_bill,'')	
                        AND (   c.house_bill_partial_indicator IS NULL	
                             OR c.house_bill_partial_indicator = brs.part_indicator_house)	
                        AND c.inbond_number<>'NONE'	
                        AND c.zone_admission_no = p_admission_number	
                      ORDER BY it_number;	
                  ELSE	
                     --all inbonds associated with this BOL bound for the ftz port (using wn1 table)	
                     INSERT INTO preftz.ft41 (ft40id, it_number)	
                     SELECT v_ft40id, n1.it_number	
                       FROM (SELECT DISTINCT wn1.wn1id,	
                                    CASE                     --NKM 02/14/2022 use Master AWB + House AWB when House AWB serves as in-bond	
                                    WHEN wn1.inbond_entry_number = COALESCE(wsc.air_waybill_number,'') THEN wsc.air_waybill_number || wsc.house_air_waybill_number	
                                    ELSE wn1.inbond_entry_number	
                                    END it_number	
                               FROM preftz.wn1	
                               JOIN preftz.ftz_reference fr 	
                                 ON fr.location_port_code = COALESCE(NULLIF(wn1.inbond_manual_diversion_port,''),	
                                                                   NULLIF(wn1.inbond_edi_diversion_port,''),	
                                                                   NULLIF(wn1.manifested_inbond_port,''))	
                               LEFT JOIN preftz.wsc ON wsc.wr1id = wn1.wr1id	
                              WHERE wn1.wr1id = brs.wr1id	
                              ORDER BY wn1.wn1id) AS n1;	
                   /*Alternative logic using the inbond_status table	
                     --all inbonds associated with this BOL bound for the ftz port (using inbond_status table)	
                     INSERT INTO preftz.ft41 (ft40id, it_number)	
                     SELECT DISTINCT v_ft40id, inbond_number	
                       FROM preftz.inbond_status ibs	
                       JOIN preftz.ftz_reference fr ON fr.location_port_code = ibs.inbond_arrival_port	
                      WHERE ibs.bill_of_lading_airwaybill = brs.bill_of_lading	
                        AND ibs.house_bill = COALESCE(brs.house_bill,'');*/	
                  END IF;	
    	
                  --NO 07/14/2026 container records (FT43)	
                  IF preftz.get_ftz_setting('PROCESS PRE_RECEIPTS') = 'CONTAINER' THEN	
                    INSERT INTO preftz.ft43 (ft40id, container_number) 
                    VALUES (v_ft40id, brs.container); -- NO 06/24/2026
                  END IF;	
    	
                  SELECT SUM(r.quantity * p.unit_net_weight)	
                    INTO v_total_weight                       --net weight of all parts admitted on this bill	
                    FROM preftz.conveyances c	
                         INNER JOIN preftz.receipts r	
                                 ON c.conveyanceid = r.conveyanceid	
                         INNER JOIN preftz.parts p 	
                                 ON r.part_number = p.part_number	
                   WHERE c.zone_admission_no = p_admission_number	
                     AND c.bill_of_lading_airwaybill = brs.bill_of_lading	
                     AND COALESCE(c.house_bill,'') = COALESCE(brs.house_bill,'')	
                     AND (   c.house_bill_partial_indicator IS NULL	
                          OR c.house_bill_partial_indicator = brs.part_indicator_house)	
                     AND r.zone_status <> 'D'                           --NKM 03/14/2024	
                     AND COALESCE(r.zone_to_zone_transfer,'N') <> 'Y';  --NKM 03/21/2022	
                     	
                  line_count = 0;	
                  v_total_charges = 0; --NKM 09/23/2021 reset total charges for a given BOL	
                  v_charges_err = NULL;    --NKM 09/23/2021 reset roundoff error array for each BOL	
                  hts_count = 0;	
                  prev_line_group = '';	
                              	
                  FOR rrs IN  --receipts	
                      SELECT SUM(r.quantity) receipt_quantity, SUM(r.quantity * rc.unit_value) receipt_value, 	
                             SUM(r.quantity * p.unit_net_weight * rc.unit_value/preftz.get_receipt_value(r.receiptid)) receipt_weight, --RTJ 01/19/2023 	
                             r.country_of_origin, rc.harmonized_tariff_schedule_number, rc.special_programs_indicator, 	
                             r.zone_status, h.unit_1, h.unit_2,	
                             SUM(COALESCE(pc.quantity1_conversion_rate,0) * r.quantity) v_qty_1,	
                             SUM(COALESCE(pc.quantity2_conversion_rate,0) * r.quantity) v_qty_2,	
                             preftz.get_hts_line_group(r.receiptid) hts_line_group,	
                             ARRAY_AGG(r.receiptid) a_receiptids --NKM 02/03/2022	
                        FROM preftz.conveyances c	
                             INNER JOIN preftz.receipts r	
                                     ON c.conveyanceid = r.conveyanceid	
                             INNER JOIN preftz.receipt_classifications rc	
                                     ON r.receiptid = rc.receiptid	
                             INNER JOIN hts_units_temp h 	
                                     ON rc.harmonized_tariff_schedule_number = h.tariff_number	
                             INNER JOIN preftz.parts p	
                                     ON r.part_number = p.part_number	
                              LEFT JOIN preftz.part_classifications pc	
                                     ON p.part_number = pc.part_number	
                                    AND rc.harmonized_tariff_schedule_number = pc.harmonized_tariff_schedule_number	
                       WHERE c.zone_admission_no = p_admission_number	
                         AND r.zone_status <>'D'	
                         AND r.quantity > 0  --RTJ 11/15/2020	
                         AND COALESCE(r.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/21/2022	
                         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021	
                         AND c.bill_of_lading_airwaybill = brs.bill_of_lading	
                         AND COALESCE(c.house_bill,'') = COALESCE(brs.house_bill,'')	
                         AND (   c.house_bill_partial_indicator IS NULL 	
                              OR c.house_bill_partial_indicator = brs.part_indicator_house)	
                       GROUP BY r.country_of_origin, rc.harmonized_tariff_schedule_number, rc.special_programs_indicator,	
                                r.zone_status, h.unit_1, h.unit_2, preftz.get_hts_line_group(r.receiptid), rc.tariff_type  --RTJ 09/05/2022	
                       ORDER BY preftz.get_hts_line_group(r.receiptid), 	
                                CASE rc.tariff_type WHEN 'BASE' THEN 0 WHEN 'DUTY9' THEN 1 ELSE 9 END,  --RTJ 09/05/2022	
                                rc.harmonized_tariff_schedule_number, r.country_of_origin	
                  LOOP	
                    RAISE NOTICE 'looping ft50; line_group: %', rrs.hts_line_group;
                    RAISE NOTICE 'looping ft50; line_group: %', rrs.hts_line_group;
                    RAISE NOTICE 'looping ft50; line_group: %', rrs.hts_line_group;

                      IF rrs.hts_line_group <> prev_line_group THEN	
                          prev_line_group = rrs.hts_line_group;	
                          line_count = preftz.get_hts_line_number  --RTJ 06/21/2021 	
                                      (p_admission_number, crs.carrier_code, brs.bill_of_lading,  --RTJ 06/21/2021	
                                       brs.house_bill, brs.part_indicator_house, rrs.hts_line_group);  --RTJ 06/29/2021	
                          hts_count = 1;	
                          v_base_uom = rrs.unit_1;	
                          v_base_qty = rrs.v_qty_1;	
                      ELSE	
                          hts_count = hts_count + 1;	
                      END IF;	
                      	
                      IF brs.gross_weight = 0 THEN 	
                          --rrs.receipt_weight is the total net weight of goods admitted on this bill of this HTS/CoO/zone status	
                          v_gross_weight = rrs.receipt_weight;	
                      ELSE	
                          --rrs.receipt_weight / v_total_weight is the percentage goods of the total net weight for this bill	
                          --                                    comprisised of this specific HTS/CoO/zone status.	
                          --                                    It is used to scale the gross weight and charges for the goods	
                          --                                    with this HTS/CoO/zone status.	
                          v_gross_weight = brs.gross_weight * rrs.receipt_weight / v_total_weight;	
                          --v_gross_weight is the gross weight assigned to this HTS/CoO/zone status	
                      END IF;	
                      IF v_gross_weight = 0 THEN v_gross_weight = 1; END IF;	
                      	
                      v_charges = brs.charges * rrs.receipt_weight / v_total_weight;	
                      --like v_gross_weight, v_charges are the charges assigned to this HTS/CoO/zone status	
	
                      --NKM 09/23/2021 	
                      v_total_charges = v_total_charges + v_charges::INTEGER;	
                      v_charges_err[line_count] = v_charges_err[line_count] + v_charges::INTEGER - v_charges;	
                      --v_charges_err is the roundoff error on the charges by line number	
                      	
                      IF crs.mode_of_transportation LIKE '1%' THEN	
                          v_hmf_fee = preftz.get_harbor_maintenance_fee (crs.port_of_unlading, rrs.receipt_value);	
                      ELSE	
                          v_hmf_fee = 0;	
                      END IF;	
                      	
                      v_value = ROUND(rrs.receipt_value + 0.000001);
                      IF v_value = 0 THEN v_value = 1; END IF;	
                      	
                      IF hts_count > 1 AND COALESCE(rrs.unit_1,'X') IN ('','X')       --NKM 04/29/2022	
                      AND LEFT(rrs.harmonized_tariff_schedule_number,2) IN('99','98') THEN --NKM 11/07/2022	
                          v_qty1_rnd = GREATEST(v_base_qty,0.01);   --NKM 03/28/2024	
                          v_unit_1 = v_base_uom;	
                      ELSE	
                          v_qty1_rnd = GREATEST(rrs.v_qty_1,0.01);  --NKM 03/28/2024	
                          v_unit_1 = rrs.unit_1;	
                      END IF;	
                      	
                      IF rrs.unit_2 = 'X' THEN	
                          v_qty2_rnd = 0;	
                          v_unit_2 = NULL;	
                      ELSE	
                          v_qty2_rnd = GREATEST(rrs.v_qty_2,0.01);  --NKM 03/28/2024	
                          v_unit_2 = rrs.unit_2;	
                      END IF;	
                      	
                      SELECT s.special_programs_indicator_type	
                        INTO v_spi_type	
                        FROM preftz.special_programs_indicator_codes s	
                       WHERE s.special_programs_indicator_code = rrs.special_programs_indicator;	
        	
                    RAISE NOTICE 'writing ft50; %, %, %', line_count, rrs.harmonized_tariff_schedule_number, v_ft40id;

                      INSERT INTO preftz.ft50	
                                 (line_item_number, harmonized_tariff_schedule_number, special_programs_indicator,	
                                  special_programs_indicator_country, special_programs_indicator_secondary,	
                                  country_of_origin, quantity_1, unit_of_measure_1, quantity_2, unit_of_measure_2,	
                                  quota_category, pn_disclaimer_flag, weight, us_dollar_value, charges,	
                                  zone_status, harbor_maintenance_fee, ft40id)	
                          VALUES (line_count, rrs.harmonized_tariff_schedule_number, 	
                                  CASE WHEN v_spi_type = 'P' THEN rrs.special_programs_indicator ELSE NULL END,	
                                  CASE WHEN v_spi_type = 'C' THEN rrs.special_programs_indicator ELSE NULL END,	
                                  CASE WHEN v_spi_type = 'S' THEN rrs.special_programs_indicator ELSE NULL END, 	
                                  rrs.country_of_origin, ROUND(v_qty1_rnd,2), v_unit_1, ROUND(v_qty2_rnd,2), 	
                                  v_unit_2, NULL, NULL, v_gross_weight, v_value, v_charges::INTEGER, rrs.zone_status, 	
                                  ROUND(v_hmf_fee,2), v_ft40id);	
        	
                      SELECT currval(pg_get_serial_sequence('preftz.ft50','ft50id')) INTO v_ft50id;	
        	
                      FOR drs IN  --descriptions	
                          SELECT DISTINCT r.manufacturer_MID_code, 	
                                 CASE WHEN hts_count = 1 THEN preftz.abi_an(p.description,45) --NKM 02/01/2023	
                                      WHEN hts_count > 1 AND SUBSTR(rc.harmonized_tariff_schedule_number,1,2) = '99'	
                                           THEN 'CHAPTER99'	
                                      WHEN hts_count > 1 AND SUBSTR(rc.harmonized_tariff_schedule_number,1,2) = '98'	
                                           THEN 'CHAPTER98'	
                                      ELSE 'MULTIPLE TARIFF'	
                                      END description	
                            FROM preftz.conveyances c	
                                 INNER JOIN preftz.receipts r	
                                         ON c.conveyanceid = r.conveyanceid	
                                 INNER JOIN preftz.receipt_classifications rc	
                                         ON r.receiptid = rc.receiptid	
                                 INNER JOIN preftz.parts p 	
                                         ON r.part_number = p.part_number	
                           WHERE c.zone_admission_no = p_admission_number	
                             AND r.zone_status <>'D'	
                             AND r.quantity > 0  --RTJ 11/15/2020	
                             AND COALESCE(r.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/21/2022	
                             AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021	
                             AND c.bill_of_lading_airwaybill = brs.bill_of_lading	
                             AND COALESCE(c.house_bill,'') = COALESCE(brs.house_bill,'')	
                             AND (   c.house_bill_partial_indicator IS NULL 	
                                  OR c.house_bill_partial_indicator = brs.part_indicator_house)	
                             AND rc.harmonized_tariff_schedule_number = rrs.harmonized_tariff_schedule_number	
                             AND COALESCE(rc.special_programs_indicator,'') = COALESCE(rrs.special_programs_indicator,'')	
                             AND r.country_of_origin = rrs.country_of_origin	
                             AND r.zone_status = rrs.zone_status	
                             AND preftz.get_hts_line_group(r.receiptid) = rrs.hts_line_group	
                      LOOP	
                          INSERT INTO preftz.ft60	
                                     (description, reference_qualifier, referenceid, ft50id)	
                              VALUES (drs.description, 'MID', drs.manufacturer_MID_code, v_ft50id);	
                      END LOOP;  --descriptions	
                      	
	
                      --NKM 02/03/2022 --include steel and aluminum import licenses	
                      IF hts_count = 1 THEN	
                         INSERT INTO preftz.ft60	
                                        (description, reference_qualifier, referenceid, ft50id)	
                         SELECT DISTINCT preftz.abi_an(p.description,45), il.import_license_type, il.import_license_number, v_ft50id --NKM 02/01/2023	
                           FROM preftz.receipts r	
                                INNER JOIN preftz.import_licenses il ON il.receiptid = r.receiptid	
                                INNER JOIN preftz.parts p ON p.part_number = r.part_number	
                          WHERE il.receiptid = ANY(rrs.a_receiptids);	
                      END IF;	
	
                      FOR urs IN  --update receipts	
                          SELECT r.receiptid, (r.quantity * p.unit_net_weight) receipt_weight,	
                                 r.quantity	
                            FROM preftz.conveyances c	
                                 INNER JOIN preftz.receipts r	
                                         ON c.conveyanceid = r.conveyanceid	
                                 INNER JOIN preftz.parts p	
                                         ON r.part_number = p.part_number 	
                           WHERE c.zone_admission_no = p_admission_number	
                             AND r.zone_status <>'D'	
                             AND r.quantity > 0  --RTJ 11/15/2020	
                             AND COALESCE(r.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/21/2022	
                             AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021	
                             AND c.bill_of_lading_airwaybill = brs.bill_of_lading	
                             AND COALESCE(c.house_bill,'') = COALESCE(brs.house_bill,'')	
                             AND (   c.house_bill_partial_indicator IS NULL 	
                                  OR c.house_bill_partial_indicator = brs.part_indicator_house)	
                             AND preftz.get_hts_line_group(r.receiptid) = rrs.hts_line_group	
                      LOOP	
                          v_weight_rnd = (brs.gross_weight * urs.receipt_weight / v_total_weight) / urs.quantity;	
                          v_charges_rnd = (brs.charges * urs.receipt_weight / v_total_weight) / urs.quantity;	
                          	
                          UPDATE preftz.receipts r	
                             SET country_of_export = COALESCE(brs.country_of_export,brs.derived_country_of_export),  --RTJ 07/21/2021	
                                 export_date = crs.export_date, --NKM 11/16/2022	
                                 gross_weight = ROUND(v_weight_rnd,4),	
                                 charges = ROUND(v_charges_rnd,4)	
                           WHERE r.receiptid = urs.receiptid;	
                      END LOOP;  --update receipts	
                  END LOOP;  --receipts	
	
                  --NKM 09/23/2021 fix roundoff error in charges	
                  v_charges_fix = brs.charges - v_total_charges; --dollars of adjustment needed to charges	
                  v_sign = sign(v_charges_fix);	
                  -- KK 02/16/2026 do not do the charges fix loop if the array v_charges_err is empty or null.
                  WHILE v_charges_fix <> 0 AND NOT (cardinality(v_charges_err) IS NULL OR cardinality(v_charges_err) = 0)                  
                  LOOP	
                      SELECT array_position(v_charges_err, (SELECT v_sign*min(roundoff_error*v_sign) FROM unnest(v_charges_err) AS roundoff_error))	
                        INTO v_fix_line;	
                                                       	
                      UPDATE preftz.ft50	
                         SET charges = charges + v_sign	
                        FROM (SELECT min(ft50id) ft50id	
                                FROM preftz.ft50	
                               WHERE ft40id = v_ft40id	
                                 AND line_item_number = v_fix_line) AS mn --Primary HTS has the lowest ft50id	
                       WHERE mn.ft50id = ft50.ft50id;	
	
                      v_charges_err[v_fix_line] = v_charges_err[v_fix_line] + v_sign;	
	
                      v_charges_fix = v_charges_fix - v_sign;	
                  END LOOP; --fix roundoff error in charges	
	
              END LOOP;  --bills of lading 	
          END LOOP;  --conveyances	
	
          --NKM 03/21/2022	
          --zone-to-zone transfers	
          --ztz groups on unique BOL - unlike normal receipts which are differentiated by bol, HBOL, and split (voyage_trip_flight_number/date)	
          v_first_ztz = TRUE;  --RTJ 07/08/2021	
          FOR bzrs IN SELECT ams.bill_of_lading,	
                             ams.manifest_quantity,   --but I need to sum by BOL? or do I even need this for ztz	
                             bol.package_quantity,    --NKM 06/24/2021 total quantity admitted on this bill across all in-bonds	
                             bol.gross_weight,        --NKM 06/24/2021 total gross weight admitted on this bill across all in-bonds	
                             bol.charges,             --NKM 06/24/2021 total charges on this bill across all in-bonds	
                             bol.conveyanceids,	
                             ams.wr1ids	
                        FROM (SELECT bill_of_lading_airwaybill, SUM(package_quantity) AS package_quantity, SUM(gross_weight) AS gross_weight,	
                                     SUM(charges) AS charges, ARRAY_AGG(conveyanceid) AS conveyanceids	
                                FROM (SELECT DISTINCT c.bill_of_lading_airwaybill, c.package_quantity, c.gross_weight, c.charges, c.conveyanceid	
                                        FROM preftz.conveyances c	
                                             INNER JOIN preftz.receipts r 	
                                                     ON c.conveyanceid = r.conveyanceid	
                                       WHERE c.zone_admission_no = p_admission_number	
                                         AND r.zone_status <>'D'	
                                         AND r.quantity > 0  --RTJ 11/15/2020	
                                         AND COALESCE(r.zone_to_zone_transfer,'N') = 'Y'   --NKM 03/21/2022	
                                         AND COALESCE(r.cloned_from_receiptid,0) = 0 --RTJ 03/05/2021	
                                      ) AS con	
                               GROUP BY bill_of_lading_airwaybill) AS bol --sums values across multiple conveyance records even if multiple conveyanceids	
                        JOIN (SELECT bill_of_lading, SUM(manifest_quantity) AS manifest_quantity, ARRAY_AGG(wr1id) AS wr1ids	
                                FROM (SELECT DISTINCT au.bill_of_lading, au.manifest_quantity, au.wr1id	
                                        FROM preftz.conveyances c	
                                             INNER JOIN preftz.receipts r	
                                                     ON c.conveyanceid = r.conveyanceid	
                                             INNER JOIN preftz.ams_response_union au	
                                                     ON c.bill_of_lading_airwaybill = au.bill_of_lading	
                                                    AND COALESCE(c.house_bill,'') = COALESCE(au.house_bill,'')	
                                                    AND (   c.house_bill_partial_indicator IS NULL	
                                                    OR c.house_bill_partial_indicator = au.part_indicator_house)	
                                       WHERE c.zone_admission_no = p_admission_number	
                                         AND r.zone_status <>'D'	
                                         AND r.quantity > 0  --RTJ 11/15/2020	
                                         AND COALESCE(r.zone_to_zone_transfer,'N') = 'Y'   --NKM 03/21/2022	
                                         AND COALESCE(r.cloned_from_receiptid,0) = 0 --RTJ 03/05/2021	
                                     ) wrx --total manifest quantity when multiple AMS records have the same BOL (e.g. air shipments) and array of all wr1ids	
                               GROUP BY bill_of_lading) AS ams	
                          ON ams.bill_of_lading = bol.bill_of_lading_airwaybill	
                       ORDER BY ams.bill_of_lading	
          LOOP	
	
              IF v_first_ztz THEN  --add Z record only if not previously added	
                  INSERT INTO preftz.ft20 (admission_type, ft10id)	
                  VALUES ('Z', v_ft10id);	
                  SELECT currval(pg_get_serial_sequence('preftz.ft20','ft20id')) INTO v_ft20id;	
                  	
                  v_first_ztz = FALSE;	
              END IF;	
	
              IF COALESCE(bzrs.package_quantity,0) = 0 THEN    --NKM 06/11/2021	
                  v_pkg_count = bzrs.manifest_quantity;  --quantity on this bill from AMS	
              ELSE	
                  v_pkg_count = bzrs.package_quantity;   --total quantity admitted on this bill	
              END IF;	
              	
              INSERT INTO preftz.ft40 (bill_of_lading_airwaybill, quantity, ft20id)	
              VALUES (bzrs.bill_of_lading, v_pkg_count, v_ft20id)	
              RETURNING ft40id INTO v_ft40id;	
                 	
              IF v_require_inbonds THEN -- NKM 06/24/2021	
                 --inbonds from the conveyance records	
                 INSERT INTO preftz.ft41 (ft40id, it_number)	
                 SELECT DISTINCT v_ft40id, 	
                        CASE                             --NKM 02/14/2022 use Master AWB + House AWB when House AWB serves as in-bond	
                        WHEN COALESCE(c.house_bill,'') = c.inbond_number THEN COALESCE(c.bill_of_lading_airwaybill,'') || c.inbond_number	
                        ELSE c.inbond_number	
                        END it_number	
                   FROM preftz.conveyances c	
                  WHERE c.conveyanceid = ANY (bzrs.conveyanceids)  --NKM 03/21/2022	
                    AND c.inbond_number<>'NONE'	
                  ORDER BY it_number;	
              ELSE	
                 --all inbonds associated with this BOL bound for the ftz port (using wn1 table)	
                 INSERT INTO preftz.ft41 (ft40id, it_number) --JM Added insert statement	
                 SELECT v_ft40id, n1.it_number	
                   FROM (SELECT wn1.wn1id,	
                                CASE                     --NKM 02/14/2022 use Master AWB + House AWB when House AWB serves as in-bond	
                                WHEN wn1.inbond_entry_number = COALESCE(wsc.air_waybill_number,'') THEN wsc.air_waybill_number || wsc.house_air_waybill_number	
                                ELSE wn1.inbond_entry_number	
                                END it_number	
                           FROM preftz.wn1	
                           JOIN preftz.ftz_reference fr	
                             ON fr.location_port_code = COALESCE(NULLIF(wn1.inbond_manual_diversion_port,''),	
                                                               NULLIF(wn1.inbond_edi_diversion_port,''),	
                                                               NULLIF(wn1.manifested_inbond_port,''))	
                           LEFT JOIN preftz.wsc ON wsc.wr1id = wn1.wr1id	
                          WHERE wn1.wr1id = ANY (bzrs.wr1ids)) AS n1 --JM added s to wr1id field	
                  GROUP BY n1.it_number	
                  ORDER BY MIN(n1.wn1id);	
              END IF;	
    	
              SELECT SUM(r.quantity * p.unit_net_weight)	
                INTO v_total_weight                       --net weight of all parts admitted on this bill	
                FROM preftz.conveyances c	
                     INNER JOIN preftz.receipts r	
                             ON c.conveyanceid = r.conveyanceid	
                     INNER JOIN preftz.parts p 	
                             ON r.part_number = p.part_number	
               WHERE c.conveyanceid = ANY (bzrs.conveyanceids); --NKM 03/21/2022	
	
              --NKM 03/21/2022	
              --zone-to-zone transfer receipts	
              line_count = 0;	
              v_total_charges = 0;	
              v_charges_err = NULL;	
              hts_count = 0;	
              prev_line_group = '';	
	
              FOR rzrs IN	
                  SELECT SUM(r.quantity) receipt_quantity, SUM(r.quantity * rc.unit_value) receipt_value,	
                         SUM(r.quantity * p.unit_net_weight * rc.unit_value/preftz.get_receipt_value(r.receiptid)) receipt_weight,  --RTJ 01/19/2023 	
                         r.country_of_origin, rc.harmonized_tariff_schedule_number, rc.special_programs_indicator,	
                         r.zone_status, h.unit_1, h.unit_2,	
                         SUM(COALESCE(pc.quantity1_conversion_rate,0) * r.quantity) v_qty_1,	
                         SUM(COALESCE(pc.quantity2_conversion_rate,0) * r.quantity) v_qty_2,	
                         preftz.get_hts_line_group(r.receiptid) hts_line_group,	
                         ARRAY_AGG(r.receiptid) a_receiptids --NKM 02/03/2022	
                            FROM preftz.conveyances c	
                                 INNER JOIN preftz.receipts r	
                                         ON c.conveyanceid = r.conveyanceid	
                                 INNER JOIN preftz.receipt_classifications rc	
                                         ON r.receiptid = rc.receiptid	
                                 INNER JOIN hts_units_temp h	
                                         ON rc.harmonized_tariff_schedule_number = h.tariff_number	
                                 INNER JOIN preftz.parts p	
                                         ON r.part_number = p.part_number	
                                  LEFT JOIN preftz.part_classifications pc	
                                         ON p.part_number = pc.part_number	
                                        AND rc.harmonized_tariff_schedule_number = pc.harmonized_tariff_schedule_number	
                           WHERE c.conveyanceid = ANY (bzrs.conveyanceids)  --NKM 03/21/2022	
                             AND r.zone_status <>'D'	
                             AND COALESCE(r.zone_to_zone_transfer,'N') = 'Y'   --NKM 03/21/2022	
                             AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021	
                           GROUP BY r.country_of_origin, rc.harmonized_tariff_schedule_number, rc.special_programs_indicator,	
                                    r.zone_status, h.unit_1, h.unit_2, preftz.get_hts_line_group(r.receiptid), rc.tariff_type  --RTJ 09/05/2022	
                           ORDER BY preftz.get_hts_line_group(r.receiptid), 	
                                    CASE rc.tariff_type WHEN 'BASE' THEN 0 WHEN 'DUTY9' THEN 1 ELSE 9 END,  --RTJ 09/05/2022	
                                    rc.harmonized_tariff_schedule_number, r.country_of_origin	
              LOOP	
    	
                  IF rzrs.hts_line_group <> prev_line_group THEN	
                      prev_line_group = rzrs.hts_line_group;	
                      --NOTE: carrier = 'ZTZ' will never conflict with a normal line_number record because only air carriers use 3 characters and this HBOL is NULL	
                      line_count = preftz.get_hts_line_number (p_admission_number, 'ZTZ', bzrs.bill_of_lading, --NKM 03/21/2022	
                                                               NULL, NULL, rzrs.hts_line_group);	
                      hts_count = 1;	
                      v_base_uom = rzrs.unit_1;	
                      v_base_qty = rzrs.v_qty_1;	
                  ELSE	
                      hts_count = hts_count + 1;	
                  END IF;	
                          	
                  IF bzrs.gross_weight = 0 THEN	
                      --rzrs.receipt_weight is the total net weight of goods admitted on this bill of this HTS/CoO/zone status	
                      v_gross_weight = rzrs.receipt_weight;	
                  ELSE	
                      --rzrs.receipt_weight / v_total_weight is the percentage goods of the total net weight for this bill	
                      --                                    comprisised of this specific HTS/CoO/zone status.	
                      --                                    It is used to scale the gross weight and charges for the goods	
                      --                                    with this HTS/CoO/zone status.	
                      v_gross_weight = bzrs.gross_weight * rzrs.receipt_weight / v_total_weight;	
                      --v_gross_weight is the gross weight assigned to this HTS/CoO/zone status	
                  END IF;	
                  IF v_gross_weight = 0 THEN v_gross_weight = 1; END IF;	
    	
                  v_charges = bzrs.charges * rzrs.receipt_weight / v_total_weight;	
                  --like v_gross_weight, v_charges are the charges assigned to this HTS/CoO/zone status	
    	
                  --NKM 09/23/2021 	
                  v_total_charges = v_total_charges + v_charges::INTEGER;	
                  v_charges_err[line_count] = v_charges_err[line_count] + v_charges::INTEGER - v_charges;	
                  --v_charges_err is the roundoff error on the charges by line number	
    	
                  v_hmf_fee = 0; --NKM 03/21/2022 always 0 for ztz	
    	
                  v_value = ROUND(rzrs.receipt_value + 0.000001);	
                  IF v_value = 0 THEN v_value = 1; END IF;	
    	
                  IF hts_count > 1 AND COALESCE(rzrs.unit_1,'X') IN ('','X')        --NKM 04/29/2022	
                  AND LEFT(rzrs.harmonized_tariff_schedule_number,2) IN('99','98') THEN --NKM 11/07/2022	
                      v_qty1_rnd = GREATEST(v_base_qty,0.01);     --NKM 03/28/2024	
                      v_unit_1 = v_base_uom;	
                  ELSE	
                      v_qty1_rnd = GREATEST(rzrs.v_qty_1,0.01);   --NKM 03/28/2024	
                      v_unit_1 = rzrs.unit_1;	
                  END IF;	
    	
                  IF rzrs.unit_2 = 'X' THEN	
                      v_qty2_rnd = 0;	
                      v_unit_2 = NULL;	
                  ELSE	
                      v_qty2_rnd = GREATEST(rzrs.v_qty_2,0.01);   --NKM 03/28/2024	
                      v_unit_2 = rzrs.unit_2;	
                  END IF;	
    	
                  SELECT s.special_programs_indicator_type	
                    INTO v_spi_type	
                    FROM preftz.special_programs_indicator_codes s	
                   WHERE s.special_programs_indicator_code = rzrs.special_programs_indicator;	
            	
                  INSERT INTO preftz.ft50	
                             (line_item_number, harmonized_tariff_schedule_number, special_programs_indicator,	
                              special_programs_indicator_country, special_programs_indicator_secondary,	
                              country_of_origin, quantity_1, unit_of_measure_1, quantity_2, unit_of_measure_2,	
                              quota_category, pn_disclaimer_flag, weight, us_dollar_value, charges,	
                              zone_status, harbor_maintenance_fee, ft40id)	
                      VALUES (line_count, rzrs.harmonized_tariff_schedule_number, 	
                              CASE WHEN v_spi_type = 'P' THEN rzrs.special_programs_indicator ELSE NULL END,	
                              CASE WHEN v_spi_type = 'C' THEN rzrs.special_programs_indicator ELSE NULL END,	
                              CASE WHEN v_spi_type = 'S' THEN rzrs.special_programs_indicator ELSE NULL END, 	
                              rzrs.country_of_origin, ROUND(v_qty1_rnd,2), v_unit_1, ROUND(v_qty2_rnd,2), 	
                              v_unit_2, NULL, NULL, v_gross_weight, v_value, v_charges::INTEGER, rzrs.zone_status, 	
                              ROUND(v_hmf_fee,2), v_ft40id);	
    	
                  SELECT currval(pg_get_serial_sequence('preftz.ft50','ft50id')) INTO v_ft50id;	
            	
                  FOR dzrs IN  --zone-to-zone descriptions	
                      SELECT DISTINCT r.manufacturer_MID_code, 	
                             CASE WHEN hts_count = 1 THEN preftz.abi_an(p.description,45) --NKM 02/01/2023	
                                  WHEN hts_count > 1 AND SUBSTR(rc.harmonized_tariff_schedule_number,1,2) = '99'	
                                       THEN 'CHAPTER99'	
                                  WHEN hts_count > 1 AND SUBSTR(rc.harmonized_tariff_schedule_number,1,2) = '98'	
                                       THEN 'CHAPTER98'	
                                  ELSE 'MULTIPLE TARIFF'	
                                  END description	
                        FROM preftz.conveyances c	
                             INNER JOIN preftz.receipts r	
                                     ON c.conveyanceid = r.conveyanceid	
                             INNER JOIN preftz.parts p	
                                     ON r.part_number = p.part_number	
                             INNER JOIN preftz.receipt_classifications rc	
                                     ON r.receiptid = rc.receiptid       	
                       WHERE c.conveyanceid = ANY (bzrs.conveyanceids)  --NKM 03/21/2022	
                         AND r.zone_status <>'D'	
                         AND COALESCE(r.zone_to_zone_transfer,'N') = 'Y'   --NKM 03/21/2022	
                         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021	
                         AND rc.harmonized_tariff_schedule_number = rzrs.harmonized_tariff_schedule_number	
                         AND COALESCE(rc.special_programs_indicator,'') = COALESCE(rzrs.special_programs_indicator,'')	
                         AND r.zone_status = rzrs.zone_status	
                         AND preftz.get_hts_line_group(r.receiptid) = rzrs.hts_line_group	
                  LOOP	
                      INSERT INTO preftz.ft60	
                                 (description, reference_qualifier, referenceid, ft50id)	
                          VALUES (dzrs.description, 'MID', dzrs.manufacturer_MID_code, v_ft50id);	
                  END LOOP;  --drs zone-to-zone	
    	
                  --NKM 02/03/2022 --include steel and aluminum import licenses	
                  IF hts_count = 1 THEN	
                     INSERT INTO preftz.ft60	
                                    (description, reference_qualifier, referenceid, ft50id)	
                     SELECT DISTINCT preftz.abi_an(p.description,45), il.import_license_type, il.import_license_number, v_ft50id --NKM 02/01/2023	
                       FROM preftz.receipts r	
                            INNER JOIN preftz.import_licenses il ON il.receiptid = r.receiptid	
                            INNER JOIN preftz.parts p ON p.part_number = r.part_number	
                      WHERE il.receiptid = ANY(rzrs.a_receiptids);	
                  END IF;	
	
                  FOR uzrs IN  --update ztz receipts	
                      SELECT r.receiptid, (r.quantity * p.unit_net_weight) receipt_weight,	
                             r.quantity	
                        FROM preftz.conveyances c	
                             INNER JOIN preftz.receipts r	
                                     ON c.conveyanceid = r.conveyanceid	
                             INNER JOIN preftz.parts p	
                                     ON r.part_number = p.part_number 	
                       WHERE c.conveyanceid = ANY (bzrs.conveyanceids)  --NKM 03/21/2022	
                         AND r.zone_status <>'D'	
                         AND COALESCE(r.zone_to_zone_transfer,'N') = 'Y'   --NKM 03/21/2022	
                         AND COALESCE(r.cloned_from_receiptid,0) = 0  --RTJ 03/05/2021	
                         AND preftz.get_hts_line_group(r.receiptid) = rzrs.hts_line_group	
                  LOOP	
                      v_weight_rnd = (bzrs.gross_weight * uzrs.receipt_weight / v_total_weight) / uzrs.quantity;	
                      v_charges_rnd = (bzrs.charges * uzrs.receipt_weight / v_total_weight) / uzrs.quantity;	
                      	
                      UPDATE preftz.receipts r	
                         SET gross_weight = ROUND(v_weight_rnd,4),	
                             charges = ROUND(v_charges_rnd,4)	
                       WHERE r.receiptid = uzrs.receiptid;	
                  END LOOP;  --update ztz receipts	
              END LOOP;  --ztz receipts	
	
              --NKM 09/23/2021 fix roundoff error in charges	
              v_charges_fix = bzrs.charges - v_total_charges; --dollars of adjustment needed to charges	
              v_sign = sign(v_charges_fix);	
              WHILE v_charges_fix <> 0	
              LOOP	
                  SELECT array_position(v_charges_err, (SELECT v_sign*min(roundoff_error*v_sign) FROM unnest(v_charges_err) AS roundoff_error))	
                    INTO v_fix_line;	
                                                   	
                  UPDATE preftz.ft50	
                     SET charges = charges + v_sign	
                    FROM (SELECT min(ft50id) ft50id	
                            FROM preftz.ft50	
                           WHERE ft40id = v_ft40id	
                             AND line_item_number = v_fix_line) AS mn --Primary HTS has the lowest ft50id	
                   WHERE mn.ft50id = ft50.ft50id;	
	
                  v_charges_err[v_fix_line] = v_charges_err[v_fix_line] + v_sign;	
	
                  v_charges_fix = v_charges_fix - v_sign;	
              END LOOP; --fix roundoff error in charges	
          END LOOP;  --zone-to-zone transfers	
	
          --adjustments	
          v_first_adjust = TRUE;	
          line_count = 0;	
          hts_count = 0;	
          prev_line_group = '';	
    	
          SELECT r.firms_code INTO v_firms FROM preftz.ftz_reference r;	
          	
          FOR ars IN 	
              SELECT SUM(ii.quantity_received) adjust_quantity, SUM(ii.quantity_received * rc.unit_value) adjust_value,	
                     SUM(ii.quantity_received * p.unit_net_weight * rc.unit_value/r.unit_price) adjust_weight,	
                     r.country_of_origin, rc.harmonized_tariff_schedule_number, rc.special_programs_indicator,	
                     ii.zone_status, h.unit_1, h.unit_2,	
                     SUM(COALESCE(pc.quantity1_conversion_rate,0) * ii.quantity_received) v_qty_1,	
                     SUM(COALESCE(pc.quantity2_conversion_rate,0) * ii.quantity_received) v_qty_2,	
                     preftz.get_hts_line_group(ii.receiptid) hts_line_group,	
                     ARRAY_AGG(r.receiptid) a_receiptids --NKM 05/19/2022	
                FROM preftz.inventory_items ii	
                     INNER JOIN preftz.adjustment_zone_admission_nos a	
                             ON ii.itemid = a.itemid	
                     INNER JOIN preftz.parts p	
                             ON ii.part_number = p.part_number	
                     INNER JOIN preftz.receipts r	
                             ON ii.receiptid = r.receiptid	
                     INNER JOIN preftz.receipt_classifications rc	
                             ON r.receiptid = rc.receiptid       	
                     INNER JOIN hts_units_temp h 	
                             ON rc.harmonized_tariff_schedule_number = h.tariff_number	
                      LEFT JOIN preftz.part_classifications pc	
                             ON p.part_number = pc.part_number	
                            AND rc.harmonized_tariff_schedule_number = pc.harmonized_tariff_schedule_number	
               WHERE ii.adjustid > 0	
                 AND ii.zone_status <> 'D'	
                 AND a.zone_admission_no = p_admission_number	
               GROUP BY r.country_of_origin, rc.harmonized_tariff_schedule_number, rc.special_programs_indicator,	
                        ii.zone_status, h.unit_1, h.unit_2, preftz.get_hts_line_group(ii.receiptid), rc.tariff_type  --RTJ 09/05/2022	
               ORDER BY preftz.get_hts_line_group(ii.receiptid), 	
                        CASE rc.tariff_type WHEN 'BASE' THEN 0 WHEN 'DUTY9' THEN 1 ELSE 9 END,  --RTJ 09/05/2022	
                        rc.harmonized_tariff_schedule_number, r.country_of_origin	
          LOOP	
              IF v_first_adjust THEN	
                  INSERT INTO preftz.ft20 	
                             (admission_type, ft10id)	
                      VALUES ('O', v_ft10id);	
                  SELECT currval(pg_get_serial_sequence('preftz.ft20','ft20id')) INTO v_ft20id;	
        	
                  --RTJ 05/21/2021	
                  INSERT INTO preftz.ft40	
                              (bill_of_lading_airwaybill, quantity, ft20id)  --RTJ 05/13/2021	
                       VALUES (v_firms || 'ADJ' || TO_CHAR(current_date,'YYMMDD') || '001', 	
                               1, v_ft20id);  --RTJ 05/13/2021	
                          	
                  SELECT currval(pg_get_serial_sequence('preftz.ft40','ft40id')) INTO v_ft40id;	
                  	
                  v_first_adjust = FALSE;	
              END IF;	
              	
              IF ars.hts_line_group <> prev_line_group THEN	
                  prev_line_group = ars.hts_line_group;	
                  line_count = preftz.get_hts_line_number  --RTJ 06/21/2021 	
                              (p_admission_number, 'ADJ',  --RTJ 06/21/2021 	
                               v_firms || 'ADJ' || TO_CHAR(current_date,'YYMMDD') || '001',  --RTJ 06/21/2021	
                               NULL, NULL, ars.hts_line_group);  --RTJ 06/29/2021  	
                  hts_count = 1;	
                  v_base_uom = ars.unit_1;	
                  v_base_qty = ars.v_qty_1;	
              ELSE	
                  hts_count = hts_count + 1;	
              END IF;	
                      	
              v_gross_weight = ars.adjust_weight;	
              IF v_gross_weight = 0 THEN v_gross_weight = 1; END IF;	
                      	
              v_charges = 0;	
              v_hmf_fee = 0;	
                      	
              v_value = ROUND(ars.adjust_value + 0.000001);	
              IF v_value = 0 THEN v_value = 1; END IF;	
    	
              IF hts_count > 1 AND COALESCE(ars.unit_1,'X') IN ('','X')        --NKM 05/05/2022	
              AND LEFT(ars.harmonized_tariff_schedule_number,2) IN('99','98') THEN --NKM 11/07/2022	
                  v_qty1_rnd = GREATEST(v_base_qty,0.01);    --NKM 03/28/2024	
                  v_unit_1 = v_base_uom;	
              ELSE	
                  v_qty1_rnd = GREATEST(ars.v_qty_1,0.01);   --NKM 03/28/2024	
                  v_unit_1 = ars.unit_1;	
              END IF;	
    	
              IF ars.unit_2 = 'X' THEN	
                  v_qty2_rnd = 0;	
                  v_unit_2 = NULL;	
              ELSE	
                  v_qty2_rnd = GREATEST(ars.v_qty_2,0.01);   --NKM 03/28/2024	
                  v_unit_2 = ars.unit_2;	
              END IF;	
                      	
              SELECT s.special_programs_indicator_type	
                INTO v_spi_type	
                FROM preftz.special_programs_indicator_codes s	
               WHERE s.special_programs_indicator_code = ars.special_programs_indicator;	
        	
              INSERT INTO preftz.ft50	
                         (line_item_number, harmonized_tariff_schedule_number, special_programs_indicator,	
                          special_programs_indicator_country, special_programs_indicator_secondary,	
                          country_of_origin, quantity_1, unit_of_measure_1, quantity_2, unit_of_measure_2,	
                          quota_category, pn_disclaimer_flag, weight, us_dollar_value, charges,	
                          zone_status, harbor_maintenance_fee, ft40id)	
                  VALUES (line_count, ars.harmonized_tariff_schedule_number, 	
                          CASE WHEN v_spi_type = 'P' THEN ars.special_programs_indicator ELSE NULL END,	
                          CASE WHEN v_spi_type = 'C' THEN ars.special_programs_indicator ELSE NULL END,	
                          CASE WHEN v_spi_type = 'S' THEN ars.special_programs_indicator ELSE NULL END, 	
                          ars.country_of_origin, ROUND(v_qty1_rnd,2), v_unit_1, ROUND(v_qty2_rnd,2), 	
                          v_unit_2, NULL, NULL, v_gross_weight, v_value, v_charges, ars.zone_status, 	
                          v_hmf_fee, v_ft40id);	
    	
              SELECT currval(pg_get_serial_sequence('preftz.ft50','ft50id')) INTO v_ft50id;	
        	
              FOR drs IN  --adjustment descriptions	
                  SELECT DISTINCT r.manufacturer_MID_code, 	
                         CASE WHEN hts_count = 1 THEN preftz.abi_an(p.description,45) --NKM 02/01/2023	
                              WHEN hts_count > 1 AND SUBSTR(rc.harmonized_tariff_schedule_number,1,2) = '99'	
                                   THEN 'CHAPTER99'	
                              WHEN hts_count > 1 AND SUBSTR(rc.harmonized_tariff_schedule_number,1,2) = '98'	
                                   THEN 'CHAPTER98'	
                              ELSE 'MULTIPLE TARIFF'	
                              END description	
                    FROM preftz.inventory_items ii	
                         INNER JOIN preftz.adjustment_zone_admission_nos a	
                                 ON ii.itemid = a.itemid	
                         INNER JOIN preftz.parts p	
                                 ON ii.part_number = p.part_number	
                         INNER JOIN preftz.receipts r	
                                 ON ii.receiptid = r.receiptid	
                         INNER JOIN preftz.receipt_classifications rc	
                                 ON r.receiptid = rc.receiptid       	
                   WHERE ii.adjustid > 0	
                     AND ii.zone_status <> 'D'	
                     AND a.zone_admission_no = p_admission_number	
                     AND rc.harmonized_tariff_schedule_number = ars.harmonized_tariff_schedule_number	
                     AND COALESCE(rc.special_programs_indicator,'') = COALESCE(ars.special_programs_indicator,'')	
                     AND ii.zone_status = ars.zone_status	
                     AND preftz.get_hts_line_group(r.receiptid) = ars.hts_line_group	
              LOOP	
                  INSERT INTO preftz.ft60	
                             (description, reference_qualifier, referenceid, ft50id)	
                      VALUES (drs.description, 'MID', drs.manufacturer_MID_code, v_ft50id);	
              END LOOP;  --drs adjustments	
	
              --NKM 05/19/2022 --include steel and aluminum import licenses	
              IF hts_count = 1 THEN	
                 INSERT INTO preftz.ft60	
                                (description, reference_qualifier, referenceid, ft50id)	
                 SELECT DISTINCT preftz.abi_an(p.description,45), il.import_license_type, il.import_license_number, v_ft50id --NKM 02/01/2023	
                   FROM preftz.receipts r	
                        INNER JOIN preftz.import_licenses il ON il.receiptid = r.receiptid	
                        INNER JOIN preftz.parts p ON p.part_number = r.part_number	
                  WHERE il.receiptid = ANY(ars.a_receiptids);	
              END IF;	
	
          END LOOP;  --adjustments	

          -- NO 2/24/2026 Create hmf from e214, inserts into archive_hmf_details table, added check for function to account for possible version issues
          IF to_regproc('preftz.create_hmf_from_e214') IS NOT NULL THEN
            INSERT INTO preftz.system_log (procedure_name, log_message)
            VALUES ('create_e214', 'Calling create_hmf_from_e214 for ' || p_admission_number);
            BEGIN
                PERFORM preftz.create_hmf_from_e214(p_admission_number);
                EXCEPTION
                    WHEN OTHERS THEN
                        INSERT INTO preftz.system_log (procedure_name, log_message)
                        VALUES ('create_e214', 'hmf_details insert failed for ' || p_admission_number || ': ' || SQLERRM);
            END;
          END IF;
    	
          --Get pre-receipt status --NKM 10/03/2022	
          v_has_pre_receipts = EXISTS(SELECT FROM preftz.receipts r WHERE r.zone_admission_no = p_admission_number AND r.pre_receipt) OR	
                               EXISTS(SELECT FROM preftz.fed_receipts fr WHERE fr.zone_admission_no = p_admission_number AND fr.pre_receipt);	
          --Get physical_arrival_status --NKM 10/03/2022	
          v_physical_arrival_status = preftz.get_arrival_status(p_admission_number);	
    	
          UPDATE preftz.e214_filing_statuses	
             SET e214_status = 'CREATED',	
                 create_status = 'PASS',	
                 document_status = NULL,	
                 census_status = NULL,	
                 concur_status = NULL,	
                 general_order_status = NULL,	
                 other_status = NULL,	
                 data_updated_after_create = 'N',	
                 post_admission_correction_status = NULL,	
                 delete_status = NULL,  --RTJ 07/09/2021	
                 temporary_deposit_status = NULL,  --RTJ 08/04/2021	
                 has_pre_receipts = v_has_pre_receipts, --NKM 10/03/2022	
                 physical_arrival_status = v_physical_arrival_status --NKM 10/03/2022	
           WHERE zone_admission_no = p_admission_number;	
           	
          v_create_status = 'CREATED';	
	
          CALL preftz.set_pga_document_status(p_admission_number,'ADMISSION'); --NKM 03/15/2023	
      	
      ELSE  --audit failed	
      	
          UPDATE preftz.e214_filing_statuses	
             SET e214_status = NULL,	
                 create_status = 'FAIL',	
                 document_status = NULL,	
                 census_status = NULL,	
                 concur_status = NULL,	
                 general_order_status = NULL,	
                 other_status = NULL,	
                 data_updated_after_create = 'N',	
                 post_admission_correction_status = NULL,	
                 delete_status = NULL,  --RTJ 07/09/2021	
                 temporary_deposit_status = NULL,  --RTJ 08/04/2021	
                 has_pre_receipts = NULL, --NKM 10/03/2022	
                 physical_arrival_status = NULL --NKM 10/03/2022	
           WHERE zone_admission_no = p_admission_number;	
      	
          v_create_status = 'FAILED';	
      	
      END IF;  --audit result	
  END IF;  --ineligble for filing (already concurred or in interim filing state)	
  	
  INSERT INTO preftz.system_log (procedure_name, log_message) 	
  VALUES ('create_e214', 'finished: ' || p_admission_number || ' ' || v_create_status);	
  	
END;	

$procedure$
;

-- PROCEDURE: preftz.concur_e214(character varying)

-- DROP PROCEDURE preftz.concur_e214(character varying);

CREATE OR REPLACE PROCEDURE preftz.concur_e214(
	p_admission_number character varying)
LANGUAGE 'plpgsql'
AS $BODY$
--CHANGE LOG:
--EG 05/14/2026 added preftz.add_template_for_receipt
--NKM 06/18/2022 added details to abi_requests
--JM  05/05/2022 Change p_zone_admission_no to p_admission_number
--NKM 05/03/2022 Added 214s with pre_receipts can not be concurred
--NKM 04/05/2021 added abi_archive
--NKM 02/25/2021 moved interactions with abi_requests and abi_requests_master to other procedures
--NKM 02/17/2021 removed deletion of abi_output table and added batchid to abi_output table
--NKM 12/23/2020 Added A & Z record creation

DECLARE
    v_batchid            INTEGER;
    v_application_code   VARCHAR(2) := 'FZ'; -- FZ = FTZ Manifest Quanitiy Concurrence / PTT / Arrival
    a_record             VARCHAR(80);
    b_record             VARCHAR(80);
    y_record             VARCHAR(80);
    z_record             VARCHAR(80);
    line_text            VARCHAR(80);
    v_received_quantity  INTEGER;
    v_ft10id             INTEGER;
    v_zoneid             VARCHAR(9);
    v_e214               VARCHAR(19);

BEGIN
 
  --NKM 05/02/2022 Do not concur if there are pre_receipts attached to this admission 
  IF EXISTS (SELECT FROM preftz.receipts WHERE zone_admission_no = p_admission_number AND pre_receipt IS TRUE) THEN --JM corrected variable name
     INSERT INTO preftz.user_logs(title, body, details)
     VALUES ('Warning: Unable to concur this e214','This e214 contains pre_receipts and cannot be concurred.','Replace pre_receipts with receipts from your ERP system and re-file.');
     INSERT INTO preftz.system_log (procedure_name,log_message)
     VALUES ('concur_e214','aborted');
     RETURN;
  END IF;

  SELECT ft10id, zoneid INTO v_ft10id, v_zoneid
    FROM preftz.ft10
   WHERE calendar_year = LEFT(p_admission_number,2)
     AND control_number = SUBSTR(p_admission_number,3,8);
     
  SELECT SUM(f4.quantity) INTO v_received_quantity
    FROM preftz.ft40 f4 INNER JOIN
         preftz.ft20 f2 ON f4.ft20id = f2.ft20id
   WHERE f2.ft10id = v_ft10id;
  
  IF v_received_quantity > 0 THEN
      v_batchid = preftz.get_new_abi_batch(v_application_code);

      UPDATE preftz.abi_requests --NKM 06/18/2022
         SET document_number = p_admission_number,
             procedure_name = 'concur_e214'
       WHERE batchid = v_batchid;

      a_record = preftz.get_a_record(v_batchid);
      INSERT INTO preftz.abi_output (abi_record,batchid)
           VALUES (UPPER(a_record), v_batchid);

      b_record = preftz.get_b_record(v_application_code);
      INSERT INTO preftz.abi_output (abi_record,batchid)
           VALUES (UPPER(b_record), v_batchid);
           
      line_text = '10' || '1' || preftz.spacefill(v_zoneid || p_admission_number, 35) || 'A ' ||
                  TRIM(TO_CHAR(v_received_quantity,'0000000000')) || 'FI' ||
                  preftz.spacefill(' ', 28);
    
          INSERT INTO preftz.abi_output(abi_record, batchid)
                   VALUES (UPPER(line_text), v_batchid);
        
      y_record = preftz.get_y_record(v_application_code);
      INSERT INTO preftz.abi_output (abi_record, batchid)
           VALUES (UPPER(y_record), v_batchid);
    
      z_record = preftz.get_z_record(v_batchid);
      INSERT INTO preftz.abi_output (abi_record, batchid)
           VALUES (UPPER(z_record), v_batchid);

      CALL preftz.archive_abi_output(v_batchid);
    
  INSERT INTO preftz.system_log(procedure_name, log_message) 
      VALUES ('concur_e214','finished');
      
      UPDATE preftz.e214_filing_statuses
        SET concur_status = 'FILED'
      WHERE zone_admission_no = p_admission_number;

--EG 05/14/2026
    IF (select  coalesce(preftz.get_ftz_setting('ADD TO CARGO TEMPLATE ON CONCUR'),'NO') = 'YES') 
    THEN 
      CALL preftz.add_template_for_receipt (p_admission_number);
    END IF;      
--EG 05/14/2026      

  END IF;
  
END;
$BODY$;


-- Drop is required because the input parameter name is changing.
DROP FUNCTION IF EXISTS preftz.get_receiptid_from_prereceiptid(integer);

CREATE OR REPLACE FUNCTION preftz.get_receiptid_from_prereceiptid(
    p_receiptid integer
)
RETURNS integer
LANGUAGE sql
STABLE
AS $function$

--Change Log:
-- EG 07/23/2026 working version


WITH target_receipt AS
(
    /*
     * The supplied ID can be either a pre-receipt
     * or an actual receipt.
     */
    SELECT
        r.zone_admission_no,
        r.part_number,
        r.quantity
    FROM preftz.receipts r
    WHERE r.receiptid = p_receiptid
      AND r.zone_admission_no IS NOT NULL
),
matching_pre_receipts AS
(
    SELECT
        r.receiptid
    FROM preftz.receipts r
    JOIN target_receipt t
      ON r.zone_admission_no = t.zone_admission_no
     AND r.part_number IS NOT DISTINCT FROM t.part_number
     AND r.quantity IS NOT DISTINCT FROM t.quantity
    WHERE r.pre_receipt IS TRUE
),
matching_actual_receipts AS
(
    SELECT
        r.receiptid
    FROM preftz.receipts r
    JOIN target_receipt t
      ON r.zone_admission_no = t.zone_admission_no
     AND r.part_number IS NOT DISTINCT FROM t.part_number
     AND r.quantity IS NOT DISTINCT FROM t.quantity
    WHERE r.pre_receipt IS NOT TRUE
),
match_counts AS
(
    SELECT
        (
            SELECT COUNT(*)
            FROM matching_pre_receipts
        ) AS pre_receipt_count,
        (
            SELECT COUNT(*)
            FROM matching_actual_receipts
        ) AS actual_receipt_count
)
SELECT ar.receiptid
FROM matching_actual_receipts ar
CROSS JOIN match_counts mc
WHERE mc.pre_receipt_count = 1
  AND mc.actual_receipt_count = 1;

$function$;--DROP FUNCTION IF EXISTS preftz.check_prereceipt_one_to_one(integer);

CREATE OR REPLACE FUNCTION preftz.check_prereceipt_one_to_one(
    p_receiptid integer
)
RETURNS text
LANGUAGE sql
STABLE
AS $function$

--Change Log: 	
-- EG 07/23/2026 working version

WITH target_receipt AS
(
    /*
     * The parameter can be an actual receipt or a pre-receipt.
     */
    SELECT
        r.zone_admission_no,
        r.part_number,
        r.unit_price,
        r.country_of_origin
    FROM preftz.receipts r
    WHERE r.receiptid = p_receiptid
      AND r.zone_admission_no IS NOT NULL
),
pre_receipt_totals AS
(
    SELECT
        COUNT(*)        AS receipt_count,
        SUM(r.quantity) AS total_quantity
    FROM preftz.receipts r
    JOIN target_receipt t
      ON r.zone_admission_no = t.zone_admission_no
     AND r.part_number IS NOT DISTINCT FROM t.part_number
     AND r.unit_price IS NOT DISTINCT FROM t.unit_price
     AND r.country_of_origin
         IS NOT DISTINCT FROM t.country_of_origin
    WHERE r.pre_receipt IS TRUE
),
actual_receipt_totals AS
(
    SELECT
        COUNT(*)        AS receipt_count,
        SUM(r.quantity) AS total_quantity
    FROM preftz.receipts r
    JOIN target_receipt t
      ON r.zone_admission_no = t.zone_admission_no
     AND r.part_number IS NOT DISTINCT FROM t.part_number
     AND r.unit_price IS NOT DISTINCT FROM t.unit_price
     AND r.country_of_origin
         IS NOT DISTINCT FROM t.country_of_origin
    WHERE r.pre_receipt IS NOT TRUE
)
SELECT
    CASE
        WHEN pr.receipt_count = 1
         AND ar.receipt_count = 1
         AND pr.total_quantity = ar.total_quantity
            THEN 'PASS'

        ELSE 'FAIL'
    END
FROM pre_receipt_totals pr
CROSS JOIN actual_receipt_totals ar;

$function$;--DROP FUNCTION IF EXISTS preftz.check_prereceipt_zone_admission_no_v2(text);

CREATE OR REPLACE FUNCTION preftz.check_prereceipt_zone_admission_no(
    p_zone_admission_no text
)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $function$

--Change Log:
-- EG 07/29/2026 working version
-- EG 07/23/2026 working version


DECLARE
    crs                         RECORD;

    v_prereceipt_count          integer;
    v_total_receipt_count       integer;

    v_matching_receiptid        integer;
BEGIN
    /*
     * Return FAIL when the admission has already been concurred.
     */
    IF EXISTS
    (
        SELECT 1
        FROM preftz.receipts r
        JOIN preftz.e214_filing_statuses f
          ON f.zone_admission_no = r.zone_admission_no
        WHERE r.pre_receipt IS TRUE
          AND r.zone_admission_no = p_zone_admission_no
          AND COALESCE(f.concur_status, '')
              NOT IN ('', 'REJECTED')
    )
    THEN
        RETURN 'FAIL';
    END IF;

    /*
     * Return NA when the admission has no pre-receipts.
     */
    SELECT COUNT(*)
    INTO v_prereceipt_count
    FROM preftz.receipts r
    WHERE r.pre_receipt IS TRUE
      AND r.zone_admission_no = p_zone_admission_no;

    IF v_prereceipt_count = 0 THEN
        RETURN 'NA';
    END IF;

    /*
     * Return NA when the admission contains only pre-receipts
     * and does not yet contain actual receipts.
     */
    SELECT COUNT(*)
    INTO v_total_receipt_count
    FROM preftz.receipts r
    WHERE r.zone_admission_no = p_zone_admission_no;

    IF v_prereceipt_count = v_total_receipt_count THEN
        RETURN 'NA';
    END IF;

    /*
     * Validate every pre-receipt and actual receipt separately.
     */
    FOR crs IN
        SELECT r.receiptid
        FROM preftz.receipts r
        WHERE r.zone_admission_no = p_zone_admission_no
        ORDER BY r.receiptid
    LOOP

         -- Check for most of conditions
         IF preftz.check_pre_receipts_1(crs.receiptid) <> 'FAIL' 
         THEN
             CONTINUE;
         END IF;

        /*
         * Check: find a matching actual receipt ID. only on qnt and part_number
         */
        v_matching_receiptid :=  preftz.get_receiptid_from_prereceiptid(crs.receiptid);
        IF v_matching_receiptid IS NOT NULL THEN
            CONTINUE;
        END IF;

        /*
         * The current receipt failed all three checks.
         */
        RETURN 'FAIL';
    END LOOP;

    /*
     * Every receipt passed at least one check.
     */
    RETURN 'PASS';
END;
$function$;--DROP PROCEDURE IF EXISTS preftz.pre_receipts_filing();
CREATE OR REPLACE PROCEDURE preftz.pre_receipts_filing (
)
LANGUAGE plpgsql
AS $procedure$

--Change Log:
-- EG 08/11/2026 logic update
-- EG 07/23/2026 working version

DECLARE
  crs              RECORD;
  v_count          integer;
  
BEGIN
         -- Log start
         INSERT INTO preftz.system_log(procedure_name, log_message, details)
         VALUES ('pre_receipts_filing', 'started', now());
        
         IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N' 
         THEN
         
         FOR crs IN -- find all NOT eligible admissions with not matching receipts and pre-receipts and generate and ERROR 
         select 
         zone_admission_no
         from preftz.receipts r 
         where
         COALESCE(r.zone_admission_no,'') <> ''
         --r.pre_receipt is TRUE 
         and preftz.check_prereceipt_zone_admission_no(r.zone_admission_no) <> 'NA'
         --and exists (select 1 from preftz.receipts r1 where r1.zone_admission_no = r.zone_admission_no and r1.pre_receipt is not true)
         and exists (select 1 from preftz.receipts r1 where r1.zone_admission_no = r.zone_admission_no and r1.pre_receipt is true)
         and r.privileged_date is null
         group by r.zone_admission_no
         order by r.zone_admission_no
         LOOP
             PERFORM preftz.audit_e214_data(crs.zone_admission_no);
         END LOOP;

        
         DROP TABLE IF EXISTS temp_e214_filing_statuses;
         
         CREATE TEMP TABLE temp_e214_filing_statuses AS
         SELECT zone_admission_no
         ,e214_date
         ,e214_status
         ,document_status
         ,census_status
         ,concur_status
         ,general_order_status
         ,other_status
         ,last_response_date
         ,data_updated_after_create
         ,post_admission_correction_status
         ,create_status
         ,email_flag
         ,currently_filed
         ,delete_status
         ,temporary_deposit_status
         ,temporary_deposit
         ,system_error
         ,has_pre_receipts
         ,physical_arrival_status
         ,accept_status
         ,notifications
         ,pga_required
         ,crossdock_created
         ,bypass_added_tariffs
         ,pre_receipt_status
         ,ptt_status
         FROM preftz.e214_filing_statuses
         WHERE COALESCE(e214_status,'') IN ('AUTHORIZED')
           AND COALESCE(concur_status ,'') NOT IN ('POSTED');


         FOR crs IN -- find all eligible admissions
         select 
         zone_admission_no
         from preftz.receipts r 
         where 
         r.pre_receipt is TRUE 
         and preftz.check_prereceipt_zone_admission_no(r.zone_admission_no) = 'PASS'
         AND COALESCE(r.zone_admission_no,'') <> ''
         group by r.zone_admission_no
         order by r.zone_admission_no
         
         LOOP
         
           -- lock all receipts for this admission
           PERFORM 1
           FROM preftz.receipts r
           WHERE r.zone_admission_no = crs.zone_admission_no
           FOR UPDATE;
           
            -- Before working on a given admission
            PERFORM 1
            FROM preftz.e214_filing_statuses
            WHERE zone_admission_no = crs.zone_admission_no
            FOR UPDATE;

            -- admission should be authorized and not concur
            select count(*) 
            into v_count
            from preftz.e214_filing_statuses efs
            where efs.zone_admission_no = crs.zone_admission_no
            AND COALESCE(efs.e214_status,'') IN ('AUTHORIZED')
            and COALESCE(efs.concur_status ,'') NOT IN ('POSTED');            
            

            IF v_count = 1 
            THEN 
               
               INSERT INTO preftz.system_log(procedure_name, log_message, details)
               VALUES ('pre_receipts_filing', 'Check if concur can be called for '||crs.zone_admission_no, now());

               IF (preftz.audit_e214_data(crs.zone_admission_no) = 'PASS') -- check and classify receipts
               THEN 
                 CALL preftz.pre_receipts_delete(crs.zone_admission_no); --move pre-receipts to preftz.deleted_pre_receipts;
                 RAISE NOTICE '1 pre-receipts deleted crs.zone_admission_no % ', crs.zone_admission_no;
               END IF; 
               
               --check one more time 
               if (preftz.check_prereceipt_zone_admission_no(crs.zone_admission_no) = 'NA') -- pre-receipts moved successfuly   
               THEN 
               
                   IF (preftz.audit_e214_data(crs.zone_admission_no) = 'PASS') -- check and classify receipts
                   THEN

                        UPDATE preftz.e214_filing_statuses t
                        SET
                            e214_status = null
                           ,currently_filed = null
                        where
                        t.zone_admission_no = crs.zone_admission_no; 
                        
                        CALL preftz.create_e214(crs.zone_admission_no); --need all w10,20, ... tables to be recreated with receipt info
                        
                        --restore original status
                        UPDATE preftz.e214_filing_statuses t
                        SET
                            e214_date     = tmp.e214_date,
                            e214_status   = tmp.e214_status,
                            create_status = tmp.create_status,
                            document_status = tmp.document_status,
                            census_status = tmp.census_status,
                            concur_status = tmp.concur_status,
                            general_order_status = tmp.general_order_status,
                            other_status = tmp.other_status,
                            last_response_date = tmp.last_response_date,
                            data_updated_after_create = tmp.data_updated_after_create,
                            post_admission_correction_status = tmp.post_admission_correction_status,
                            email_flag = tmp.email_flag,
                            currently_filed = tmp.currently_filed,
                            delete_status = tmp.delete_status,
                            temporary_deposit_status = tmp.temporary_deposit_status,
                            temporary_deposit = tmp.temporary_deposit,
                            system_error = tmp.system_error,
                            has_pre_receipts = tmp.has_pre_receipts,
                            physical_arrival_status = tmp.physical_arrival_status,
                            accept_status = tmp.accept_status,
                            notifications = tmp.notifications,
                            pga_required = tmp.pga_required,
                            crossdock_created = tmp.crossdock_created,
                            bypass_added_tariffs = tmp.bypass_added_tariffs,
                            pre_receipt_status = tmp.pre_receipt_status,
                            ptt_status = tmp.ptt_status
                        FROM temp_e214_filing_statuses tmp
                        WHERE t.zone_admission_no = tmp.zone_admission_no
                        and t.zone_admission_no = crs.zone_admission_no ;
                        
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK_CONCUR')  	
    THEN  	
                        CALL preftz.concur_e214(crs.zone_admission_no); --concur
                        
                        RAISE NOTICE '2 concur_e214 was called for % ', crs.zone_admission_no;
                        
                        INSERT INTO preftz.system_log(procedure_name, log_message, details)
                        VALUES ('pre_receipts_filing', 'concur_e214 was called for '||crs.zone_admission_no, now());
    END IF; 	                        
                        
                   END IF; -- check and classify receipts

               END IF;-- pre-receipts moved successfuly   
            
            END IF; --IF v_count = 1 
            
         END LOOP;
         
    END IF;--IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N' 
    

    -- Log finish
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('pre_receipts_filing' , 'finished', now());

EXCEPTION WHEN OTHERS THEN
    
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('pre_receipts_filing', 'ERROR: ' || SQLERRM, now());
    RAISE;
END;
$procedure$;

--DROP PROCEDURE IF EXISTS preftz.pre_receipts_delete(varchar);

CREATE OR REPLACE PROCEDURE preftz.pre_receipts_delete(
    IN p_admission_number varchar
)
LANGUAGE plpgsql
AS $procedure$

--Change Log:
-- EG 07/29/2026 working version
-- EG 07/23/2026 working version

DECLARE
    v_count            integer;
    crs_many_to_many   record;


BEGIN
    -- Log start
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('pre_receipts_delete(' || COALESCE(p_admission_number,'') || ')', 'started', now());
    
    --do not process if pre_receipts were already deleted
    SELECT COUNT(*)
    INTO v_count
    FROM preftz.deleted_pre_receipts ftf
    WHERE ftf.zone_admission_no = p_admission_number;
                       
    IF (v_count > 0 ) THEN  --do not do anything
       INSERT INTO preftz.system_log(procedure_name, log_message, details)
       VALUES ('pre_receipts_delete' , 'deleted pre-receipts already exist for adm_no: '||p_admission_number, now());
       RETURN;
    END IF;                       
    

 if (preftz.check_prereceipt_zone_admission_no(p_admission_number) = 'PASS')
 THEN

    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('pre_receipts_delete', 'check_prereceipt_zone_admission_no is PASS', now());

    -- Lock receipts for this admission number
    PERFORM  1
    FROM preftz.receipts r
    WHERE r.zone_admission_no = p_admission_number
    FOR UPDATE;

    --Delete old snapshot rows not needed ?
    --DELETE FROM preftz.deleted_pre_receipts dpr     WHERE dpr.zone_admission_no = p_admission_number;

    -- Insert new snapshot rows
    INSERT INTO preftz.deleted_pre_receipts (
        receiptid, part_number, receipt_date, quantity, unit_price,
        manufacturer_mid_code, country_of_origin, bill_of_lading_proxy,
        commercial_invoice_number, transaction_reference, zone_admission_no,
        zone_status, foreign_unit_price, currency_code, currency_exchange_rate,
        privileged_date, conveyanceid, country_of_export, export_date,
        gross_weight, charges, zone_to_zone_transfer, cloned_from_receiptid,
        inbond_number, pre_receipt, unit_assist, kit_receiptid
        ,container
        ,matching_receiptid
    )
    SELECT
        r.receiptid, r.part_number, r.receipt_date, r.quantity, r.unit_price,
        r.manufacturer_mid_code, r.country_of_origin, r.bill_of_lading_proxy,
        r.commercial_invoice_number, r.transaction_reference, r.zone_admission_no,
        r.zone_status, r.foreign_unit_price, r.currency_code, r.currency_exchange_rate,
        r.privileged_date, r.conveyanceid, r.country_of_export, r.export_date,
        r.gross_weight, r.charges, r.zone_to_zone_transfer, r.cloned_from_receiptid,
        r.inbond_number, r.pre_receipt, r.unit_assist, r.kit_receiptid
        ,r.container
        ,preftz.get_receiptid_from_prereceiptid(r.receiptid)
        --,-1
    FROM preftz.receipts r
    WHERE r.zone_admission_no = p_admission_number
    AND r.pre_receipt is true;

   
       -- Insert new snapshot rows
       INSERT INTO preftz.archived_updated_receipts (
           receiptid, part_number, receipt_date, quantity, unit_price,
           manufacturer_mid_code, country_of_origin, bill_of_lading_proxy,
           commercial_invoice_number, transaction_reference, zone_admission_no,
           zone_status, foreign_unit_price, currency_code, currency_exchange_rate,
           privileged_date, conveyanceid, country_of_export, export_date,
           gross_weight, charges, zone_to_zone_transfer, cloned_from_receiptid,
           inbond_number, pre_receipt, unit_assist, kit_receiptid
           ,container
           )
       SELECT
           r.receiptid, r.part_number, r.receipt_date, r.quantity, r.unit_price,
           r.manufacturer_mid_code, r.country_of_origin, r.bill_of_lading_proxy,
           r.commercial_invoice_number, r.transaction_reference, r.zone_admission_no,
           r.zone_status, r.foreign_unit_price, r.currency_code, r.currency_exchange_rate,
           r.privileged_date, r.conveyanceid, r.country_of_export, r.export_date,
           r.gross_weight, r.charges, r.zone_to_zone_transfer, r.cloned_from_receiptid,
           r.inbond_number, r.pre_receipt, r.unit_assist, r.kit_receiptid
           ,r.container
       FROM preftz.receipts r
       WHERE r.zone_admission_no = p_admission_number
       AND r.pre_receipt is not true;
       
       --change receipts values to pre-receipts values for  one-to-one cases
       UPDATE preftz.receipts r
       SET 
        privileged_date = ftf.privileged_date  
       ,unit_price = ftf.unit_price 
       ,country_of_origin = ftf.country_of_origin
       ,manufacturer_mid_code = ftf.manufacturer_mid_code
       FROM preftz.deleted_pre_receipts ftf
       WHERE r.pre_receipt IS NOT TRUE
       AND r.receiptid = ftf.matching_receiptid   
       AND r.zone_admission_no = p_admission_number
       ;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        
        INSERT INTO preftz.system_log
        (
            procedure_name,
            log_message,
            details
        )
        VALUES
        (
            'pre_receipts_delete',
            'Updated '
                || v_count
                || ' one-to-one actual receipts for admission: '
                || p_admission_number,
            NOW()
        );       

/*
 * Process every valid many-to-many pre-receipt group.
 */
FOR crs_many_to_many IN
    SELECT
        MAX(x.receiptid) AS r_id,
        x.part_id
    FROM
    (
        SELECT
            r.receiptid,
            preftz.check_pre_receipts_1(
                r.receiptid
            ) AS part_id
        FROM preftz.receipts r
        WHERE r.zone_admission_no =
              p_admission_number
          AND r.pre_receipt IS TRUE
    ) x
    WHERE x.part_id <> 'FAIL'
    GROUP BY
        x.part_id
    ORDER BY
        x.part_id
LOOP
    /*
     * Update all unmatched actual receipts for this part
     * using the representative pre-receipt.
     */
    UPDATE preftz.receipts r
    SET
        privileged_date =
            dpr.privileged_date,
        unit_price =
            dpr.unit_price,
        country_of_origin =
            dpr.country_of_origin,
        manufacturer_mid_code =
            dpr.manufacturer_mid_code
    FROM preftz.deleted_pre_receipts dpr
    WHERE dpr.receiptid =
          crs_many_to_many.r_id
      AND dpr.zone_admission_no =
          p_admission_number
      AND r.zone_admission_no =
          p_admission_number
      AND r.part_number
          IS NOT DISTINCT FROM
              crs_many_to_many.part_id
      AND r.pre_receipt IS NOT TRUE

      /*
       * Exclude actual receipts already handled by
       * the one-to-one update.
       */
      AND NOT EXISTS
      (
          SELECT 1
          FROM preftz.deleted_pre_receipts dpr1
          WHERE dpr1.zone_admission_no =
                p_admission_number
            AND dpr1.matching_receiptid =
                r.receiptid
      );

    INSERT INTO preftz.system_log
    (
        procedure_name,
        log_message,
        details
    )
    VALUES
    (
        'pre_receipts_delete',
        'Updated many-to-many actual receipts for admission: '
        || p_admission_number
        || ', part: '
        || crs_many_to_many.part_id
        || ', representative pre-receiptid: '
        || crs_many_to_many.r_id,
        NOW()
    );
END LOOP;


/*
 * Delete all pre-receipts after all one-to-one and
 * many-to-many actual receipt updates are complete.
 */
DELETE FROM preftz.receipts r
WHERE r.zone_admission_no = p_admission_number
  AND r.pre_receipt IS TRUE;

GET DIAGNOSTICS v_count = ROW_COUNT;

INSERT INTO preftz.system_log
(
    procedure_name,
    log_message,
    details
)
VALUES
(
    'pre_receipts_delete',
    'Deleted '
        || v_count
        || ' pre-receipts for admission: '
        || p_admission_number,
    NOW()
);


/*
 * Verify that all pre-receipts were deleted.
 *
 * Raising an exception rolls back:
 * - Actual receipt updates
 * - Pre-receipt deletions
 * - Snapshot inserts
 * - Archive inserts
 */
IF preftz.check_prereceipt_zone_admission_no( p_admission_number ) <> 'NA'
THEN
    RAISE EXCEPTION
        'Not all pre-receipts were deleted for admission %',
        p_admission_number;
END IF;

/*
   --check if ALL pre-receipts were deleted ? 
   if (preftz.check_prereceipt_zone_admission_no(p_admission_number) <> 'NA')
   THEN

    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('pre_receipts_delete', 'ERROR: Not all pre-receipts were deleted', now());

    --move it back to receipts table
    INSERT INTO preftz.receipts (
        receiptid, part_number, receipt_date, quantity, unit_price,
        manufacturer_mid_code, country_of_origin, bill_of_lading_proxy,
        commercial_invoice_number, transaction_reference, zone_admission_no,
        zone_status, foreign_unit_price, currency_code, currency_exchange_rate,
        privileged_date, conveyanceid, country_of_export, export_date,
        gross_weight, charges, zone_to_zone_transfer, cloned_from_receiptid,
        inbond_number, pre_receipt, unit_assist, kit_receiptid
        ,container
    )
    SELECT
        r.receiptid, r.part_number, r.receipt_date, r.quantity, r.unit_price,
        r.manufacturer_mid_code, r.country_of_origin, r.bill_of_lading_proxy,
        r.commercial_invoice_number, r.transaction_reference, r.zone_admission_no,
        r.zone_status, r.foreign_unit_price, r.currency_code, r.currency_exchange_rate,
        r.privileged_date, r.conveyanceid, r.country_of_export, r.export_date,
        r.gross_weight, r.charges, r.zone_to_zone_transfer, r.cloned_from_receiptid,
        r.inbond_number, r.pre_receipt, r.unit_assist, r.kit_receiptid
        ,r.container
    FROM preftz.deleted_pre_receipts r
    LEFT JOIN preftz.receipts ro ON ro.receiptid = r.receiptid 
    AND ro.zone_admission_no = r.zone_admission_no
    WHERE r.zone_admission_no = p_admission_number
    AND ro.receiptid is null
    AND r.pre_receipt is true;

    DELETE FROM preftz.deleted_pre_receipts dpr
    WHERE dpr.zone_admission_no = p_admission_number;

   END IF;
*/

END IF;

    -- Log finish
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('pre_receipts_delete(' || COALESCE(p_admission_number,'') || ')', 'finished', now());
    
END;
$procedure$;

--DROP PROCEDURE IF EXISTS preftz.link_receipts_to_conveyances_by_inbond();
CREATE OR REPLACE PROCEDURE preftz.link_receipts_to_conveyances_by_inbond (
)
LANGUAGE plpgsql
AS $procedure$

--Change Log: 
-- EG 08/20/2026 adding a logic to unlink actual receipts when e214_status is not AUTHORIZED and pre-receipts exist for the admission.
-- EG 07/23/2026 working version
-- EG Original 4/7/2026 auto delete pre-receipts DEV-257

DECLARE
  crs              RECORD;
  v_conveyanceid      INTEGER;
  v_zone_admission_no VARCHAR(10);
  
  v_concur_status     VARCHAR(16);
  v_e214_status       VARCHAR(50);

  v_count             INTEGER;
  v_bol_proxy         VARCHAR(50);

  v_log_count         INTEGER;


BEGIN
    -- Log start
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('link_receipts_to_conveyances_by_inbond', 'started', NOW());

            IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N' 
            THEN

                       select count(*)
                       into v_log_count
                       FROM preftz.fed_receipts ;
                       INSERT INTO preftz.system_log(procedure_name, log_message, details)
                       VALUES ('link_receipts_to_conveyances_by_inbond', '# of fed receipts: ' || v_log_count, NOW());

              
              FOR crs IN 
                 SELECT fr.bill_of_lading_proxy, fr.receiptid, fr.pre_receipt
                 FROM preftz.receipts fr
                 WHERE   
                  COALESCE(fr.zone_admission_no,'') = ''
                  AND fr.conveyanceid IS NULL
                  AND COALESCE(fr.zone_status, '') <> 'D'
                  AND fr.quantity > 0 
                  AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y')
                  ORDER BY fr.receiptid
                  FOR UPDATE SKIP LOCKED
                  LOOP
                  
                       -- Reset per-loop variables to avoid accidental reuse
                       v_conveyanceid      := NULL;
                       v_zone_admission_no := NULL;
                       v_concur_status     := NULL;
                       v_e214_status       := NULL;
                       v_count             := 0;


                       SELECT c.conveyanceid, c.zone_admission_no
                       INTO v_conveyanceid,v_zone_admission_no
                       FROM preftz.conveyances c
                       where c.inbond_number  = crs.bill_of_lading_proxy  -- here INBOND for TRF
                       group by c.conveyanceid, c.zone_admission_no
                       order by c.conveyanceid, c.zone_admission_no
                       limit 1
                       ;

                       IF 
                       (
                       (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK') -- for Anatolia use BOL not an inbond
                       AND 
                       ((SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N' )
                       )
                       THEN  	
                           SELECT c.conveyanceid, c.zone_admission_no
                           INTO v_conveyanceid,v_zone_admission_no
                           FROM preftz.conveyances c
                           where c.bill_of_lading_airwaybill  = crs.bill_of_lading_proxy --here BOL
                           group by c.conveyanceid, c.zone_admission_no
                           order by c.conveyanceid, c.zone_admission_no
                           limit 1
                           ;
                        END IF; 	

            
                       --do not process if pre_receipts were already deleted
                       select count(*)
                       into v_count
                       FROM preftz.deleted_pre_receipts ftf
                       where ftf.conveyanceid = v_conveyanceid;
                       
                       SELECT COALESCE(efs.concur_status,''), COALESCE(efs.e214_status,'')
                       INTO v_concur_status, v_e214_status
                       FROM preftz.e214_filing_statuses efs
                       WHERE efs.zone_admission_no = v_zone_admission_no;

                       --do not process if e214 is in NULL satus and this is a receipt
                       IF (COALESCE(v_e214_status,'') <> 'AUTHORIZED') AND (crs.pre_receipt is not true) 
                       THEN
                         CONTINUE; --skip to next loop iteration
                       END IF;
                       
                       
                       IF  (v_conveyanceid IS NOT NULL) 
                       AND (COALESCE(v_concur_status,'') <> 'POSTED')  
                       AND (COALESCE(v_concur_status,'') <> 'FILED')  
                       AND (v_count = 0)
                       THEN  
                          
                          SELECT crl.bill_of_lading_proxy   
                          INTO v_bol_proxy
                          FROM preftz.conveyances_receipts_links crl
                          WHERE crl.conveyanceid  = v_conveyanceid
                          AND crl.bill_of_lading_proxy = crs.bill_of_lading_proxy
                          ;
                          
                          IF (v_bol_proxy IS NULL) THEN  --NOT found conveyances_receipts_links -> need  to create
                            INSERT INTO preftz.conveyances_receipts_links (bill_of_lading_proxy, conveyanceid, link_status)
                            VALUES (crs.bill_of_lading_proxy, v_conveyanceid, 'LINKED');
                          END IF;

                         UPDATE preftz.receipts fr --link receipt to the conveyanceid
                         SET 
                             zone_admission_no = v_zone_admission_no
                            ,conveyanceid      = v_conveyanceid
                         WHERE fr.receiptid  = crs.receiptid;

                       END IF; --IF  (v_conveyanceid IS NOT NULL) ...
                       
                  END LOOP;    
              
              /*
               * Unlink actual receipts when:
               * 1. e214_status is not AUTHORIZED;
               * 2. At least one pre-receipt exists for the admission; and
               * 3. At least one actual receipt exists for the admission.
               */
              WITH admissions_to_unlink AS
              (
                  SELECT DISTINCT
                      efs.zone_admission_no
                  FROM preftz.e214_filing_statuses efs
                  WHERE COALESCE(efs.e214_status, '') <> 'AUTHORIZED'
                    AND COALESCE(efs.zone_admission_no, '') <> ''
              
                    /*
                     * Pre-receipt exists.
                     */
                    AND EXISTS
                    (
                        SELECT 1
                        FROM preftz.receipts pr
                        WHERE pr.zone_admission_no =
                              efs.zone_admission_no
                          AND pr.pre_receipt IS TRUE
                    )
              
                    /*
                     * Actual receipt exists.
                     */
                    AND EXISTS
                    (
                        SELECT 1
                        FROM preftz.receipts ar
                        WHERE ar.zone_admission_no =
                              efs.zone_admission_no
                          AND ar.pre_receipt IS NOT TRUE
                    )
              )
              UPDATE preftz.receipts r
              SET
                  zone_admission_no = NULL,
                  conveyanceid      = NULL
              FROM admissions_to_unlink au
              WHERE r.zone_admission_no = au.zone_admission_no
                AND r.pre_receipt IS NOT TRUE;
              
              GET DIAGNOSTICS v_count = ROW_COUNT;
              
              INSERT INTO preftz.system_log
              (
                  procedure_name,
                  log_message,
                  details
              )
              VALUES
              (
                  'link_receipts_to_conveyances_by_inbond',
                  'Unlinked '
                      || v_count
                      || ' actual receipts for admissions where '
                      || 'e214_status is not AUTHORIZED and pre-receipts exist',
                  NOW()
              );                  
                 
            END IF;--IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N' 

    -- Log finish
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('link_receipts_to_conveyances_by_inbond' , 'finished', now());

END;
$procedure$;


--DROP PROCEDURE IF EXISTS preftz.assign_zone_admission();
CREATE OR REPLACE PROCEDURE preftz.assign_zone_admission (
)
LANGUAGE plpgsql
AS $procedure$

--Change Log:
-- EG 08/20/2026 adding a logic for DELETED status to avoid assigning a deleted admission number to a conveyance.
-- EG Original 4/7/2026 auto delete pre-receipts DEV-257

DECLARE
  crs              RECORD;
  v_current_admission_no  VARCHAR(10) DEFAULT NULL;
BEGIN
    -- Log start
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('assign_zone_admission', 'started', NOW());

    IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N' 
    THEN
        FOR crs IN 
        SELECT DISTINCT c.conveyanceid
        FROM preftz.conveyances c
        JOIN preftz.receipts r ON r.conveyanceid = c.conveyanceid
        WHERE COALESCE(c.zone_admission_no,'') = ''
              AND COALESCE(r.zone_admission_no,'') = ''
        LOOP

           --RAISE NOTICE '1 crs.conveyanceid % ', crs.conveyanceid;
           
           -- lock conveyance row
           PERFORM 1
           FROM preftz.conveyances
           WHERE conveyanceid = crs.conveyanceid
           FOR UPDATE SKIP LOCKED;
           
           IF NOT FOUND THEN --locked skipped
             CONTINUE;
           END IF;
        
           v_current_admission_no := NULL;
           
           SELECT zone_admission_no
           INTO v_current_admission_no
           FROM preftz.e214_filing_statuses efs
           WHERE NOT EXISTS (
               SELECT 1 FROM preftz.conveyances c 
               WHERE c.zone_admission_no = efs.zone_admission_no
           )
           AND NOT EXISTS (
               SELECT 1 FROM preftz.receipts r 
               WHERE r.zone_admission_no = efs.zone_admission_no
           )
           and efs.e214_status = ''                          --EG 08/20/2026 
           and efs.delete_status is distinct from 'DELETED'  --EG 08/20/2026 
           ORDER BY zone_admission_no
           FOR UPDATE SKIP LOCKED
           LIMIT 1;

     
           --RAISE NOTICE '2 v_current_admission_no % ', v_current_admission_no;
           
           IF (v_current_admission_no is NULL) 
           THEN
              v_current_admission_no := (select preftz.get_next_zone_admission_number());
              --RAISE NOTICE '2a v_current_admission_no % ', v_current_admission_no;
           END IF;
           
           -- lock the admission number so no one else can take it
--           PERFORM 1
           --FROM preftz.e214_filing_statuses
           --WHERE zone_admission_no = v_current_admission_no
           --FOR UPDATE;
           
           CALL preftz.assign_conveyances_to_214(crs.conveyanceid, v_current_admission_no);
           
           UPDATE preftz.e214_filing_statuses e
           SET 
              has_pre_receipts = 
              EXISTS(SELECT 1 FROM preftz.receipts r WHERE r.zone_admission_no = v_current_admission_no AND r.pre_receipt is TRUE)
           WHERE zone_admission_no = v_current_admission_no;
           
           
           INSERT INTO preftz.system_log(procedure_name, log_message, details)  
           VALUES ('assign_zone_admission', ' Assigned id: '|| crs.conveyanceid ||' adm no: '|| v_current_admission_no, now());

       END LOOP;
       
    END IF; -- (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N' 

    -- Log finish
    INSERT INTO preftz.system_log(procedure_name, log_message,details)
    VALUES ('assign_zone_admission' , 'finished', now());

EXCEPTION WHEN OTHERS THEN
    
    INSERT INTO preftz.system_log(procedure_name, log_message,details)
    VALUES ('assign_zone_admission', 'ERROR: ' || SQLERRM, now());
    RAISE;
END;
$procedure$;
--DROP PROCEDURE IF EXISTS preftz.process_fed_receipt_updates();

CREATE OR REPLACE PROCEDURE preftz.process_fed_receipt_updates()
LANGUAGE plpgsql
AS $procedure$

--Change Log:
-- EG 07/23/2026 working version

/*
The final order is:

Pre-receipts: AUDITING, UPDATE, and ERROR—always call.
Actual receipts: AUDITING and ERROR—always call.
Actual receipts: UPDATE—apply the exclusion logic.

logic for CALL of update_e214_after_create

*/

DECLARE
    crs_pre_receipt       RECORD;
    crs_receipt           RECORD;
    v_called_admissions   text[] DEFAULT ARRAY[]::text[];

    v_pre_call_count      integer DEFAULT 0;
    v_receipt_call_count  integer DEFAULT 0;
    v_skip_count          integer DEFAULT 0;
BEGIN
    /*
     * Log procedure start.
     */
    INSERT INTO preftz.system_log
    (
        procedure_name,
        log_message,
        details
    )
    VALUES
    (
        'process_fed_receipt_updates',
        'started',
        NOW()
    );

    /*
     * First loop:
     * Pre-receipts always call update_e214_after_create.
     */
    FOR crs_pre_receipt IN
    SELECT DISTINCT
        fr.zone_admission_no
    FROM preftz.fed_receipts fr
    INNER JOIN preftz.e214_filing_statuses efs
      ON efs.zone_admission_no = fr.zone_admission_no
    WHERE fr.fed_status IN
          (
              'AUDITING',
              'UPDATE',
              'ERROR'
          )
      AND fr.pre_receipt IS TRUE
      AND fr.zone_admission_no IS NOT NULL
      AND COALESCE(efs.concur_status, '')
          IN ('', 'REJECTED')
      AND COALESCE(efs.e214_status, '') <> ''
    ORDER BY
        fr.zone_admission_no
LOOP
    CALL preftz.update_e214_after_create(
        crs_pre_receipt.zone_admission_no
    );

    v_pre_call_count := v_pre_call_count + 1;

    INSERT INTO preftz.system_log
    (
        procedure_name,
        log_message,
        details
    )
    VALUES
    (
        'process_fed_receipt_updates',
        'Called update_e214_after_create for pre-receipt admission: '
            || crs_pre_receipt.zone_admission_no,
        NOW()
    );

    v_called_admissions :=
        array_append
        (
            v_called_admissions,
            crs_pre_receipt.zone_admission_no::text
        );
END LOOP;

    /*
 * Second loop:
 * Process AUDITING and ERROR actual receipts.
 *
 * These statuses always call update_e214_after_create,
 * unless the admission was already processed by the
 * pre-receipt loop.
 */
FOR crs_receipt IN
    SELECT DISTINCT
        fr.zone_admission_no
    FROM preftz.fed_receipts fr
    INNER JOIN preftz.e214_filing_statuses efs
      ON efs.zone_admission_no = fr.zone_admission_no
    WHERE fr.fed_status IN ('AUDITING', 'ERROR')
      AND fr.pre_receipt IS NOT TRUE
      AND fr.zone_admission_no IS NOT NULL
      AND COALESCE(efs.concur_status, '')
          IN ('', 'REJECTED')
      AND COALESCE(efs.e214_status, '') <> ''
    ORDER BY
        fr.zone_admission_no
LOOP
    /*
     * Do not call again if already processed by
     * the pre-receipt loop.
     */
    IF crs_receipt.zone_admission_no::text =
       ANY(v_called_admissions)
    THEN
        v_skip_count := v_skip_count + 1;

        INSERT INTO preftz.system_log
        (
            procedure_name,
            log_message,
            details
        )
        VALUES
        (
            'process_fed_receipt_updates',
            'Skipped AUDITING/ERROR actual-receipt admission '
            || 'because it was already processed: '
            || crs_receipt.zone_admission_no,
            NOW()
        );

        CONTINUE;
    END IF;

    /*
     * AUDITING and ERROR always call the procedure.
     */
    CALL preftz.update_e214_after_create(
        crs_receipt.zone_admission_no
    );

    v_receipt_call_count := v_receipt_call_count + 1;

    INSERT INTO preftz.system_log
    (
        procedure_name,
        log_message,
        details
    )
    VALUES
    (
        'process_fed_receipt_updates',
        'Called update_e214_after_create for '
        || 'AUDITING/ERROR actual-receipt admission: '
        || crs_receipt.zone_admission_no,
        NOW()
    );

    v_called_admissions :=
        array_append
        (
            v_called_admissions,
            crs_receipt.zone_admission_no::text
        );
END LOOP;


/*
 * Third loop:
 * Process UPDATE actual receipts.
 *
 * The authorized/pre-receipt exclusion is applied only here.
 */
FOR crs_receipt IN
    SELECT DISTINCT
        fr.zone_admission_no
    FROM preftz.fed_receipts fr
    INNER JOIN preftz.e214_filing_statuses efs
      ON efs.zone_admission_no = fr.zone_admission_no
    WHERE fr.fed_status = 'UPDATE'
      AND fr.pre_receipt IS NOT TRUE
      AND fr.zone_admission_no IS NOT NULL
      AND COALESCE(efs.concur_status, '')
          IN ('', 'REJECTED')
      AND COALESCE(efs.e214_status, '') <> ''
    ORDER BY
        fr.zone_admission_no
LOOP
    /*
     * The admission was already processed by either:
     * - the pre-receipt loop; or
     * - the AUDITING/ERROR loop.
     */
    IF crs_receipt.zone_admission_no::text =
       ANY(v_called_admissions)
    THEN
        v_skip_count := v_skip_count + 1;

        INSERT INTO preftz.system_log
        (
            procedure_name,
            log_message,
            details
        )
        VALUES
        (
            'process_fed_receipt_updates',
            'Skipped UPDATE actual-receipt admission because '
            || 'it was already processed: '
            || crs_receipt.zone_admission_no,
            NOW()
        );

        CONTINUE;
    END IF;

    /*
     * Skip UPDATE when:
     *
     * 1. A pre-receipt exists in preftz.receipts; and
     * 2. e214_status is AUTHORIZED.
     */
    IF EXISTS
    (
        SELECT 1
        FROM preftz.receipts r
        WHERE r.zone_admission_no =
              crs_receipt.zone_admission_no
          AND r.pre_receipt IS TRUE
    )
    AND EXISTS
    (
        SELECT 1
        FROM preftz.e214_filing_statuses efs
        WHERE efs.zone_admission_no =
              crs_receipt.zone_admission_no
          AND efs.e214_status = 'AUTHORIZED'
    )
    THEN
        v_skip_count := v_skip_count + 1;

        INSERT INTO preftz.system_log
        (
            procedure_name,
            log_message,
            details
        )
        VALUES
        (
            'process_fed_receipt_updates',
            'Skipped UPDATE actual-receipt admission because a '
            || 'pre-receipt exists and e214 status is AUTHORIZED: '
            || crs_receipt.zone_admission_no,
            NOW()
        );

        CONTINUE;
    END IF;

    CALL preftz.update_e214_after_create(
        crs_receipt.zone_admission_no
    );

    v_receipt_call_count := v_receipt_call_count + 1;

    INSERT INTO preftz.system_log
    (
        procedure_name,
        log_message,
        details
    )
    VALUES
    (
        'process_fed_receipt_updates',
        'Called update_e214_after_create for '
        || 'UPDATE actual-receipt admission: '
        || crs_receipt.zone_admission_no,
        NOW()
    );

    v_called_admissions :=
        array_append
        (
            v_called_admissions,
            crs_receipt.zone_admission_no::text
        );
END LOOP;

    /*
     * Log procedure completion and summary.
     */
    INSERT INTO preftz.system_log
    (
        procedure_name,
        log_message,
        details
    )
    VALUES
    (
        'process_fed_receipt_updates',
        'finished; pre-receipt calls: '
            || v_pre_call_count
            || '; actual-receipt calls: '
            || v_receipt_call_count
            || '; skipped admissions: '
            || v_skip_count,
        NOW()
    );
END;
$procedure$;--DROP PROCEDURE IF EXISTS preftz.process_auto_concur();

CREATE OR REPLACE PROCEDURE preftz.process_auto_concur()
LANGUAGE plpgsql
AS $procedure$

--Change Log:
--EG Original 8/5/2026 process automatic linking and concurrence

DECLARE
    v_auto_concur_setting text;
BEGIN
    /*
     * Log start.
     */
    INSERT INTO preftz.system_log
    (
        procedure_name,
        log_message,
        details
    )
    VALUES
    (
        'process_auto_concur',
        'started',
        NOW()
    );

    v_auto_concur_setting :=
        COALESCE(
            preftz.get_ftz_setting('AUTO CONCUR'),
            'NO'
        );

    IF v_auto_concur_setting = 'AUTO_LINK_CONCUR' THEN
        INSERT INTO preftz.system_log
        (
            procedure_name,
            log_message,
            details
        )
        VALUES
        (
            'process_auto_concur',
            'AUTO CONCUR setting is AUTO_LINK_CONCUR; processing started',
            NOW()
        );

        --CALL preftz.link_receipts_to_conveyances_by_inbond();

        --CALL preftz.assign_zone_admission();

        CALL preftz.pre_receipts_filing();

    ELSE
        INSERT INTO preftz.system_log
        (
            procedure_name,
            log_message,
            details
        )
        VALUES
        (
            'process_auto_concur',
            'Processing skipped; AUTO CONCUR setting is: '
                || v_auto_concur_setting,
            NOW()
        );
    END IF;

    /*
     * Log finish.
     */
    INSERT INTO preftz.system_log
    (
        procedure_name,
        log_message,
        details
    )
    VALUES
    (
        'process_auto_concur',
        'finished',
        NOW()
    );
END;
$procedure$;--DROP FUNCTION IF EXISTS preftz.check_pre_receipts_1(integer);

CREATE OR REPLACE FUNCTION preftz.check_pre_receipts_1(
    p_receiptid integer
)
RETURNS text
LANGUAGE plpgsql
AS $function$

--Change Log:
-- EG 07/29/2026 working version

DECLARE
    v_zone_admission_no varchar;
    v_part_number       varchar;
    v_fail_count        integer;
    v_pre_count         integer;
BEGIN

/*
One-to-one match → FAIL
Invalid receipt/admission/part → FAIL
No unmatched pre-receipts → FAIL
Different COO, unit price, or privileged dates → FAIL
Missing actual group or different quantity totals → FAIL
All checks pass → returns part_number
*/

   -- Exclude if one-to one match exists for this pre-receipt
    if preftz.get_receiptid_from_prereceiptid(p_receiptid) is NOT NULL
    THEN
        RETURN 'FAIL';
    END IF;

    /*
     * Get admission and part from provided receiptid.
     * p_receiptid can be either a pre-receipt or actual receipt.
     */
    SELECT
        r.zone_admission_no,
        r.part_number
    INTO
        v_zone_admission_no,
        v_part_number
    FROM preftz.receipts r
    WHERE r.receiptid = p_receiptid;

    IF v_zone_admission_no IS NULL
       OR v_part_number IS NULL
    THEN
        RETURN 'FAIL';
    END IF;

    /*
     * Make sure there are pre-receipts for this admission and part.
     */
     SELECT COUNT(*)
     INTO v_pre_count
     FROM preftz.receipts r
     WHERE r.zone_admission_no = v_zone_admission_no
       AND r.part_number = v_part_number
       AND r.pre_receipt IS TRUE
       AND preftz.get_receiptid_from_prereceiptid(r.receiptid) IS NULL;
     
     IF v_pre_count = 0 THEN
         RETURN 'FAIL';
     END IF;

    /*
     * First check:
     * For this admission and part_number only,
     * all pre-receipts must have the same:
     * country_of_origin, unit_price, privileged_date.
     *
     * NULL logic:
     * NULL is treated as its own value.
     */
    SELECT COUNT(*)
    INTO v_fail_count
    FROM (
        SELECT
            r.zone_admission_no,
            r.part_number
        FROM preftz.receipts r
        WHERE r.zone_admission_no = v_zone_admission_no
          AND r.part_number = v_part_number
          AND r.pre_receipt IS TRUE
          AND preftz.get_receiptid_from_prereceiptid(r.receiptid) is NULL
        GROUP BY
            r.zone_admission_no,
            r.part_number
        HAVING COUNT(DISTINCT COALESCE(r.country_of_origin::text, '<NULL>')) > 1
            OR COUNT(DISTINCT COALESCE(r.unit_price::text, '<NULL>')) > 1
            OR COUNT(DISTINCT COALESCE(r.privileged_date::text, '<NULL>')) > 1
    ) x;

    IF v_fail_count > 0 THEN
        RETURN 'FAIL';
    END IF;

    /*
     * Second check:
     * For this admission and part_number only, compare:
     *
     * SUM(pre_receipt.quantity) = SUM(actual_receipt.quantity)
     *
     * Do not compare country_of_origin, unit_price, or privileged_date here.
     */
    WITH pre_receipts AS (
        SELECT
            r.zone_admission_no,
            r.part_number,
            SUM(r.quantity) AS pre_receipt_quantity
        FROM preftz.receipts r
        WHERE r.zone_admission_no = v_zone_admission_no
          AND r.part_number = v_part_number
          AND r.pre_receipt IS TRUE
          AND preftz.get_receiptid_from_prereceiptid(r.receiptid) is NULL
        GROUP BY
            r.zone_admission_no,
            r.part_number
    ),
    actual_receipts AS (
        SELECT
            r.zone_admission_no,
            r.part_number,
            SUM(r.quantity) AS actual_receipt_quantity
        FROM preftz.receipts r
        WHERE r.zone_admission_no = v_zone_admission_no
          AND r.part_number = v_part_number
          AND r.pre_receipt IS NOT TRUE
          AND preftz.get_receiptid_from_prereceiptid(r.receiptid) is NULL
        GROUP BY
            r.zone_admission_no,
            r.part_number
    )
    SELECT COUNT(*)
    INTO v_fail_count
    FROM pre_receipts pr
    FULL JOIN actual_receipts ar
      ON ar.zone_admission_no = pr.zone_admission_no
     AND ar.part_number = pr.part_number
    WHERE pr.zone_admission_no IS NULL
       OR ar.zone_admission_no IS NULL
       OR pr.pre_receipt_quantity IS DISTINCT FROM ar.actual_receipt_quantity;

    IF v_fail_count > 0 THEN
        RETURN 'FAIL';
    END IF;

    RETURN v_part_number;

END;
$function$; --DROP FUNCTION IF EXISTS preftz.compare_fed_receipt(integer);

CREATE OR REPLACE FUNCTION preftz.compare_fed_receipt(
    p_receiptid integer
)
RETURNS varchar
LANGUAGE plpgsql
STABLE
AS $function$

--Change Log: 	
-- EG 08/20/2026 blocked conveyance comparison 
-- EG 07/16/2026 Compare fed_receipts columns with all other tables to know if anything chaged during front end UPDATE 


DECLARE
    v_receipt_result             varchar(20) DEFAULT 'FAIL';
    v_conveyance_result          varchar(20) DEFAULT 'FAIL';
    v_cast_smelt_result          varchar(20) DEFAULT 'FAIL';
    v_melt_pour_result           varchar(20) DEFAULT 'FAIL';
    v_derivative_content_result  varchar(20) DEFAULT 'FAIL';
    v_percentage_value_result    varchar(20) DEFAULT 'FAIL';
    v_case_number_result         varchar(20) DEFAULT 'FAIL';
    v_import_license_result      varchar(20) DEFAULT 'FAIL';
    v_user_reference_result      varchar(20) DEFAULT 'FAIL';

    v_result                     varchar(10);
BEGIN
    /*
     * Required comparison:
     * fed_receipts to receipts.
     */
    SELECT
        CASE
            WHEN EXISTS
            (
                SELECT 1
                FROM preftz.fed_receipts fr
                JOIN preftz.receipts r
                  ON r.receiptid = fr.receiptid
                WHERE fr.receiptid = p_receiptid

                  AND COALESCE(fr.part_number, '') =
                      COALESCE(r.part_number, '')

                  AND COALESCE(fr.receipt_date::text, '') =
                      COALESCE(r.receipt_date::text, '')

                  AND COALESCE(fr.quantity::text, '') =
                      COALESCE(r.quantity::text, '')

                  AND COALESCE(fr.unit_price::text, '') =
                      COALESCE(r.unit_price::text, '')

                  AND COALESCE(fr.manufacturer_mid_code, '') =
                      COALESCE(r.manufacturer_mid_code, '')

                  AND COALESCE(fr.country_of_origin::text, '') =
                      COALESCE(r.country_of_origin::text, '')

                  AND COALESCE(fr.bill_of_lading_proxy, '') =
                      COALESCE(r.bill_of_lading_proxy, '')

                  AND COALESCE(fr.commercial_invoice_number, '') =
                      COALESCE(r.commercial_invoice_number, '')

                  AND COALESCE(fr.transaction_reference, '') =
                      COALESCE(r.transaction_reference, '')

                  AND COALESCE(fr.zone_admission_no, '') =
                      COALESCE(r.zone_admission_no, '')

                  AND COALESCE(fr.zone_status, '') =
                      COALESCE(r.zone_status, '')

                  AND COALESCE(fr.foreign_unit_price::text, '') =
                      COALESCE(r.foreign_unit_price::text, '')

                  AND COALESCE(fr.currency_code, '') =
                      COALESCE(r.currency_code, '')

                  AND COALESCE(fr.currency_exchange_rate::text, '') =
                      COALESCE(r.currency_exchange_rate::text, '')

                  AND COALESCE(fr.conveyanceid::text, '') =
                      COALESCE(r.conveyanceid::text, '')

                  AND COALESCE(fr.country_of_export::text, '') =
                      COALESCE(r.country_of_export::text, '')

                  --AND COALESCE(fr.zone_to_zone_transfer::text, '') =
                  --    COALESCE(r.zone_to_zone_transfer::text, '')

                  AND COALESCE(fr.inbond_number, '') =
                      COALESCE(r.inbond_number, '')

                  AND COALESCE(fr.pre_receipt::text, '') =
                      COALESCE(r.pre_receipt::text, '')

                  AND COALESCE(fr.unit_assist::text, '') =
                      COALESCE(r.unit_assist::text, '')

                  AND COALESCE(fr.container, '') =
                      COALESCE(r.container, '')
            )
            THEN 'PASS_MATCH'
            ELSE 'FAIL'
        END
    INTO v_receipt_result;

    /*
     * fed_receipts to conveyances.
     */
    SELECT
        CASE
            WHEN c.conveyanceid IS NULL THEN
                CASE
                    WHEN fr.conveyanceid IS NULL

                     AND COALESCE(
                             BTRIM(fr.bill_of_lading_airwaybill),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.house_bill),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.house_bill_partial_indicator),
                             ''
                         ) = ''

                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.bill_of_lading_airwaybill, '') =
                    COALESCE(c.bill_of_lading_airwaybill, '')

                AND COALESCE(fr.house_bill, '') =
                    COALESCE(c.house_bill, '')

                AND COALESCE(fr.house_bill_partial_indicator, '') =
                    COALESCE(c.house_bill_partial_indicator, '')

            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_conveyance_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.conveyances c
      ON c.conveyanceid = fr.conveyanceid
    WHERE fr.receiptid = p_receiptid;

    v_conveyance_result :=
        COALESCE(v_conveyance_result, 'FAIL');

    /*
     * fed_receipts to receipt_cast_and_smelt.
     */
    SELECT
        CASE
            WHEN rcs.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             BTRIM(fr.country_of_cast),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.primary_country_of_smelt),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.secondary_country_of_smelt),
                             ''
                         ) = ''
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.country_of_cast, '') =
                    COALESCE(rcs.country_of_cast, '')

                AND COALESCE(fr.primary_country_of_smelt, '') =
                    COALESCE(rcs.primary_country_of_smelt, '')

                AND COALESCE(fr.secondary_country_of_smelt, '') =
                    COALESCE(rcs.secondary_country_of_smelt, '')
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_cast_smelt_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.receipt_cast_and_smelt rcs
      ON rcs.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_cast_smelt_result :=
        COALESCE(v_cast_smelt_result, 'FAIL');

    /*
     * fed_receipts to receipt_melt_and_pour.
     */
    SELECT
        CASE
            WHEN rmp.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             BTRIM(fr.country_of_melt),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.country_of_pour),
                             ''
                         ) = ''
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.country_of_melt, '') =
                    COALESCE(rmp.country_of_melt, '')

                AND COALESCE(fr.country_of_pour, '') =
                    COALESCE(rmp.country_of_pour, '')
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_melt_pour_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.receipt_melt_and_pour rmp
      ON rmp.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_melt_pour_result :=
        COALESCE(v_melt_pour_result, 'FAIL');

    /*
     * fed_receipts to receipt_derivative_content.
     */
    SELECT
        CASE
            WHEN rdc.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             fr.steel_content_weight,
                             0::double precision
                         ) = 0::double precision

                     AND COALESCE(
                             fr.aluminum_content_weight,
                             0::double precision
                         ) = 0::double precision

                     AND COALESCE(
                             fr.copper_content_weight,
                             0::double precision
                         ) = 0::double precision
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(
                        fr.steel_content_weight,
                        0::double precision
                    ) =
                    COALESCE(
                        rdc.steel_content_weight,
                        0::double precision
                    )

                AND COALESCE(
                        fr.aluminum_content_weight,
                        0::double precision
                    ) =
                    COALESCE(
                        rdc.aluminum_content_weight,
                        0::double precision
                    )

                AND COALESCE(
                        fr.copper_content_weight,
                        0::double precision
                    ) =
                    COALESCE(
                        rdc.copper_content_weight,
                        0::double precision
                    )
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_derivative_content_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.receipt_derivative_content rdc
      ON rdc.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_derivative_content_result :=
        COALESCE(v_derivative_content_result, 'FAIL');

    /*
     * fed_receipts to receipt_percentage_value.
     */
    SELECT
        CASE
            WHEN rpv.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             fr.usmca_percent_us_value,
                             0::double precision
                         ) = 0::double precision
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                COALESCE(
                    fr.usmca_percent_us_value,
                    0::double precision
                ) =
                COALESCE(
                    rpv.percent_us_value,
                    0::double precision
                )
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_percentage_value_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.receipt_percentage_value rpv
      ON rpv.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_percentage_value_result :=
        COALESCE(v_percentage_value_result, 'FAIL');

    /*
     * fed_receipts to receipt_case_numbers.
     */
    SELECT
        CASE
            WHEN rcn.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             BTRIM(fr.antidumping_case_number),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.countervailing_case_number),
                             ''
                         ) = ''
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.antidumping_case_number, '') =
                    COALESCE(rcn.antidumping_case_number, '')

                AND COALESCE(fr.countervailing_case_number, '') =
                    COALESCE(rcn.countervailing_case_number, '')
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_case_number_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.receipt_case_numbers rcn
      ON rcn.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_case_number_result :=
        COALESCE(v_case_number_result, 'FAIL');

    /*
     * fed_receipts to import_licenses.
     */
    SELECT
        CASE
            WHEN il.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             BTRIM(fr.import_license_type),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.import_license_number),
                             ''
                         ) = ''
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.import_license_type, '') =
                    COALESCE(il.import_license_type, '')

                AND COALESCE(fr.import_license_number, '') =
                    COALESCE(il.import_license_number, '')
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_import_license_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.import_licenses il
      ON il.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_import_license_result :=
        COALESCE(v_import_license_result, 'FAIL');

    /*
     * fed_receipts to user_references.
     */
    SELECT
        CASE
            WHEN ur.tableid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             BTRIM(fr.user_reference1),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.user_reference2),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.user_reference3),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.user_reference4),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.user_reference5),
                             ''
                         ) = ''
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.user_reference1, '') =
                    COALESCE(ur.user_reference1, '')

                AND COALESCE(fr.user_reference2, '') =
                    COALESCE(ur.user_reference2, '')

                AND COALESCE(fr.user_reference3, '') =
                    COALESCE(ur.user_reference3, '')

                AND COALESCE(fr.user_reference4, '') =
                    COALESCE(ur.user_reference4, '')

                AND COALESCE(fr.user_reference5, '') =
                    COALESCE(ur.user_reference5, '')
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_user_reference_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.user_references ur
      ON ur.tableid = fr.receiptid
     AND ur.table_name = 'receipts'
    WHERE fr.receiptid = p_receiptid;

    v_user_reference_result :=
        COALESCE(v_user_reference_result, 'FAIL');

    /*
     * Optional tables pass when their status is either:
     *   PASS_MATCH
     *   PASS_NOT_FOUND
     */
    IF v_receipt_result = 'PASS_MATCH'

    --    AND v_conveyance_result IN (
    --        'PASS_MATCH',
    --        'PASS_NOT_FOUND'
    --    )

       AND v_cast_smelt_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_melt_pour_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_derivative_content_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_percentage_value_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_case_number_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_import_license_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_user_reference_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )
    THEN
        v_result := 'PASS';
    ELSE
        v_result := 'FAIL';
    END IF;

    RAISE NOTICE
        E'compare_fed_receipt receiptid: %\n'
        '  receipt_result:            %\n'
        '  conveyance_result:         %\n'
        '  cast_smelt_result:         %\n'
        '  melt_pour_result:          %\n'
        '  derivative_content_result: %\n'
        '  percentage_value_result:   %\n'
        '  case_number_result:        %\n'
        '  import_license_result:     %\n'
        '  user_reference_result:     %\n'
        '  final_result:              %',
        p_receiptid,
        v_receipt_result,
        v_conveyance_result,
        v_cast_smelt_result,
        v_melt_pour_result,
        v_derivative_content_result,
        v_percentage_value_result,
        v_case_number_result,
        v_import_license_result,
        v_user_reference_result,
        v_result;

    RETURN v_result;
END;

$function$;
CREATE OR REPLACE PROCEDURE preftz.process_receipt_updates()
LANGUAGE 'plpgsql'
AS $$

--Change Log:
-- EG 08/23/2026 do not call update_e214_after_create if AUTO CONCUR is set to AUTO_LINK_CONCUR and pre-receipts exists
-- KK 04/06/2026 CSMS # 68253075 - GUIDANCE: Section 232 Duties on Imports of Aluminum, Steel, and Copper
--NKM 09/18/2023 Use set privileged_date = current_date when changing from N, otherwise use receipt_date
--NKM 04/21/2023 Added aluminum cast & smelt fields
--RTJ 01/20/2023 added unit assist 
--NKM 12/16/2022 Added handling of update to part_number on inventory_items
--NKM 10/03/2022 Added use of update_e214_after_create
--NKM 07/12/2022 Added roundoff error protections using v_tol
--NKM 03/18/2022 Restricted query that strips conveyanceid and admission_no from domestic receipts to updated receipts
--NKM 02/02/2022 Added import_licenses table
--NKM 09/14/2021 Recognizes a null admission number as a change
--RTJ 07/15/2021 Remove receipt from 214 if status is changed to domestic
--NKM 06/24/2021 Added inbond_number to receipts feed
--RTJ 05/16/2021 Reset e214 status if previously created
--RTJ 05/06/2021 Add part_number to updated fields
--               Remove handling of adjusts from this receipt now that all adjusts have their own receipt records
--               Update handling of quantities to accommodate partially depleted receipts

--RTJ 03/30/2021 Include handling for case numbers
--RTJ 11/13/2020 Created for handling updates to receipts

DECLARE
  v_tol               DOUBLE PRECISION DEFAULT preftz.get_ftz_setting('ROUNDOFF TOLERANCE'); --NKM 07/12/2022
  rrs                 RECORD; --NKM 10/03/2022
    
BEGIN
    INSERT INTO preftz.system_log (procedure_name,log_message) 
        VALUES ('process_receipt_updates','started');
        
-- EG 08/23/2026 begining
  --normal process
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'NO') 
    THEN  	        

        --flag 214s as having been updated
        --NKM 10/03/2022 changed to loop over reset_e214_filing_status
        FOR rrs IN SELECT fr.zone_admission_no --NKM 10/03/2022
                     FROM preftz.fed_receipts fr
                    WHERE fr.fed_status = 'UPDATE'
                    UNION
                   SELECT r.zone_admission_no
                     FROM preftz.receipts r
                     JOIN preftz.fed_receipts fr on fr.receiptid = r.receiptid
                    WHERE fr.fed_status = 'UPDATE'
        LOOP
            CALL preftz.update_e214_after_create(rrs.zone_admission_no); --NKM 10/03/2022
        END LOOP;

    END IF;


    -- ignore edited receipts and do not call update_e214_after_create 
    -- if pre-receit was AUTHORIZED and AUTO CONCUR is set to AUTO_LINK_CONCUR
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK_CONCUR')  	
    THEN  

        FOR rrs IN SELECT fr.zone_admission_no 
                     FROM preftz.fed_receipts fr
                    WHERE fr.fed_status = 'UPDATE'
                    AND fr.pre_receipt IS TRUE 
                    UNION
                   SELECT r.zone_admission_no
                     FROM preftz.receipts r
                     JOIN preftz.fed_receipts fr on fr.receiptid = r.receiptid
                    WHERE fr.fed_status = 'UPDATE'
                    AND fr.pre_receipt IS TRUE 
        LOOP
            CALL preftz.update_e214_after_create(rrs.zone_admission_no); 
        END LOOP;

        FOR rrs IN SELECT fr.zone_admission_no 
                     FROM preftz.fed_receipts fr
                    WHERE fr.fed_status = 'UPDATE'
                    AND fr.pre_receipt IS NOT TRUE 
                    /*    Pre-receipt does not exist.  */
                    AND NOT EXISTS
                    (
                        SELECT 1
                        FROM preftz.receipts pr
                        WHERE pr.zone_admission_no =
                              fr.zone_admission_no
                          AND pr.pre_receipt IS TRUE
                    )
                    UNION
                   SELECT r.zone_admission_no
                     FROM preftz.receipts r
                     JOIN preftz.fed_receipts fr on fr.receiptid = r.receiptid
                    WHERE fr.fed_status = 'UPDATE'
                    AND fr.pre_receipt IS NOT TRUE 
                    /*    Pre-receipt does not exist.  */
                    AND NOT EXISTS
                    (
                        SELECT 1
                        FROM preftz.receipts pr
                        WHERE pr.zone_admission_no =
                              r.zone_admission_no
                          AND pr.pre_receipt IS TRUE
                    )

        LOOP
            CALL preftz.update_e214_after_create(rrs.zone_admission_no); 
        END LOOP;

    END IF;	

-- EG 08/23/2026 end



    --RTJ 07/15/2021 
    --update 214 number and conveyance link if status was changed to domestic
    UPDATE preftz.fed_receipts fr
       SET zone_admission_no = NULL,
           conveyanceid = NULL 
     WHERE fr.fed_status = 'UPDATE' --NKM 03/18/2022 (also added unrestricted update to audit_fed_receipts)
       AND fr.zone_status = 'D';
    --RTJ 07/15/2021 
    
    --update receipts data
    UPDATE preftz.receipts r
       SET part_number = fr.part_number,
           receipt_date = fr.receipt_date,
           quantity = fr.quantity,
           unit_price = fr.unit_price,
           manufacturer_mid_code = fr.manufacturer_mid_code,
           country_of_origin = fr.country_of_origin,
           bill_of_lading_proxy = fr.bill_of_lading_proxy,
           commercial_invoice_number = fr.commercial_invoice_number,
           transaction_reference = fr.transaction_reference,
           zone_admission_no = fr.zone_admission_no,
           zone_status = fr.zone_status,
           foreign_unit_price = fr.foreign_unit_price,
           currency_code = fr.currency_code,
           currency_exchange_rate = fr.currency_exchange_rate,
           privileged_date = CASE WHEN fr.zone_status = 'P' AND r.zone_status = 'N' THEN current_date  --NKM 09/18/2023
                                  WHEN fr.zone_status = 'P' AND r.zone_status <> 'N' THEN r.privileged_date
                                  ELSE NULL END,
           conveyanceid = fr.conveyanceid,
           inbond_number = fr.inbond_number,  -- NKM 06/24/2021
           unit_assist = fr.unit_assist  --RTJ 01/20/2023
      FROM preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND r.receiptid = fr.receiptid;
       
    --RTJ 03/30/2021 update receipt_case_numbers data
    UPDATE preftz.receipt_case_numbers rcn
       SET antidumping_case_number = fr.antidumping_case_number,
           countervailing_case_number = fr.countervailing_case_number
      FROM preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND rcn.receiptid = fr.receiptid
       AND (   COALESCE(fr.antidumping_case_number,'') <> ''
            OR COALESCE(fr.countervailing_case_number,'') <> '');
       
    DELETE FROM preftz.receipt_case_numbers rcn
     USING preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND rcn.receiptid = fr.receiptid
       AND COALESCE(fr.antidumping_case_number,'') = ''
       AND COALESCE(fr.countervailing_case_number,'') = '';
       
    INSERT INTO preftz.receipt_case_numbers
          (receiptid, antidumping_case_number, countervailing_case_number)
    SELECT fr.receiptid, fr.antidumping_case_number, fr.countervailing_case_number
      FROM preftz.fed_receipts fr
           LEFT JOIN preftz.receipt_case_numbers rcn
                  ON fr.receiptid = rcn.receiptid
     WHERE fr.fed_status = 'UPDATE'
       AND rcn.receiptid IS NULL
       AND (   COALESCE(fr.antidumping_case_number,'') <> ''
            OR COALESCE(fr.countervailing_case_number,'') <> '');
    --RTJ 03/30/2021


    --NKM 02/02/2022 added import_licenses table
    UPDATE preftz.import_licenses il                      --update record if it already exists
       SET import_license_type = fr.import_license_type,
           import_license_number = fr.import_license_number
      FROM preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND il.receiptid = fr.receiptid
       AND fr.import_license_number IS NOT NULL;
       
    DELETE FROM preftz.import_licenses il                 --delete record if it is not needed
     USING preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND il.receiptid = fr.receiptid
       AND fr.import_license_number IS NULL;

    INSERT INTO preftz.import_licenses                    --add record if it does not exist
          (receiptid, import_license_type, import_license_number)
    SELECT fr.receiptid, fr.import_license_type, fr.import_license_number
      FROM preftz.fed_receipts fr
           LEFT JOIN preftz.import_licenses il
                  ON fr.receiptid = il.receiptid
     WHERE fr.fed_status = 'UPDATE'
       AND il.receiptid IS NULL
       AND fr.import_license_number IS NOT NULL;
    --NKM 02/02/2022

    --NKM 04/21/2023 added aluminum cast & smelt
    UPDATE preftz.receipt_cast_and_smelt rcs             --update record if it already exists
       SET country_of_cast = fr.country_of_cast,
           primary_country_of_smelt = fr.primary_country_of_smelt,
           secondary_country_of_smelt = fr.secondary_country_of_smelt
      FROM preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND rcs.receiptid = fr.receiptid
       AND fr.country_of_cast IS NOT NULL;
       
    DELETE FROM preftz.receipt_cast_and_smelt rcs        --delete record if it is not needed
     USING preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND rcs.receiptid = fr.receiptid
       AND fr.country_of_cast IS NULL;

    INSERT INTO preftz.receipt_cast_and_smelt            --add record if it does not exist
          (receiptid, country_of_cast, primary_country_of_smelt, secondary_country_of_smelt)
    SELECT fr.receiptid, fr.country_of_cast, fr.primary_country_of_smelt, fr.secondary_country_of_smelt
      FROM preftz.fed_receipts fr
           LEFT JOIN preftz.receipt_cast_and_smelt rcs
                  ON fr.receiptid = rcs.receiptid
     WHERE fr.fed_status = 'UPDATE'
       AND rcs.receiptid IS NULL
       AND fr.country_of_cast IS NOT NULL;
    --NKM 04/21/2023

    -- KK 04/06/2026 if we have weight values then update, otherwise do not
    FOR rrs IN
        SELECT fr.receiptid, COALESCE(fr.steel_content_weight,0.0) as steel_content_weight, 
            COALESCE(fr.aluminum_content_weight,0.0) as aluminum_content_weight, 
            COALESCE(fr.copper_content_weight,0.0) as copper_content_weight,
            COALESCE(p.unit_net_weight,0.0) as unit_net_weight
        FROM preftz.fed_receipts fr
        JOIN preftz.parts p ON p.part_number = fr.part_number
        WHERE fr.fed_status = 'UPDATE'
            AND (fr.steel_content_weight IS NOT NULL 
                OR fr.aluminum_content_weight IS NOT NULL
                OR fr.copper_content_weight IS NOT NULL)
    LOOP
        DELETE FROM preftz.receipt_derivative_content rdc WHERE rdc.receiptid = rrs.receiptid;
        --update records to receipt_derivative_content table
        INSERT INTO preftz.receipt_derivative_content
            (receiptid, steel_content_weight, aluminum_content_weight, copper_content_weight, unit_net_weight)
        VALUES
            (rrs.receiptid, rrs.steel_content_weight, rrs.aluminum_content_weight, rrs.copper_content_weight, rrs.unit_net_weight);
    END LOOP;
       
    --update user_references data
    UPDATE preftz.user_references ur
       SET user_reference1 = fr.user_reference1,
           user_reference2 = fr.user_reference2,
           user_reference3 = fr.user_reference3,
           user_reference4 = fr.user_reference4,
           user_reference5 = fr.user_reference5
      FROM preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND ur.tableid = fr.receiptid
       AND ur.table_name = 'receipts'
       AND COALESCE(fr.user_reference1, fr.user_reference2, fr.user_reference3,
                    fr.user_reference4, fr.user_reference5, '') <> '';
                    
    DELETE FROM preftz.user_references ur
     USING preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND ur.tableid = fr.receiptid
       AND ur.table_name = 'receipts'
       AND COALESCE(fr.user_reference1, fr.user_reference2, fr.user_reference3,
                    fr.user_reference4, fr.user_reference5, '') = '';
                    
    INSERT INTO preftz.user_references
               (table_name, tableid, user_reference1, user_reference2, user_reference3,
                user_reference4, user_reference5)
         SELECT 'receipts', fr.receiptid, fr.user_reference1, fr.user_reference2,
                fr.user_reference3, fr.user_reference4, fr.user_reference5
           FROM preftz.fed_receipts fr
                LEFT JOIN preftz.user_references ur
                       ON ur.tableid = fr.receiptid
                      AND ur.table_name = 'receipts'
          WHERE fr.fed_status = 'UPDATE'
            AND ur.tableid IS NULL 
            AND COALESCE(fr.user_reference1, fr.user_reference2, fr.user_reference3,
                         fr.user_reference4, fr.user_reference5, '') <> '';
       
    --remove current receipt_classifications data
    --data will be refreshed when 214 is (re)created
    DELETE FROM preftz.receipt_classifications rc
     USING preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND fr.receiptid = rc.receiptid;
    
    --update inventory_items receipt_date
    UPDATE preftz.inventory_items ii
       SET receipt_date = fr.receipt_date
      FROM preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND fr.receiptid = ii.receiptid
       --AND COALESCE(ii.adjustid,0) = 0  --RTJ 05/06/2021
       AND fr.receipt_date <> ii.receipt_date;
       
    --update inventory_items quantities 
    UPDATE preftz.inventory_items ii
       SET quantity_received = fr.quantity,
           quantity_on_hand = preftz.roundto(preftz.rounddiff(ii.quantity_on_hand + fr.quantity, ii.quantity_received, v_tol), fr.quantity, v_tol)  --RTJ 05/06/2021 --NKM 07/12/2022
      FROM preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND fr.receiptid = ii.receiptid
       --AND COALESCE(ii.adjustid,0) = 0  --RTJ 05/06/2021
       AND NOT preftz.isequal(fr.quantity, ii.quantity_received, v_tol); --NKM 07/12/2022
       
    --RTJ 05/06/2021 handle inventory_items zone_status change
    UPDATE preftz.inventory_items ii
       SET zone_status = fr.zone_status
      FROM preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND fr.receiptid = ii.receiptid
       AND fr.zone_status <> ii.zone_status;
       
    --NKM 12/06/2022 handle inventory_items part_number change
    UPDATE preftz.inventory_items ii
       SET part_number = fr.part_number
      FROM preftz.fed_receipts fr
     WHERE fr.fed_status = 'UPDATE'
       AND fr.receiptid = ii.receiptid
       AND fr.part_number <> ii.part_number;
       
    --RTJ 05/06/2021 removed update of zone status on up adjusts from this receipt
    --now that all up adjusts have their own receipt data

    INSERT INTO preftz.system_log (procedure_name,log_message) 
        VALUES ('process_receipt_updates','finished');
       
END;
$$;



