The Smartcard Financial Settlement System

Introduction
For the Assignment for Database Programming and Administration you are
required to write a Financial Settlement System (FSS) for a Smartcard Transaction
Centre.

The Deliverables for the Assignment are structured in a way to enable you to
achieve a mark that is related to the amount of work that you will contribute and
the level of knowledge that you have attained. The detailed marking structure can
be found at the rear of the document.

Overview

For some time now there has been a trial deployment of a Smartcard System in
various locations throughout the country. A number of different types of Smartcard
terminals have been deployed at selected sites. The types of terminals include
Parking Meters, Payphones, various Vending machines and ticketing machines at
selected railway stations. A number of Smartcard enabled terminals have also
been placed in selected retail outlets like Newsagents and University canteens
enabling the holders of the Smart cards to pay for their purchases using these
cards.

The term electronic cash is often used when talking about Smartcard transactions;
however the electronic cash needs to be converted to real cash so that the
merchants, accepting the cards as payment, can be reimbursed. During the trial
phase, the merchants were reimbursed manually, once a week. The settlement
amount calculations have been done by the staff in our IT department and the
merchants were sent a cheque for the amount of the settlement. During the initial
trial phase the merchants were not charged a fee on the Smartcard transactions.
The Smartcard System is moving into the next phase of deployment. The number
of merchants will be increased and there is a requirement to automate the
Settlement process. The payment to the Merchants will be done via a direct credit
into their nominated bank accounts and is to be done daily.
Each month the merchants will be charged a fee for the use of the Smartcard. The
fee to be charged will be a percentage of the total transactions for the month. The
actual amount is yet to be negotiated and it will be uniform for every transaction.
The fee collection will be done via a direct debit from the merchant bank account.
The merchant will also be sent a statement showing the money banked and the
fees charged for the month.
Your task is to write the application for the Smartcard Financial Settlement
System. You are required to only create the daily settlement system and
associated report. The application is to run in the Oracle Database and is to be
written using the PL*Sql language. 

The components of the application are
The Daily Settlement file and a corresponding report
A report to identify any potential fraud
System control using a RUN table
An email to a nominated recipient with the Banking report file as an attachment

The details of the application follow.
Daily Settlement
Deskbank File
The FSS system will be required to run daily and at the conclusion of the run, will
produce a banking file that will be known as a Deskbank file. The Deskbank file
will be sent to the designated banking organization electronically, most likely using
a secure FTP channel.
The Deskbank file, when run in the banking system will contain information
necessary to credit the merchants bank account with the amount collected by the
Smartcard transactions. The total of the deposits into the merchants accounts is to
be offset by a debit from our working bank account. The total of the deposits and
the debits is to reconcile to zero.
This file is intended to be read by the banks systems.
A sample Deskbank file and the file specification can be found in the Appendix
