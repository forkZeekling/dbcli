/*[[Enable/Disable Trace: Usage: trace [<sql_id>|<SES-XXXXX>|<SYS-XXXXX>|<ORA-XXXXX>|<sid,serial#>|<event>|me|default] [trace_level]  ]]
    Trace specific SQL ID(11g+ only):  trace <sql_id>      [trace_level]
    Trace specific Session          :  trace <sid,serial>  [trace_level] -- Only able to trace the sid in local instance
    Trace specific ORA error        :  trace <ORA-XXXXX>   [trace_level] -- System level,ORA-00001(unique constraint violated) for example
    Trace session-level event       :  trace <SES-XXXXX>   [trace_level] -- SES-10046 for example, see "ora events" for more info
    Trace system-level event        :  trace <SYS-XXXXX>   [trace_level] -- SYS-10046 for example, see "ora events" for more info
    Trace this session(event 10046) :  trace me            [trace_level]
    Trace for a specific event      :  trace <event_name>  [trace_level]
    
    Parameter "trace_level"(default as 12 not specify):
        off or  0 :   turn off trace
        on  or  1 :   turn on with header or without binds/waits
                2 :   turn on with public header
                4 :   turn on with binds only
                8 :   turn on with waits only
                10:   turn on with full dump information 
                12:   turn on with binds/waits
                
    Availble values for <event_name> and related levels:
        buffers       : dump buffer header in SGA
        controlf      : dump control file
        locks         : dump LCK lock info
        redohdr       : dump redo header
        loghist       : dump historical items of control ifle
        file_hdrs     : dump all data file headers
        systemstate   : dump the system stats and processses
        processsate   : dump process stats
        coalesec      : dump free extents
        library_cache : dump libaray cache(1:stats,2:hash table histogram,3:object handle,4:obj struct(heap 0))
        heapdump      : dump sga/pga/uga(1:PGA header,2:SGA header,4:UGA header,8:current call,16:user call,32:large call,etc)
        global_area   : dump sga/pga/uga(1:PGA,2:SGA,4:UGA,8:indirect-memory)
        row_cache     : dump dictionary buffer cache(1:row cache stats,2:hash table histogram,3:obj struct)
        hanganalyze   : dump hange info
        latches       : dump latch info
        
        Others        : workareatab_dump,shared_server_state,treedump,errorstack,events
    --[[
        @check_ver1: 11.2={ ,plan_stat=>''all_executions''}, default={}
    --]]    
]]*/

set feed off
DECLARE
    target  VARCHAR2(100) := :V1;
    args    VARCHAR2(30)  := :V2;
    v_stmt  VARCHAR2(300);
    typ     VARCHAR2(30);
    lv      PLS_INTEGER;
    serial# PLS_INTEGER;

    PROCEDURE get_trace_file(p_sid INT) IS
    BEGIN
        FOR r IN (SELECT u_dump.value || '/' || SYS_CONTEXT('userenv', 'instance_name') || '_ora_' || p.spid ||
                          nvl2(p.traceid, '_' || p.traceid, NULL) || '.trc' fil, s.serial#
                  FROM   v$parameter u_dump
                  CROSS  JOIN v$process p
                  JOIN   v$session s
                  ON     p.addr = s.paddr
                  WHERE  u_dump.name = 'user_dump_dest'
                  AND    s.sid = p_sid) LOOP
            serial# := r.serial#;
            dbms_output.put_line('Target trace file is ' || r.fil);
        END LOOP;
    
        IF serial# IS NULL THEN
            raise_application_error(-20001, 'Cannot find session with sid = ' || p_sid || ' in local instance!');
        END IF;
    END;

    PROCEDURE check_int_arg(obj VARCHAR2) IS
    BEGIN
        lv := regexp_substr(NVL(obj, '12'), '^\d+$');
        IF upper(obj)='ON' then
            lv := 1;
        ELSIF upper(obj)='OFF' then
            lv := 0;
        ELSIF lv IS NULL THEN
            raise_application_error(-20001, 'Invalid data type of parameter "' || obj || '", number is expected!');
        END IF;
    END;
BEGIN
    check_int_arg(args);
    IF regexp_like(target, '^\d+,\d+$') THEN
        target := regexp_substr(target,'\d+');
        get_trace_file(target);
        IF lv>0 THEN
            v_stmt := 'BEGIN dbms_monitor.session_trace_enable('||target||', '||serial#||', case when '||BITAND(lv, 8)||' >0 then true else false end,case when '||BITAND(lv, 4)||' >0 then true else false end &check_ver1);END;';
        ELSE
            v_stmt := 'BEGIN dbms_monitor.session_trace_disable('||target||', '||serial#||');END;';
        END IF;
    ELSIF regexp_like(upper(target), '^ORA\-\d+$') THEN
        IF lv>0 THEN
            v_stmt := 'ALTER SYSTEM SET events = ''' || (0+regexp_substr(target, '\d+$')) || ' TRACE NAME ERRORSTACK LEVEL '||lv||'''';
        ELSE
            v_stmt := 'ALTER SYSTEM SET events = ''' || (0+regexp_substr(target, '\d+$')) || ' TRACE NAME ERRORSTACK OFF''';
        END IF;
    ELSIF upper(target) ='ME' OR regexp_like(UPPER(target), '^(SES|SYS)\-\d+$') THEN
        COMMIT;
        IF upper(target) ='ME' THEN 
            target := '10046';
            typ    := 'SESSION';
        ELSE
            typ    := CASE WHEN regexp_substr(upper(target),'^[^\-]+')='SES' THEN 'SESSION' ELSE 'SYSTEM' END;
            target := regexp_substr(target,'\d+$');
        END IF;
        IF lv>0 THEN
            IF typ='SESSION' THEN
                EXECUTE IMMEDIATE 'alter session set timed_statistics = true';
                EXECUTE IMMEDIATE 'alter session set tracefile_identifier=''' || ('dbcli' || round(dbms_random.value(10000, 99999))) || '''';
                get_trace_file(USERENV('sid'));
            END IF;
            v_stmt := 'alter '||typ||' set events = '''||target||' trace name context forever, level ' || lv || '''';
        ELSE
            IF typ='SESSION' THEN
                get_trace_file(USERENV('sid'));
                EXECUTE IMMEDIATE 'alter session set tracefile_identifier=''''';
            END IF;
            v_stmt := 'alter '||typ||' set events = '''||target||' trace name context off''';
        END IF;
    ELSIF regexp_like(target, '^\w+$') and length(target)=13 THEN
        IF lv>0 THEN
            v_stmt := 'ALTER SYSTEM SET events = ''sql_trace[SQL:' || target || '] {pgadep: exactdepth 0} {callstack: fname opiexe} plan_stat=all_executions, wait='||case when BITAND(lv, 8)>0 then 'true' else 'false' end ||',bind='||case when BITAND(lv, 4)>0 then 'true' else 'false' end ||'''';
        ELSE
            v_stmt := 'ALTER SYSTEM SET events = ''sql_trace[SQL:' || target || '] off''';
        END IF;
    ELSIF target IS NOT NULL THEN
        IF lv>0 THEN
            EXECUTE IMMEDIATE 'alter session set tracefile_identifier=''' || ('dbcli' || round(dbms_random.value(10000, 99999))) || '''';
            get_trace_file(USERENV('sid'));
            v_stmt := 'alter session set events ''immediate trace name '||target||' level ' || lv || '''';
        END IF;
    ELSE
        raise_application_error(-20001,'Please specify the trace options, type "ora -h trace" for more detail!');
    END IF;

    IF v_stmt IS NOT NULL THEN
        BEGIN
            IF LV>0 THEN dbms_output.put_line('Executing statement: ' || v_stmt); END IF;
            EXECUTE IMMEDIATE v_stmt;
            IF LV=0 THEN dbms_output.put_line('Executing statement: ' || v_stmt); END IF;
        EXCEPTION WHEN OTHERS THEN
            raise_application_error(-20001,sqlerrm||': '|| v_stmt);
        END;
    END IF;
END;
/