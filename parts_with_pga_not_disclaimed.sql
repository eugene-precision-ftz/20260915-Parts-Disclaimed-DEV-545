create OR REPLACE view preftz.parts_with_pga_not_disclaimed
-- MH 07/27/2026 original - added as view to email daily
as 
 with parts as (    
    SELECT pc.part_number, pc.harmonized_tariff_schedule_number, htsr.pga_code_array, pe.pga_disclaim
FROM preftz.part_classifications pc 
LEFT JOIN preftz.harmonized_tariff_schedule_reference htsr ON htsr.tariff_number = pc.harmonized_tariff_schedule_number
    AND CURRENT_DATE BETWEEN record_begin_effective_date AND record_end_effective_date
LEFT JOIN preftz.parts_extension pe ON pe.part_number = pc.part_number
WHERE pc.tariff_type = 'BASE'
    AND htsr.pga_code_array IS NOT NULL
    AND pe.pga_disclaim IS NULL
)

select pa.part_number, pa.harmonized_tariff_schedule_number from preftz.parts_disclaimed pd
left join parts pa on pd.part_number = pa.part_number and pd.hts = pa.harmonized_tariff_schedule_number
where pd.part_number is null ;
