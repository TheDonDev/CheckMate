// lib/constants/dropdown_data.dart

/// List of schools available in the university.
const List<String> schoolsList = [
  "School of Science Technology and Engineering",
  "School of Health Sciences",
  "School of Education and Social Sciences",
  "School of Business, Economics and Human Resource Development"
];

/// Map linking schools to their respective departments.
/// Keys are school names (must match entries in [schoolsList]).
/// Values are lists of department names within that school.
const Map<String, List<String>> departmentsMap = {
  "School of Science Technology and Engineering": [
    "Department of Chemistry and Biochemistry",
    "Department of Mathematics, Physics and Computer",
    "Department of Biological and Agricultural Sciences",
  ],
  "School of Health Sciences": [
    "Department of Public Health, Nutrition and Behavioural Sciences",
    "Department of Anatomy, Physiology and Medical Biochemistry",
    "Department of Medical Laboratory Sciences",
    "Department of Physiotherapy",
  ],
  "School of Education and Social Sciences": [
    "Department of Language and Literature Education",
    "Department of Humanities and Social Sciences",
    "Department of Educational Psychology, Management and Policy Studies",
    "Department of Curriculum Instruction and Educational Foundations",
  ],
  "School of Business, Economics and Human Resource Development": [
    "Department of Finance, Accounting and Procurement and Economics (FAPE)",
    "Department of Marketing, Hospitality and Human Resource",
  ],
};

/// Map linking schools to the courses offered within them.
/// Keys are school names (must match entries in [schoolsList]).
/// Values are lists of course names offered in that school.
/// Note: It might be more accurate to link courses to *departments*, but this structure links them to schools as provided.
const Map<String, List<String>> coursesMap = {
  "School of Health Sciences": [
    "Master’s in Public Health",
    "Msc Medical Microbiology",
    "Bachelor of Science Medical Laboratory Sciences",
    "Bachelor of Science Medical Psychology",
    "Bachelor of Science Physical Therapy",
    "Bachelor of Science Environmental Health"
  ],
  "School of Science Technology and Engineering": [
    "Bachelor of Science Microbiology",
    "Bachelor of Science Computer Science",
    "Bachelor of Science Applied Statistics with Computing",
    "Diploma in Information Communication and Technology",
    "Diploma in Applied Biology",
    "Diploma in Analytical Chemistry"
  ],
  "School of Business, Economics and Human Resource Development": [
    "MBA-Finance",
    "MBA-Strategic Management",
    "MBA-Accounting",
    "MBA-Entrepreneurship",
    "MBA-Business Leadership",
    "Bachelor of Hotel and Hospitality Management",
    "Bachelor of Business Management",
    "Bachelor of Science Communication and Public relations",
    "Bachelor of Arts Economics",
    "Diploma in Business Management",
    "Diploma in Banking and Finance",
    "Diploma in Hotel and Restaurant Management",
    "Diploma in Tourism Management"
  ],
  "School of Education and Social Sciences": [
    "Master of Education, Language Education (English, Kiswahili)",
    "Post-Graduate Diploma in Education",
    "Bachelor of Education Science",
    "Bachelor of Education Arts",
    "Bachelor of Science Counseling Psychology",
    "Bachelor of Arts Community Development",
    "Diploma in Social Work",
    "Diploma in Community Development"
  ],
};

/// List of specific venues or locations within the university.
/// Used potentially for scheduling or location selection elsewhere in the app.
const List<String> venuesList = [
  "SKILLS LAB HALL (TU)", // SL-HALL
  "SKILLS LAB HALL-ANNEX 1 (TU)", // SL-A1
  "SKILLS LAB HALL-ANNEX 2(TU)", // SL-A2
  "HOTEL & HOSPITALITY WORKSHOP", // HH-W
  "HOTEL & HOSPITALITY ANNEX", // HH-A
  "NEW GENERAL LAB (SSTE BLOCK)", // NGL
  "NEW LECTURE ROOM 1 (SSTE BLOCK)", // NLR-1
  "NEW LECTURE ROOM 2 (SSTE BLOCK)", // NLR-2
  "NEW SCIENCE BLOCK LECTURE HALL 1 (SSTE BLOCK)", // NSB-LH1
  "NEW SCIENCE BLOCK LECTURE HALL 2 (SSTE BLOCK)", // NSB-LH2
  "NEW SCIENCE BLOCK LECTURE HALL 3 (SSTE BLOCK)", // NSB-LH3
  "MEDICAL LAB LECTURE HALL 2 (SHS BLOCK)", // ML-LH2
  "MEDICAL LAB LECTURE HALL 3 (SHS BLOCK)",
  "MEDICAL LAB LECTURE HALL 4 (SHS BLOCK)", // ML-LH3/4
  "PHYSIOTHERAPY SKILLS LAB (SHS BLOCK)", // PT-SL
  "COMPUTER LAB (SSTE BLOCK)", // COM-LB
  "MICRO-TEACHING LAB (FORMER LIBRARY)", // MT-LB
  "LIBRARY FIRST FLOOR MAIN HALL (NEW LIBRARY)", // LIB-FFM
  "LIBRARY FIRST FLOOR ANNEX (NEW LIBRARY)", // LIB-FFA
  "LIBRARY SECOND FLOOR MAIN HALL (NEW LIBRARY)", // LIB-SFM
  "LIBRARY SECOND FLOOR ANNEX (NEW LIBRARY)", // LIB-SFA
  "LIBRARY LECTURE HALL 3 (LIBRARY 3RD FLOOR)", // LIB-LH3
  "LIBRARY LECTURE HALL 4 (LIBRARY 4TH FLOOR)", // LIB-LH4
  "GEOGRAPHY LAB (FORMER LIBRARY)", // GEO-LB
  "COUNSELING PSYCHOLOGY LAB (FORMER LIBRARY)", // CP-LB
];

/// List of academic years of study for students.
/// Used in the registration screen for students.
const List<String> yearsList = [
  "1st Year",
  "2nd Year",
  "3rd Year",
  "4th Year"
  // Add "5th Year", etc., if applicable for certain courses
];

/// List of academic semesters.
/// Used in the registration screen for students.
const List<String> semestersList = [
  "Semester 1",
  "Semester 2"
  // Add "Semester 3" or "Trimester" options if applicable
];
