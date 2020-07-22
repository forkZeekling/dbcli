/*[[Show session memory usage: @@NAME [<sid|spid>]
Refer to Tanel Poder's same script
    --[[
       Templates:
           @11g : 11.1={, pm.sql_id},10.0={}
    ]]--
]]*/

set feed off
col allocated,used,max_allocated,bytes for kmg

SELECT inst_id, SID, NAME,  VALUE bytes
FROM   TABLE(gv$(CURSOR (
            SELECT /*+no_expand use_hash(a b) no_merge(b) swap_join_inputs(b)*/ 
                   userenv('instance') inst_id, A.SID, A.VALUE,A.statistic#
            FROM   v$sesstat a, (select distinct sid from v$sql_workarea_active) b
            WHERE  a.sid = b.sid(+)
            AND    (:V1 IS NOT NULL AND :V1 = A.SID OR :V1 IS NULL AND b.sid IS NOT NULL)
            AND    VALUE > 0)))
JOIN   v$statname
USING  (statistic#)
WHERE   NAME LIKE '%memory%'
ORDER  BY inst_id, sid, NAME;

SELECT *
FROM   TABLE(gv$(CURSOR (
            SELECT /*+no_expand use_hash(s p pm a)*/
                   userenv('instance') inst_id,
                   s.sid,
                   p.spid,
                   pm.category,
                   allocated,used,max_allocated
            FROM   v$session s, v$process p, v$process_memory pm,(select distinct sid from v$sql_workarea_active) a
            WHERE  s.paddr = p.addr
            AND    p.pid = pm.pid
            AND    s.sid = a.sid(+)
            AND    (:V1 IS NOT NULL AND :V1 IN (s.sid, p.spid) OR :V1 IS NULL AND a.sid is not null))))
ORDER  BY inst_id, sid, category;

SELECT /*+no_expand use_hash(s p pm)*/
       s.inst_id,
       s.sid,
       p.spid,
       qcinst_id,
       qcsid 
       &11g
       ,pm.operation_type,
       pm.operation_id plan_line,
       pm.policy,
       ROUND(pm.active_time / 1000000, 1) active_sec,
       round(pm.actual_mem_used / 1024 / 1024, 2) act_mb_used,
       round(pm.max_mem_used / 1024 / 1024, 2) max_mb_used,
       round(pm.work_area_size / 1024 / 1024, 2) work_area_mb,
       pm.number_passes,
       pm.tempseg_size,
       pm.tablespace
FROM   gv$session s, gv$process p, gv$sql_workarea_active pm
WHERE  s.paddr = p.addr
AND    s.inst_id = p.inst_id
AND    s.sid = pm.sid
AND    pm.inst_id = s.inst_id
AND    (:V1 IS NULL OR :V1 IN (s.sid, p.spid))
ORDER  BY s.inst_id, s.sid;

