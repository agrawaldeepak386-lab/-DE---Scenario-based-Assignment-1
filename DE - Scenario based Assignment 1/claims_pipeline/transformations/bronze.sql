-------------------------------------------------------------------------------------
-----------------------------BRONZE LAYER--------------------------------------------
-------------------------------------------------------------------------------------

create or refresh streaming table ${catalog}.bronze.plans as 
select *,_metadata.file_path as file_path,current_timestamp as ingestion_ts from stream(
read_files('/Volumes/${catalog}/raw/landing/plans',
format => 'csv', 
header => 'true',
inferColumnTypes => 'false',
schemaEvolutionMode => 'addnewColumns',
rescuedDataColumn=>'_rescued_data')
);

create or refresh streaming table ${catalog}.bronze.members as 
select *,_metadata.file_path as file_path,current_timestamp as ingestion_ts from stream(
read_files('/Volumes/${catalog}/raw/landing/members',
format => 'csv',
 header => 'true',
 inferColumnTypes => 'false',
 schemaEvolutionMode => 'addnewColumns',
 rescuedDataColumn=>'_rescued_data')
 );

create or refresh streaming table ${catalog}.bronze.hospital_network_history as 
select *,_metadata.file_path as file_path,current_timestamp as ingestion_ts from stream(
    read_files('/Volumes/${catalog}/raw/landing/hospital_network_history',
    format => 'csv', 
    header => 'true',
    inferColumnTypes => 'false',
    schemaEvolutionMode => 'addnewColumns',
    rescuedDataColumn=>'_rescued_data')
    );


create or refresh streaming table ${catalog}.bronze.hospitals as 
select *,_metadata.file_path as file_path,current_timestamp as ingestion_ts from stream(
    read_files('/Volumes/${catalog}/raw/landing/hospitals',
    format => 'csv', 
    header => 'true',
    inferColumnTypes => 'false',
    schemaEvolutionMode => 'addnewColumns',
    rescuedDataColumn=>'_rescued_data')
    );


create or refresh streaming table ${catalog}.bronze.claims as 
select *,_metadata.file_path as file_path,current_timestamp as ingestion_ts from stream(
    read_files('/Volumes/${catalog}/raw/landing/claims/claims_raw',
    format => 'json', 
    multiline=>'true',
    schemaEvolutionMode => 'addnewColumns',
    rescuedDataColumn=>'_rescued_data')
    );

create or refresh streaming table ${catalog}.bronze.policy as 
select *,_metadata.file_path as file_path,current_timestamp as ingestion_ts from stream(
    read_files('/Volumes/${catalog}/raw/landing/policy_changes_cdc',
    format => 'json', 
    multiline=>'true',
    schemaEvolutionMode => 'addnewColumns',
    rescuedDataColumn=>'_rescued_data')
    );
