with source as (
    select * from {{ source('nhtsa_raw', 'complaints') }}
),

typed as (
    select
        {{ safe_int('odino') }}                                          as complaint_id,
        regexp_replace(trim(mfr_name), '^redundant\s+', '', 'i')         as manufacturer,
        upper(regexp_replace(trim(maketxt), '^redundant\s+', '', 'i'))   as make,
        upper(regexp_replace(trim(modeltxt), '^redundant\s+', '', 'i'))  as model,
        {{ safe_int('yeartxt') }}                                        as model_year_raw,
        upper(trim(compdesc))                                            as component_full,
        upper(trim(split_part(compdesc, ':', 1)))                        as component_raw,
        crash = 'Y'                                                      as is_crash,
        fire = 'Y'                                                       as is_fire,
        medical_attn = 'Y'                                               as needed_medical_attention,
        vehicles_towed_yn = 'Y'                                          as was_towed,
        police_rpt_yn = 'Y'                                              as reported_to_police,
        {{ safe_int('injured') }}                                        as injured_raw,
        {{ safe_int('deaths') }}                                         as deaths_raw,
        {{ safe_int('miles') }}                                          as miles,
        {{ safe_int('veh_speed') }}                                      as speed_raw,
        {{ safe_date('ldate') }}                                         as received_date,
        {{ safe_date('faildate') }}                                      as failure_date_raw,
        nullif(upper(trim(state)), '')                                   as state_raw,
        nullif(trim(cmpl_type), '')                                      as complaint_source,
        nullif(trim(cdescr), '')                                         as complaint_text,
        _source_file,
        _loaded_at
    from source
    where prod_type = 'V'
)

select
    complaint_id::text || '|' || coalesce(component_full, 'NONE')    as complaint_component_id,
    complaint_id,
    manufacturer,
    make,
    model,
    case when model_year_raw between 1950 and 2030 then model_year_raw end as model_year,
    component_full,
    component_raw,
    case
        when component_raw = 'ENGINE AND ENGINE COOLING' then 'ENGINE'
        else component_raw
    end                                                                as component,
    is_crash,
    is_fire,
    needed_medical_attention,
    was_towed,
    reported_to_police,
    case when injured_raw between 0 and 98 then injured_raw end       as num_injured,
    case when deaths_raw  between 0 and 98 then deaths_raw  end       as num_deaths,
    miles,
    case when speed_raw between 0 and 200 then speed_raw end          as vehicle_speed_mph,
    received_date,
    case when failure_date_raw between date '1990-01-01' and received_date
         then failure_date_raw end                                     as failure_date,
    case when state_raw ~ '^[A-Z]{2}$' and state_raw <> '00'
         then state_raw end                                            as consumer_state,
    complaint_source,
    complaint_text,
    _source_file,
    _loaded_at
from typed