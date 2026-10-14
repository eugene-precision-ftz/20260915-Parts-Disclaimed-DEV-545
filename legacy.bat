COPY /B C:\FTZ\develop\preftz-mothership\view\parts_with_pga_not_disclaimed.sql DB\parts_with_pga_not_disclaimed.sql 

COPY /B C:\FTZ\develop\preftz-mothership\table\parts_disclaimed.sql DB\parts_disclaimed.sql 
COPY /B C:\FTZ\develop\preftz-mothership\table\fed_parts_disclaimed.sql DB\fed_parts_disclaimed.sql 
COPY /B C:\FTZ\develop\preftz-mothership\table\raw_fed_parts_disclaimed.sql DB\raw_fed_parts_disclaimed.sql 

COPY /B C:\FTZ\develop\preftz-mothership\procedure\audit_fed_parts_disclaimed.sql DB\audit_fed_parts_disclaimed.sql
