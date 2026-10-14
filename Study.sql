--DISCLAIM staudy

select * from client_setup cs

select * from preftz.ftz_settings t

select * from preftz.ftz_settings_options fso 

cd C:\Users\gorbu\AppData\Roaming\DBeaverData\drivers\clients\postgresql\win\17

psql "postgresql://postgres:2436@localhost:5432/postgres" -c "\COPY preftz.raw_fed_parts_disclaimed(raw_file_text) FROM 'c:\ftz\part_disclaimed.txt';"

------------------------------------------------------------------------------------
--$$$$$$$$$$$$$$$$$$$$$$$$

--delete from preftz.raw_fed_parts_disclaimed;
select * from preftz.raw_fed_parts_disclaimed;

CALL preftz.parse_raw_feed($$fed_parts_disclaimed$$);
CALL preftz.audit_raw_feed($$fed_parts_disclaimed$$);

--delete from preftz.feed_errors
select * from preftz.feed_errors

select * from preftz.raw_fed_parts_disclaimed;
select * from preftz.fed_parts_disclaimed;

select * into preftz.parts_disclaimed_copy from preftz.parts_disclaimed;
select * from preftz.parts_disclaimed;


UPDATE preftz.fed_parts_disclaimed fe
SET fed_status = 'NEW'
WHERE fed_status = 'AUDITING';

call preftz.audit_fed_parts_disclaimed();

--delete from preftz.fed_parts_disclaimed;
--delete from preftz.parts_disclaimed;
--delete from preftz.feed_errors

select * from preftz.fed_parts_disclaimed order by part_number ;
select * from preftz.feed_errors order by tableid;
select * from preftz.parts_disclaimed;

               SELECT fr.parts_disclaimed_id, fr.create_date, fr.fed_status, fr.part_number, fr.pga_code_array, fr.hts, fr.mid_key, fr.vendor_id, fr.coo_iso, fr.government_agency_code, fr.government_agency_program_code, fr.government_agency_processing_code, fr.intended_use_code, fr.disclaimer, fr.item_type, fr.product_code_qualifier, fr.product_code_number, fr.source_type_code, fr.country_code, fr.trade_name_brand_name, fr.commodity_characteristic_description, fr.entity_role_code, fr.entity_identification_code, fr.enitity_number, fr.entity_name, fr.entity_address_1, fr.entity_address_2, fr.entity_apartment_number_suite_number, fr.entity_city, fr.entity_state_province, fr.entity_country, fr.entity_zip_postal_code, fr.individual_qualifier, fr.individual_name, fr.telephone_number_of_the_individual, fr.email_address_for_the_individual, fr.affirmation_of_compliance_code, fr.affirmation_of_compliance_qualifier, fr.remarks_type_code, fr.remarks_text, fr.temperature_qualifier, fr.lot_number_qualifier, fr.lot_number, fr.pga_line_value, fr.packaging_qualifier, fr.quatity, fr.unit_of_measure, fr.container_number1, fr.container_number2, fr.container_number3, fr.anticipated_arrival_information, fr.anticipated_arrival_date_at_port_of_entry, fr.anticipated_arrival_time_at_port_of_entry, fr.inspection_or_arrival_location_code, fr.insection_or_arival_location, fr.additional_information_qualifier_code, fr.additional_information
               FROM preftz.fed_parts_disclaimed fr
               WHERE fr.fed_status = 'AUDITING'  


--drop index preftz.parts_disclaimed_idx_1
CREATE unique INDEX parts_disclaimed_idx_1 ON preftz.parts_disclaimed (
 part_number , hts , mid_key , coo_iso 
 , government_agency_code , government_agency_processing_code , government_agency_program_code
,intended_use_code,  entity_role_code
);
               
               

select
 part_number , hts , mid_key , coo_iso 
, government_agency_code , government_agency_processing_code , government_agency_program_code
,intended_use_code
, entity_role_code
from preftz.fed_parts_disclaimed
WHERE 
--fed_status = 'AUDITING'
--AND 
pga_code_array LIKE '%FD2%'
group by 
part_number , hts , mid_key , coo_iso 
, government_agency_code , government_agency_processing_code , government_agency_program_code
,intended_use_code ,entity_role_code
--having count(*) > 1
;

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
    WHERE fr.fed_status = 'NEW'
      AND fr.pga_code_array = 'FD2'


--delete from preftz.parts_disclaimed;
select * from preftz.parts_disclaimed_copy;
select * from preftz.parts_disclaimed;


select 1,id,null ,* from preftz.parts_disclaimed_copy
where part_number = '16592269'
union all
select 2,*,11 from preftz.parts_disclaimed
where part_number = '16592269'


select 
* 
from preftz.parts_disclaimed_copy
join  preftz.parts_disclaimed

;


select * from preftz.parts_disclaimed_copy
where part_number  = '21286366'
;

select * from preftz.parts_disclaimed_copy
where part_number  = '10055686'
order by part_number, mid_key, entity_role_code
;



select 
part_number, mid_key, entity_role_code
,* 
from preftz.parts_disclaimed_copy
order by part_number, mid_key, entity_role_code;


XXno FD2 - error it , delete any not FD2 make   = FD2 

key
part_number, hts, mid, coo, gov_ag_code, gov_prog_code, gov_process_code, intended_use_code (not null, null is ERROR),
entity_role_code,

XXrequired : item_type, 
XXprod_code_qualif, prod_code_number, source_type_code not null for FD2 -> error if null
XXzip, all addresses, names
XXPK needs : indiv_name, phone, email.

XXadd fed_id column into id , can be renamed

XXnot null in the new feed and null in the table -> update
XXnull in new feed and not null in the table -> error

XXcommodity_descr, entity_role_code (MF,DEQ,FD1,DP,PK) every part must have all 5


clean up: 
intended_use_code if null delete null 
entity_address_code, and zip
put records in question back to fed table 

select 
*
from preftz.parts_disclaimed
where pga_code_array is null
;

update preftz.parts_disclaimed
set pga_code_array = '{FD2}'
where pga_code_array is null;



--drop table preftz.parts_disclaimed_1

--1
select 
* 
into preftz.parts_disclaimed_1
from preftz.parts_disclaimed--_copy
;
--49414

select * 
from preftz.parts_disclaimed_1
where part_number  = '10055686'
order by part_number, mid_key, entity_role_code
;

--2 delete null intended_use_code

select 
distinct pga_code_array
from preftz.parts_disclaimed_1
where entity_role_code is null 
or btrim(entity_role_code) = ''
;
-- !!! must not have FD2 
--7873

delete from preftz.parts_disclaimed_1 where entity_role_code is null or btrim(entity_role_code) = '' ;

select 
distinct pga_code_array
,count(*) over (PARTITION by pga_code_array)
from preftz.parts_disclaimed_1
;

select 
*
--delete
from preftz.parts_disclaimed_1
where pga_code_array is null
;

{EP5,FD1}	11185
{FD2}	30316

delete from preftz.parts_disclaimed_1 where pga_code_array = '{EP5,FD1}' ;

update preftz.parts_disclaimed_1 set pga_code_array = 'FD2'where pga_code_array = '{FD2}' ;
--30316

--3

update preftz.parts_disclaimed_1
set 
  part_number                                    = upper(btrim(part_number                              ))
, pga_code_array                                 = upper(btrim(pga_code_array                           ))
, hts                                            = upper(btrim(hts                                      ))
, mid_key                                        = upper(btrim(mid_key                                  ))
, vendor_id                                      = upper(btrim(vendor_id                                ))
, coo_iso                                        = upper(btrim(coo_iso                                  ))
, government_agency_code                         = upper(btrim(government_agency_code                   ))
, government_agency_program_code                 = upper(btrim(government_agency_program_code           ))
, government_agency_processing_code              = upper(btrim(government_agency_processing_code        ))
, intended_use_code                              = upper(btrim(intended_use_code                        ))
, disclaimer                                     = upper(btrim(disclaimer                               ))
, item_type                                      = upper(btrim(item_type                                ))
, product_code_qualifier                         = upper(btrim(product_code_qualifier                   ))
, product_code_number                            = upper(btrim(product_code_number                      ))
, source_type_code                               = upper(btrim(source_type_code                         ))
, country_code                                   = upper(btrim(country_code                             ))
, trade_name_brand_name                          = upper(btrim(trade_name_brand_name                    ))
, commodity_characteristic_description           = upper(btrim(commodity_characteristic_description     ))
, entity_role_code                               = upper(btrim(entity_role_code                         ))
, entity_identification_code                     = upper(btrim(entity_identification_code               ))
, enitity_number                                 = upper(btrim(enitity_number                           ))
, entity_name                                    = upper(btrim(entity_name                              ))
, entity_address_1                               = upper(btrim(entity_address_1                         ))
, entity_address_2                               = upper(btrim(entity_address_2                         ))
, entity_apartment_number_suite_number           = upper(btrim(entity_apartment_number_suite_number     ))
, entity_city                                    = upper(btrim(entity_city                              ))
, entity_state_province                          = upper(btrim(entity_state_province                    ))
, entity_country                                 = upper(btrim(entity_country                           ))
, entity_zip_postal_code                         = upper(btrim(entity_zip_postal_code                   ))
, individual_qualifier                           = upper(btrim(individual_qualifier                     ))
, individual_name                                = upper(btrim(individual_name                          ))
, telephone_number_of_the_individual             = upper(btrim(telephone_number_of_the_individual       ))
, email_address_for_the_individual               = upper(btrim(email_address_for_the_individual         ))
, affirmation_of_compliance_code                 = upper(btrim(affirmation_of_compliance_code           ))
, affirmation_of_compliance_qualifier            = upper(btrim(affirmation_of_compliance_qualifier      ))
, remarks_type_code                              = upper(btrim(remarks_type_code                        ))
, remarks_text                                   = upper(btrim(remarks_text                             ))
, temperature_qualifier                          = upper(btrim(temperature_qualifier                    ))
, lot_number_qualifier                           = upper(btrim(lot_number_qualifier                     ))
, lot_number                                     = upper(btrim(lot_number                               ))
, pga_line_value                                 = upper(btrim(pga_line_value                           ))
, packaging_qualifier                            = upper(btrim(packaging_qualifier                      ))
, quatity                                        = upper(btrim(quatity                                  ))
, unit_of_measure                                = upper(btrim(unit_of_measure                          ))
, container_number1                              = upper(btrim(container_number1                        ))
, container_number2                              = upper(btrim(container_number2                        ))
, container_number3                              = upper(btrim(container_number3                        ))
, anticipated_arrival_information                = upper(btrim(anticipated_arrival_information          ))
, anticipated_arrival_date_at_port_of_entry      = upper(btrim(anticipated_arrival_date_at_port_of_entry))
, anticipated_arrival_time_at_port_of_entry      = upper(btrim(anticipated_arrival_time_at_port_of_entry))
, inspection_or_arrival_location_code            = upper(btrim(inspection_or_arrival_location_code      ))
, insection_or_arival_location                   = upper(btrim(insection_or_arival_location             ))
, additional_information_qualifier_code          = upper(btrim(additional_information_qualifier_code    ))
, additional_information                         = upper(btrim(additional_information                   ))



update preftz.parts_disclaimed_1
set 
  part_number                                    = NULLIF(part_number                              ,'')
, pga_code_array                                 = NULLIF(pga_code_array                           ,'')
, hts                                            = NULLIF(hts                                      ,'')
, mid_key                                        = NULLIF(mid_key                                  ,'')
, vendor_id                                      = NULLIF(vendor_id                                ,'')
, coo_iso                                        = NULLIF(coo_iso                                  ,'')
, government_agency_code                         = NULLIF(government_agency_code                   ,'')
, government_agency_program_code                 = NULLIF(government_agency_program_code           ,'')
, government_agency_processing_code              = NULLIF(government_agency_processing_code        ,'')
, intended_use_code                              = NULLIF(intended_use_code                        ,'')
, disclaimer                                     = NULLIF(disclaimer                               ,'')
, item_type                                      = NULLIF(item_type                                ,'')
, product_code_qualifier                         = NULLIF(product_code_qualifier                   ,'')
, product_code_number                            = NULLIF(product_code_number                      ,'')
, source_type_code                               = NULLIF(source_type_code                         ,'')
, country_code                                   = NULLIF(country_code                             ,'')
, trade_name_brand_name                          = NULLIF(trade_name_brand_name                    ,'')
, commodity_characteristic_description           = NULLIF(commodity_characteristic_description     ,'')
, entity_role_code                               = NULLIF(entity_role_code                         ,'')
, entity_identification_code                     = NULLIF(entity_identification_code               ,'')
, enitity_number                                 = NULLIF(enitity_number                           ,'')
, entity_name                                    = NULLIF(entity_name                              ,'')
, entity_address_1                               = NULLIF(entity_address_1                         ,'')
, entity_address_2                               = NULLIF(entity_address_2                         ,'')
, entity_apartment_number_suite_number           = NULLIF(entity_apartment_number_suite_number     ,'')
, entity_city                                    = NULLIF(entity_city                              ,'')
, entity_state_province                          = NULLIF(entity_state_province                    ,'')
, entity_country                                 = NULLIF(entity_country                           ,'')
, entity_zip_postal_code                         = NULLIF(entity_zip_postal_code                   ,'')
, individual_qualifier                           = NULLIF(individual_qualifier                     ,'')
, individual_name                                = NULLIF(individual_name                          ,'')
, telephone_number_of_the_individual             = NULLIF(telephone_number_of_the_individual       ,'')
, email_address_for_the_individual               = NULLIF(email_address_for_the_individual         ,'')
, affirmation_of_compliance_code                 = NULLIF(affirmation_of_compliance_code           ,'')
, affirmation_of_compliance_qualifier            = NULLIF(affirmation_of_compliance_qualifier      ,'')
, remarks_type_code                              = NULLIF(remarks_type_code                        ,'')
, remarks_text                                   = NULLIF(remarks_text                             ,'')
, temperature_qualifier                          = NULLIF(temperature_qualifier                    ,'')
, lot_number_qualifier                           = NULLIF(lot_number_qualifier                     ,'')
, lot_number                                     = NULLIF(lot_number                               ,'')
, pga_line_value                                 = NULLIF(pga_line_value                           ,'')
, packaging_qualifier                            = NULLIF(packaging_qualifier                      ,'')
, quatity                                        = NULLIF(quatity                                  ,'')
, unit_of_measure                                = NULLIF(unit_of_measure                          ,'')
, container_number1                              = NULLIF(container_number1                        ,'')
, container_number2                              = NULLIF(container_number2                        ,'')
, container_number3                              = NULLIF(container_number3                        ,'')
, anticipated_arrival_information                = NULLIF(anticipated_arrival_information          ,'')
, anticipated_arrival_date_at_port_of_entry      = NULLIF(anticipated_arrival_date_at_port_of_entry,'')
, anticipated_arrival_time_at_port_of_entry      = NULLIF(anticipated_arrival_time_at_port_of_entry,'')
, inspection_or_arrival_location_code            = NULLIF(inspection_or_arrival_location_code      ,'')
, insection_or_arival_location                   = NULLIF(insection_or_arival_location             ,'')
, additional_information_qualifier_code          = NULLIF(additional_information_qualifier_code    ,'')
, additional_information                         = NULLIF(additional_information                   ,'')



--4 find if duplicate exists
alter table preftz.parts_disclaimed_1 add column md5_v text;

select 
md5( 
   coalesce( part_number                          ,'')   
|| coalesce( pga_code_array                       ,'')   
|| coalesce( hts                                  ,'')   
|| coalesce( mid_key                              ,'')   
|| coalesce( vendor_id                            ,'')   
|| coalesce( coo_iso                              ,'')   
|| coalesce( government_agency_code               ,'')   
|| coalesce( government_agency_program_code       ,'')   
|| coalesce( government_agency_processing_code    ,'')   
|| coalesce( intended_use_code                    ,'')   
|| coalesce( entity_role_code       ,'')
|| coalesce( disclaimer                                  ,'')   
|| coalesce( item_type                                   ,'')   
|| coalesce( product_code_qualifier                      ,'')   
|| coalesce( product_code_number                         ,'')   
|| coalesce( source_type_code                            ,'')   
|| coalesce( country_code                                ,'')   
|| coalesce( trade_name_brand_name                       ,'')   
|| coalesce( commodity_characteristic_description        ,'')   
|| coalesce( entity_identification_code                  ,'')   
|| coalesce( enitity_number                              ,'')   
|| coalesce( entity_name                                 ,'')   
|| coalesce( entity_address_1                            ,'')   
|| coalesce( entity_address_2                            ,'')   
|| coalesce( entity_apartment_number_suite_number        ,'')   
|| coalesce( entity_city                                 ,'')   
|| coalesce( entity_state_province                       ,'')   
|| coalesce( entity_country                              ,'')   
|| coalesce( entity_zip_postal_code                      ,'')   
|| coalesce( individual_qualifier                        ,'')   
|| coalesce( individual_name                             ,'')   
|| coalesce( telephone_number_of_the_individual          ,'')   
|| coalesce( email_address_for_the_individual            ,'')   
|| coalesce( affirmation_of_compliance_code              ,'')   
|| coalesce( affirmation_of_compliance_qualifier         ,'')   
|| coalesce( remarks_type_code                           ,'')   
|| coalesce( remarks_text                                ,'')   
|| coalesce( temperature_qualifier                       ,'')   
|| coalesce( lot_number_qualifier                        ,'')   
|| coalesce( lot_number                                  ,'')   
|| coalesce( pga_line_value                              ,'')   
|| coalesce( packaging_qualifier                         ,'')   
|| coalesce( quatity                                     ,'')   
|| coalesce( unit_of_measure                             ,'')   
|| coalesce( container_number1                           ,'')   
|| coalesce( container_number2                           ,'')   
|| coalesce( container_number3                           ,'')   
|| coalesce( anticipated_arrival_information             ,'')   
|| coalesce( anticipated_arrival_date_at_port_of_entry   ,'')   
|| coalesce( anticipated_arrival_time_at_port_of_entry   ,'')   
|| coalesce( inspection_or_arrival_location_code         ,'')   
|| coalesce( insection_or_arival_location                ,'')   
|| coalesce( additional_information_qualifier_code       ,'')   
|| coalesce( additional_information                      ,'')   
) x
,*
from preftz.parts_disclaimed_1
where part_number  = '3084083'
order by x 

update preftz.parts_disclaimed_1
set md5_v =  
md5( 
   coalesce( part_number                          ,'')   
|| coalesce( pga_code_array                       ,'')   
|| coalesce( hts                                  ,'')   
|| coalesce( mid_key                              ,'')   
|| coalesce( vendor_id                            ,'')   
|| coalesce( coo_iso                              ,'')   
|| coalesce( government_agency_code               ,'')   
|| coalesce( government_agency_program_code       ,'')   
|| coalesce( government_agency_processing_code    ,'')   
|| coalesce( intended_use_code                    ,'')   
|| coalesce( entity_role_code       ,'')
|| coalesce( disclaimer                                  ,'')   
|| coalesce( item_type                                   ,'')   
|| coalesce( product_code_qualifier                      ,'')   
|| coalesce( product_code_number                         ,'')   
|| coalesce( source_type_code                            ,'')   
|| coalesce( country_code                                ,'')   
|| coalesce( trade_name_brand_name                       ,'')   
|| coalesce( commodity_characteristic_description        ,'')   
|| coalesce( entity_identification_code                  ,'')   
|| coalesce( enitity_number                              ,'')   
|| coalesce( entity_name                                 ,'')   
|| coalesce( entity_address_1                            ,'')   
|| coalesce( entity_address_2                            ,'')   
|| coalesce( entity_apartment_number_suite_number        ,'')   
|| coalesce( entity_city                                 ,'')   
|| coalesce( entity_state_province                       ,'')   
|| coalesce( entity_country                              ,'')   
|| coalesce( entity_zip_postal_code                      ,'')   
|| coalesce( individual_qualifier                        ,'')   
|| coalesce( individual_name                             ,'')   
|| coalesce( telephone_number_of_the_individual          ,'')   
|| coalesce( email_address_for_the_individual            ,'')   
|| coalesce( affirmation_of_compliance_code              ,'')   
|| coalesce( affirmation_of_compliance_qualifier         ,'')   
|| coalesce( remarks_type_code                           ,'')   
|| coalesce( remarks_text                                ,'')   
|| coalesce( temperature_qualifier                       ,'')   
|| coalesce( lot_number_qualifier                        ,'')   
|| coalesce( lot_number                                  ,'')   
|| coalesce( pga_line_value                              ,'')   
|| coalesce( packaging_qualifier                         ,'')   
|| coalesce( quatity                                     ,'')   
|| coalesce( unit_of_measure                             ,'')   
|| coalesce( container_number1                           ,'')   
|| coalesce( container_number2                           ,'')   
|| coalesce( container_number3                           ,'')   
|| coalesce( anticipated_arrival_information             ,'')   
|| coalesce( anticipated_arrival_date_at_port_of_entry   ,'')   
|| coalesce( anticipated_arrival_time_at_port_of_entry   ,'')   
|| coalesce( inspection_or_arrival_location_code         ,'')   
|| coalesce( insection_or_arival_location                ,'')   
|| coalesce( additional_information_qualifier_code       ,'')   
|| coalesce( additional_information                      ,'')   
) ;



select 
md5_v
,count(*)
,min(id)
from preftz.parts_disclaimed_1
group by 
md5_v
having count(*) >1
;
--3766

delete from preftz.parts_disclaimed_1 
where id in
(
select 
min(id)
from preftz.parts_disclaimed_1
group by 
md5_v
having count(*) >1
)
;


--5

update preftz.parts_disclaimed_1
set 
entity_city = 'HUIZHOU'
where 
entity_city = 'HUIZHOU HUIZHOU';
--2374

update preftz.parts_disclaimed_1
set md5_v =  
md5( 
   coalesce( part_number                          ,'')   
|| coalesce( pga_code_array                       ,'')   
|| coalesce( hts                                  ,'')   
|| coalesce( mid_key                              ,'')   
|| coalesce( vendor_id                            ,'')   
|| coalesce( coo_iso                              ,'')   
|| coalesce( government_agency_code               ,'')   
|| coalesce( government_agency_program_code       ,'')   
|| coalesce( government_agency_processing_code    ,'')   
|| coalesce( intended_use_code                    ,'')   
|| coalesce( entity_role_code       ,'')
|| coalesce( disclaimer                                  ,'')   
|| coalesce( item_type                                   ,'')   
|| coalesce( product_code_qualifier                      ,'')   
|| coalesce( product_code_number                         ,'')   
|| coalesce( source_type_code                            ,'')   
|| coalesce( country_code                                ,'')   
|| coalesce( trade_name_brand_name                       ,'')   
|| coalesce( commodity_characteristic_description        ,'')   
|| coalesce( entity_identification_code                  ,'')   
|| coalesce( enitity_number                              ,'')   
|| coalesce( entity_name                                 ,'')   
|| coalesce( entity_address_1                            ,'')   
|| coalesce( entity_address_2                            ,'')   
|| coalesce( entity_apartment_number_suite_number        ,'')   
|| coalesce( entity_city                                 ,'')   
|| coalesce( entity_state_province                       ,'')   
|| coalesce( entity_country                              ,'')   
--|| coalesce( entity_zip_postal_code                      ,'')   
|| coalesce( individual_qualifier                        ,'')   
|| coalesce( individual_name                             ,'')   
|| coalesce( telephone_number_of_the_individual          ,'')   
|| coalesce( email_address_for_the_individual            ,'')   
|| coalesce( affirmation_of_compliance_code              ,'')   
|| coalesce( affirmation_of_compliance_qualifier         ,'')   
|| coalesce( remarks_type_code                           ,'')   
|| coalesce( remarks_text                                ,'')   
|| coalesce( temperature_qualifier                       ,'')   
|| coalesce( lot_number_qualifier                        ,'')   
|| coalesce( lot_number                                  ,'')   
|| coalesce( pga_line_value                              ,'')   
|| coalesce( packaging_qualifier                         ,'')   
|| coalesce( quatity                                     ,'')   
|| coalesce( unit_of_measure                             ,'')   
|| coalesce( container_number1                           ,'')   
|| coalesce( container_number2                           ,'')   
|| coalesce( container_number3                           ,'')   
|| coalesce( anticipated_arrival_information             ,'')   
|| coalesce( anticipated_arrival_date_at_port_of_entry   ,'')   
|| coalesce( anticipated_arrival_time_at_port_of_entry   ,'')   
|| coalesce( inspection_or_arrival_location_code         ,'')   
|| coalesce( insection_or_arival_location                ,'')   
|| coalesce( additional_information_qualifier_code       ,'')   
|| coalesce( additional_information                      ,'')   
) ;



select 
md5_v
,count(*)
,min(id)
from preftz.parts_disclaimed_1
group by 
md5_v
having count(*) >1
;
--2374

delete from preftz.parts_disclaimed_1 
where id in
(
select 
min(id)
from preftz.parts_disclaimed_1
group by 
md5_v
having count(*) >1
)
;
--2374



-------



select 
 part_number , hts , mid_key , coo_iso 
 , government_agency_code ga , government_agency_processing_code gc, government_agency_program_code gcc
,intended_use_code,  entity_role_code
from preftz.parts_disclaimed_1
group by 
 part_number , hts , mid_key , coo_iso 
 , government_agency_code , government_agency_processing_code , government_agency_program_code
,intended_use_code,  entity_role_code
having count(*) >1
;
--start/6140  2/6140 4/2374 5/0



select
 part_number , hts , mid_key , coo_iso 
 , government_agency_code ga , government_agency_processing_code gc, government_agency_program_code gcc
,intended_use_code,  entity_role_code
,* 
from preftz.parts_disclaimed_1
--where part_number  = '5695394' --!!!!! NULL intend to use code 
order by part_number, mid_key, entity_role_code
;




select
sl.procedure_name 
,sl.log_message 
--,sl.details 
,log_date
,(log_date AT TIME ZONE 'UTC') AT TIME ZONE 'America/New_York'
--delete 
from preftz.system_log sl 
where sl.procedure_name like '%audit_fed_parts_disclaimed%'
--where sl.procedure_name like '%pre_receipts_filing%'
--where sl.procedure_name like '%process_auto_concur%'
--where sl.procedure_name like '%create_e214%'
--where sl.procedure_name like '%nightly_background_job%' and sl.log_date >= '2026-08-11'
--where sl.procedure_name like '%link_receipts_to_conveyances_by_inbond%'
--and sl.log_message like 'MARKED AS DUPLICATE%'
order by sl.logid desc;

select 
part_number , pga_code_array , hts , coo_iso , vendor_id , entity_role_code  
from preftz.parts_disclaimed
group by part_number , pga_code_array , hts , coo_iso , vendor_id, entity_role_code
having count(*) >1
;



SELECT
    fields.key AS column_name,
    COUNT(*) FILTER (
        WHERE fields.value = 'null'::jsonb
    ) AS null_count
FROM preftz.parts_disclaimed_copy AS t
CROSS JOIN LATERAL jsonb_each(to_jsonb(t)) AS fields
GROUP BY fields.key
HAVING COUNT(*) FILTER (
    WHERE fields.value = 'null'::jsonb
) > 0
ORDER BY null_count DESC, column_name;


select 
* 
from preftz.parts_disclaimed_copy
where nullif(entity_role_code,'') is null


-------------------------------------------------------------

select * 
from preftz.receipt_classifications rc 

select * 
from preftz.inventory_not_on_cargo_release_template

SELECT inoc.* ,htsr.pga_code_array
FROM preftz.inventory_not_on_cargo_release_template inoc 
LEFT JOIN preftz.harmonized_tariff_schedule_reference htsr ON htsr.tariff_number = inoc.hts_number
    AND htsr.record_end_effective_date > CURRENT_DATE

    
    
-- preftz.inventory_not_on_cargo_release_template source

CREATE OR REPLACE VIEW preftz.inventory_not_on_cargo_release_template
AS 

WITH unnested_cargo_template AS (
         SELECT wer.weekly_estimate_recordid,
            wer.hts_number,
            wer.country_of_origin,
            wer.manufacturer_id_code,
            unnest(wer.chapter99_hts_numbers) AS chap99_hts
           FROM preftz.weekly_estimate_records wer
          WHERE wer.release_documentid = 0 AND wer.privileged_foreign IS TRUE
        ), section122_ids AS (
         SELECT DISTINCT unnested_cargo_template.weekly_estimate_recordid
           FROM unnested_cargo_template
        ), template_rows_ordered AS (
         SELECT t.weekly_estimate_recordid,
            t.hts_number,
            t.country_of_origin,
            t.manufacturer_id_code,
            array_agg(t.chap99_hts ORDER BY t.chap99_hts) AS chapter99_hts_numbers
           FROM unnested_cargo_template t
             JOIN section122_ids s ON s.weekly_estimate_recordid = t.weekly_estimate_recordid
          GROUP BY t.weekly_estimate_recordid, t.hts_number, t.country_of_origin, t.manufacturer_id_code
        ), target_receipts_with_inventory AS (
         SELECT ii.receiptid
           FROM preftz.inventory_items ii
          WHERE ii.quantity_on_hand > 0::double precision AND COALESCE(ii.receiptid, '-1'::integer) > 0 AND ii.zone_status <> 'D'::bpchar
        UNION
         SELECT ii.receiptid
           FROM preftz.inventory_items ii
             JOIN preftz.weekly_shipments_items_links sil ON sil.itemid = ii.itemid
          WHERE ii.quantity_on_hand = 0::double precision AND COALESCE(ii.receiptid, '-1'::integer) > 0 AND ii.zone_status <> 'D'::bpchar
        ), receipt_rows_ordered AS (
         SELECT r.receiptid,
            rc.harmonized_tariff_schedule_number,
            r.country_of_origin,
            r.manufacturer_mid_code,
            array_remove(array_agg(DISTINCT rc_added.harmonized_tariff_schedule_number ORDER BY rc_added.harmonized_tariff_schedule_number), NULL::character varying) AS chapter99_hts_numbers
           FROM preftz.receipts r
             JOIN target_receipts_with_inventory tr_1 ON tr_1.receiptid = r.receiptid
             JOIN preftz.receipt_classifications rc ON rc.receiptid = r.receiptid AND rc.tariff_type::text = 'BASE'::text
             LEFT JOIN preftz.receipt_classifications rc_added ON rc_added.receiptid = r.receiptid AND rc_added.tariff_type::text <> 'BASE'::text
          GROUP BY r.receiptid, rc.harmonized_tariff_schedule_number, r.country_of_origin, r.manufacturer_mid_code
        ), distinct_receipt_rows AS (
         SELECT rr_1.harmonized_tariff_schedule_number,
            rr_1.country_of_origin,
            rr_1.manufacturer_mid_code,
            rr_1.chapter99_hts_numbers,
            sum(r.quantity) AS qty,
            sum(r.quantity * preftz.get_receipt_value(r.receiptid)) AS val
           FROM receipt_rows_ordered rr_1
             JOIN preftz.receipts r ON r.receiptid = rr_1.receiptid
          GROUP BY rr_1.harmonized_tariff_schedule_number, rr_1.country_of_origin, rr_1.manufacturer_mid_code, rr_1.chapter99_hts_numbers
        )
 SELECT rr.harmonized_tariff_schedule_number AS hts_number,
    rr.country_of_origin,
    rr.manufacturer_mid_code,
    rr.chapter99_hts_numbers,
    round(rr.qty) AS total_receipt_quantity,
    round(rr.val) AS total_receipt_value
   FROM distinct_receipt_rows rr
     LEFT JOIN template_rows_ordered tr ON rr.harmonized_tariff_schedule_number::text = tr.hts_number::text AND rr.country_of_origin = tr.country_of_origin::bpchar AND rr.manufacturer_mid_code::text = tr.manufacturer_id_code::text AND rr.chapter99_hts_numbers = tr.chapter99_hts_numbers
  WHERE tr.hts_number IS NULL;    
    

SELECT definition, * 
FROM pg_views 
WHERE schemaname = 'preftz' 
AND viewname = 'inventory_not_on_cargo_release_template';


         SELECT rr_1.harmonized_tariff_schedule_number,
            rr_1.country_of_origin,
            rr_1.manufacturer_mid_code,
            rr_1.chapter99_hts_numbers,
            sum(r.quantity) AS qty,
            sum(r.quantity * preftz.get_receipt_value(r.receiptid)) AS val
           FROM receipt_rows_ordered rr_1
             JOIN preftz.receipts r ON r.receiptid = rr_1.receiptid
          GROUP BY rr_1.harmonized_tariff_schedule_number, rr_1.country_of_origin, rr_1.manufacturer_mid_code, rr_1.chapter99_hts_numbers
          
--Get pre_receipts without cargo_release_template match
          
select * from preftz.pre_receipts_not_on_cargo_release_template;          
          
CREATE OR REPLACE VIEW preftz.pre_receipts_not_on_cargo_release_template
AS 
WITH receipt_rows_ordered AS (
         SELECT r.receiptid,
            rc.harmonized_tariff_schedule_number,
            r.country_of_origin,
            r.manufacturer_mid_code,
            array_remove(array_agg(DISTINCT rc_added.harmonized_tariff_schedule_number ORDER BY rc_added.harmonized_tariff_schedule_number), NULL::character varying) AS chapter99_hts_numbers
           FROM preftz.receipts r
             JOIN preftz.receipt_classifications rc ON rc.receiptid = r.receiptid AND rc.tariff_type::text = 'BASE'::text
             LEFT JOIN preftz.receipt_classifications rc_added ON rc_added.receiptid = r.receiptid AND rc_added.tariff_type::text <> 'BASE'::text
             where pre_receipt
             and preftz.check_pre_receipt_against_template(r.receiptid) = 'FAIL'
          GROUP BY r.receiptid, rc.harmonized_tariff_schedule_number, r.country_of_origin, r.manufacturer_mid_code
        ), distinct_receipt_rows AS (
         SELECT rr_1.harmonized_tariff_schedule_number,
            rr_1.country_of_origin,
            rr_1.manufacturer_mid_code,
            rr_1.chapter99_hts_numbers,
            sum(r.quantity) AS qty,
            sum(r.quantity * preftz.get_receipt_value(r.receiptid)) AS val
           FROM receipt_rows_ordered rr_1
             JOIN preftz.receipts r ON r.receiptid = rr_1.receiptid
          GROUP BY rr_1.harmonized_tariff_schedule_number, rr_1.country_of_origin, rr_1.manufacturer_mid_code, rr_1.chapter99_hts_numbers
        )
 SELECT rr.harmonized_tariff_schedule_number AS hts_number,
    rr.country_of_origin,
    rr.manufacturer_mid_code,
    rr.chapter99_hts_numbers,
    round(rr.qty) AS total_pre_receipt_quantity,
    round(rr.val) AS total_pre_receipt_value
    ,htsr.pga_code_array
   FROM distinct_receipt_rows rr
   LEFT JOIN preftz.harmonized_tariff_schedule_reference htsr ON htsr.tariff_number = rr.harmonized_tariff_schedule_number
   AND htsr.record_end_effective_date > CURRENT_DATE
   order by hts_number , manufacturer_mid_code, country_of_origin, chapter99_hts_numbers;
--19 
   
 
SELECT inoc.* ,htsr.pga_code_array
FROM preftz.inventory_not_on_cargo_release_template inoc 
LEFT JOIN preftz.harmonized_tariff_schedule_reference htsr ON htsr.tariff_number = inoc.hts_number
    AND htsr.record_end_effective_date > CURRENT_DATE
    
select * from preftz.harmonized_tariff_schedule_reference     
where tariff_number   in
(
'8203206060'
,'8205598000'
,'8207907585'
,'8504406018'
,'8504407018'
,'8504409580'
,'8529909800'
,'8536694040'
,'8541410000'
,'8543709860'
,'9027102000'  
)       
order by tariff_number
        
 SELECT rr.harmonized_tariff_schedule_number AS hts_number,
    rr.country_of_origin,
    rr.manufacturer_mid_code,
    rr.chapter99_hts_numbers,
    round(rr.qty) AS total_receipt_quantity,
    round(rr.val) AS total_receipt_value
   FROM distinct_receipt_rows rr
     LEFT JOIN template_rows_ordered tr ON rr.harmonized_tariff_schedule_number::text = tr.hts_number::text AND rr.country_of_origin = tr.country_of_origin::bpchar AND rr.manufacturer_mid_code::text = tr.manufacturer_id_code::text AND rr.chapter99_hts_numbers = tr.chapter99_hts_numbers
  WHERE tr.hts_number IS NULL;    
    

 select
 preftz.check_pre_receipt_against_template(r.receiptid)
 ,*
 from preftz.receipts r
 --join preftz.receipt_classifications rc1 on r.receiptid  = rc1.receiptid  
 where pre_receipt
 order by r.receiptid desc
 
 --1688
 
SELECT inoc.* ,htsr.pga_code_array
FROM preftz.inventory_not_on_cargo_release_template inoc 
LEFT JOIN preftz.harmonized_tariff_schedule_reference htsr ON htsr.tariff_number = inoc.hts_number
    AND htsr.record_end_effective_date > CURRENT_DATE

select
 preftz.check_pre_receipt_against_template(r.receiptid)
 ,*
 from preftz.receipts r
 where pre_receipt
 and preftz.check_pre_receipt_against_template(r.receiptid) = 'FAIL'
 order by r.receiptid desc
  
 
 
 
    select coalesce(t2.hts_number, 'FAIL') 
--   into v_status
   from 
   (
   SELECT
     hts,
     hts99,
     r.country_of_origin,
     r.manufacturer_mid_code,
     CASE WHEN r.zone_status = 'P' THEN true ELSE false END AS is_privileged
   FROM preftz.receipts r
   --LEFT 
   JOIN (
     SELECT
       rc.receiptid,
       harmonized_tariff_schedule_number AS hts,
       (
         SELECT array_agg(rc1.harmonized_tariff_schedule_number)
         FROM preftz.receipt_classifications rc1
         WHERE rc1.tariff_type <> 'BASE'
           AND rc1.receiptid = rc.receiptid
           AND rc1.harmonized_tariff_schedule_number IS NOT NULL
       ) AS hts99
     FROM preftz.receipt_classifications rc
     WHERE rc.receiptid = 628883
       AND rc.tariff_type = 'BASE'
   ) rc2
     ON r.receiptid = rc2.receiptid
   WHERE r.receiptid = 628883
   and rc2.hts is not null
   AND r.pre_receipt is TRUE
   )t1 
   left join 
   (
   select 
    wer.hts_number 
   ,wer.chapter99_hts_numbers 
   ,wer.country_of_origin 
   ,wer.manufacturer_id_code 
   ,coalesce(wer.privileged_foreign,false) privileged 
   --,count(*)
   from preftz.weekly_estimate_records wer 
   where wer.release_documentid = 0
   and wer.manufacturer_id_code  = 'CNNECLOG515SHA'
   group by 
   wer.hts_number 
   ,wer.chapter99_hts_numbers 
   ,wer.country_of_origin 
   ,wer.manufacturer_id_code
   ,coalesce(wer.privileged_foreign,false)
   ) t2
   ON t1.hts = t2.hts_number 
   AND t1.country_of_origin = t2.country_of_origin 
   AND t1.manufacturer_mid_code = t2.manufacturer_id_code 
   AND t1.is_privileged = t2.privileged 
   AND COALESCE(t1.hts99, ARRAY[]::varchar[]) @> COALESCE(t2.chapter99_hts_numbers, ARRAY[]::varchar[])
   AND COALESCE(t1.hts99, ARRAY[]::varchar[]) <@ COALESCE(t2.chapter99_hts_numbers, ARRAY[]::varchar[]);


select preftz.check_pre_receipt_against_template(628883)    
    
 
hts       |hts99     |country_of_origin|manufacturer_mid_code|is_privileged|
----------+----------+-----------------+---------------------+-------------+
8542310025|{99030586}|TW               |CNNECLOG515SHA       |true         |


