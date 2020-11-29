create or replace package Pkg_FSS_Settlement as
PROCEDURE DailySettlement(p_date in date default sysdate);
PROCEDURE DailyBankingSummary(p_date in date default sysdate);
END Pkg_FSS_Settlement;
/
CREATE OR REPLACE PACKAGE BODY Pkg_FSS_Settlement as
v_runned BOOLEAN;
FUNCTION Reset_runned return boolean;
FUNCTION f_centre(p_text VARCHAR2) RETURN VARCHAR2;
PROCEDURE run_failed(p_methodName varchar2);
PROCEDURE insert_data_RunTable;
PROCEDURE get_new_records;
PROCEDURE to_Settle;
PROCEDURE send_email(p_date in date default sysdate);
PROCEDURE create_deskbank_file(p_date in date default sysdate);
PROCEDURE create_dailyBankingSummary(p_reportDate in date DEFAULT sysdate);
FUNCTION generate_lodgementref return varchar2;

FUNCTION Reset_runned return boolean IS
v_date date;
v_outcome varchar2(15);
Begin
    select max(RUNEND), max(RUNOUTCOME)into v_date, v_outcome from FSS_RUN_TABLE;
    if trunc(v_date)= trunc(sysdate) then
    v_runned := true;
    return v_runned;
    ELSE
    v_runned := false;
    return v_runned;
    END IF;
END;

PROCEDURE run_failed(p_methodname varchar2) IS
v_date date;
Begin
    select max(RUNSTART) into v_date from FSS_RUN_TABLE
    where TRUNC(v_date) = TRUNC(sysdate);
    update FSS_RUN_TABLE
        set RUNOUTCOME = 'Fail',
            REMARKS = p_methodname;
    commit;
END run_failed;

PROCEDURE insert_data_RunTable IS
Begin
        INSERT INTO FSS_RUN_TABLE(RUNID, RUNSTART, RUNEND, RUNOUTCOME, REMARKS)
        VALUES (generate_runID.nextval, sysdate, NULL, NULL, 'started');
        commit;
END insert_data_RunTable;

PROCEDURE get_new_records IS
BEGIN
    INSERT INTO FSS_DAILY_TRANSACTION(TRANSACTIONNR,
                                    DOWNLOADDATE,
                                    TERMINALID,
                                    CARDID,
                                    TRANSCATIONDATE,
                                    CARDOLDVALUE,
                                    TRANSACTIONAMOUNT,
                                    CARDNEWVALUE,
                                    TRANSACTIONSTATUS,
                                    ERRORCODE)
    select * from FSS_TRANSACTIONS
    where not exists (select FSS_DAILY_TRANSACTION.TRANSACTIONNR from FSS_DAILY_TRANSACTION 
                      where FSS_TRANSACTIONS.TRANSACTIONNR = FSS_DAILY_TRANSACTION.TRANSACTIONNR);
    commit;
EXCEPTION 
    WHEN OTHERS THEN 
        common.log('Procedure get_new_record failed.');
        run_failed('get_new_record');
END get_new_records;

PROCEDURE to_Settle IS
v_total_credit number :=0;
v_total_debit number :=0;
v_minsettle number;
v_org_account varchar2(10);
v_org_title varchar2(32);
v_org_bsb varchar2(6);
v_lodgementnum varchar2(15);
v_startday date;
v_number_of_record number := 0;
cursor c1 Is
    SELECT FSS_Merchant.MERCHANTBANKBSB bsb, 
                FSS_Merchant.MERCHANTBANKACCNR account,
                SUBSTR(FSS_Merchant.MERCHANTLASTNAME, 1, 32) Name,
                FSS_Merchant.MERCHANTID Merchantid,
                SUM(FSS_DAILY_TRANSACTION.TRANSACTIONAMOUNT) total_Amount
           FROM FSS_Merchant JOIN FSS_Terminal ON FSS_Merchant.MERCHANTID = FSS_Terminal.MERCHANTID 
           JOIN FSS_DAILY_TRANSACTION ON FSS_DAILY_TRANSACTION.TERMINALID = FSS_Terminal.TERMINALID
          WHERE LODGEMENTREF IS null 
          GROUP BY SUBSTR(FSS_Merchant.MERCHANTLASTNAME, 1, 32), FSS_Merchant.MERCHANTID, 
                   FSS_Merchant.MERCHANTBANKBSB, FSS_Merchant.MERCHANTBANKACCNR;
r1 c1%rowtype;
Begin
    select to_number(replace(REFERENCEVALUE,'.')) into v_minsettle from FSS_REFERENCE where referenceID='DMIN';
    for r1 in c1 loop
        v_number_of_record := v_number_of_record + 1;
        v_lodgementnum := generate_lodgementref;
        if r1.total_Amount > v_minsettle then
        v_total_credit := v_total_credit + r1.total_Amount;
        insert into FSS_DAILY_SETTLEMENT(LodgementRef, RecordType, bsb, transaction_code, credit, MerchantID, 
                                         USER_TITLE, Bankflag, Remitter, GSTTAX, Settle_Date, BANKACCOUNT,TOTAL_VALUE)
        values(v_lodgementnum, 1, r1.bsb, 50, r1.total_Amount, r1.MerchantID, r1.name, 'F',
               'SMARTCAD TRANS', '00000000', sysdate, r1.account, r1.total_Amount);
        update FSS_DAILY_TRANSACTION
        set FSS_DAILY_TRANSACTION.LodgementRef = v_lodgementnum
        where EXISTS(select r1.MerchantID from FSS_terminal
                     where FSS_DAILY_TRANSACTION.terminalID = FSS_terminal.terminalID
                     and FSS_terminal.merchantID = r1.MerchantID
                     and FSS_DAILY_TRANSACTION.lodgementRef is null);
        end if;
    end loop;
    v_total_debit := v_total_credit;
    v_lodgementnum := generate_lodgementref;
    select ORGBANKACCOUNT, ORGACCOUNTTITLE, ORGBSBNR into 
           v_org_account, v_org_title, v_org_bsb
    from FSS_ORGANISATION;
    insert into FSS_DAILY_SETTLEMENT(LodgementRef, RecordType, bsb, transaction_code, debit, 
                                         USER_TITLE, Bankflag, Remitter, GSTTAX, Settle_Date, BANKACCOUNT,total_value)
    values(v_lodgementnum, 1, v_org_bsb, 12, v_total_debit, v_org_title, 'N',
               'SMARTCAD TRANS', '00000000', sysdate, v_org_account,v_total_debit);
    select max(RUNSTART) into v_startday from FSS_RUN_TABLE;
    update FSS_RUN_TABLE
    set RUNEND = sysdate,
        RUNOUTCOME = 'Success',
        REMARKS = 'Completed'
        where trunc(v_startday) = trunc(sysdate);
    commit;
    EXCEPTION 
        WHEN OTHERS THEN 
            common.log('Procedure to_Settle failed.');
            run_failed('to_Settle');
END to_Settle;

procedure send_email(p_date in date default sysdate) IS
p_subject VARCHAR2(255) := 'DeskBank file report and daily summary report of '||to_char(p_date,'DD-MON-YYYY');
p_recipient VARCHAR2(50) := '283759218@qq.com';
p_sender VARCHAR2(50) := 'procedure@uts.edu.au';
p_message VARCHAR2(255);
v_attachment VARCHAR2(50) := '12803920_DSREP_'||to_char(p_date,'DDMMYYYY')||'.rpt';
v_mailhost VARCHAR2(50) := 'postoffice.uts.edu.au';
v_boundary_text VARCHAR2(25) := '--boundary text';
v_recipient VARCHAR2(80);
v_num_lines NUMBER := 0;
con_nl VARCHAR2(2) := CHR(13)||CHR(10);
con_email_footer VARCHAR2(250) := 'This is the email footer';
v_file utl_file.file_type;
mail_conn UTL_SMTP.connection;
Begin
mail_conn := UTL_SMTP.open_connection(v_mailhost,25);
UTL_SMTP.helo(mail_conn, v_mailhost);
UTL_SMTP.mail(mail_conn, p_sender);
UTL_SMTP.rcpt(mail_conn,p_recipient);
UTL_SMTP.open_data(mail_conn);
UTL_SMTP.write_data(mail_conn,'From :'||p_sender||con_nl);
UTL_SMTP.write_data(mail_conn,'To :'||p_recipient||con_nl);
UTL_SMTP.write_data(mail_conn,'Subject :'||p_subject||con_nl);
UTL_SMTP.write_data(mail_conn,v_boundary_text||con_nl);
UTL_SMTP.write_data(mail_conn,'Mime-Version: 1.0'||con_nl);
UTL_SMTP.write_data(mail_conn,'Content-type: text/plain; charset=us-ascii'||con_nl);
UTL_SMTP.write_data(mail_conn,con_nl||'Sent From the OMS Database by the PL/SQL application'||con_nl);
UTL_SMTP.write_data(mail_conn,'The report data is in the attached file'||con_nl||con_nl);
UTL_SMTP.write_data(mail_conn,'Regards'||con_nl);
UTL_SMTP.write_data(mail_conn,'The OMS Database'||con_nl||con_nl);
UTL_SMTP.write_data(mail_conn,con_nl||'This is an automatically generated email so please do not reply'||con_nl||con_nl);
UTL_SMTP.write_data(mail_conn,con_nl||v_boundary_text||con_nl);
UTL_SMTP.write_data(mail_conn,con_nl||'Content-Type: application/octet-stream; name='||'"'||v_attachment||'"'||con_nl);
UTL_SMTP.write_data(mail_conn,con_nl||'Content-Transfer-Encoding: 7bit'||con_nl);
v_file := UTL_FILE.FOPEN('HAOTIAN_DIR', v_attachment,'R');
while v_num_lines < 20
LOOP
    UTL_FILE.GET_LINE(v_file,p_message);
    UTL_SMTP.write_data(mail_conn, p_message||con_nl);
    v_num_lines := v_num_lines + 1;
END LOOP;
UTL_FILE.FCLOSE(v_file); 
UTL_SMTP.write_data(mail_conn,con_nl||'--'||v_boundary_text||'--'||con_nl);
UTL_SMTP.close_data(mail_conn);
UTL_SMTP.quit(mail_conn);
EXCEPTION
    WHEN OTHERS THEN
        common.log('Procedure send_email failed.');
        run_failed('send_email');
        UTL_SMTP.close_data(mail_conn);
END send_email;

PROCEDURE create_deskbank_file(p_date in date default sysdate) IS
v_credit number;
v_debit number;
v_number_of_records number :=0;
v_file UTL_FILE.FILE_TYPE;
v_fileline varchar2(255);
v_filename varchar2(255) := '12803920_DS_'||to_char(p_date,'DDMMYYYY')||'.dat';
cursor c2 IS
    select lodgementref, bsb, TRANSACTION_CODE, credit, debit, USER_TITLE, bankflag, GSTTAX, BANKACCOUNT, total_value
    from FSS_DAILY_SETTLEMENT
    where TRUNC(settle_date) = TRUNC(p_date);
r2 c2%rowtype;
Begin
v_file := UTL_FILE.FOPEN('HAOTIAN_DIR',v_filename,'W');
v_fileline := to_char(RPAD('0',18)||RPAD(two_dig_num.nextval||'WBS',12)||RPAD('S/CARD BUS PAYMENTS',26)||
                      RPAD('038759'||'INVOICES',12)||to_char(sysdate,'DDMMYY'));
UTL_FILE.PUT_LINE(v_file, v_fileline);
for r2 in c2 loop        
        v_fileline := to_char(RPAD('1'||substr(r2.bsb,1,3)||'-'||substr(r2.bsb,4,3)||r2.BANKACCOUNT,18)||
                      RPAD(r2.TRANSACTION_CODE||LPAD(r2.total_value,10,'0')||r2.USER_TITLE,44)||RPAD(r2.Bankflag,3)||' '||
                      r2.lodgementRef||'032-797 001006'||'SMARTCARD TRANS'||' '||r2.GSTTAX);
        utl_file.put_line(v_file, v_fileline);
        v_number_of_records := v_number_of_records + 1;
END loop;
v_fileline := to_char(RPAD('7999-999',20)||RPAD(v_credit-v_debit,10,'0')||LPAD(v_credit,10,'0')||
                      LPAD(v_debit,10,'0')||LPAD(LPAD(v_number_of_records,6,'0'),24));
utl_file.put_line(v_file, v_fileline);
utl_file.fclose(v_file);
EXCEPTION
    WHEN OTHERS THEN
        common.log('Procedure create_deskbank file failed.');
        run_failed('create_deskbank_file');
utl_file.fclose(v_file);
END create_deskbank_file;

FUNCTION generate_lodgementref return varchar2 IS
Begin
return to_char(to_char(sysdate,'YYYYMMDD')||LPAD(GET_LODGEMENT.NEXTVAL,7,'0'));
END generate_lodgementref;

FUNCTION f_centre(p_text VARCHAR2) RETURN VARCHAR2 IS
v_pageWidth NUMBER := 98;
v_textWidth NUMBER;
BEGIN
v_textWidth := LENGTH(p_text) / 2;
RETURN LPAD(p_text, (v_pageWidth/2) + v_textWidth, ' ');
END f_centre;

PROCEDURE create_dailyBankingSummary(p_reportDate in date DEFAULT sysdate) is
v_debit number :=0;
v_file UTL_FILE.FILE_TYPE;
v_fileline varchar2(255);
v_filename varchar2(255) := '12803920_DSREP_'||to_char(p_reportDate,'DDMMYYYY')||'.rpt';
cursor c3 IS
    select MerchantID, USER_TITLE, BSB, BANKACCOUNT, DEBIT, CREDIT
    from FSS_DAILY_SETTLEMENT
    where TRUNC(SETTLE_DATE) = TRUNC(p_reportDate);
r3 c3%rowtype;
Begin
select debit into v_debit
from FSS_DAILY_SETTLEMENT
where debit is not null
and TRUNC(SETTLE_DATE) = TRUNC(p_reportDate);
v_file := UTL_FILE.FOPEN('HAOTIAN_DIR',v_filename,'W');
utl_file.put_line(v_file, f_centre('SMARTCARD SETTLEMENT SYSTEM'));
utl_file.put_line(v_file, f_centre('DAILY DESKBANK SUMMARY'));
utl_file.put_line(v_file,'Date '||to_char(p_reportDate, 'DD-MON-YYYY')||LPAD('Page 1',69));
utl_file.put_line(v_file,' ');
v_fileline := RPAD('Merchant ID',13)||RPAD('Merchant Name',35)||RPAD('Acount Number', 20)||RPAD('Debit',6)|| LPAD('Credit',10);
utl_file.put_line(v_file,v_fileline);
v_fileline := RPAD('-',10,'-')||' '||RPAD('-',34,'-')||'  '||RPAD('-',17,'-')||' '||RPAD('-',10,'-')||'   '||RPAD('-',9,'-');
utl_file.put_line(v_file,v_fileline);
for r3 in c3 loop
    v_fileline := NVL(RPAD(r3.MerchantID,12),RPAD(' ',12))||RPAD(r3.USER_TITLE,35)||RPAD(substr(r3.bsb,1,3)||'-'||substr(r3.bsb,4,6)||r3.BANKACCOUNT,16)
                  ||NVL(LPAD(to_number(r3.Debit/100,'999999.99'),12),LPAD(' ',12))||NVL(LPAD(to_number(r3.credit/100,'999999.99'),11),LPAD(' ',11));
    utl_file.put_line(v_file,v_fileline);
END LOOP;
v_fileline := LPAD(LPAD('-',27,'-'),88);
utl_file.put_line(v_file,v_fileline);
v_fileline := 'BALANCE TOTAL'||LPAD(to_number(v_debit/100,'999999.99'),62)||LPAD(to_number(v_debit/100,'999999.99'),11);
utl_file.put_line(v_file,v_fileline);
utl_file.put_line(v_file,' ');
utl_file.put_line(v_file,' ');
utl_file.put_line(v_file,'Deskbank file Name : '||'<'||v_filename||'> ');
utl_file.put_line(v_file,'Dispatch Date      : '||to_char(sysdate,'DD MON YYYY'));
utl_file.put_line(v_file,f_centre('***** End of Report *****'));
utl_file.fclose(v_file);
END create_dailyBankingSummary;

PROCEDURE DailySettlement(p_date in date default sysdate) IS
Begin
if Reset_runned = false then
insert_data_RunTable;
get_new_records;
to_settle;
ELSE
dbms_output.put_line('Date has settled today.');
common.log('Date has settled today.' );
END IF;
create_deskbank_file(p_date);
END DailySettlement;

PROCEDURE DailyBankingSummary(p_date in date default sysdate) IS
Begin
create_dailyBankingSummary(p_date);
send_email(p_date);
END DailyBankingSummary;


END Pkg_FSS_Settlement;
/
--SELECT * FROM ALL_DIRECTORIES WHERE DIRECTORY_NAME='HAOTIAN';
