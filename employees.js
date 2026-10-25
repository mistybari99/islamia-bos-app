/* Islamia BOS · Employees (#/employees, #/employee/<id>, #/deeds): staff registration, pay structure, facilities, documents, roles and DEEDS.
   Server: supabase/phase41.sql - employee_save / employee_submit / employee_status_set / employee_locations_set / employee_link_profile / employee_set_photo / employee_dup_check /
   employee_doc_add / employee_doc_void / employee_pay_set (p_dry = preview) / employee_pay_current / employee_pay_history / employee_pay_account_get / leave_entitlement_set /
   employee_benefit_save / employee_benefits_list / deed_template_save / deed_template_retire / deed_save / deed_revise / deed_activate / deed_end / deed_expire_due / deeds_expiring.
   Screens: list (avatars, search, filters, summary, per-row menu) · registration wizard (Personal > Job > Pay & facilities > Documents & photo > Deed > Review; a draft is saved at every step) ·
   profile with tabs (Overview, Pay [only with the salary right], Facilities, Documents, Deeds, History) and print views (ID card, profile sheet, deed) · deeds screen (expiring deeds, templates, clause editor).
   Nothing is deleted: people are retired by status, pay is a new dated version, a deed changes through a revision. Photos use the private bucket 'photos' (prefix EMP/<place>/ portraits, EMPDOC/<place>/ documents). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H, nm } = A;
const L = B.L, lab = B.lab;
const U = B.s2;
const { money, nnum, rid, LOCS } = U;
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: L('কর্মচারী', 'Employees', 'Employees'), add: L('নতুন কর্মচারী', 'Add employee', 'নতুন Employee'), search: L('নাম / নম্বর / মোবাইল / NID', 'Name / no. / mobile / NID', 'Name / no. / mobile / NID'),
  filters: L('ফিল্টার', 'Filters', 'Filter'), all: L('সব', 'All', 'সব'), status: L('অবস্থা', 'Status', 'Status'), place: L('জায়গা', 'Place', 'Place'), role: L('রোল', 'Role', 'Role'), type: L('ধরন', 'Type', 'Type'),
  none: L('কেউ নেই', 'Nobody yet', 'কেউ নেই'), noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  s_draft: L('ড্রাফট', 'Draft', 'Draft'), s_active: L('কর্মরত', 'Active', 'Active'), s_on_leave: L('ছুটিতে', 'On leave', 'On leave'), s_resigned: L('পদত্যাগ', 'Resigned', 'Resigned'),
  s_terminated: L('বরখাস্ত', 'Terminated', 'Terminated'), s_retired: L('অবসর', 'Retired', 'Retired'), s_discarded: L('বাতিল ড্রাফট', 'Discarded draft', 'Discarded'),
  t_permanent: L('স্থায়ী', 'Permanent', 'Permanent'), t_contract: L('চুক্তিভিত্তিক', 'Contract', 'Contract'), t_daily: L('দৈনিক মজুরি', 'Daily wage', 'Daily wage'), t_part_time: L('খণ্ডকালীন', 'Part time', 'Part time'), t_trainee: L('শিক্ষানবিস', 'Trainee', 'Trainee'),
  open: L('খুলুন', 'Open', 'Open'), edit: L('তথ্য বদলান', 'Edit details', 'তথ্য বদলান'), addDeed: L('ডিড যোগ করুন', 'Add deed', 'Deed যোগ'), addDoc: L('কাগজ / ছবি যোগ', 'Add document', 'Document যোগ'),
  chStatus: L('অবস্থা বদলান', 'Change status', 'Status বদলান'), linkLogin: L('লগইন অ্যাকাউন্টের সাথে জুড়ুন', 'Link to login account', 'Login account-এর সাথে জুড়ুন'), copyMobile: L('মোবাইল কপি', 'Copy mobile', 'Mobile কপি'),
  copied: L('কপি হয়েছে', 'Copied', 'কপি হয়েছে'), back: L('পেছনে', 'Back', 'Back'), next: L('পরের ধাপ', 'Next', 'Next'), saveDraft: L('ড্রাফট রাখুন', 'Save draft', 'Draft রাখুন'), finish: L('নিবন্ধন সম্পন্ন', 'Finish registration', 'Registration সম্পন্ন'),
  save: L('সেভ', 'Save', 'Save'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'), done: L('হয়েছে', 'Done', 'Done'), preview: L('আগে দেখুন (কিছু লেখা হবে না)', 'Preview (nothing is saved)', 'আগে দেখুন (কিছু save হবে না)'), print: L('প্রিন্ট', 'Print', 'Print'),
  st0: L('ব্যক্তিগত', 'Personal', 'ব্যক্তিগত'), st1: L('কাজ', 'Job', 'কাজ'), st2: L('বেতন ও সুবিধা', 'Pay & facilities', 'বেতন ও সুবিধা'), st3: L('কাগজ ও ছবি', 'Documents & photo', 'কাগজ ও ছবি'), st4: L('ডিড', 'Deed', 'Deed'), st5: L('যাচাই', 'Review', 'Review'),
  nameBn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nameEn: L('নাম (ইংরেজি)', 'Name (English)', 'Name (English)'), nick: L('ডাকনাম', 'Nickname', 'ডাকনাম'), gender: L('লিঙ্গ', 'Gender', 'Gender'),
  male: L('পুরুষ', 'Male', 'Male'), female: L('নারী', 'Female', 'Female'), other: L('অন্যান্য', 'Other', 'Other'), dob: L('জন্ম ডেট', 'Date of birth', 'জন্ম date'), blood: L('রক্তের গ্রুপ', 'Blood group', 'Blood group'),
  marital: L('বৈবাহিক অবস্থা', 'Marital status', 'Marital status'), single: L('অবিবাহিত', 'Single', 'Single'), married: L('বিবাহিত', 'Married', 'Married'), divorced: L('বিবাহবিচ্ছিন্ন', 'Divorced', 'Divorced'), widowed: L('বিধবা / বিপত্নীক', 'Widowed', 'Widowed'),
  nid: L('জাতীয় পরিচয়পত্র (NID)', 'National ID (NID)', 'NID নম্বর'), mobile: L('মোবাইল', 'Mobile', 'Mobile'), email: L('ইমেইল', 'Email', 'Email'), present: L('বর্তমান ঠিকানা', 'Present address', 'বর্তমান ঠিকানা'),
  permanent: L('স্থায়ী ঠিকানা', 'Permanent address', 'স্থায়ী ঠিকানা'), emName: L('জরুরি যোগাযোগ - নাম', 'Emergency contact - name', 'জরুরি যোগাযোগ - নাম'), emRel: L('সম্পর্ক', 'Relation', 'সম্পর্ক'), emMob: L('জরুরি মোবাইল', 'Emergency mobile', 'জরুরি mobile'),
  edu: L('শিক্ষা', 'Education', 'শিক্ষা'), workPlace: L('কর্মস্থল (প্রধান)', 'Main work place', 'কর্মস্থল (প্রধান)'), otherPlaces: L('আরও যেখানে কাজ করতে পারেন', 'Other places they may work', 'আরও যেখানে কাজ করতে পারেন'),
  joining: L('যোগদানের ডেট', 'Joining date', 'যোগদানের date'), probEnd: L('শিক্ষানবিসকাল শেষ', 'Probation ends', 'Probation শেষ'), desig: L('পদবি', 'Designation', 'Designation'), dept: L('বিভাগ', 'Department', 'Department'),
  jobRole: L('প্রধান রোল (ডিডের জন্য)', 'Main role (for deeds)', 'প্রধান role (deed-এর জন্য)'), device: L('ফিঙ্গারপ্রিন্ট মেশিনের আইডি', 'Fingerprint device ID', 'Fingerprint device ID'), notes: L('নোট', 'Notes', 'Note'), otherTxt: L('অন্য পদবি লিখুন', 'Type another designation', 'অন্য designation লিখুন'),
  dupNid: L('এই NID আগেই আছে:', 'This NID already exists:', 'এই NID আগেই আছে:'), dupMob: L('এই মোবাইল আগেই আছে:', 'This mobile already exists:', 'এই mobile আগেই আছে:'),
  payHead: L('বেতন কাঠামো', 'Pay structure', 'বেতন কাঠামো'), effFrom: L('কার্যকর ডেট', 'Effective from', 'কার্যকর Date'), basis: L('বেতনের ভিত্তি', 'Pay basis', 'Pay basis'), monthly: L('মাসিক', 'Monthly', 'Monthly'), daily: L('দৈনিক', 'Daily', 'Daily'), hourly: L('ঘণ্টা', 'Hourly', 'Hourly'),
  basic: L('মূল বেতন', 'Basic', 'Basic'), allow: L('ভাতা', 'Allowance', 'Allowance'), deduct: L('কর্তন', 'Deduction', 'Deduction'), amount: L('টাকা', 'Amount', 'Amount'), pct: L('% (মূল বেতনের)', '% of basic', '% of basic'),
  otRule: L('ওভারটাইম', 'Overtime', 'Overtime'), otNone: L('নেই', 'None', 'নেই'), otRate: L('ঘণ্টায় নির্দিষ্ট টাকা', 'Fixed rate per hour', 'ঘণ্টায় fixed rate'), otMult: L('ঘণ্টার মজুরির গুণ (১.৫ / ২.০)', 'Multiple of hourly pay (1.5 / 2.0)', 'ঘণ্টার মজুরির গুণ (1.5 / 2.0)'),
  otVal: L('মান', 'Value', 'Value'), bonus: L('উৎসব বোনাস', 'Festival bonus', 'Festival bonus'), bName: L('নাম', 'Name', 'Name'), bMonths: L('মূল বেতনের কত মাস', 'Months of basic', 'Months of basic'), bMin: L('কমপক্ষে চাকরির মাস', 'Min. service months', 'Min. service months'),
  addBonus: L('＋ বোনাস', '＋ Bonus', '＋ Bonus'), gross: L('মোট (gross)', 'Gross', 'Gross'), net: L('হাতে (net)', 'Net', 'Net'), noPay: L('বেতন কাঠামো এখনো দেওয়া হয়নি', 'No pay structure yet', 'বেতন কাঠামো এখনো দেওয়া হয়নি'),
  saveRaise: L('নতুন কাঠামো সেভ', 'Save as new version', 'নতুন কাঠামো save'), noSalary: L('বেতন দেখা বা বদলানোর অনুমতি নেই', 'You are not allowed to see or set pay', 'বেতন দেখা বা বদলানোর permission নেই'),
  history: L('ইতিহাস', 'History', 'History'), leave: L('বছরে ছুটির দিন', 'Leave days per year', 'বছরে ছুটির দিন'), benefits: L('অন্যান্য সুবিধা', 'Other facilities', 'অন্যান্য সুবিধা'), benKind: L('ধরন', 'Kind', 'Kind'),
  benDesc: L('বিবরণ', 'Description', 'Description'), benVal: L('মাসে মূল্য', 'Value per month', 'Value per month'), addBen: L('＋ সুবিধা', '＋ Facility', '＋ Facility'), endBen: L('শেষ করুন', 'End', 'End'),
  portrait: L('ছবি', 'Portrait photo', 'Portrait photo'), camera: L('📷 ক্যামেরা', '📷 Camera', '📷 Camera'), gallery: L('🖼 গ্যালারি', '🖼 Gallery', '🖼 Gallery'), docKind: L('কাগজের ধরন', 'Document kind', 'Document kind'), noteL: L('নোট', 'Note', 'Note'),
  d_nid: L('NID', 'NID', 'NID'), d_contract: L('চুক্তিপত্র', 'Contract', 'Contract'), d_cv: L('জীবনবৃত্তান্ত (CV)', 'CV', 'CV'), d_certificate: L('সনদ', 'Certificate', 'Certificate'), d_guarantor: L('জামিনদারের কাগজ', 'Guarantor paper', 'Guarantor paper'), d_photo: L('ছবি', 'Photo', 'Photo'), d_other: L('অন্যান্য', 'Other', 'Other'),
  voidDoc: L('ভয়েড', 'Void', 'Void'), why: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (3+ letters)', 'কারণ লিখুন (কমপক্ষে ৩ অক্ষর)'), uploading: L('আপলোড হচ্ছে…', 'Uploading…', 'Uploading…'), needPlace: L('আগে কর্মস্থল বাছুন ও ড্রাফট রাখুন', 'Choose the work place and save the draft first', 'আগে কর্মস্থল বাছুন ও draft রাখুন'),
  deedsH: L('ডিড (চুক্তি / দায়িত্বপত্র)', 'Deeds', 'Deeds'), deedRole: L('রোল', 'Role', 'Role'), tpl: L('টেমপ্লেট', 'Template', 'Template'), blank: L('ফাঁকা (নিজে লিখব)', 'Blank (I will write it)', 'ফাঁকা (নিজে লিখব)'), titleL: L('শিরোনাম', 'Title', 'Title'),
  start: L('শুরু', 'Start', 'Start'), end: L('শেষ (ফাঁকা = অনির্দিষ্ট)', 'End (empty = open)', 'End (ফাঁকা = open)'), probDays: L('শিক্ষানবিসকাল (দিন)', 'Probation (days)', 'Probation (days)'), noticeDays: L('নোটিশ (দিন)', 'Notice (days)', 'Notice (days)'),
  deposit: L('জামানত (টাকা)', 'Security deposit', 'Security deposit'), gName: L('জামিনদারের নাম', 'Guarantor name', 'Guarantor name'), gMob: L('জামিনদারের মোবাইল', 'Guarantor mobile', 'Guarantor mobile'), gNid: L('জামিনদারের NID', 'Guarantor NID', 'Guarantor NID'),
  clauses: L('ধারাসমূহ', 'Clauses', 'Clauses'), addClause: L('＋ ধারা', '＋ Clause', '＋ Clause'), k_text: L('লেখা', 'Text', 'Text'), k_rule: L('নিয়ম', 'Rule', 'Rule'), k_amount: L('টাকার অঙ্ক', 'Amount', 'Amount'), k_duration: L('সময়কাল', 'Duration', 'Duration'),
  textBn: L('বাংলায় লিখুন', 'Text (Bangla)', 'বাংলায় লিখুন'), textEn: L('ইংরেজিতে লিখুন', 'Text (English)', 'English-এ লিখুন'), value: L('মান', 'Value', 'Value'), unit: L('একক', 'Unit', 'Unit'),
  saveDeed: L('ড্রাফট সেভ', 'Save draft deed', 'Draft deed save'), activate: L('কার্যকর করুন', 'Put in force', 'কার্যকর করুন'), revise: L('নতুন সংস্করণ', 'Revise', 'নতুন version'), endDeed: L('শেষ করুন', 'End deed', 'Deed শেষ'),
  dActive: L('কার্যকর', 'Active', 'Active'), dDraft: L('ড্রাফট', 'Draft', 'Draft'), dExpired: L('মেয়াদ শেষ', 'Expired', 'Expired'), dTerminated: L('বাতিল', 'Ended', 'Ended'), dSuperseded: L('নতুন সংস্করণ এসেছে', 'Superseded', 'Superseded'),
  rev: L('সংস্করণ', 'Revision', 'Revision'), signed: L('সইয়ের ডেট', 'Signed on', 'Signed on'), attach: L('সই করা কাগজ জুড়ুন', 'Attach signed paper', 'Signed paper জুড়ুন'),
  expiring: L('শেষ হতে চলেছে', 'Ending soon', 'শেষ হতে চলেছে'), daysLeft: L('দিন বাকি', 'days left', 'days left'), overdue: L('মেয়াদ পেরিয়েছে', 'Past its end', 'মেয়াদ পেরিয়েছে'), templates: L('ডিড টেমপ্লেট', 'Deed templates', 'Deed templates'),
  newTpl: L('＋ নতুন টেমপ্লেট', '＋ New template', '＋ নতুন template'), version: L('সংস্করণ', 'Version', 'Version'), retire: L('বন্ধ করুন', 'Retire', 'Retire'), reopen: L('আবার চালু', 'Reopen', 'Reopen'), noTpl: L('এখনো কোনো টেমপ্লেট নেই', 'No templates yet', 'এখনো কোনো template নেই'),
  tOverview: L('সারাংশ', 'Overview', 'Overview'), tPay: L('বেতন', 'Pay', 'Pay'), tFac: L('সুবিধা', 'Facilities', 'Facilities'), tDocs: L('কাগজ', 'Documents', 'Documents'), tDeeds: L('ডিড', 'Deeds', 'Deeds'), tHist: L('ইতিহাস', 'History', 'History'),
  idCard: L('আইডি কার্ড প্রিন্ট', 'Print ID card', 'ID card print'), profSheet: L('প্রোফাইল শিট প্রিন্ট', 'Print profile sheet', 'Profile sheet print'), reason: L('কারণ', 'Reason', 'Reason'), date: L('ডেট', 'Date', 'Date'),
  pickLogin: L('লগইন অ্যাকাউন্ট বাছুন', 'Choose a login account', 'Login account বাছুন'), unlink: L('সংযোগ খুলুন', 'Unlink', 'Unlink'), linked: L('জোড়া আছে', 'Linked', 'Linked'),
  review: L('যাচাই করে শেষ করুন', 'Check, then finish', 'যাচাই করে শেষ করুন'), regDone: L('নিবন্ধন হয়েছে', 'Registered', 'Registered'), mustName: L('নাম ও কর্মস্থল লাগবে', 'Name and work place are required', 'নাম ও কর্মস্থল লাগবে'),
  sumNo: L('নম্বর', 'No.', 'No.'), joinedOn: L('যোগদান', 'Joined', 'Joined'), bank: L('ব্যাংক অ্যাকাউন্ট', 'Bank account', 'Bank account'), wallet: L('মোবাইল ওয়ালেট', 'Mobile wallet', 'Mobile wallet'),
  expiresIn: L('ডিড শেষ হবে', 'Deed ends', 'Deed শেষ'), makeFirst: L('আগে ব্যক্তিগত ধাপ সেভ করুন', 'Save the personal step first', 'আগে personal step save করুন'), deedNote: L('ডিড কার্যকর করতে ডিড-অনুমতি লাগে; ড্রাফট এখানেই রাখা যায়।', 'Putting a deed in force needs the deed right; a draft can be kept here.', 'Deed কার্যকর করতে deed-permission লাগে; draft এখানেই রাখা যায়।'),
};
const T = (k) => lab(X[k]);
const ST = ['active', 'on_leave', 'resigned', 'terminated', 'retired', 'draft'];
const TYPES = ['permanent', 'contract', 'daily', 'part_time', 'trainee'];
const DOCK = ['nid', 'contract', 'cv', 'certificate', 'guarantor', 'other'];
const BENK = ['meal', 'uniform', 'accommodation', 'transport', 'phone', 'insurance', 'other'];
const BENL = { meal: L('খাবার', 'Meals', 'Meals'), uniform: L('ইউনিফর্ম', 'Uniform', 'Uniform'), accommodation: L('থাকা', 'Accommodation', 'Accommodation'), transport: L('যাতায়াত', 'Transport', 'Transport'), phone: L('ফোন', 'Phone', 'Phone'), insurance: L('বীমা', 'Insurance', 'Insurance'), other: L('অন্যান্য', 'Other', 'Other') };
const PRESETS = [['allowance', 'House rent', L('বাড়ি ভাড়া', 'House rent', 'House rent')], ['allowance', 'Medical', L('চিকিৎসা', 'Medical', 'Medical')], ['allowance', 'Transport', L('যাতায়াত', 'Transport', 'Transport')],
  ['allowance', 'Food', L('খাবার', 'Food', 'Food')], ['allowance', 'Mobile', L('মোবাইল', 'Mobile', 'Mobile')], ['allowance', 'Tiffin', L('টিফিন', 'Tiffin', 'Tiffin')],
  ['deduction', 'Provident fund', L('প্রভিডেন্ট ফান্ড', 'Provident fund', 'Provident fund')], ['deduction', 'Insurance', L('বীমা কিস্তি', 'Insurance', 'Insurance')]];
const ERR = {
  not_allowed: X.noperm, module_off: L('কর্মচারী নিবন্ধন এখন বন্ধ (সুইচবোর্ডে)', 'Employee registration is switched off (Switchboard)', 'Employee registration এখন বন্ধ (Switchboard-এ)'),
  name_required: L('নাম লিখুন', 'Write the name', 'নাম লিখুন'), location_required: L('কর্মস্থল বাছুন', 'Choose the work place', 'কর্মস্থল বাছুন'), bad_location: L('কর্মস্থল ঠিক নয়', 'Work place is not valid', 'কর্মস্থল ঠিক নয়'),
  bad_mobile: L('মোবাইল নম্বর ঠিক নয় (01XXXXXXXXX)', 'Mobile number is not valid (01XXXXXXXXX)', 'Mobile number ঠিক নয় (01XXXXXXXXX)'), bad_nid: L('NID ১০, ১৩ বা ১৭ অঙ্কের হতে হবে', 'NID must be 10, 13 or 17 digits', 'NID ১০, ১৩ বা ১৭ digit হতে হবে'),
  bad_date: L('ডেট ঠিক নয়', 'Date is not valid', 'Date ঠিক নয়'), bad_email: L('ইমেইল ঠিক নয়', 'Email is not valid', 'Email ঠিক নয়'), too_long: L('লেখা অনেক বড়', 'Text is too long', 'Text অনেক বড়'),
  duplicate_nid: L('এই NID-এর কর্মচারী আগেই আছে', 'An employee with this NID already exists', 'এই NID-এর employee আগেই আছে'), duplicate_mobile: L('এই মোবাইল অন্য কর্মচারীর', 'This mobile belongs to another employee', 'এই mobile অন্য employee-র'),
  duplicate_device_id: L('এই মেশিন-আইডি অন্যজনের', 'This device ID belongs to someone else', 'এই device ID অন্যজনের'), bad_role: L('রোল ঠিক নয়', 'Role is not valid', 'Role ঠিক নয়'),
  joining_date_required: L('যোগদানের ডেট দিন', 'Enter the joining date', 'Joining date দিন'), designation_required: L('পদবি দিন', 'Enter the designation', 'Designation দিন'),
  reason_required: L('কারণ লিখুন', 'Write a reason', 'কারণ লিখুন'), owner_only: L('শুধু মালিক ফিরিয়ে আনতে পারেন', 'Only the owner can bring a person back', 'শুধু owner ফিরিয়ে আনতে পারেন'), same_status: L('এই অবস্থাই আছে', 'Already in this status', 'এই status-ই আছে'),
  profile_already_linked: L('এই লগইন অন্য কর্মচারীর সাথে জোড়া', 'This login is linked to another employee', 'এই login অন্য employee-র সাথে জোড়া'), bad_amount: L('টাকার অঙ্ক ঠিক নয়', 'Amount is not valid', 'Amount ঠিক নয়'),
  bad_ot_value: L('ওভারটাইমের মান ঠিক নয়', 'Overtime value is not valid', 'Overtime value ঠিক নয়'), deductions_exceed_gross: L('কর্তন মোটের চেয়ে বেশি', 'Deductions are more than gross pay', 'কর্তন মোটের চেয়ে বেশি'),
  duplicate_component: L('একই নামের দুটি লাইন', 'Two lines with the same name', 'একই নামের দুটি line'), component_amount_or_percent: L('টাকা বা % - যেকোনো একটি দিন', 'Give an amount or a % - one of them', 'Amount বা % - যেকোনো একটি'),
  bad_bonus: L('বোনাসের তথ্য ঠিক নয়', 'Bonus data is not valid', 'Bonus data ঠিক নয়'), bad_path: L('ফাইলের জায়গা ঠিক নয়', 'File location is not valid', 'File location ঠিক নয়'),
  active_deed_exists: L('এই রোলে আগেই একটি কার্যকর ডিড আছে - নতুন সংস্করণ করুন', 'An active deed for this role exists - make a revision', 'এই role-এ আগেই active deed আছে - revision করুন'),
  deed_not_draft: L('কার্যকর ডিড বদলানো যায় না - নতুন সংস্করণ করুন', 'An active deed cannot be edited - make a revision', 'Active deed বদলানো যায় না - revision করুন'),
  start_date_required: L('শুরুর ডেট দিন', 'Enter the start date', 'Start date দিন'), clauses_required: L('অন্তত একটি ধারা লিখুন', 'Write at least one clause', 'অন্তত একটি clause লিখুন'),
  clause_text_required: L('প্রতিটি ধারায় লেখা চাই', 'Every clause needs text', 'প্রতিটি clause-এ text চাই'), bad_clause_value: L('টাকা/সময়ের মান সংখ্যা হতে হবে', 'Amount / duration value must be a number', 'Amount / duration value সংখ্যা হতে হবে'),
  employee_not_working: L('এই ব্যক্তি আর কর্মরত নন', 'This person no longer works here', 'এই ব্যক্তি আর কর্মরত নন'), revision_already_open: L('একটি নতুন সংস্করণ আগেই খোলা আছে', 'A revision is already open', 'একটি revision আগেই খোলা আছে'),
  template_role_mismatch: L('টেমপ্লেট অন্য রোলের', 'The template is for another role', 'Template অন্য role-এর'), bad_title: L('শিরোনাম লিখুন', 'Enter a title', 'Title লিখুন'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : (m || 'error'); };
const stL = (s) => T('s_' + s);
const stCls = (s) => (s === 'active' ? 'ok' : s === 'on_leave' || s === 'draft' ? 'warn' : s === 'resigned' || s === 'terminated' || s === 'retired' ? 'bad' : '');
const EMP_COLS = 'id,employee_no,full_name_bn,full_name_en,nickname,photo_path,gender,date_of_birth,blood_group,nid_no,mobile,email,present_address,permanent_address,emergency_name,emergency_relation,emergency_mobile,marital_status,education,joining_date,probation_end,designation,department,primary_location_id,primary_role_code,employment_type,status,status_date,status_reason,profile_id,device_user_id,notes';
const D = { base: null, rows: [], q: '', fs: '', fl: '', fr: '', ft: '', urls: {}, caps: {} };
const W = { id: null, client: rid(), step: 0, d: {}, locs: [], pay: {}, comps: [], bonus: [], leave: {}, ben: [], docs: [], photo: null, deed: {}, dupes: null, paySaved: false };
const C = { rows: [], ctx: null };

async function can(code, loc) {
  if (S.ctx.is_owner) return true;
  const k = code + '|' + (loc == null ? '' : loc); if (k in D.caps) return D.caps[k];
  let v = false;
  if (loc != null) v = await U.grant(code, loc); else for (const l of LOCS()) { if (await U.grant(code, l.id)) { v = true; break; } }
  D.caps[k] = v; return v;
}
async function base() {
  if (D.base) return D.base;
  const [r, o, lv] = await Promise.all([sb.from('staff_roles').select('code,name_bn,name_en,major,active,sort').order('sort'),
    sb.from('option_lists').select('list_code,value_code,label_bn,label_en,active,sort').in('list_code', ['emp_designation', 'emp_department']).order('sort'),
    sb.from('leave_types').select('code,name_bn,name_en,paid,default_days,active,sort').order('sort')]);
  const ol = (o.data || []).filter((x) => x.active !== false);
  D.base = { roles: (r.data || []).filter((x) => x.active !== false), desig: ol.filter((x) => x.list_code === 'emp_designation'), dept: ol.filter((x) => x.list_code === 'emp_department'), leave: (lv.data || []).filter((x) => x.active !== false) };
  return D.base;
}
const bl = (o) => (S.lang === 'en' ? (o.label_en || o.label_bn) : o.label_bn);
const rl = (o) => (S.lang === 'en' ? (o.name_en || o.name_bn) : o.name_bn);
const locName = (id) => { const l = ((B.ENV && B.ENV.locs) || []).find((x) => x.id === id); return l ? nm(l) : ''; };
const roleName = (code) => { const r = D.base && D.base.roles.find((x) => x.code === code); return r ? rl(r) : (code || ''); };
const desigName = (v) => { const o = D.base && D.base.desig.find((x) => x.value_code === v); return o ? bl(o) : (v || ''); };
const deptName = (v) => { const o = D.base && D.base.dept.find((x) => x.value_code === v); return o ? bl(o) : (v || ''); };
const ename = (e) => (S.lang === 'en' && e.full_name_en ? e.full_name_en : e.full_name_bn);
const initials = (e) => esc(String(ename(e) || '?').trim().slice(0, 1).toUpperCase());
const fld = (id, label, val, attrs = '') => `<div><label for="${id}">${esc(label)}</label><input id="${id}" value="${esc(val == null ? '' : val)}" autocomplete="off" ${attrs}></div>`;
const dfld = (id, label, val) => fld(id, label, val, 'type="date"');
const sel = (id, label, opts, val, attrs = '') => `<div>${label ? `<label for="${id}">${esc(label)}</label>` : ''}<select id="${id}" ${attrs}>${opts.map(([v, t]) => `<option value="${esc(v)}" ${String(v) === String(val == null ? '' : val) ? 'selected' : ''}>${esc(t)}</option>`).join('')}</select></div>`;
const val = (id) => { const el = $('#' + id); return el ? el.value.trim() : ''; };
const locOpts = (blank) => [...(blank ? [['', '—']] : []), ...LOCS().map((l) => [l.id, nm(l)])];
async function urlsFor(paths) {
  const need = paths.filter((p) => p && !D.urls[p]); if (!need.length) return;
  try { const r = await sb.storage.from('photos').createSignedUrls(need, 3600); (r && r.data || []).forEach((x) => { if (x && x.signedUrl) D.urls[x.path || need[(r.data || []).indexOf(x)]] = x.signedUrl; }); } catch (e) { /* pictures are optional */ }
}
const avatar = (e, cls = '') => (e.photo_path && D.urls[e.photo_path] ? `<img class="em-av ${cls}" alt="" src="${esc(D.urls[e.photo_path])}">` : `<span class="em-av ${cls}" aria-hidden="true">${initials(e)}</span>`);
const css = document.createElement('style'); css.id = 'emcss';
css.textContent = `.em-av{width:44px;height:44px;border-radius:50%;object-fit:cover;flex:none;display:inline-flex;align-items:center;justify-content:center;background:var(--hair);color:var(--muted);font-weight:700;border:1px solid var(--hair)}
.em-av.big{width:72px;height:72px;font-size:1.5rem}.em-row{display:flex;align-items:center;gap:10px}.em-row .nm{overflow-wrap:anywhere}.em-row .grow{flex:1;min-width:0}
.em-sum{display:flex;gap:6px;flex-wrap:wrap;margin:8px 0}.em-kv{display:flex;justify-content:space-between;gap:10px;padding:6px 0;border-bottom:1px solid var(--hair);font-size:.9rem}.em-kv span:first-child{color:var(--muted)}.em-kv b{text-align:end;overflow-wrap:anywhere}
.em-steps{display:flex;gap:4px;margin:6px 0 10px}.em-steps i{flex:1;height:5px;border-radius:3px;background:var(--hair)}.em-steps i.on{background:var(--sig-ok,#2a7)}.em-warn{color:var(--sig-bad);font-size:.85rem;overflow-wrap:anywhere}
.em-line{display:grid;grid-template-columns:1fr 1fr;gap:6px;padding:8px 0;border-bottom:1px solid var(--hair)}.em-line .wide{grid-column:1/-1}.em-bar{position:sticky;bottom:0;display:flex;gap:8px;padding:10px 0;background:var(--bg);border-top:1px solid var(--hair);margin-top:12px}.em-bar button{flex:1}
.em-card{width:85.6mm;height:54mm;border:1px solid #333;border-radius:3mm;padding:3mm;display:flex;gap:3mm;align-items:center;color:#000;background:#fff;font-size:11px}.em-card img,.em-card .em-av{width:22mm;height:26mm;border-radius:2mm}
.em-paper{color:#000;background:#fff;padding:8px;font-size:12px}.em-paper h2{margin:0 0 6px}.em-paper .em-kv span:first-child{color:#444}.em-paper ol{padding-inline-start:18px}.em-sign{display:flex;justify-content:space-between;margin-top:36px}.em-sign div{border-top:1px solid #000;padding-top:4px;min-width:35%;text-align:center}
#em_print{display:none}@media print{body>*:not(#em_print){display:none!important}#em_print{display:block!important}}`;
document.head.appendChild(css);

// ---------------- list ----------------
async function loadList() {
  const r = await sb.from('employees').select('id,employee_no,full_name_bn,full_name_en,nickname,photo_path,mobile,nid_no,designation,department,primary_location_id,primary_role_code,employment_type,status,status_date,joining_date,profile_id').neq('status', 'discarded').order('employee_no', { ascending: true });
  D.rows = r.error ? [] : (r.data || []);
  await urlsFor(D.rows.map((e) => e.photo_path));
}
const matches = (e) => {
  const q = D.q.toLowerCase().replace(/[\s-]/g, '');
  if (q && ![e.full_name_bn, e.full_name_en, e.nickname, e.employee_no, e.mobile, e.nid_no].some((x) => String(x || '').toLowerCase().replace(/[\s-]/g, '').includes(q))) return false;
  return (!D.fs || e.status === D.fs) && (!D.fl || String(e.primary_location_id) === D.fl) && (!D.fr || e.primary_role_code === D.fr) && (!D.ft || e.employment_type === D.ft);
};
function listHTML() {
  const rows = D.rows.filter(matches), cnt = (f) => D.rows.filter(f).length;
  const sum = `<div class="em-sum"><span class="chip ok">${esc(T('s_active'))} ${cnt((e) => e.status === 'active')}</span><span class="chip warn">${esc(T('s_on_leave'))} ${cnt((e) => e.status === 'on_leave')}</span>
    <span class="chip bad">${esc(T('s_resigned'))}/${esc(T('s_terminated'))}/${esc(T('s_retired'))} ${cnt((e) => ['resigned', 'terminated', 'retired'].includes(e.status))}</span><span class="chip">${esc(T('s_draft'))} ${cnt((e) => e.status === 'draft')}</span></div>`;
  const body = rows.length ? rows.map((e) => `<div class="card em-row" data-emid="${esc(e.id)}">${avatar(e)}<a class="grow" href="#/employee/${esc(e.id)}"><div class="nm"><b>${esc(ename(e))}</b> <span class="muted">${esc(e.employee_no || T('s_draft'))}</span></div>
      <div class="muted">${esc(desigName(e.designation))}${e.designation ? ' · ' : ''}${esc(locName(e.primary_location_id))}${e.mobile ? ' · ' + esc(e.mobile) : ''}</div></a>
      <span class="chip ${stCls(e.status)}">${esc(stL(e.status))}</span><button class="mini" data-act="em_menu" data-v="${esc(e.id)}" aria-label="⋮">⋮</button></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  return sum + body;
}
function listFilters() {
  const b = D.base;
  return `<details class="card" data-ctl="off"><summary>${esc(T('filters'))}</summary><div class="stack">
    ${sel('em_fs', T('status'), [['', T('all')], ...ST.map((s) => [s, stL(s)])], D.fs)}${sel('em_fl', T('place'), [['', T('all')], ...locOpts()], D.fl)}
    ${sel('em_fr', T('role'), [['', T('all')], ...b.roles.map((r) => [r.code, rl(r)])], D.fr)}${sel('em_ft', T('type'), [['', T('all')], ...TYPES.map((s) => [s, T('t_' + s)])], D.ft)}</div></details>`;
}
async function listView() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), `<div class="row"><input id="em_q" placeholder="${esc(T('search'))}" value="${esc(D.q)}" autocomplete="off" aria-label="${esc(T('search'))}"><button class="primary" data-act="em_new">＋ ${esc(T('add'))}</button><a class="mini" href="#/deeds" aria-label="${esc(T('deedsH'))}" style="display:inline-flex;align-items:center;justify-content:center">📜</a></div>
    <div id="em_filters"></div><div id="em_list"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  try { await base(); $('#em_filters').innerHTML = listFilters(); await loadList(); $('#em_list').innerHTML = listHTML(); } catch (e) { fail(e); }
}
function redrawList() { const el = $('#em_list'); if (el) el.innerHTML = listHTML(); }

// ---------------- row menu ----------------
async function menu(id) {
  const e = D.rows.find((x) => x.id === id) || (await sb.from('employees').select(EMP_COLS).eq('id', id).maybeSingle()).data; if (!e) return;
  const mg = await can('employee_manage', e.primary_location_id);
  const b = (act, label, extra = '') => `<button class="full" data-act="${act}" data-v="${esc(id)}" ${extra}>${esc(label)}</button>`;
  openSheet(`<div class="stack"><div class="em-row">${avatar(e)}<div><b>${esc(ename(e))}</b><div class="muted">${esc(e.employee_no || T('s_draft'))}</div></div></div>
    <a class="full" href="#/employee/${esc(id)}" data-act="closesheet">${esc(T('open'))}</a>
    ${mg ? b('em_edit', T('edit')) + b('em_adddeed', T('addDeed')) + b('em_adddoc', T('addDoc')) + b('em_status', T('chStatus')) + b('em_link', T('linkLogin')) : ''}
    ${e.mobile ? b('em_copy', T('copyMobile'), `data-m="${esc(e.mobile)}"`) : ''}</div>`);
}

// ---------------- wizard ----------------
const STEPS = ['st0', 'st1', 'st2', 'st3', 'st4', 'st5'];
const PERSONAL = ['full_name_bn', 'full_name_en', 'nickname', 'gender', 'date_of_birth', 'blood_group', 'marital_status', 'nid_no', 'mobile', 'email', 'present_address', 'permanent_address', 'emergency_name', 'emergency_relation', 'emergency_mobile', 'education'];
const BIDS = { full_name_bn: 'nameBn', full_name_en: 'nameEn', nickname: 'nick', nid_no: 'nid', mobile: 'mobile', email: 'email', present_address: 'present', permanent_address: 'permanent', emergency_name: 'emName', emergency_relation: 'emRel', emergency_mobile: 'emMob', education: 'edu' };
function wizStart(row) {
  Object.assign(W, { id: row ? row.id : null, client: rid(), step: 0, d: row ? { ...row } : {}, locs: [], pay: {}, comps: [], bonus: [], leave: {}, ben: [], docs: [], photo: row ? row.photo_path : null, deed: {}, dupes: null, paySaved: false, existing: !!row, canPay: false, canSeePay: false });
}
function collectStep() {
  const s = W.step, d = W.d;
  if (s === 0) { PERSONAL.forEach((k) => { const el = $('#w_' + k); if (el) d[k] = el.value.trim(); }); const p = $('#w_primary_location_id'); if (p) d.primary_location_id = p.value; }
  if (s === 1) { ['joining_date', 'probation_end', 'employment_type', 'department', 'primary_role_code', 'device_user_id', 'notes'].forEach((k) => { const el = $('#w_' + k); if (el) d[k] = el.value.trim(); });
    const ds = $('#w_designation'); if (ds) d.designation = ds.value === '__other' ? val('w_designation_txt') : ds.value; W.locs = $$('.w_loc:checked').map((x) => Number(x.value)); }
}
function payload() { const d = {}; const keys = W.step === 0 ? [...PERSONAL, 'primary_location_id'] : ['joining_date', 'probation_end', 'employment_type', 'designation', 'department', 'primary_role_code', 'device_user_id', 'notes'];
  keys.forEach((k) => { if (k in W.d) { const v = W.d[k]; d[k] = v === '' ? null : v; } }); if (d.primary_location_id != null) d.primary_location_id = Number(d.primary_location_id); if (d.employment_type == null && 'employment_type' in d) delete d.employment_type; return d; }
async function saveStep() {
  collectStep();
  if (W.step > 1) return true;
  if (W.step === 0 && (!W.d.full_name_bn || !W.d.primary_location_id)) { toast(T('mustName')); return false; }
  const r = await sb.rpc('employee_save', { p_id: W.id, p_client: W.id ? null : W.client, p_data: payload(), p_dry: false });
  if (r.error) { toast(eText(r.error)); return false; }
  W.id = r.data.id; W.d.employee_no = r.data.employee_no; W.d.status = r.data.status;
  if (W.step === 1) { const q = await sb.rpc('employee_locations_set', { p_id: W.id, p_locs: W.locs.filter((l) => l !== Number(W.d.primary_location_id)) }); if (q.error) { toast(eText(q.error)); return false; } }
  const w = r.data.warnings && r.data.warnings.mobile; if (w && w.length) toast(lab(X.dupMob) + ' ' + w.map((x) => x.name).join(', '));
  return true;
}
const stepBar = () => `<div class="em-steps" aria-hidden="true">${STEPS.map((_, i) => `<i class="${i <= W.step ? 'on' : ''}"></i>`).join('')}</div><h3>${W.step + 1}/6 · ${esc(T(STEPS[W.step]))}</h3>`;
function personalHTML() {
  const d = W.d, g = (k, a) => fld('w_' + k, T(BIDS[k]), d[k], a || '');
  return `<div class="stack">${sel('w_primary_location_id', T('workPlace'), locOpts(true), d.primary_location_id)}${g('full_name_bn')}${g('full_name_en')}${g('nickname')}
    ${sel('w_gender', T('gender'), [['', '—'], ['male', T('male')], ['female', T('female')], ['other', T('other')]], d.gender)}${dfld('w_date_of_birth', T('dob'), d.date_of_birth)}
    ${sel('w_blood_group', T('blood'), [['', '—'], ...['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'].map((x) => [x, x])], d.blood_group)}
    ${sel('w_marital_status', T('marital'), [['', '—'], ...['single', 'married', 'divorced', 'widowed'].map((x) => [x, T(x)])], d.marital_status)}
    ${g('nid_no', 'inputmode="numeric"')}${g('mobile', 'inputmode="tel"')}<div id="w_dup" class="em-warn" role="status"></div>${g('email', 'type="email"')}${g('present_address')}${g('permanent_address')}
    ${g('emergency_name')}${g('emergency_relation')}${g('emergency_mobile', 'inputmode="tel"')}${g('education')}</div>`;
}
function jobHTML() {
  const d = W.d, b = D.base, dsel = d.designation && !b.desig.some((x) => x.value_code === d.designation);
  return `<div class="stack">${dfld('w_joining_date', T('joining'), d.joining_date)}${dfld('w_probation_end', T('probEnd'), d.probation_end)}
    ${sel('w_employment_type', T('type'), TYPES.map((x) => [x, T('t_' + x)]), d.employment_type || 'permanent')}
    ${sel('w_designation', T('desig'), [['', '—'], ...b.desig.map((x) => [x.value_code, bl(x)]), ['__other', T('other')]], dsel ? '__other' : d.designation)}
    <div id="w_dtxtw" ${dsel ? '' : 'hidden'}>${fld('w_designation_txt', T('otherTxt'), dsel ? d.designation : '')}</div>
    ${sel('w_department', T('dept'), [['', '—'], ...b.dept.map((x) => [x.value_code, bl(x)])], d.department)}${sel('w_primary_role_code', T('jobRole'), [['', '—'], ...b.roles.map((r) => [r.code, rl(r)])], d.primary_role_code)}
    ${fld('w_device_user_id', T('device'), d.device_user_id)}
    <div><label>${esc(T('otherPlaces'))}</label><div class="row wrap" data-ctl="off">${LOCS().filter((l) => String(l.id) !== String(d.primary_location_id)).map((l) => `<label class="tog" style="display:inline-flex;gap:6px;align-items:center;min-height:40px"><input type="checkbox" class="w_loc" value="${l.id}" ${W.locs.includes(l.id) ? 'checked' : ''}> ${esc(nm(l))}</label>`).join('')}</div></div>
    ${fld('w_notes', T('notes'), d.notes)}</div>`;
}
function compRow(c, i) {
  return `<div class="em-line" data-ci="${i}"><div class="wide"><b>${esc(c.kind === 'allowance' ? T('allow') : T('deduct'))}</b> <button class="mini" data-act="em_comp_del" data-v="${i}" aria-label="✕">✕</button></div>
    ${fld('w_cn' + i, T('bName'), c.name)}${sel('w_cm' + i, '', [['amount', T('amount')], ['percent', T('pct')]], c.mode || 'amount')}${fld('w_cv' + i, T('value'), c.value, 'inputmode="decimal"')}</div>`;
}
function readPay() {
  const p = W.pay; ['eff', 'basis', 'basic', 'otr', 'otv', 'note'].forEach((k) => { const el = $('#w_p_' + k); if (el) p[k] = el.value.trim(); });
  W.comps.forEach((c, i) => { const n = $('#w_cn' + i); if (n) { c.name = n.value.trim(); c.mode = val('w_cm' + i); c.value = val('w_cv' + i); } });
  W.bonus.forEach((b, i) => { const n = $('#w_bn' + i); if (n) { b.name = n.value.trim(); b.months = val('w_bm' + i); b.min = val('w_bs' + i); } });
  W.leave = W.leave || {}; $$('.w_lv').forEach((x) => { W.leave[x.dataset.t] = x.value.trim(); });
  W.ben.forEach((b, i) => { const k = $('#w_bk' + i); if (k && !b.id) { b.kind = k.value; b.desc = val('w_bd' + i); b.value = val('w_bv' + i); b.from = val('w_bf' + i); } });
}
function payArgs(dry) {
  const p = W.pay, basic = nnum(p.basic);
  const comps = W.comps.filter((c) => c.name).map((c) => ({ kind: c.kind, name: c.name, taxable: false, ...(c.mode === 'percent' ? { percent_of_basic: nnum(c.value) } : { amount: nnum(c.value) }) }));
  const bonus = W.bonus.filter((b) => b.name).map((b) => ({ name: b.name, months_of_basic: nnum(b.months), min_service_months: nnum(b.min) || 0 }));
  const ot = p.otr || 'none';
  return { p_emp: W.id, p_effective: p.eff || today(), p_basis: p.basis || 'monthly', p_basic: basic, p_ot_rule: ot, p_ot_value: ot === 'none' ? null : nnum(p.otv), p_bonus: bonus, p_components: comps, p_note: p.note || null, p_client: dry ? null : (W.payClient = W.payClient || rid()), p_dry: !!dry };
}
function payBox(r) {
  return `<div class="card"><div class="em-kv"><span>${esc(T('basic'))}</span><b>${money(r.basic)}</b></div>${(r.components || []).map((c) => `<div class="em-kv"><span>${esc(c.kind === 'allowance' ? '＋' : '−')} ${esc(c.name)}${c.percent_of_basic != null ? ' (' + esc(c.percent_of_basic) + '%)' : ''}</span><b>${money(c.calc)}</b></div>`).join('')}
    <div class="em-kv"><span>${esc(T('gross'))}</span><b>${money(r.gross)}</b></div><div class="em-kv"><span>${esc(T('net'))}</span><b>${money(r.net)}</b></div></div>`;
}
function payHTML() {
  const p = W.pay, b = D.base;
  const leave = `<h4>${esc(T('leave'))}</h4><div class="em-line">${b.leave.map((t) => `<div><label>${esc(S.lang === 'en' ? t.name_en : t.name_bn)}</label><input class="w_lv" data-t="${esc(t.code)}" inputmode="decimal" value="${esc(W.leave[t.code] != null ? W.leave[t.code] : t.default_days)}"></div>`).join('')}</div>`;
  const ben = `<h4>${esc(T('benefits'))}</h4>${W.ben.map((x, i) => (x.id ? `<div class="em-kv"><span>${esc(lab(BENL[x.kind]))} · ${esc(x.desc || '')}</span><b>${x.value != null ? money(x.value) : ''}</b></div>`
    : `<div class="em-line" data-bi="${i}">${sel('w_bk' + i, T('benKind'), BENK.map((k) => [k, lab(BENL[k])]), x.kind)}${fld('w_bd' + i, T('benDesc'), x.desc)}${W.canPay ? fld('w_bv' + i, T('benVal'), x.value, 'inputmode="decimal"') : ''}${dfld('w_bf' + i, T('start'), x.from || W.d.joining_date || today())}</div>`)).join('')}
    <button class="full" data-act="em_ben_add">${esc(T('addBen'))}</button>`;
  if (!W.canPay) return `<div class="stack"><p class="muted">${esc(T('noSalary'))}</p>${leave}${ben}</div>`;
  return `<div class="stack"><h4>${esc(T('payHead'))}</h4>${dfld('w_p_eff', T('effFrom'), p.eff || today())}${sel('w_p_basis', T('basis'), [['monthly', T('monthly')], ['daily', T('daily')], ['hourly', T('hourly')]], p.basis || 'monthly')}
    ${fld('w_p_basic', T('basic'), p.basic, 'inputmode="decimal"')}${W.comps.map(compRow).join('')}
    <div class="row wrap" data-ctl="off">${PRESETS.map(([k, n, l], i) => `<button class="mini" style="min-width:auto;padding:0 10px" data-act="em_comp_add" data-k="${k}" data-n="${esc(n)}">＋ ${esc(lab(l))}</button>`).join('')}
      <button class="mini" style="min-width:auto;padding:0 10px" data-act="em_comp_add" data-k="allowance" data-n="">＋ ${esc(T('allow'))}</button><button class="mini" style="min-width:auto;padding:0 10px" data-act="em_comp_add" data-k="deduction" data-n="">＋ ${esc(T('deduct'))}</button></div>
    ${sel('w_p_otr', T('otRule'), [['none', T('otNone')], ['rate_per_hour', T('otRate')], ['multiple_of_hourly', T('otMult')]], p.otr || 'none')}${fld('w_p_otv', T('otVal'), p.otv, 'inputmode="decimal"')}
    <h4>${esc(T('bonus'))}</h4>${W.bonus.map((x, i) => `<div class="em-line">${fld('w_bn' + i, T('bName'), x.name)}${fld('w_bm' + i, T('bMonths'), x.months, 'inputmode="decimal"')}${fld('w_bs' + i, T('bMin'), x.min, 'inputmode="numeric"')}</div>`).join('')}
    <button class="full" data-act="em_bonus_add">${esc(T('addBonus'))}</button>${fld('w_p_note', T('noteL'), p.note)}
    <div class="row"><button class="full" data-act="em_pay_prev">${esc(T('preview'))}</button><button class="full primary" data-act="em_pay_save">${esc(T('saveRaise'))}</button></div><div id="w_pay_out"></div>${leave}${ben}</div>`;
}
function docsHTML() {
  if (!W.id) return `<p class="muted">${esc(T('makeFirst'))}</p>`;
  return `<div class="stack"><div class="em-row">${avatar({ photo_path: W.photo, full_name_bn: W.d.full_name_bn }, 'big')}<div><label>${esc(T('portrait'))}</label><div class="row wrap" data-ctl="off"><label class="phadd mini" style="display:inline-flex;align-items:center;padding:0 12px;min-height:40px;border:1px dashed var(--hair);border-radius:12px">${esc(T('camera'))}<input type="file" accept="image/*" capture="environment" hidden id="w_cam"></label>
    <label class="phadd mini" style="display:inline-flex;align-items:center;padding:0 12px;min-height:40px;border:1px dashed var(--hair);border-radius:12px">${esc(T('gallery'))}<input type="file" accept="image/*" hidden id="w_gal"></label></div></div></div>
    <h4>${esc(T('tDocs'))}</h4>${sel('w_dk', T('docKind'), DOCK.map((k) => [k, T('d_' + k)]), 'nid')}${fld('w_dn', T('noteL'), '')}<label class="phadd mini" style="display:inline-flex;align-items:center;padding:0 12px;min-height:40px;border:1px dashed var(--hair);border-radius:12px">📎 ${esc(T('addDoc'))}<input type="file" accept="image/*" hidden id="w_doc"></label>
    <div id="w_doclist">${W.docs.map((x) => `<div class="em-kv"><span>${esc(T('d_' + x.kind))}</span><b>${esc(x.note || '')}</b></div>`).join('')}</div><div id="w_up" class="muted"></div></div>`;
}
function deedFormHTML(v, idp) {
  const b = D.base; const role = v.role || W.d.primary_role_code || (b.roles[0] || {}).code;
  return `<div class="stack">${sel(idp + 'role', T('deedRole'), b.roles.map((r) => [r.code, rl(r)]), role)}${sel(idp + 'tpl', T('tpl'), [['', T('blank')], ...tplFor(role).map((t) => [t.id, (S.lang === 'en' && t.title_en ? t.title_en : t.title_bn) + ' · v' + t.version])], v.template_id)}
    ${fld(idp + 'title', T('titleL'), v.title)}${dfld(idp + 'start', T('start'), v.start_date)}${dfld(idp + 'end', T('end'), v.end_date)}${fld(idp + 'prob', T('probDays'), v.probation_days, 'inputmode="numeric"')}${fld(idp + 'notice', T('noticeDays'), v.notice_days, 'inputmode="numeric"')}
    ${fld(idp + 'dep', T('deposit'), v.security_deposit, 'inputmode="decimal"')}${fld(idp + 'gn', T('gName'), v.guarantor_name)}${fld(idp + 'gm', T('gMob'), v.guarantor_mobile, 'inputmode="tel"')}${fld(idp + 'gi', T('gNid'), v.guarantor_nid, 'inputmode="numeric"')}
    <h4>${esc(T('clauses'))}</h4><div id="${idp}cl">${clauseEditor()}</div></div>`;
}
function tplFor(role) { const m = new Map(); (D.tpls || []).filter((t) => t.role_code === role).forEach((t) => { const o = m.get(t.family_id); if (!o || o.version < t.version) m.set(t.family_id, t); }); return [...m.values()].filter((t) => t.active); }
async function loadTpls() { const r = await sb.from('deed_templates').select('id,family_id,version,role_code,title_bn,title_en,clauses,active,created_at').order('id', { ascending: true }); D.tpls = r.error ? [] : (r.data || []); }
function reviewHTML() {
  const d = W.d, kv = (k, v) => (v ? `<div class="em-kv"><span>${esc(T(k))}</span><b>${esc(v)}</b></div>` : '');
  return `<div class="card">${kv('nameBn', d.full_name_bn)}${kv('nameEn', d.full_name_en)}${kv('workPlace', locName(Number(d.primary_location_id)))}${kv('mobile', d.mobile)}${kv('nid', d.nid_no)}${kv('joining', d.joining_date)}${kv('desig', desigName(d.designation))}${kv('type', d.employment_type ? T('t_' + d.employment_type) : '')}</div>
    ${W.paySaved ? `<p class="chip ok">${esc(T('payHead'))} ✓</p>` : ''}<div id="w_dupr" class="em-warn"></div>`;
}
function wizHTML() {
  const body = [personalHTML, jobHTML, payHTML, docsHTML, () => deedFormHTML(W.deed, 'wd_') + `<p class="muted">${esc(T('deedNote'))}</p>`, reviewHTML][W.step]();
  const last = W.step === 5;
  return stepBar() + `<div id="w_body">${body}</div><div class="em-bar">${W.step > 0 ? `<button data-act="em_prev">${esc(T('back'))}</button>` : ''}<button data-act="em_draft">${esc(T('saveDraft'))}</button>${last ? `<button class="primary" data-act="em_finish">${esc(T('finish'))}</button>` : `<button class="primary" data-act="em_next">${esc(T('next'))}</button>`}</div>`;
}
async function wizView(id) {
  if (B.loadStatic) await B.loadStatic();
  shell(T('add'), `<div id="w_wrap"><p class="muted">${esc(T('loading'))}</p></div>`, 'employees');
  try {
    await base(); await loadTpls();
    if (id && W.id !== id) { const r = await sb.from('employees').select(EMP_COLS).eq('id', id).maybeSingle(); if (!r.data) return; wizStart(r.data); const lr = await sb.from('employee_locations').select('location_id,active').eq('employee_id', id); W.locs = (lr.data || []).filter((x) => x.active !== false).map((x) => x.location_id); }
    if (!id && W.id) wizStart(null);
    W.canPay = await can('employee_manage') && (await can('salary_manage', W.d.primary_location_id ? Number(W.d.primary_location_id) : undefined));
    if (W.id && W.existing && W.canPay && !W.pay.basic) { const p = await sb.rpc('employee_pay_current', { p_emp: W.id }); if (p.data) Object.assign(W.pay, { basis: p.data.pay_basis, basic: p.data.basic, otr: p.data.ot_rule, otv: p.data.ot_value }); }
    redrawWiz();
  } catch (e) { fail(e); }
}
function redrawWiz() { const el = $('#w_wrap'); if (el) el.innerHTML = wizHTML(); }
async function dupCheck() {
  const nid = val('w_nid_no'), mob = val('w_mobile'); const out = $('#w_dup'); if (!out) return;
  if (!nid && !mob) { out.textContent = ''; return; }
  const r = await sb.rpc('employee_dup_check', { p_nid: nid || null, p_mobile: mob || null, p_exclude: W.id }); if (r.error || !r.data) return;
  const f = (a) => a.map((x) => `<a href="#/employee/${esc(x.id)}">${esc(x.name)} (${esc(x.employee_no || '')})</a>`).join(', ');
  out.innerHTML = (r.data.nid && r.data.nid.length ? esc(T('dupNid')) + ' ' + f(r.data.nid) + '<br>' : '') + (r.data.mobile && r.data.mobile.length ? esc(T('dupMob')) + ' ' + f(r.data.mobile) : '');
}
async function wizPhoto(file, kind) {
  if (!W.id || !W.d.primary_location_id) return toast(T('needPlace'));
  const out = $('#w_up'); if (out) out.textContent = T('uploading');
  const loc = Number(W.d.primary_location_id);
  const path = await U.uploadPhoto(file, [kind === 'photo' ? 'EMP' : 'EMPDOC'], loc);
  if (kind === 'photo') { const r = await sb.rpc('employee_set_photo', { p_id: W.id, p_path: path }); if (r.error) return toast(eText(r.error)); W.photo = path; await urlsFor([path]); }
  else { const r = await sb.rpc('employee_doc_add', { p_id: W.id, p_kind: val('w_dk') || 'other', p_path: path, p_note: val('w_dn') || null, p_client: rid() }); if (r.error) return toast(eText(r.error)); W.docs.push({ kind: val('w_dk') || 'other', note: val('w_dn') }); }
  redrawWiz(); toast(T('saved'));
}
async function saveExtras() {
  readPay();
  const lv = W.id ? Object.entries(W.leave || {}) : [];
  for (const [t, v] of lv) { const n = nnum(v); if (Number.isFinite(n)) { const r = await sb.rpc('leave_entitlement_set', { p_emp: W.id, p_type: t, p_days: n }); if (r.error) { toast(eText(r.error)); return false; } } }
  for (const x of W.ben) { if (x.id || !(x.desc || x.value)) continue; const v = x.value === '' || x.value == null ? null : nnum(x.value);
    const r = await sb.rpc('employee_benefit_save', { p_id: null, p_client: rid(), p_emp: W.id, p_kind: x.kind || 'meal', p_desc: x.desc || null, p_value: W.canPay ? v : null, p_from: x.from || today(), p_to: null });
    if (r.error) { toast(eText(r.error)); return false; } x.id = r.data.id; }
  if (W.canPay && W.pay.basic && !W.paySaved) { const r = await sb.rpc('employee_pay_set', payArgs(false)); if (r.error) { toast(eText(r.error)); return false; } W.paySaved = true; }
  return true;
}
async function saveDeedStep() {
  const v = readDeed('wd_'); if (!v.title && !v.template_id) return true;
  const r = await sb.rpc('deed_save', deedArgs(v, W.id, W.deed.id || null, W.deed.client = W.deed.client || rid()));
  if (r.error) { toast(eText(r.error)); return false; } Object.assign(W.deed, v, { id: r.data.id }); return true;
}

// ---------------- deed form + clause editor ----------------
function clauseEditor() {
  return C.rows.map((c, i) => `<div class="em-line" data-cl="${i}"><div class="wide row between"><b>${i + 1}.</b><span>${i > 0 ? `<button class="mini" data-act="cl_up" data-v="${i}" aria-label="▲">▲</button>` : ''}${i < C.rows.length - 1 ? `<button class="mini" data-act="cl_down" data-v="${i}" aria-label="▼">▼</button>` : ''}<button class="mini" data-act="cl_del" data-v="${i}" aria-label="✕">✕</button></span></div>
    <div class="wide">${sel('cl_k' + i, T('type'), ['text', 'rule', 'amount', 'duration'].map((k) => [k, T('k_' + k)]), c.kind || 'text')}</div>
    <div class="wide"><label for="cl_b${i}">${esc(T('textBn'))}</label><textarea id="cl_b${i}" rows="2">${esc(c.text_bn || '')}</textarea></div><div class="wide"><label for="cl_e${i}">${esc(T('textEn'))}</label><textarea id="cl_e${i}" rows="2">${esc(c.text_en || '')}</textarea></div>
    ${fld('cl_v' + i, T('value'), c.value, 'inputmode="decimal"')}${fld('cl_u' + i, T('unit'), c.unit)}</div>`).join('') + `<button class="full" data-act="cl_add">${esc(T('addClause'))}</button>`;
}
function readClauses() { C.rows = C.rows.map((c, i) => (document.getElementById('cl_k' + i) ? { kind: val('cl_k' + i), text_bn: val('cl_b' + i), text_en: val('cl_e' + i), value: val('cl_v' + i), unit: val('cl_u' + i) } : c)); }
const redrawClauses = () => { const el = ['dd_cl', 'wd_cl', 'tp_cl'].map((i) => document.getElementById(i)).find(Boolean); if (el) el.innerHTML = clauseEditor(); };
function readDeed(idp) {
  readClauses();
  const n = (id) => { const x = val(id); return x === '' ? null : nnum(x); };
  return { role: val(idp + 'role'), template_id: val(idp + 'tpl') ? Number(val(idp + 'tpl')) : null, title: val(idp + 'title'), start_date: val(idp + 'start') || null, end_date: val(idp + 'end') || null, probation_days: n(idp + 'prob'), notice_days: n(idp + 'notice'),
    security_deposit: n(idp + 'dep'), guarantor_name: val(idp + 'gn') || null, guarantor_mobile: val(idp + 'gm') || null, guarantor_nid: val(idp + 'gi') || null };
}
const clausesOut = () => C.rows.filter((c) => c.text_bn || c.text_en).map((c) => ({ kind: c.kind || 'text', text_bn: c.text_bn || null, text_en: c.text_en || null, value: c.value || null, unit: c.unit || null }));
function deedArgs(v, emp, id, client) {
  return { p_id: id, p_client: id ? null : client, p_emp: emp, p_template: v.template_id, p_role: v.role, p_title: v.title || null, p_clauses: clausesOut().length ? clausesOut() : null, p_start: v.start_date, p_end: v.end_date, p_probation: v.probation_days, p_notice: v.notice_days,
    p_deposit: v.security_deposit, p_gname: v.guarantor_name, p_gmobile: v.guarantor_mobile, p_gnid: v.guarantor_nid };
}
function onTplPick(idp) {
  const id = Number(val(idp + 'tpl')); const t = (D.tpls || []).find((x) => x.id === id);
  if (t) { C.rows = (t.clauses || []).map((c) => ({ ...c })); const ti = $('#' + idp + 'title'); if (ti && !ti.value) ti.value = S.lang === 'en' && t.title_en ? t.title_en : t.title_bn; } else C.rows = [];
  redrawClauses();
}

// ---------------- profile ----------------
const P = { id: null, tab: 'ov', e: null };
const kv = (k, v) => (v == null || v === '' ? '' : `<div class="em-kv"><span>${esc(typeof k === 'string' && X[k] ? T(k) : k)}</span><b>${esc(v)}</b></div>`);
async function profileView(id) {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), `<div id="pf_body"><p class="muted">${esc(T('loading'))}</p></div>`, 'employees');
  try {
    await base(); await loadTpls();
    const r = await sb.from('employees').select(EMP_COLS).eq('id', id).maybeSingle();
    if (!r.data) { $('#pf_body').innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; return; }
    P.id = id; P.e = r.data; const e = r.data;
    P.mg = await can('employee_manage', e.primary_location_id); P.sv = await can('salary_view', e.primary_location_id); P.dm = await can('deed_manage', e.primary_location_id);
    const q = (t) => sb.from(t).select('*').eq('employee_id', id);
    const [dc, dd, lg, lv, lc, bn] = await Promise.all([P.mg ? q('employee_documents') : { data: [] }, P.mg || P.dm ? q('employee_deeds') : { data: [] }, q('employee_status_log').order('id', { ascending: false }), q('employee_leave_entitlements'), q('employee_locations'), sb.rpc('employee_benefits_list', { p_emp: id })]);
    Object.assign(P, { docs: (dc.data || []).filter((x) => !x.void), deeds: dd.data || [], log: lg.data || [], leave: lv.data || [], locs: (lc.data || []).filter((x) => x.active !== false), ben: bn.data || [], pay: null, payHist: [], acct: null });
    if (P.sv) { const [p, h, a] = await Promise.all([sb.rpc('employee_pay_current', { p_emp: id }), sb.rpc('employee_pay_history', { p_emp: id }), sb.rpc('employee_pay_account_get', { p_emp: id })]); P.pay = p.data || null; P.payHist = h.data || []; P.acct = a.data || null; }
    await urlsFor([e.photo_path, ...P.docs.map((x) => x.file_path)]);
    drawProfile();
  } catch (e) { fail(e); }
}
function tabsHTML() {
  const tabs = [['ov', 'tOverview'], ...(P.sv ? [['pay', 'tPay']] : []), ['fac', 'tFac'], ...(P.mg ? [['docs', 'tDocs']] : []), ...(P.mg || P.dm ? [['deeds', 'tDeeds']] : []), ['hist', 'tHist']];
  return `<div class="ptabs" role="tablist">${tabs.map(([k, l]) => `<button role="tab" data-act="pf_tab" data-v="${k}" aria-selected="${P.tab === k}">${esc(T(l))}</button>`).join('')}</div>`;
}
function ovHTML(e) {
  return `<div class="card">${kv('nameEn', e.full_name_en)}${kv('nick', e.nickname)}${kv('mobile', e.mobile)}${kv('email', e.email)}${kv('gender', e.gender ? T(e.gender) : '')}${kv('dob', e.date_of_birth)}${kv('blood', e.blood_group)}${kv('marital', e.marital_status ? T(e.marital_status) : '')}${kv('nid', e.nid_no)}
    ${kv('present', e.present_address)}${kv('permanent', e.permanent_address)}${kv('emName', e.emergency_name)}${kv('emRel', e.emergency_relation)}${kv('emMob', e.emergency_mobile)}${kv('edu', e.education)}</div>
    <div class="card">${kv('workPlace', locName(e.primary_location_id))}${kv('otherPlaces', P.locs.map((l) => locName(l.location_id)).join(', '))}${kv('joining', e.joining_date)}${kv('probEnd', e.probation_end)}${kv('type', T('t_' + e.employment_type))}${kv('desig', desigName(e.designation))}${kv('dept', deptName(e.department))}
    ${kv('jobRole', e.primary_role_code ? roleName(e.primary_role_code) : '')}${kv('device', e.device_user_id)}${kv('linked', e.profile_id ? '✓' : '')}${kv('notes', e.notes)}</div>`;
}
function payTab() {
  if (!P.pay) return `<p class="muted">${esc(T('noPay'))}</p>`;
  const p = P.pay, ot = p.ot_rule === 'none' ? T('otNone') : (p.ot_rule === 'rate_per_hour' ? money(p.ot_value) + ' / h' : '× ' + p.ot_value);
  return `<div class="card"><div class="em-kv"><span>${esc(T('effFrom'))}</span><b>${esc(p.effective_from)}</b></div><div class="em-kv"><span>${esc(T('basis'))}</span><b>${esc(T(p.pay_basis))}</b></div></div>${payBox(p)}
    <div class="card">${kv('otRule', ot)}${(p.bonus_rules || []).map((b) => kv(b.name, b.months_of_basic + ' × ' + T('basic') + (b.min_service_months ? ' · ≥ ' + b.min_service_months : ''))).join('')}${P.acct ? kv('bank', P.acct.bank_account) + kv('wallet', P.acct.mobile_wallet) : ''}</div>
    <h4>${esc(T('history'))}</h4>${P.payHist.map((h) => `<div class="em-kv"><span>${esc(h.effective_from)}</span><b>${money(h.basic)} → ${money(h.net)}</b></div>`).join('')}${P.mg ? `<button class="full" data-act="em_edit" data-v="${esc(P.id)}" data-step="2">${esc(T('saveRaise'))}</button>` : ''}`;
}
function facTab() {
  const lv = P.leave.map((x) => { const t = D.base.leave.find((y) => y.code === x.leave_type); return kv(t ? (S.lang === 'en' ? t.name_en : t.name_bn) : x.leave_type, x.days_per_year); }).join('');
  return `<h4>${esc(T('leave'))}</h4><div class="card">${lv || `<p class="muted">${esc(T('none'))}</p>`}</div><h4>${esc(T('benefits'))}</h4>${P.ben.length ? P.ben.map((b) => `<div class="card"><div class="em-kv"><span>${esc(lab(BENL[b.kind]))}</span><b>${b.value_per_month != null ? money(b.value_per_month) : ''}</b></div>
    <div class="muted">${esc(b.description || '')} · ${esc(b.from_date)}${b.to_date ? ' → ' + esc(b.to_date) : ''}</div>${P.mg && b.active ? `<button class="mini" style="min-width:auto;padding:0 10px" data-act="pf_ben_end" data-v="${b.id}">${esc(T('endBen'))}</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}`;
}
function docsTab() {
  return `<button class="full" data-act="em_adddoc" data-v="${esc(P.id)}">${esc(T('addDoc'))}</button>` + (P.docs.length ? P.docs.map((x) => `<div class="card em-row">${D.urls[x.file_path] ? `<img class="em-av" alt="" src="${esc(D.urls[x.file_path])}">` : '<span class="em-av">📄</span>'}<div class="grow"><b>${esc(T('d_' + x.kind))}</b><div class="muted">${esc(x.note || '')} ${esc(String(x.uploaded_at || '').slice(0, 10))}</div></div>
    <button class="mini" data-act="pf_doc_void" data-v="${x.id}" aria-label="${esc(T('voidDoc'))}">✕</button></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`);
}
const dStat = (s) => ({ active: T('dActive'), draft: T('dDraft'), expired: T('dExpired'), terminated: T('dTerminated'), superseded: T('dSuperseded') }[s] || s);
function deedsTab() {
  const ds = [...P.deeds].sort((a, b) => b.id - a.id);
  return `${P.mg ? `<button class="full" data-act="em_adddeed" data-v="${esc(P.id)}">${esc(T('addDeed'))}</button>` : ''}` + (ds.length ? ds.map((d) => `<div class="card" data-act="dd_open" data-v="${d.id}" style="cursor:pointer"><div class="row between"><b>${esc(d.title)}</b><span class="chip ${d.status === 'active' ? 'ok' : d.status === 'draft' ? 'warn' : ''}">${esc(dStat(d.status))}</span></div>
    <div class="muted">${esc(roleName(d.role_code))} · ${esc(T('rev'))} ${d.revision_no} · ${esc(d.start_date || '')}${d.end_date ? ' → ' + esc(d.end_date) : ''}</div></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`);
}
function histTab() { return P.log.length ? P.log.map((l) => `<div class="em-kv"><span>${esc(l.status_date || '')}</span><b>${esc(l.from_status ? stL(l.from_status) + ' → ' : '')}${esc(stL(l.to_status))}${l.reason ? ' · ' + esc(l.reason) : ''}</b></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`; }
function drawProfile() {
  const e = P.e, body = { ov: () => ovHTML(e), pay: payTab, fac: facTab, docs: docsTab, deeds: deedsTab, hist: histTab }[P.tab]();
  $('#pf_body').innerHTML = `<div class="card em-row">${avatar(e, 'big')}<div class="grow"><div class="nm"><b>${esc(ename(e))}</b></div><div class="muted">${esc(e.employee_no || T('s_draft'))} · ${esc(desigName(e.designation))}</div><div class="muted">${esc(locName(e.primary_location_id))}</div></div>
    <span class="chip ${stCls(e.status)}">${esc(stL(e.status))}</span><button class="mini" data-act="em_menu" data-v="${esc(e.id)}" aria-label="⋮">⋮</button></div>
    <div class="row wrap" data-ctl="off"><button class="mini" style="min-width:auto;padding:0 10px" data-act="pf_print" data-v="card">${esc(T('idCard'))}</button><button class="mini" style="min-width:auto;padding:0 10px" data-act="pf_print" data-v="sheet">${esc(T('profSheet'))}</button></div>${tabsHTML()}<div id="pf_tab">${body}</div>`;
}

// ---------------- print ----------------
function printNow(html) {
  const old = $('#em_print'); if (old) old.remove();
  const d = document.createElement('div'); d.id = 'em_print'; d.innerHTML = `<div class="em-paper">${html}</div>`; document.body.appendChild(d);
  try { window.print(); } finally { setTimeout(() => { const x = $('#em_print'); if (x) x.remove(); }, 800); }
}
function cardHTML(e) { return `<div class="em-card">${e.photo_path && D.urls[e.photo_path] ? `<img alt="" src="${esc(D.urls[e.photo_path])}">` : `<span class="em-av">${initials(e)}</span>`}<div><div style="font-size:14px"><b>${esc(ename(e))}</b></div><div>${esc(e.employee_no || '')}</div><div>${esc(desigName(e.designation))}</div><div>${esc(locName(e.primary_location_id))}</div><div>${esc(e.mobile || '')}</div></div></div>`; }
function sheetHTML(e) {
  return `<h2>${esc(ename(e))} · ${esc(e.employee_no || '')}</h2>${cardHTML(e)}<div style="margin-top:8px">${kv('nameBn', e.full_name_bn)}${kv('mobile', e.mobile)}${kv('nid', e.nid_no)}${kv('dob', e.date_of_birth)}${kv('blood', e.blood_group)}${kv('present', e.present_address)}${kv('permanent', e.permanent_address)}${kv('emName', e.emergency_name)}${kv('emMob', e.emergency_mobile)}
    ${kv('workPlace', locName(e.primary_location_id))}${kv('joining', e.joining_date)}${kv('type', T('t_' + e.employment_type))}${kv('desig', desigName(e.designation))}${kv('status', stL(e.status))}</div>`;
}
function deedPrint(d, e) {
  const cl = (d.clauses || []).map((c) => `<li>${esc(S.lang === 'en' ? (c.text_en || c.text_bn) : (c.text_bn || c.text_en))}${c.value ? ` <b>${esc(c.value)} ${esc(c.unit || '')}</b>` : ''}</li>`).join('');
  return `<h2>${esc(d.title)}</h2>${kv('nameBn', e ? ename(e) : '')}${kv('sumNo', e && e.employee_no)}${kv('deedRole', roleName(d.role_code))}${kv('start', d.start_date)}${kv('end', d.end_date)}${kv('probDays', d.probation_days)}${kv('noticeDays', d.notice_days)}${kv('deposit', d.security_deposit != null ? money(d.security_deposit) : '')}
    ${kv('gName', d.guarantor_name)}${kv('gMob', d.guarantor_mobile)}<h3>${esc(T('clauses'))}</h3><ol>${cl}</ol><div class="em-sign"><div>${esc(ename(e || {}))}</div><div>${esc(T('gName'))}</div><div>Owner</div></div>`;
}

// ---------------- sheets: status, link, document, deed ----------------
function statusSheet(id) {
  openSheet(`<div class="stack"><h3>${esc(T('chStatus'))}</h3>${sel('ss_s', T('status'), ST.filter((s) => s !== 'draft').map((s) => [s, stL(s)]), 'active')}${dfld('ss_d', T('date'), today())}${fld('ss_r', T('reason'), '')}
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="full primary" data-act="ss_save" data-v="${esc(id)}">${esc(T('save'))}</button></div></div>`);
}
async function linkSheet(id) {
  const r = await sb.from('profiles').select('id,staff_id,full_name,status').order('staff_id'); const rows = (r.data || []).filter((p) => p.status === 'active');
  openSheet(`<div class="stack"><h3>${esc(T('linkLogin'))}</h3>${sel('lk_p', T('pickLogin'), [['', '—'], ...rows.map((p) => [p.id, (p.full_name || p.staff_id) + ' · ' + p.staff_id])], '')}
    <div class="row"><button class="full" data-act="lk_save" data-v="${esc(id)}" data-un="1">${esc(T('unlink'))}</button><button class="full primary" data-act="lk_save" data-v="${esc(id)}">${esc(T('save'))}</button></div></div>`);
}
function docSheet(id) {
  openSheet(`<div class="stack"><h3>${esc(T('addDoc'))}</h3>${sel('w_dk', T('docKind'), DOCK.map((k) => [k, T('d_' + k)]), 'nid')}${fld('w_dn', T('noteL'), '')}
    <label class="phadd mini" style="display:inline-flex;align-items:center;padding:0 12px;min-height:44px;border:1px dashed var(--hair);border-radius:12px">📎 ${esc(T('addDoc'))}<input type="file" accept="image/*" hidden id="ds_file" data-emp="${esc(id)}"></label><div id="ds_out" class="muted"></div></div>`);
}
async function deedSheet(empId, deed) {
  await base(); if (!D.tpls) await loadTpls();
  const e = (D.rows.find((x) => x.id === empId)) || P.e || (await sb.from('employees').select('id,full_name_bn,full_name_en,primary_role_code,primary_location_id,employee_no,status').eq('id', empId).maybeSingle()).data || {};
  C.rows = deed ? (deed.clauses || []).map((c) => ({ ...c })) : [];
  C.ctx = { emp: empId, deed };
  const v = deed || { role: e.primary_role_code };
  openSheet(`<div class="stack"><h3>${esc(T('addDeed'))} · ${esc(ename(e))}</h3>${deedFormHTML({ ...v, role: deed ? deed.role_code : v.role, template_id: deed ? deed.template_id : null }, 'dd_')}
    <div class="row"><button class="full" data-act="dd_save" data-v="0">${esc(T('saveDeed'))}</button>${(await can('deed_manage', e.primary_location_id)) ? `<button class="full primary" data-act="dd_save" data-v="1">${esc(T('activate'))}</button>` : ''}</div></div>`);
}
async function deedView(id) {
  const r = await sb.from('employee_deeds').select('*').eq('id', id).maybeSingle(); const d = r.data; if (!d) return;
  const er = await sb.from('employees').select('id,employee_no,full_name_bn,full_name_en,primary_location_id').eq('id', d.employee_id).maybeSingle(); const e = er.data || {};
  const dm = await can('deed_manage', e.primary_location_id), mg = await can('employee_manage', e.primary_location_id);
  C.ctx = { emp: d.employee_id, deed: d, e };
  openSheet(`<div class="stack"><div class="row between"><h3>${esc(d.title)}</h3><span class="chip ${d.status === 'active' ? 'ok' : d.status === 'draft' ? 'warn' : ''}">${esc(dStat(d.status))}</span></div>
    <div class="card">${kv('nameBn', e.full_name_bn)}${kv('deedRole', roleName(d.role_code))}${kv('rev', d.revision_no)}${kv('start', d.start_date)}${kv('end', d.end_date)}${kv('signed', d.signed_at)}${kv('deposit', d.security_deposit != null ? money(d.security_deposit) : '')}${kv('gName', d.guarantor_name)}</div>
    <ol>${(d.clauses || []).map((c) => `<li>${esc(S.lang === 'en' ? (c.text_en || c.text_bn) : (c.text_bn || c.text_en))}${c.value ? ' <b>' + esc(c.value) + ' ' + esc(c.unit || '') + '</b>' : ''}</li>`).join('')}</ol>
    <div class="row wrap" data-ctl="off"><button class="mini" style="min-width:auto;padding:0 10px" data-act="dd_print">${esc(T('print'))}</button>
    ${d.status === 'draft' && mg ? `<button class="mini" style="min-width:auto;padding:0 10px" data-act="dd_edit">${esc(T('edit'))}</button>` : ''}${d.status === 'draft' && dm ? `<button class="mini primary" style="min-width:auto;padding:0 10px" data-act="dd_activate">${esc(T('activate'))}</button>` : ''}
    ${d.status === 'active' && mg ? `<button class="mini" style="min-width:auto;padding:0 10px" data-act="dd_revise">${esc(T('revise'))}</button>` : ''}${d.status === 'active' && dm ? `<button class="mini" style="min-width:auto;padding:0 10px" data-act="dd_end">${esc(T('endDeed'))}</button>` : ''}
    ${d.status === 'active' && mg && !d.signed_doc_path ? `<label class="mini" style="display:inline-flex;align-items:center;padding:0 10px;min-height:36px">${esc(T('attach'))}<input type="file" accept="image/*" hidden id="dd_signed"></label>` : ''}</div></div>`);
}

// ---------------- deeds screen ----------------
async function deedsView() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('deedsH'), `<div id="dl_body"><p class="muted">${esc(T('loading'))}</p></div>`, 'employees');
  try {
    await base(); await loadTpls();
    const dm = await can('deed_manage'); D.dm = dm;
    const ex = await sb.rpc('deeds_expiring', { p_days: null });
    const exp = (ex.data || []).map((x) => `<div class="card" data-act="dd_open" data-v="${x.deed_id}" style="cursor:pointer"><div class="row between"><b>${esc(x.full_name_bn)}</b><span class="chip ${x.days_left < 0 ? 'bad' : 'warn'}">${x.days_left < 0 ? esc(T('overdue')) : x.days_left + ' ' + esc(T('daysLeft'))}</span></div><div class="muted">${esc(x.employee_no || '')} · ${esc(roleName(x.role_code))} · ${esc(x.end_date)}</div></div>`).join('');
    const fam = new Map(); D.tpls.forEach((t) => { const o = fam.get(t.family_id); if (!o || o.version < t.version) fam.set(t.family_id, t); });
    const tp = [...fam.values()].map((t) => `<div class="card"><div class="row between"><b>${esc(S.lang === 'en' && t.title_en ? t.title_en : t.title_bn)}</b><span class="chip ${t.active ? 'ok' : ''}">v${t.version}</span></div><div class="muted">${esc(roleName(t.role_code))} · ${(t.clauses || []).length} ${esc(T('clauses'))}</div>
      ${dm ? `<div class="row"><button class="mini" style="min-width:auto;padding:0 10px" data-act="tp_edit" data-v="${t.id}">${esc(T('edit'))}</button><button class="mini" style="min-width:auto;padding:0 10px" data-act="tp_retire" data-v="${t.family_id}" data-on="${t.active ? 0 : 1}">${esc(t.active ? T('retire') : T('reopen'))}</button></div>` : ''}</div>`).join('');
    $('#dl_body').innerHTML = `<h3>${esc(T('expiring'))}</h3>${exp || `<p class="muted">${esc(T('none'))}</p>`}<h3>${esc(T('templates'))}</h3>${dm ? `<button class="full" data-act="tp_new">${esc(T('newTpl'))}</button>` : ''}${tp || `<p class="muted">${esc(T('noTpl'))}</p>`}`;
  } catch (e) { fail(e); }
}
function tplSheet(t) {
  C.rows = t ? (t.clauses || []).map((c) => ({ ...c })) : []; C.ctx = { tpl: t };
  openSheet(`<div class="stack"><h3>${esc(T('templates'))}${t ? ' · v' + t.version + ' → v' + (t.version + 1) : ''}</h3>${sel('tp_role', T('deedRole'), D.base.roles.map((r) => [r.code, rl(r)]), t ? t.role_code : '')}${fld('tp_bn', T('titleL') + ' (' + 'BN)', t ? t.title_bn : '')}${fld('tp_en', T('titleL') + ' (EN)', t ? t.title_en : '')}
    <h4>${esc(T('clauses'))}</h4><div id="tp_cl">${clauseEditor()}</div><div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="full primary" data-act="tp_save">${esc(T('save'))}</button></div></div>`);
}

// ---------------- handlers ----------------
const go = (h) => { location.hash = h; };
Object.assign(H, {
  em_new: () => { wizStart(null); go('#/employees/new'); },
  em_menu: (a) => menu(a.dataset.v),
  em_edit: (a) => { closeSheet(); wizStart(null); W.id = null; go('#/employees/edit/' + a.dataset.v); if (a.dataset.step) W.goStep = Number(a.dataset.step); },
  em_copy: async (a) => { try { await navigator.clipboard.writeText(a.dataset.m); } catch (e) { /* clipboard may be blocked */ } closeSheet(); toast(T('copied')); },
  em_status: (a) => { closeSheet(); statusSheet(a.dataset.v); },
  em_link: (a) => { closeSheet(); return linkSheet(a.dataset.v); },
  em_adddoc: (a) => { closeSheet(); docSheet(a.dataset.v); },
  em_adddeed: (a) => { closeSheet(); return deedSheet(a.dataset.v, null); },
  ss_save: async (a) => { const r = await sb.rpc('employee_status_set', { p_id: a.dataset.v, p_status: val('ss_s'), p_date: val('ss_d') || today(), p_reason: val('ss_r') || null }); if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); route(); },
  lk_save: async (a) => { const r = await sb.rpc('employee_link_profile', { p_id: a.dataset.v, p_profile: a.dataset.un ? null : (val('lk_p') || null) }); if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); route(); },
  pf_tab: (a) => { P.tab = a.dataset.v; drawProfile(); },
  pf_print: (a) => printNow(a.dataset.v === 'card' ? cardHTML(P.e) : sheetHTML(P.e)),
  pf_doc_void: async (a) => { const n = window.prompt(T('why')); if (!n || n.trim().length < 3) return; const r = await sb.rpc('employee_doc_void', { p_doc: Number(a.dataset.v), p_reason: n.trim() }); if (r.error) return toast(eText(r.error)); toast(T('saved')); route(); },
  pf_ben_end: async (a) => { const r = await sb.rpc('employee_benefit_end', { p_id: Number(a.dataset.v), p_to: today() }); if (r.error) return toast(eText(r.error)); toast(T('saved')); route(); },
  // wizard
  em_next: async () => { if (W.step === 2 && !(await saveExtras())) return; if (W.step === 4 && !(await saveDeedStep())) return; if (W.step < 2 && !(await saveStep())) return; if (W.step === 2) readPay(); W.step++; redrawWiz(); },
  em_prev: () => { collectStep(); if (W.step === 2) readPay(); W.step--; redrawWiz(); },
  em_draft: async () => { if (W.step === 2) { if (!(await saveExtras())) return; } else if (W.step === 4) { if (!(await saveDeedStep())) return; } else if (!(await saveStep())) return; toast(T('saved')); },
  em_finish: async () => { const r = await sb.rpc('employee_submit', { p_id: W.id }); if (r.error) return toast(eText(r.error)); toast(T('regDone') + ' ' + (r.data.employee_no || '')); const id = W.id; wizStart(null); W.id = null; go('#/employee/' + id); },
  em_comp_add: (a) => { readPay(); W.comps.push({ kind: a.dataset.k, name: a.dataset.n, mode: a.dataset.k === 'allowance' && /rent|Medical|Transport|Food/.test(a.dataset.n) ? 'percent' : 'amount', value: '' }); redrawWiz(); },
  em_comp_del: (a) => { readPay(); W.comps.splice(Number(a.dataset.v), 1); redrawWiz(); },
  em_bonus_add: () => { readPay(); W.bonus.push({ name: 'Eid', months: '1', min: '6' }); redrawWiz(); },
  em_ben_add: () => { readPay(); W.ben.push({ kind: 'meal', desc: '', value: '', from: '' }); redrawWiz(); },
  em_pay_prev: async () => { readPay(); const r = await sb.rpc('employee_pay_set', payArgs(true)); const out = $('#w_pay_out'); if (r.error) return toast(eText(r.error)); out.innerHTML = `<p class="muted">${esc(T('preview'))}</p>` + payBox(r.data); },
  em_pay_save: async () => { readPay(); const r = await sb.rpc('employee_pay_set', payArgs(false)); if (r.error) return toast(eText(r.error)); W.paySaved = true; W.payClient = null; $('#w_pay_out').innerHTML = payBox(r.data); toast(T('saved')); },
  // clauses
  cl_add: () => { readClauses(); C.rows.push({ kind: 'text' }); redrawClauses(); },
  cl_del: (a) => { readClauses(); C.rows.splice(Number(a.dataset.v), 1); redrawClauses(); },
  cl_up: (a) => { readClauses(); const i = Number(a.dataset.v); [C.rows[i - 1], C.rows[i]] = [C.rows[i], C.rows[i - 1]]; redrawClauses(); },
  cl_down: (a) => { readClauses(); const i = Number(a.dataset.v); [C.rows[i + 1], C.rows[i]] = [C.rows[i], C.rows[i + 1]]; redrawClauses(); },
  // deeds
  dd_open: (a) => deedView(Number(a.dataset.v)),
  dd_save: async (a) => { const v = readDeed('dd_'), cx = C.ctx; const dr = cx.deed && cx.deed.status === 'draft' ? cx.deed : null;
    const r = await sb.rpc('deed_save', deedArgs(v, cx.emp, dr ? dr.id : null, rid())); if (r.error) return toast(eText(r.error));
    if (a.dataset.v === '1') { const q = await sb.rpc('deed_activate', { p_id: r.data.id, p_signed_at: null, p_signed_doc: null }); if (q.error) return toast(eText(q.error)); }
    closeSheet(); toast(T('saved')); route(); },
  dd_edit: () => deedSheet(C.ctx.emp, C.ctx.deed),
  dd_activate: async () => { const r = await sb.rpc('deed_activate', { p_id: C.ctx.deed.id, p_signed_at: null, p_signed_doc: null }); if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); route(); },
  dd_revise: async () => { const r = await sb.rpc('deed_revise', { p_id: C.ctx.deed.id, p_client: rid() }); if (r.error) return toast(eText(r.error)); const d = (await sb.from('employee_deeds').select('*').eq('id', r.data.id).maybeSingle()).data; closeSheet(); if (d) await deedSheet(d.employee_id, d); },
  dd_end: async () => { const n = window.prompt(T('why')); if (!n || n.trim().length < 3) return; const r = await sb.rpc('deed_end', { p_id: C.ctx.deed.id, p_reason: n.trim() }); if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); route(); },
  dd_print: () => printNow(deedPrint(C.ctx.deed, C.ctx.e || P.e)),
  tp_new: () => tplSheet(null), tp_edit: (a) => tplSheet(D.tpls.find((t) => t.id === Number(a.dataset.v))),
  tp_save: async () => { readClauses(); const t = C.ctx.tpl; const r = await sb.rpc('deed_template_save', { p_family: t ? t.family_id : null, p_role: val('tp_role'), p_title_bn: val('tp_bn'), p_title_en: val('tp_en') || null, p_clauses: clausesOut(), p_client: rid() }); if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); route(); },
  tp_retire: async (a) => { const r = await sb.rpc('deed_template_retire', { p_family: Number(a.dataset.v), p_active: a.dataset.on === '1' }); if (r.error) return toast(eText(r.error)); route(); },
});
function route() { const f = window.BOS_PAGES; const p = location.hash.replace(/^#\/?/, '').split('/'); if (p[0] === 'employees') return f.employees(); if (p[0] === 'employee') return f.employee(); if (p[0] === 'deeds') return f.deeds(); }
document.addEventListener('input', (e) => {
  if (e.target.id === 'em_q') { D.q = e.target.value; redrawList(); }
  if (e.target.id === 'w_nid_no' || e.target.id === 'w_mobile') { clearTimeout(dupCheck.t); dupCheck.t = setTimeout(dupCheck, 350); }
});
document.addEventListener('change', async (e) => {
  const id = e.target.id;
  if (id === 'em_fs') { D.fs = e.target.value; redrawList(); } if (id === 'em_fl') { D.fl = e.target.value; redrawList(); } if (id === 'em_fr') { D.fr = e.target.value; redrawList(); } if (id === 'em_ft') { D.ft = e.target.value; redrawList(); }
  if (id === 'w_designation') { const w = $('#w_dtxtw'); if (w) w.hidden = e.target.value !== '__other'; }
  if (id === 'w_primary_location_id') W.d.primary_location_id = e.target.value;
  if (id === 'dd_role' || id === 'wd_role') { const p = id.slice(0, 3); const s = $('#' + p + 'tpl'); if (s) { const keep = [['', T('blank')], ...tplFor(e.target.value).map((t) => [t.id, (S.lang === 'en' && t.title_en ? t.title_en : t.title_bn) + ' · v' + t.version])]; s.innerHTML = keep.map(([v, t]) => `<option value="${esc(v)}">${esc(t)}</option>`).join(''); } }
  if (id === 'dd_tpl' || id === 'wd_tpl') { C.idp = id.slice(0, 3); onTplPick(C.idp); }
  const f = e.target.files && e.target.files[0];
  if ((id === 'w_cam' || id === 'w_gal') && f) { try { await wizPhoto(f, 'photo'); } catch (er) { fail(er); } }
  if (id === 'w_doc' && f) { try { await wizPhoto(f, 'doc'); } catch (er) { fail(er); } }
  if (id === 'ds_file' && f) { try { const emp = e.target.dataset.emp; const er = (D.rows.find((x) => x.id === emp)) || P.e || (await sb.from('employees').select('id,primary_location_id').eq('id', emp).maybeSingle()).data;
      const path = await U.uploadPhoto(f, ['EMPDOC'], er.primary_location_id); const r = await sb.rpc('employee_doc_add', { p_id: emp, p_kind: val('w_dk') || 'other', p_path: path, p_note: val('w_dn') || null, p_client: rid() });
      if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); route(); } catch (er) { fail(er); } }
  if (id === 'dd_signed' && f) { try { const d = C.ctx.deed; const er = P.e || C.ctx.e; const path = await U.uploadPhoto(f, ['EMPDOC'], er.primary_location_id); const r = await sb.rpc('deed_attach_signed', { p_id: d.id, p_path: path }); if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); route(); } catch (er) { fail(er); } }
});

// ---------------- routes ----------------
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, {
  employees: () => { const p = location.hash.replace(/^#\/?/, '').split('/'); if (p[1] === 'new') return wizView(null); if (p[1] === 'edit' && p[2]) return wizView(p[2]).then(() => { if (W.goStep != null) { W.step = W.goStep; W.goStep = null; redrawWiz(); } }); return listView(); },
  employee: () => { const p = location.hash.replace(/^#\/?/, '').split('/'); if (P.id !== p[1]) P.tab = 'ov'; return p[1] ? profileView(p[1]) : listView(); },
  deeds: deedsView,
});
B.employees = { eText };
})();
