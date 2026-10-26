with complaints as (
    select
        complaint_id,
        min(make)                                          as make,
        min(model)                                         as model,
        min(date_trunc('month', received_date))::date      as month,
        bool_or(is_crash)                                  as is_crash,
        bool_or(is_fire)                                   as is_fire,
        bool_or(coalesce(num_injured, 0) > 0)              as has_injury
    from {{ ref('stg_complaints') }}
    group by complaint_id
),

topics as (
    select complaint_id, topic
    from {{ source('nlp', 'complaint_topics') }}
    where topic_type = 'defect'
),

monthly as (
    select
        c.make, c.model, t.topic, c.month,
        count(*)                                   as complaints,
        count(*) filter (where c.is_crash)         as crash_complaints,
        count(*) filter (where c.is_fire)          as fire_complaints,
        count(*) filter (where c.has_injury)       as injury_complaints
    from complaints c
    join topics t on t.complaint_id = c.complaint_id
    group by c.make, c.model, t.topic, c.month
),

series as (
    select make, model, topic, min(month) as first_month
    from monthly
    group by make, model, topic
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
        s.make, s.model, s.topic, m.month,
        coalesce(mo.complaints, 0)         as complaints,
        coalesce(mo.crash_complaints, 0)   as crash_complaints,
        coalesce(mo.fire_complaints, 0)    as fire_complaints,
        coalesce(mo.injury_complaints, 0)  as injury_complaints
    from series s
    cross join months m
    left join monthly mo
        on  mo.make = s.make
        and mo.model = s.model
        and mo.topic = s.topic
        and mo.month = m.month
    where m.month >= s.first_month
),

rolling as (
    select
        *,
        avg(complaints)         over w as baseline_avg,
        stddev_samp(complaints) over w as baseline_std,
        count(*)                over w as baseline_months
    from filled
    window w as (
        partition by make, model, topic
        order by month
        rows between 12 preceding and 1 preceding
    )
)

select
    make || '|' || model || '|' || topic || '|' || month       as series_month_id,
    make,
    model,
    topic,
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