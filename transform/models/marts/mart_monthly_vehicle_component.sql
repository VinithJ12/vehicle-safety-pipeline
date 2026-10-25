with complaints as (
    select
        complaint_id,
        make,
        model,
        component,
        date_trunc('month', received_date)::date      as month,
        is_crash,
        is_fire,
        coalesce(num_injured, 0) > 0                  as has_injury
    from {{ ref('stg_complaints') }}
    where component is not null
),

monthly as (
    select
        make, model, component, month,
        count(distinct complaint_id)                                  as complaints,
        count(distinct complaint_id) filter (where is_crash)          as crash_complaints,
        count(distinct complaint_id) filter (where is_fire)           as fire_complaints,
        count(distinct complaint_id) filter (where has_injury)        as injury_complaints
    from complaints
    group by make, model, component, month
),

series as (
    select make, model, component, min(month) as first_month
    from monthly
    group by make, model, component
    having sum(complaints) >= 30
),

months as (
    select generate_series(
        (select min(month) from monthly),
        (select max(month) from monthly),
        interval '1 month'
    )::date as month
),

filled as (
    select
        s.make, s.model, s.component, m.month,
        coalesce(mo.complaints, 0)         as complaints,
        coalesce(mo.crash_complaints, 0)   as crash_complaints,
        coalesce(mo.fire_complaints, 0)    as fire_complaints,
        coalesce(mo.injury_complaints, 0)  as injury_complaints
    from series s
    cross join months m
    left join monthly mo
        on  mo.make = s.make
        and mo.model = s.model
        and mo.component = s.component
        and mo.month = m.month
    where m.month >= s.first_month
),

rolling as (
    select
        *,
        avg(complaints)          over w as baseline_avg,
        stddev_samp(complaints)  over w as baseline_std,
        count(*)                 over w as baseline_months
    from filled
    window w as (
        partition by make, model, component
        order by month
        rows between 12 preceding and 1 preceding
    )
)

select
    make || '|' || model || '|' || component || '|' || month   as series_month_id,
    make,
    model,
    component,
    month,
    complaints,
    crash_complaints,
    fire_complaints,
    injury_complaints,
    round(baseline_avg::numeric, 2)                             as baseline_avg,
    round(baseline_std::numeric, 2)                             as baseline_std,
    baseline_months,
    case when baseline_std > 0
         then round(((complaints - baseline_avg) / baseline_std)::numeric, 2)
    end                                                         as z_score,
    (
        baseline_months >= 6
        and complaints >= 10
        and complaints > baseline_avg + 3 * greatest(baseline_std, 1)
    )                                                           as is_spike,
    month = (select max(month) from months)                     as is_partial_month
from rolling