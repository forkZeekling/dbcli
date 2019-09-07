/*[[
  Show mutex sleep info. Usage: @@NAME [<sid>] [<inst_id>]
  Refer to Doc ID 1298015.1/1298471.1/1310764.1

  Mainly used to diagnostic below events:
  =======================================
  * cursor: mutex X                  
  * cursor: mutex S                  
  * cursor: pin X                    
  * cursor: pin S                    
  * cursor: pin S wait on X          
  * library cache: mutex X           
  * library cache: bucket mutex X    
  * library cache: dependency mutex X
  * library cache: mutex S           


  Example Output:
  ================
    INST_ID        LAST_TIME           HASH    SLEEPS CNT     LOCATION      MUTEX_TYPE   OBJECT
    ------- ----------------------- ---------- ------ --- ---------------- ------------- -------------------
          2 2019-09-03 23:56:10.107 1011610568     25  25 kglhdgn2 106     Library Cache select type#,blocks
          2 2019-09-03 23:56:10.108 1736623433      5   5 kglpndl1  95     Library Cache SEG$
          2 2019-09-03 23:56:10.108 1736623433      4   4 kgllkdl1  85     Library Cache SEG$
          2 2019-09-03 23:56:10.108 1736623433      3   2 kglpnal1  90     Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      3   2 kglget2   2      Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      2   2 kglpin1   4      Library Cache SEG$
          2 2019-09-03 23:56:10.107 1736623433      1   1 kglpnal2  91     Library Cache SEG$
          3 2019-09-03 23:27:39.394 1736623433      3   3 kglpndl1  95     Library Cache SEG$
    --[[
        &V2: default={&instance}
    --]]
]]*/

set feed off

SELECT DISTINCT *
FROM   TABLE(gv$(CURSOR ( --
          SELECT /*+ordered user_nl(b)*/
                  userenv('instance') inst_id,
                  sid,
                  a.event,
                  P1 HASH_VALUE,
                  decode(trunc(p3 / 4294967296), 0, trunc(p3 / 65536), trunc(p3 / 4294967296)) mutex_loc_id,
                  nullif(decode(trunc(p2 / 4294967296), 0, trunc(P2 / 65536), trunc(P2 / 4294967296)),0) holder_sid,
                  mod(p2,64436) refs,
                  a.sql_id,
                  c.location,
                  substr(TRIM(b.KGLNAOBJ), 1, 100) || CASE
                      WHEN b.KGLNAOBJ LIKE 'table_%' AND
                           regexp_like(regexp_substr(b.KGLNAOBJ, '[^\_]+', 1, 4), '^[0-9A-Fa-f]+$') THEN
                       ' (obj# ' || to_number(regexp_substr(b.KGLNAOBJ, '[^\_]+', 1, 4), 'xxxxxxxxxx') || ')'
                  END SQL_TEXT
          FROM   v$session a, x$kglob b, x$mutex_sleep c
          WHERE  a.p1 = b.kglnahsh
          AND    trunc(a.p3 / 65536) = c.location_id(+)
          AND    a.p1text = 'idn'
          AND    a.p2text = 'value'
          AND    a.p3text = 'where'
          AND    userenv('instance') = nvl(:V2, userenv('instance')))));



SELECT * FROM (
    SELECT *
    FROM   TABLE(gv$(CURSOR(
                      SELECT  /*+ordered use_hash(b)*/
                              DISTINCT 
                              userenv('instance') inst_id,
                              a.*,
                              substr(kglnaobj, 1, 100) OBJ
                      FROM   (
                          SELECT mutex_identifier HASH_VALUE,
                                 MAX(SLEEP_TIMESTAMP) LAST_TIME,
                                 SUM(sleeps) sleeps,
                                 COUNT(1) CNT,
                                 SUM(gets) gets,
                                 location_id l_id,
                                 location,
                                 mutex_type,
                                 p1raw
                          FROM   x$mutex_sleep_history
                          WHERE  userenv('instance') = nvl(:V2, userenv('instance'))
                          GROUP  BY mutex_identifier,location_id, location, mutex_type,p1raw
                      ) A,x$kglob b
                      WHERE a.HASH_VALUE=b.kglnahsh
                     )))
    ORDER  BY LAST_TIME DESC)
WHERE  rownum <= 50;
