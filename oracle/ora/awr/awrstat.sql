/*[[
    Show the AWR performance trend for a specific SQL. Usage: @@NAME <sql_id|plan_hash_value|signature> [-d|-p] [-m]
    -d: Group by day, otherwise group in detail
    -p: Group by plan_hash_value
    -m: Group by signature, otherwise group by sql id

    Sample Output:
    ==============
         TIME         SQL_ID      PLAN_HASH EXEC PARSE VERS SEENS  ELA   ELA(Avg) IOWAIT CPUWAIT CCWAIT CLWAIT APWAIT PLSQL BUFF CELLIO OFLIN OFLOUT READ WRITE ROWS# FETCHES  PX
    -------------- ------------- ---------- ---- ----- ---- ----- ------ -------- ------ ------- ------ ------ ------ ----- ---- ------ ----- ------ ---- ----- ----- ------- ----
    20190412 10:00 310wr50c2fjv0 3971591178 3623 14499    2     1 31.05m    0.51s   0.0%   98.9%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2862    3623 3627
    20190412 09:00 310wr50c2fjv0 3971591178 3590 14357    2     1 30.79m    0.51s   0.0%   98.8%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  3577    3590 3587
    20190412 08:00 310wr50c2fjv0 3971591178 3611 14442    2     1 30.26m    0.50s   0.0%   98.9%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2436    3610 3582
    20190412 07:00 310wr50c2fjv0 3971591178 3593 14373    2     1 30.42m    0.51s   0.0%   98.9%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2671    3592 3578
    20190412 06:00 310wr50c2fjv0 3971591178 3601 14408    2     1 30.43m    0.51s   0.0%   99.0%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2946    3598 3591
    20190412 05:00 310wr50c2fjv0 3971591178 3585 14340    2     1 30.39m    0.51s   0.0%   99.0%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2839    3585 3585
    20190412 04:00 310wr50c2fjv0 3971591178 3618 14467    2     1 30.55m    0.51s   0.0%   98.9%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2723    3618 3620
    20190412 03:00 310wr50c2fjv0 3971591178 3585 14340    2     1 30.21m    0.51s   0.0%   99.0%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2827    3585 3586
    20190412 02:00 310wr50c2fjv0 3971591178 3623 14494    2     1 30.32m    0.50s   0.0%   99.0%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2674    3623 3622
    20190412 01:00 310wr50c2fjv0 3971591178 3585 14340    2     1 29.94m    0.50s   0.0%   98.9%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2901    3585 3579
    20190412 00:00 310wr50c2fjv0 3971591178 3612 14449    2     1 30.25m    0.50s   0.0%   98.9%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2917    3612 3606
    20190411 23:00 310wr50c2fjv0 3971591178 3601 14399    2     1 29.53m    0.49s   0.0%   98.9%   0.0%   0.0%   0.0%  0.0% 0  B   0  B  0  B   0  B 0  B  0  B  2555    3600 3580
    --[[
        &BASE : s={sql_id}, m={signature}
        &TIM  : t={YYYYMMDD HH24:MI}, d={YYYYMMDD} p={" "}
        &avg  : default={1}, avg={nullif(SUM(GREATEST(exec,parse)),0)}
        @ver  : 11.2={} default={--}
        @ARGS : 1
    --]]
]]*/

ORA _sqlstat
col ela,ELA(Avg) format smhd2
col iowait,cpuwait,ccwait,clwait,apwait,plsql for pct1
Col buff,read,write,cellio,oflin,oflout format kmg

select time,sql_id,plan_hash,
       sum(exec)   exec,
       sum(parse)  parse,
       max(vers)  vers,
       count(1)    SEENS,
       sum(ela)    ELA,
       round(sum(ela)/nullif(decode(SUM(exec),0,floor(sum(parse)/greatest(sum(px_count),1)),sum(exec)),0),2) "ELA(Avg)",
       sum(iowait)/sum(ela) iowait,
       sum(cpuwait)/sum(ela) cpuwait,
       sum(ccwait)/sum(ela) ccwait,
       sum(clwait)/sum(ela) clwait,
       sum(apwait)/sum(ela)  apwait,
       sum(plsql)/sum(ela)  plsql,
       round(sum(buff)/&avg,2) buff,
       &ver round(sum(cellio)/&avg,2) cellio, round(sum(oflin)/&avg,2) oflin, round(sum(oflout)/&avg,2) oflout,
       round(sum(read)/&avg,2) read,
       round(sum(write)/&avg,2)  write,
       round(sum(rows#)/&avg,2) rows#,
       round(sum(fetches)/&avg,2) fetches,
       max(px_count) px
FROM(
    select /*+no_expand*/
           to_char(max(tim),'&TIM') time,sql_id,plan_hash,
           sum(exec)   exec,
           sum(parse)  parse,
           max(vers)  vers,
           count(1)    SEENS,
           sum(ela)    ELA,
           sum(iowait) iowait,
           sum(cpuwait) cpuwait,
           sum(ccwait) ccwait,
           sum(clwait) clwait,
           sum(apwait) apwait,
           max(px_count) px_count,
           sum(buff) buff,
           sum(read) read,
           sum(write) write,
           sum(cellio) cellio,
           sum(oflin) oflin,
           sum(oflout) oflout,
           sum(rows#) rows#,
           sum(fetches) fetches,
           sum(PLSQL) PLSQL
    from(
        select a.end_interval_time tim,
               a.sql_id,
               a.plan_hash_value plan_hash,
               a.executions EXEC,
               a.version_count vers,
               a.parse_calls parse,
               nvl(MIN(decode(executions,0,null,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN 0 FOLLOWING AND UNBOUNDED FOLLOWING),
                   MAX(decode(parse_calls,0,null,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN UNBOUNDED PRECEDING AND 0 PRECEDING)) snap_id,
               round(a.elapsed_time,2) ela,
               ROUND(a.iowait,2) iowait,
               ROUND(a.cpu_time,2) cpuwait,
               ROUND(a.ccwait,2) ccwait,
               ROUND(a.clwait,2) clwait,
               ROUND(a.apwait,2) apwait,
               a.px_servers_execs px_count,
               PLSEXEC_TIME+JAVEXEC_TIME PLSQL,
               cellio,oflin,oflout,
               greatest(disk_reads,phyread) READ,
               nvl(phywrite,direct_writes) WRITE,
               buffer_gets buff,
               a.rows_processed rows#,
               a.fetches
         from &awr$sqlstat  a
        WHERE :V1 in(sql_id,''||plan_hash_value,''||signature))
    group by snap_id,sql_id,plan_hash
    having sum(ela)>0)
 group by time,sql_id,plan_hash
 order by 1 desc