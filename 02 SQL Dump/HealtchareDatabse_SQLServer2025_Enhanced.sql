/*
===============================================================================
HealtchareDatabse - SQL Server 2025 Healthcare / Mirth Connect Training Database
SYNTHETIC TRAINING DATA ONLY - NO REAL PHI

Enhanced training design:
- 1,200 synthetic patients
- Beginner-friendly physical column order in dbo.Patient
- Core patient identifiers, names, DOB, country and language kept together
- Additional healthcare fields for insurance, encounters, HL7, labs and auditing
- Data-quality enrichment for coherent City / ProvinceState / Country values
- 16 normalized tables, indexes, teaching views and stored procedures
- Designed for SQL Server + SSMS + Mirth Connect / JDBC demonstrations

WARNING: Drops and rebuilds HealtchareDatabse if it already exists.
===============================================================================
*/

USE master;
GO
IF DB_ID(N'HealtchareDatabse') IS NOT NULL
BEGIN
    ALTER DATABASE HealtchareDatabse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE HealtchareDatabse;
END;
GO
CREATE DATABASE HealtchareDatabse;
GO
ALTER DATABASE HealtchareDatabse SET RECOVERY SIMPLE;
GO
USE HealtchareDatabse;
GO

CREATE TABLE dbo.Facility(
    FacilityID int IDENTITY PRIMARY KEY,
    FacilityCode varchar(10) NOT NULL UNIQUE,
    FacilityName nvarchar(120) NOT NULL,
    FacilityType varchar(40) NULL,
    City nvarchar(80) NOT NULL,
    ProvinceState nvarchar(80) NOT NULL,
    Country nvarchar(80) NOT NULL,
    TimeZone varchar(80) NULL,
    ActiveFlag bit NOT NULL CONSTRAINT DF_Facility_ActiveFlag DEFAULT 1
);

CREATE TABLE dbo.Department(
    DepartmentID int IDENTITY PRIMARY KEY,
    FacilityID int NOT NULL REFERENCES dbo.Facility(FacilityID),
    DepartmentCode varchar(15) NOT NULL UNIQUE,
    DepartmentName nvarchar(120) NOT NULL,
    ServiceLine nvarchar(80) NOT NULL,
    CostCenterCode varchar(20) NULL,
    DepartmentPhone varchar(30) NULL,
    ActiveFlag bit NOT NULL CONSTRAINT DF_Department_ActiveFlag DEFAULT 1
);

CREATE TABLE dbo.Location(
    LocationID int IDENTITY PRIMARY KEY,
    DepartmentID int NOT NULL REFERENCES dbo.Department(DepartmentID),
    UnitCode varchar(20) NOT NULL,
    RoomCode varchar(20) NOT NULL,
    BedCode varchar(20) NOT NULL,
    LocationDescription nvarchar(150) NOT NULL,
    LocationType varchar(30) NOT NULL,
    Building nvarchar(80) NULL,
    FloorNumber int NULL,
    ActiveFlag bit NOT NULL CONSTRAINT DF_Location_ActiveFlag DEFAULT 1
);

CREATE TABLE dbo.Provider(
    ProviderID int IDENTITY PRIMARY KEY,
    ProviderNumber varchar(20) NOT NULL UNIQUE,
    FirstName nvarchar(60) NOT NULL,
    LastName nvarchar(60) NOT NULL,
    FullName AS (LTRIM(RTRIM(CONCAT(FirstName,N' ',LastName)))),
    ProviderType varchar(40) NULL,
    Credentials varchar(30) NULL,
    Specialty nvarchar(100) NOT NULL,
    DepartmentID int NOT NULL REFERENCES dbo.Department(DepartmentID),
    Phone varchar(30) NULL,
    Email varchar(150) NULL,
    LicenseNumber varchar(30) NOT NULL,
    ActiveFlag bit NOT NULL CONSTRAINT DF_Provider_ActiveFlag DEFAULT 1
);

CREATE TABLE dbo.Patient(
    -- Core identifiers and frequently taught demographics are intentionally first
    -- so SELECT * is easier to demonstrate in beginner YouTube lessons.
    PatientID int IDENTITY PRIMARY KEY,
    EnterpriseMRN varchar(20) NOT NULL UNIQUE,
    FacilityMRN varchar(20) NOT NULL,

    FirstName nvarchar(60) NOT NULL,
    MiddleName nvarchar(60) NULL,
    LastName nvarchar(60) NOT NULL,
    FullName AS (CONCAT(FirstName,N' ',COALESCE(NULLIF(LTRIM(RTRIM(MiddleName)),N'')+N' ',N''),LastName)),
    PreferredName nvarchar(60) NULL,

    DateOfBirth date NOT NULL,
    AgeYears int NULL,
    AgeGroup varchar(30) NOT NULL,
    SexAtBirth varchar(10) NOT NULL,
    GenderIdentity varchar(40) NOT NULL,
    Pronouns varchar(30) NULL,
    MaritalStatus varchar(30) NULL,

    CountryOfBirth nvarchar(80) NOT NULL,
    Citizenship nvarchar(80) NOT NULL,
    Country nvarchar(80) NOT NULL,
    ProvinceState nvarchar(80) NOT NULL,
    City nvarchar(80) NOT NULL,
    PostalCode varchar(20) NOT NULL,

    PrimaryLanguage nvarchar(50) NOT NULL,
    SecondaryLanguage nvarchar(50) NULL,
    InterpreterRequired bit NOT NULL,

    MobilePhone varchar(30) NULL,
    HomePhone varchar(30) NULL,
    EmailAddress varchar(150) NULL,
    PreferredContactMethod varchar(20) NOT NULL,
    AddressLine1 nvarchar(120) NOT NULL,
    AddressLine2 nvarchar(120) NULL,

    HealthCardNumber varchar(25) NULL,
    HealthCardVersion varchar(5) NULL,
    HealthCardExpiry date NULL,
    LegacyMRN varchar(20) NULL,
    NationalIDToken varchar(64) NULL,

    PrimaryCareProviderID int NULL REFERENCES dbo.Provider(ProviderID),
    EmergencyContactName nvarchar(120) NULL,
    EmergencyContactRelationship varchar(40) NULL,
    EmergencyContactPhone varchar(30) NULL,

    BloodType varchar(5) NULL,
    RhFactor char(1) NULL,
    OrganDonorFlag bit NOT NULL,
    SmokingStatus varchar(30) NOT NULL,
    AlcoholUse varchar(30) NOT NULL,
    HeightCm decimal(5,2) NULL,
    WeightKg decimal(6,2) NULL,
    BMI decimal(5,2) NULL,
    PregnancyStatus varchar(30) NOT NULL,
    DisabilityStatus varchar(50) NOT NULL,
    MobilityStatus varchar(50) NOT NULL,
    CommunicationNeeds varchar(100) NULL,

    PrivacyLevel varchar(20) NOT NULL,
    ConsentStatus varchar(30) NOT NULL,
    PatientStatus varchar(30) NOT NULL,
    DeceasedFlag bit NOT NULL,
    DeathDateTime datetime2(0) NULL,
    RegistrationSource varchar(40) NOT NULL,
    CreatedAt datetime2(0) NOT NULL,
    UpdatedAt datetime2(0) NOT NULL,
    LastSeenAt datetime2(0) NULL,

    CONSTRAINT CK_Patient_AgeYears CHECK(AgeYears IS NULL OR AgeYears BETWEEN 0 AND 125),
    CONSTRAINT CK_Patient_Deceased CHECK(
        (DeceasedFlag=0 AND DeathDateTime IS NULL) OR
        (DeceasedFlag=1 AND DeathDateTime IS NOT NULL)
    )
);

CREATE TABLE dbo.InsurancePolicy(
    InsurancePolicyID bigint IDENTITY PRIMARY KEY,
    PatientID int NOT NULL REFERENCES dbo.Patient(PatientID),
    PayerCode varchar(20) NULL,
    PayerName nvarchar(120) NOT NULL,
    PlanName nvarchar(120) NOT NULL,
    MemberNumber varchar(40) NOT NULL,
    GroupNumber varchar(40) NULL,
    RelationshipToSubscriber varchar(30) NULL,
    CoverageType varchar(40) NULL,
    FinancialClass varchar(30) NOT NULL,
    EffectiveDate date NOT NULL,
    ExpiryDate date NULL,
    PrimaryFlag bit NOT NULL
);

CREATE TABLE dbo.Encounter(
    EncounterID bigint IDENTITY PRIMARY KEY,
    VisitNumber varchar(25) NOT NULL UNIQUE,
    AccountNumber varchar(30) NULL,
    PatientID int NOT NULL REFERENCES dbo.Patient(PatientID),
    FacilityID int NOT NULL REFERENCES dbo.Facility(FacilityID),
    DepartmentID int NOT NULL REFERENCES dbo.Department(DepartmentID),
    LocationID int NULL REFERENCES dbo.Location(LocationID),
    PatientClass varchar(10) NOT NULL,
    EncounterType varchar(40) NOT NULL,
    EncounterStatus varchar(30) NOT NULL,
    ServiceCode varchar(20) NOT NULL,
    AdmissionType varchar(30) NULL,
    ReasonForVisit nvarchar(120) NULL,
    ChiefComplaint nvarchar(200) NULL,
    AdmitDateTime datetime2(0) NOT NULL,
    DischargeDateTime datetime2(0) NULL,
    AttendingProviderID int NOT NULL REFERENCES dbo.Provider(ProviderID),
    AdmittingProviderID int NULL REFERENCES dbo.Provider(ProviderID),
    ReferringProviderID int NULL REFERENCES dbo.Provider(ProviderID),
    AdmissionSource varchar(40) NOT NULL,
    DischargeDisposition varchar(60) NULL,
    AssignedUnit varchar(20) NULL,
    AssignedRoom varchar(20) NULL,
    AssignedBed varchar(20) NULL,
    PriorUnit varchar(20) NULL,
    PriorRoom varchar(20) NULL,
    PriorBed varchar(20) NULL,
    FinancialClass varchar(30) NOT NULL,
    CreatedAt datetime2(0) NOT NULL,
    UpdatedAt datetime2(0) NOT NULL,
    CONSTRAINT CK_Encounter_Dates CHECK(DischargeDateTime IS NULL OR DischargeDateTime>=AdmitDateTime)
);

CREATE TABLE dbo.ADTEvent(
    ADTEventID bigint IDENTITY PRIMARY KEY,
    EncounterID bigint NOT NULL REFERENCES dbo.Encounter(EncounterID),
    PatientID int NOT NULL REFERENCES dbo.Patient(PatientID),
    TriggerEvent varchar(5) NOT NULL,
    MessageType varchar(15) NOT NULL,
    HL7Version varchar(10) NULL,
    SourceSystem varchar(60) NULL,
    DestinationSystem varchar(60) NULL,
    EventReasonCode varchar(30) NULL,
    EventDateTime datetime2(0) NOT NULL,
    FromUnit varchar(20) NULL,
    FromRoom varchar(20) NULL,
    FromBed varchar(20) NULL,
    ToUnit varchar(20) NULL,
    ToRoom varchar(20) NULL,
    ToBed varchar(20) NULL,
    MessageControlID varchar(50) NOT NULL UNIQUE,
    ProcessingStatus varchar(20) NOT NULL
);

CREATE TABLE dbo.Diagnosis(
    DiagnosisID bigint IDENTITY PRIMARY KEY,
    EncounterID bigint NOT NULL REFERENCES dbo.Encounter(EncounterID),
    PatientID int NOT NULL REFERENCES dbo.Patient(PatientID),
    DiagnosisCode varchar(20) NOT NULL,
    CodeSystem varchar(30) NULL,
    DiagnosisDescription nvarchar(200) NOT NULL,
    DiagnosisCategory nvarchar(100) NOT NULL,
    DiagnosisType varchar(30) NOT NULL,
    DiagnosisRank int NULL,
    PresentOnAdmission bit NOT NULL,
    DiagnosisDate date NOT NULL,
    ActiveFlag bit NOT NULL
);

CREATE TABLE dbo.Allergy(
    AllergyID bigint IDENTITY PRIMARY KEY,
    PatientID int NOT NULL REFERENCES dbo.Patient(PatientID),
    AllergenCode varchar(30) NULL,
    CodeSystem varchar(30) NULL,
    Allergen nvarchar(120) NOT NULL,
    AllergyType varchar(40) NOT NULL,
    Reaction nvarchar(150) NOT NULL,
    Severity varchar(20) NOT NULL,
    VerificationStatus varchar(30) NULL,
    Status varchar(20) NOT NULL,
    OnsetDate date NULL
);

CREATE TABLE dbo.MedicationOrder(
    MedicationOrderID bigint IDENTITY PRIMARY KEY,
    EncounterID bigint NOT NULL REFERENCES dbo.Encounter(EncounterID),
    PatientID int NOT NULL REFERENCES dbo.Patient(PatientID),
    OrderNumber varchar(30) NOT NULL UNIQUE,
    MedicationCode varchar(30) NOT NULL,
    MedicationCodeSystem varchar(40) NULL,
    MedicationName nvarchar(150) NOT NULL,
    Dose decimal(10,2) NOT NULL,
    DoseUnit varchar(20) NOT NULL,
    Route varchar(30) NOT NULL,
    Frequency varchar(30) NOT NULL,
    PRNFlag bit NULL,
    OrderStatus varchar(20) NOT NULL,
    OrderDateTime datetime2(0) NOT NULL,
    StartDateTime datetime2(0) NULL,
    EndDateTime datetime2(0) NULL,
    OrderingProviderID int NOT NULL REFERENCES dbo.Provider(ProviderID)
);

CREATE TABLE dbo.LabOrder(
    LabOrderID bigint IDENTITY PRIMARY KEY,
    EncounterID bigint NOT NULL REFERENCES dbo.Encounter(EncounterID),
    PatientID int NOT NULL REFERENCES dbo.Patient(PatientID),
    AccessionNumber varchar(30) NOT NULL UNIQUE,
    PlacerOrderNumber varchar(40) NULL,
    FillerOrderNumber varchar(40) NULL,
    OrderCode varchar(20) NOT NULL,
    OrderName nvarchar(120) NOT NULL,
    SpecimenType varchar(50) NULL,
    Priority varchar(20) NOT NULL,
    OrderStatus varchar(20) NOT NULL,
    OrderDateTime datetime2(0) NOT NULL,
    CollectedDateTime datetime2(0) NULL,
    ResultedDateTime datetime2(0) NULL,
    OrderingProviderID int NOT NULL REFERENCES dbo.Provider(ProviderID)
);

CREATE TABLE dbo.LabResult(
    LabResultID bigint IDENTITY PRIMARY KEY,
    LabOrderID bigint NOT NULL REFERENCES dbo.LabOrder(LabOrderID),
    TestCode varchar(20) NOT NULL,
    LOINCCode varchar(20) NULL,
    TestName nvarchar(120) NOT NULL,
    ValueType varchar(10) NULL,
    ResultValue varchar(50) NOT NULL,
    ResultUnit varchar(30) NULL,
    ReferenceRange varchar(50) NULL,
    AbnormalFlag varchar(10) NULL,
    ResultStatus varchar(20) NOT NULL,
    ObservationDateTime datetime2(0) NOT NULL
);

CREATE TABLE dbo.InterfaceMessage(
    InterfaceMessageID bigint IDENTITY PRIMARY KEY,
    PatientID int NULL REFERENCES dbo.Patient(PatientID),
    EncounterID bigint NULL REFERENCES dbo.Encounter(EncounterID),
    ChannelName varchar(120) NOT NULL,
    MessageType varchar(20) NOT NULL,
    TriggerEvent varchar(10) NULL,
    HL7Version varchar(10) NULL,
    MessageControlID varchar(50) NOT NULL UNIQUE,
    SourceSystem varchar(60) NOT NULL,
    DestinationSystem varchar(60) NOT NULL,
    Direction varchar(20) NULL,
    TransportProtocol varchar(20) NULL,
    ReceivedDateTime datetime2(0) NOT NULL,
    ProcessedDateTime datetime2(0) NULL,
    ProcessingTimeMs int NULL,
    ProcessingStatus varchar(20) NOT NULL,
    AckStatus varchar(20) NULL,
    RetryCount int NOT NULL DEFAULT 0,
    PayloadFormat varchar(20) NOT NULL
);

CREATE TABLE dbo.InterfaceError(
    InterfaceErrorID bigint IDENTITY PRIMARY KEY,
    InterfaceMessageID bigint NOT NULL REFERENCES dbo.InterfaceMessage(InterfaceMessageID),
    ErrorDateTime datetime2(0) NOT NULL,
    Severity varchar(20) NULL,
    ErrorCode varchar(40) NOT NULL,
    ErrorCategory varchar(60) NOT NULL,
    SegmentName varchar(10) NULL,
    FieldPosition varchar(20) NULL,
    ErrorMessage nvarchar(500) NOT NULL,
    ResolvedFlag bit NOT NULL,
    ResolutionNotes nvarchar(500) NULL
);

CREATE TABLE dbo.AuditLog(
    AuditLogID bigint IDENTITY PRIMARY KEY,
    EventDateTime datetime2(0) NOT NULL,
    UserOrSystem varchar(100) NOT NULL,
    ApplicationName varchar(100) NULL,
    WorkstationName varchar(100) NULL,
    ActionType varchar(30) NOT NULL,
    EntityType varchar(50) NOT NULL,
    EntityID varchar(50) NOT NULL,
    PatientID int NULL REFERENCES dbo.Patient(PatientID),
    Description nvarchar(500) NOT NULL,
    SourceIP varchar(45) NULL
);
GO

INSERT dbo.Facility(FacilityCode,FacilityName,City,ProvinceState,Country) VALUES
('MCTH',N'MirthCare University Hospital',N'Toronto',N'Ontario',N'Canada'),
('MCRC',N'MirthCare Rehabilitation Centre',N'Brampton',N'Ontario',N'Canada'),
('MCCL',N'MirthCare Community Clinic',N'Mississauga',N'Ontario',N'Canada');

INSERT dbo.Department(FacilityID,DepartmentCode,DepartmentName,ServiceLine) VALUES
(1,'ED',N'Emergency Department',N'Emergency'),(1,'CARD',N'Cardiology',N'Medicine'),
(1,'NEUR',N'Neurology',N'Medicine'),(1,'ONC',N'Oncology',N'Cancer Care'),
(1,'ORTH',N'Orthopedics',N'Surgery'),(1,'GENS',N'General Surgery',N'Surgery'),
(1,'ICU',N'Intensive Care Unit',N'Critical Care'),(1,'MED',N'General Internal Medicine',N'Medicine'),
(1,'OBS',N'Observation Unit',N'Emergency'),(1,'MH',N'Mental Health',N'Mental Health'),
(1,'PEDS',N'Pediatrics',N'Child Health'),(1,'OBGYN',N'Obstetrics and Gynecology',N'Women''s Health'),
(1,'RENAL',N'Nephrology',N'Medicine'),(1,'RESP',N'Respiratory Medicine',N'Medicine'),
(2,'REHAB',N'Inpatient Rehabilitation',N'Rehabilitation'),(2,'CCC',N'Complex Continuing Care',N'Continuing Care'),
(2,'PT',N'Physiotherapy',N'Rehabilitation'),(2,'OT',N'Occupational Therapy',N'Rehabilitation'),
(3,'FAM',N'Family Medicine Clinic',N'Primary Care'),(3,'DIAB',N'Diabetes Education Clinic',N'Ambulatory');
GO

;WITH n AS(
 SELECT TOP(125) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) n
 FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT dbo.Location(DepartmentID,UnitCode,RoomCode,BedCode,LocationDescription,LocationType)
SELECT 1+((n-1)%20),CONCAT('U',RIGHT('00'+CAST(1+((n-1)%20) AS varchar(2)),2)),
       CONCAT('R',100+((n-1)%80)),CONCAT('B',1+((n-1)%2)),
       CONCAT('Unit ',1+((n-1)%20),' Room ',100+((n-1)%80),' Bed ',1+((n-1)%2)),
       CHOOSE(1+((n-1)%5),'Inpatient','Outpatient','Emergency','Rehabilitation','Clinic')
FROM n;

;WITH n AS(
 SELECT TOP(80) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) n FROM sys.all_objects
)
INSERT dbo.Provider(ProviderNumber,FirstName,LastName,Specialty,DepartmentID,Phone,Email,LicenseNumber)
SELECT CONCAT('PRV',RIGHT('00000'+CAST(n AS varchar(5)),5)),
       CHOOSE(1+((n-1)%20),N'Alex',N'Maya',N'Daniel',N'Sofia',N'Arjun',N'Layla',N'Noah',N'Emma',N'Omar',N'Anika',N'Lucas',N'Isabella',N'Ethan',N'Amina',N'Leo',N'Nora',N'Ryan',N'Zara',N'Adrian',N'Priya'),
       CHOOSE(1+((n*7-1)%20),N'Newton',N'Santos',N'Rahman',N'Chen',N'Patel',N'Martin',N'Okafor',N'Kim',N'Rossi',N'Singh',N'Garcia',N'Brown',N'Hassan',N'Kowalski',N'Nguyen',N'Wilson',N'Khan',N'Murphy',N'Silva',N'Ito'),
       CHOOSE(1+((n-1)%15),N'Emergency Medicine',N'Cardiology',N'Neurology',N'Oncology',N'Orthopedic Surgery',N'General Surgery',N'Critical Care',N'Internal Medicine',N'Psychiatry',N'Pediatrics',N'Obstetrics',N'Nephrology',N'Respiratory Medicine',N'Rehabilitation Medicine',N'Family Medicine'),
       1+((n-1)%20),CONCAT('+1-416-555-',RIGHT('0000'+CAST(1000+n AS varchar(4)),4)),
       CONCAT('provider',n,'@mirthcare.example'),CONCAT('CPSO-SYN-',100000+n)
FROM n;
GO

;WITH n AS(
 SELECT TOP(1200) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) n
 FROM sys.all_objects a CROSS JOIN sys.all_objects b
), p AS(
 SELECT n,DATEADD(day,-((n*37)%365),DATEADD(year,-(n%96),CAST('2026-08-01' AS date))) DOB
 FROM n
)
INSERT dbo.Patient(
 EnterpriseMRN,FacilityMRN,LegacyMRN,HealthCardNumber,HealthCardVersion,HealthCardExpiry,NationalIDToken,
 FirstName,MiddleName,LastName,PreferredName,DateOfBirth,AgeGroup,SexAtBirth,GenderIdentity,Pronouns,
 MaritalStatus,BloodType,RhFactor,PrimaryLanguage,SecondaryLanguage,CountryOfBirth,Citizenship,
 AddressLine1,AddressLine2,City,ProvinceState,PostalCode,Country,HomePhone,MobilePhone,EmailAddress,
 PreferredContactMethod,EmergencyContactName,EmergencyContactRelationship,EmergencyContactPhone,
 PrimaryCareProviderID,OrganDonorFlag,SmokingStatus,AlcoholUse,HeightCm,WeightKg,BMI,PregnancyStatus,
 DisabilityStatus,MobilityStatus,CommunicationNeeds,InterpreterRequired,PrivacyLevel,ConsentStatus,
 PatientStatus,DeceasedFlag,DeathDateTime,RegistrationSource,CreatedAt,UpdatedAt,LastSeenAt)
SELECT
 CONCAT('MCU',RIGHT('0000000'+CAST(n AS varchar(7)),7)),
 CONCAT(CHOOSE(1+((n-1)%3),'MCTH','MCRC','MCCL'),RIGHT('000000'+CAST(200000+n AS varchar(6)),6)),
 CASE WHEN n%5=0 THEN CONCAT('LEG',500000+n) END,
 CASE WHEN n%11=0 THEN NULL ELSE CONCAT('SYN',7000000000+n) END,
 CASE WHEN n%11=0 THEN NULL ELSE CHAR(65+n%26)+CHAR(65+(n*3)%26) END,
 CASE WHEN n%11=0 THEN NULL ELSE DATEFROMPARTS(2027+n%5,12,31) END,
 CONVERT(varchar(64),HASHBYTES('SHA2_256',CONCAT('MIRTHCARE-',n)),2),
 CHOOSE(1+((n-1)%40),N'Aarav',N'Mateo',N'Leona',N'Amara',N'Kai',N'Zoya',N'Noel',N'Mira',N'Diego',N'Anaya',N'Rafael',N'Ada',N'Nikhil',N'Selene',N'Karim',N'Elena',N'Theo',N'Aisha',N'Rian',N'Mei',N'Kabir',N'Lina',N'Samir',N'Nadia',N'Marco',N'Ivy',N'Arlo',N'Sana',N'Jonas',N'Kiara',N'Emil',N'Rhea',N'Yusuf',N'Clara',N'Andre',N'Noor',N'Dev',N'Alina',N'Milan',N'Tara'),
 CASE WHEN n%3=0 THEN CHOOSE(1+((n-1)%10),N'James',N'Rose',N'Kumar',N'Marie',N'Lee',N'Anne',N'Ray',N'Jade',N'Luis',N'Grace') END,
 CHOOSE(1+((n*7-1)%40),N'Santos',N'Rahman',N'Chen',N'Patel',N'Martin',N'Okafor',N'Kim',N'Rossi',N'Singh',N'Garcia',N'Brown',N'Hassan',N'Kowalski',N'Nguyen',N'Wilson',N'Khan',N'Murphy',N'Silva',N'Ito',N'Das',N'Bennett',N'Costa',N'Malik',N'Park',N'Shah',N'Lopez',N'Young',N'Nakamura',N'Roy',N'Ahmed',N'Fernandez',N'Bose',N'Campbell',N'Jensen',N'Sato',N'Ibrahim',N'Taylor',N'Mehta',N'Clark',N'Pereira'),
 CASE WHEN n%4=0 THEN CHOOSE(1+((n-1)%10),N'Champ',N'Nova',N'Sunny',N'Rocket',N'Jazz',N'Max',N'Sky',N'Ace',N'Rio',N'Joy') END,
 DOB,
 CASE WHEN DATEDIFF(year,DOB,'2026-08-01')<1 THEN 'Infant' WHEN DATEDIFF(year,DOB,'2026-08-01')<13 THEN 'Child' WHEN DATEDIFF(year,DOB,'2026-08-01')<18 THEN 'Adolescent' WHEN DATEDIFF(year,DOB,'2026-08-01')<65 THEN 'Adult' ELSE 'Older Adult' END,
 CHOOSE(1+((n-1)%3),'Male','Female','Intersex'),
 CHOOSE(1+((n-1)%6),'Man','Woman','Non-binary','Transgender Man','Transgender Woman','Prefer not to say'),
 CHOOSE(1+((n-1)%6),'he/him','she/her','they/them','he/him','she/her','not specified'),
 CHOOSE(1+((n-1)%5),'Single','Married','Divorced','Widowed','Common-law'),
 CHOOSE(1+((n-1)%8),'A','A','B','B','AB','AB','O','O'),CASE WHEN n%2=0 THEN '+' ELSE '-' END,
 CHOOSE(1+((n-1)%12),N'English',N'French',N'Hindi',N'Telugu',N'Spanish',N'Arabic',N'Mandarin',N'Punjabi',N'Portuguese',N'Korean',N'Italian',N'Tamil'),
 CASE WHEN n%4=0 THEN CHOOSE(1+((n-1)%8),N'English',N'French',N'Hindi',N'Spanish',N'Arabic',N'Mandarin',N'Punjabi',N'Portuguese') END,
 CHOOSE(1+((n-1)%20),N'Canada',N'India',N'Brazil',N'Portugal',N'Argentina',N'France',N'Nigeria',N'China',N'Japan',N'South Korea',N'Egypt',N'Pakistan',N'Italy',N'Germany',N'Mexico',N'Philippines',N'United Kingdom',N'Australia',N'Kenya',N'United States'),
 CHOOSE(1+((n*3-1)%20),N'Canadian',N'Indian',N'Brazilian',N'Portuguese',N'Argentinian',N'French',N'Nigerian',N'Chinese',N'Japanese',N'South Korean',N'Egyptian',N'Pakistani',N'Italian',N'German',N'Mexican',N'Filipino',N'British',N'Australian',N'Kenyan',N'American'),
 CONCAT(100+n%8900,N' Training Avenue'),CASE WHEN n%5=0 THEN CONCAT(N'Unit ',1+n%30) END,
 CHOOSE(1+((n-1)%15),N'Toronto',N'Brampton',N'Mississauga',N'Ottawa',N'Vancouver',N'Calgary',N'Montreal',N'Hyderabad',N'Lisbon',N'Rio de Janeiro',N'Paris',N'Lagos',N'Tokyo',N'Manila',N'Mexico City'),
 CHOOSE(1+((n-1)%12),N'Ontario',N'Ontario',N'Ontario',N'Quebec',N'British Columbia',N'Alberta',N'Telangana',N'Lisbon',N'Rio de Janeiro',N'Île-de-France',N'Lagos',N'Tokyo'),
 CONCAT(CHAR(65+n%26),n%10,CHAR(65+(n*2)%26),' ',(n+3)%10,CHAR(65+(n*5)%26),(n+7)%10),
 CHOOSE(1+((n-1)%20),N'Canada',N'Canada',N'Canada',N'Canada',N'Canada',N'Canada',N'India',N'Portugal',N'Brazil',N'France',N'Nigeria',N'Japan',N'Philippines',N'Mexico',N'United States',N'China',N'Italy',N'Germany',N'Australia',N'Pakistan'),
 CASE WHEN n%4<>0 THEN CONCAT('+1-416-555-',RIGHT('0000'+CAST(1000+n%8999 AS varchar(4)),4)) END,
 CONCAT('+1-647-555-',RIGHT('0000'+CAST(1000+(n*7)%8999 AS varchar(4)),4)),CONCAT('patient',n,'@training.mirthcare.example'),
 CHOOSE(1+((n-1)%4),'Mobile','Email','Home Phone','Patient Portal'),CONCAT(N'Emergency Contact ',n),
 CHOOSE(1+((n-1)%6),'Spouse','Parent','Sibling','Child','Friend','Guardian'),
 CONCAT('+1-905-555-',RIGHT('0000'+CAST(1000+(n*11)%8999 AS varchar(4)),4)),1+((n-1)%80),
 CASE WHEN n%3=0 THEN 1 ELSE 0 END,CHOOSE(1+((n-1)%5),'Never','Former','Current','Unknown','Passive exposure'),
 CHOOSE(1+((n-1)%5),'None','Occasional','Moderate','Frequent','Unknown'),
 CAST(145+(n*13)%55 AS decimal(5,2)),CAST(45+(n*17)%80 AS decimal(6,2)),
 CAST((45+(n*17)%80)/POWER((145+(n*13)%55)/100.0,2) AS decimal(5,2)),
 CASE WHEN ((n-1)%3)=1 AND DATEDIFF(year,DOB,'2026-08-01') BETWEEN 15 AND 50 THEN CHOOSE(1+((n-1)%4),'Not pregnant','Pregnant','Unknown','Not documented') ELSE 'Not applicable' END,
 CHOOSE(1+((n-1)%6),'None','Visual impairment','Hearing impairment','Cognitive impairment','Physical disability','Multiple'),
 CHOOSE(1+((n-1)%6),'Independent','Cane','Walker','Wheelchair','Two-person assist','Bedbound'),
 CASE WHEN n%7=0 THEN CHOOSE(1+((n-1)%5),'Large print','Hearing assistance','Communication board','Interpreter','Caregiver support') END,
 CASE WHEN n%6=0 THEN 1 ELSE 0 END,CHOOSE(1+((n-1)%4),'Standard','Restricted','VIP','Research'),
 CHOOSE(1+((n-1)%4),'Full consent','Limited consent','Pending','Declined optional sharing'),
 CASE WHEN n%37=0 THEN 'Deceased' ELSE 'Active' END,CASE WHEN n%37=0 THEN 1 ELSE 0 END,
 CASE WHEN n%37=0 THEN DATEADD(day,-(n%300),CAST('2026-07-31' AS datetime2)) END,
 CHOOSE(1+((n-1)%6),'Emergency','Registration Desk','Clinic','Referral','Transfer','Patient Portal'),
 DATEADD(day,-(365+n%1200),CAST('2026-08-01' AS datetime2)),DATEADD(day,-n%90,CAST('2026-08-01' AS datetime2)),
 CASE WHEN n%37=0 THEN NULL ELSE DATEADD(day,-n%180,CAST('2026-08-01' AS datetime2)) END
FROM p;
GO

INSERT dbo.InsurancePolicy(PatientID,PayerName,PlanName,MemberNumber,FinancialClass,EffectiveDate,ExpiryDate,PrimaryFlag)
SELECT PatientID,
 CHOOSE(1+((PatientID-1)%8),N'Ontario Health',N'MirthCare Benefits',N'Blue Training Shield',N'Global Student Health',N'Workers Compensation Training',N'Federal Health Program',N'Private International Plan',N'Self Pay'),
 CHOOSE(1+((PatientID-1)%6),N'OHIP Synthetic',N'Extended Health',N'Basic Hospital',N'International Visitor',N'Workplace Injury',N'Self Pay'),
 CONCAT('MEM',900000000+PatientID),CHOOSE(1+((PatientID-1)%6),'PROV','PRIVATE','SELF','WSIB','FED','INTL'),
 '2024-01-01','2028-12-31',1
FROM dbo.Patient;
GO

;WITH e AS(
 SELECT p.PatientID,v.Seq FROM dbo.Patient p CROSS JOIN(VALUES(1),(2),(3))v(Seq)
 WHERE p.DeceasedFlag=0 OR v.Seq<3
)
INSERT dbo.Encounter(VisitNumber,PatientID,FacilityID,DepartmentID,LocationID,PatientClass,EncounterType,EncounterStatus,
 ServiceCode,AdmitDateTime,DischargeDateTime,AttendingProviderID,AdmittingProviderID,ReferringProviderID,AdmissionSource,
 DischargeDisposition,AssignedUnit,AssignedRoom,AssignedBed,PriorUnit,PriorRoom,PriorBed,FinancialClass,CreatedAt,UpdatedAt)
SELECT CONCAT('VIS',RIGHT('0000000000'+CAST(PatientID*10+Seq AS varchar(10)),10)),PatientID,1+((PatientID+Seq-2)%3),
 1+((PatientID*3+Seq-2)%20),1+((PatientID*5+Seq-2)%125),CHOOSE(1+((PatientID+Seq-2)%4),'I','O','E','R'),
 CHOOSE(1+((PatientID+Seq-2)%6),'Inpatient','Outpatient','Emergency','Rehabilitation','Clinic','Observation'),'Discharged',
 CHOOSE(1+((PatientID+Seq-2)%15),'ED','CARD','NEUR','ONC','ORTH','GENS','ICU','MED','MH','PEDS','OBGYN','RENAL','RESP','REHAB','CCC'),
 DATEADD(day,-(30+(PatientID*Seq)%900),DATEADD(hour,(PatientID+Seq)%24,CAST('2026-08-01' AS datetime2))),
 DATEADD(day,-(27+(PatientID*Seq)%900),DATEADD(hour,(PatientID+Seq)%24,CAST('2026-08-01' AS datetime2))),
 1+((PatientID*7+Seq-2)%80),1+((PatientID*11+Seq-2)%80),1+((PatientID*13+Seq-2)%80),
 CHOOSE(1+((PatientID+Seq-2)%6),'Emergency','Clinic Referral','Transfer','Scheduled','Physician Referral','Self Referral'),
 CHOOSE(1+((PatientID+Seq-2)%6),'Home','Rehabilitation','Long Term Care','Transfer','Against Medical Advice','Expired'),
 CONCAT('U',RIGHT('00'+CAST(1+(PatientID+Seq)%20 AS varchar(2)),2)),CONCAT('R',100+(PatientID+Seq)%80),CONCAT('B',1+(PatientID+Seq)%2),
 CONCAT('U',RIGHT('00'+CAST(1+(PatientID+Seq+3)%20 AS varchar(2)),2)),CONCAT('R',100+(PatientID+Seq+7)%80),CONCAT('B',1+(PatientID+Seq+1)%2),
 CHOOSE(1+((PatientID+Seq-2)%6),'PROV','PRIVATE','SELF','WSIB','FED','INTL'),
 DATEADD(day,-(35+(PatientID*Seq)%900),CAST('2026-08-01' AS datetime2)),DATEADD(day,-(27+(PatientID*Seq)%900),CAST('2026-08-01' AS datetime2))
FROM e;
GO

;WITH a AS(SELECT TOP(180) PatientID FROM dbo.Patient WHERE DeceasedFlag=0 ORDER BY PatientID)
INSERT dbo.Encounter(VisitNumber,PatientID,FacilityID,DepartmentID,LocationID,PatientClass,EncounterType,EncounterStatus,
 ServiceCode,AdmitDateTime,DischargeDateTime,AttendingProviderID,AdmittingProviderID,ReferringProviderID,AdmissionSource,
 DischargeDisposition,AssignedUnit,AssignedRoom,AssignedBed,PriorUnit,PriorRoom,PriorBed,FinancialClass,CreatedAt,UpdatedAt)
SELECT CONCAT('ACT',RIGHT('0000000000'+CAST(PatientID AS varchar(10)),10)),PatientID,1,1+((PatientID-1)%20),1+((PatientID*9-1)%125),
 CASE WHEN PatientID%5=0 THEN 'R' ELSE 'I' END,CASE WHEN PatientID%5=0 THEN 'Rehabilitation' ELSE 'Inpatient' END,
 'Active',CHOOSE(1+((PatientID-1)%12),'CARD','NEUR','ONC','ORTH','ICU','MED','MH','PEDS','OBGYN','RENAL','RESP','REHAB'),
 DATEADD(day,-(1+PatientID%25),DATEADD(hour,PatientID%24,CAST('2026-08-01' AS datetime2))),NULL,
 1+((PatientID*7-1)%80),1+((PatientID*11-1)%80),1+((PatientID*13-1)%80),
 CHOOSE(1+((PatientID-1)%4),'Emergency','Transfer','Scheduled','Clinic Referral'),NULL,
 CONCAT('U',RIGHT('00'+CAST(1+PatientID%20 AS varchar(2)),2)),CONCAT('R',100+PatientID%80),CONCAT('B',1+PatientID%2),
 NULL,NULL,NULL,CHOOSE(1+((PatientID-1)%6),'PROV','PRIVATE','SELF','WSIB','FED','INTL'),
 DATEADD(day,-(2+PatientID%25),CAST('2026-08-01' AS datetime2)),CAST('2026-08-01' AS datetime2)
FROM a;
GO

INSERT dbo.ADTEvent(EncounterID,PatientID,TriggerEvent,MessageType,EventDateTime,ToUnit,ToRoom,ToBed,MessageControlID,ProcessingStatus)
SELECT EncounterID,PatientID,'A01','ADT^A01',AdmitDateTime,AssignedUnit,AssignedRoom,AssignedBed,CONCAT('A01-',EncounterID),'PROCESSED' FROM dbo.Encounter;
INSERT dbo.ADTEvent(EncounterID,PatientID,TriggerEvent,MessageType,EventDateTime,FromUnit,FromRoom,FromBed,ToUnit,ToRoom,ToBed,MessageControlID,ProcessingStatus)
SELECT EncounterID,PatientID,'A08','ADT^A08',DATEADD(hour,4,AdmitDateTime),AssignedUnit,AssignedRoom,AssignedBed,AssignedUnit,AssignedRoom,AssignedBed,CONCAT('A08-',EncounterID),'PROCESSED' FROM dbo.Encounter WHERE EncounterID%2=0;
INSERT dbo.ADTEvent(EncounterID,PatientID,TriggerEvent,MessageType,EventDateTime,FromUnit,FromRoom,FromBed,ToUnit,ToRoom,ToBed,MessageControlID,ProcessingStatus)
SELECT EncounterID,PatientID,'A02','ADT^A02',DATEADD(day,1,AdmitDateTime),PriorUnit,PriorRoom,PriorBed,AssignedUnit,AssignedRoom,AssignedBed,CONCAT('A02-',EncounterID),'PROCESSED' FROM dbo.Encounter WHERE PatientClass IN('I','R') AND EncounterID%3=0;
INSERT dbo.ADTEvent(EncounterID,PatientID,TriggerEvent,MessageType,EventDateTime,FromUnit,FromRoom,FromBed,MessageControlID,ProcessingStatus)
SELECT EncounterID,PatientID,'A03','ADT^A03',DischargeDateTime,AssignedUnit,AssignedRoom,AssignedBed,CONCAT('A03-',EncounterID),'PROCESSED' FROM dbo.Encounter WHERE DischargeDateTime IS NOT NULL;
GO

INSERT dbo.Diagnosis(EncounterID,PatientID,DiagnosisCode,DiagnosisDescription,DiagnosisCategory,DiagnosisType,PresentOnAdmission,DiagnosisDate,ActiveFlag)
SELECT EncounterID,PatientID,
 CHOOSE(1+((EncounterID-1)%20),'I10','E11.9','J45.909','E78.5','I50.9','J18.9','N18.3','M17.9','F41.9','F32.9','G43.909','K21.9','I48.91','D64.9','E03.9','M54.5','N39.0','R07.9','S72.009A','C50.919'),
 CHOOSE(1+((EncounterID-1)%20),N'Essential hypertension',N'Type 2 diabetes mellitus',N'Asthma',N'Hyperlipidemia',N'Heart failure',N'Pneumonia',N'Chronic kidney disease stage 3',N'Osteoarthritis of knee',N'Anxiety disorder',N'Depressive disorder',N'Migraine',N'Gastroesophageal reflux disease',N'Atrial fibrillation',N'Anemia',N'Hypothyroidism',N'Low back pain',N'Urinary tract infection',N'Chest pain',N'Hip fracture',N'Breast cancer'),
 CHOOSE(1+((EncounterID-1)%10),N'Cardiovascular',N'Endocrine',N'Respiratory',N'Metabolic',N'Renal',N'Musculoskeletal',N'Mental Health',N'Neurological',N'Infectious Disease',N'Oncology'),
 CASE WHEN EncounterID%4=0 THEN 'Secondary' ELSE 'Primary' END,CASE WHEN EncounterID%5=0 THEN 0 ELSE 1 END,
 CAST(AdmitDateTime AS date),1
FROM dbo.Encounter;

INSERT dbo.Allergy(PatientID,Allergen,AllergyType,Reaction,Severity,Status,OnsetDate)
SELECT PatientID,CHOOSE(1+((PatientID-1)%12),N'Penicillin',N'Shellfish',N'Peanuts',N'Latex',N'Sulfonamides',N'Ibuprofen',N'Contrast Media',N'Egg',N'Milk',N'Pollen',N'Dust Mites',N'No Known Drug Allergy'),
 CHOOSE(1+((PatientID-1)%4),'Drug','Food','Environmental','Other'),CHOOSE(1+((PatientID-1)%8),N'Rash',N'Hives',N'Swelling',N'Nausea',N'Wheezing',N'Anaphylaxis',N'Itching',N'Unknown'),
 CHOOSE(1+((PatientID-1)%4),'Mild','Moderate','Severe','Unknown'),'Active',DATEADD(year,-(1+PatientID%20),CAST('2026-01-01' AS date))
FROM dbo.Patient WHERE PatientID%3<>0;
GO

INSERT dbo.MedicationOrder(EncounterID,PatientID,OrderNumber,MedicationCode,MedicationName,Dose,DoseUnit,Route,Frequency,OrderStatus,OrderDateTime,OrderingProviderID)
SELECT EncounterID,PatientID,CONCAT('MED',RIGHT('0000000000'+CAST(EncounterID AS varchar(10)),10)),
 CHOOSE(1+((EncounterID-1)%12),'ACET','METF','AMLO','ATOR','PANT','SALB','FURO','ENOX','CEF','OND','GABA','LEV'),
 CHOOSE(1+((EncounterID-1)%12),N'Acetaminophen',N'Metformin',N'Amlodipine',N'Atorvastatin',N'Pantoprazole',N'Salbutamol',N'Furosemide',N'Enoxaparin',N'Ceftriaxone',N'Ondansetron',N'Gabapentin',N'Levothyroxine'),
 CAST(CHOOSE(1+((EncounterID-1)%8),1,2,5,10,20,40,500,1000) AS decimal(10,2)),CHOOSE(1+((EncounterID-1)%4),'mg','mg','mcg','mL'),
 CHOOSE(1+((EncounterID-1)%5),'PO','IV','SC','INH','IM'),CHOOSE(1+((EncounterID-1)%6),'DAILY','BID','TID','QID','Q4H PRN','STAT'),
 CASE WHEN EncounterStatus='Active' THEN 'ACTIVE' ELSE 'COMPLETED' END,DATEADD(hour,1,AdmitDateTime),AttendingProviderID
FROM dbo.Encounter;

INSERT dbo.LabOrder(EncounterID,PatientID,AccessionNumber,OrderCode,OrderName,Priority,OrderStatus,OrderDateTime,CollectedDateTime,ResultedDateTime,OrderingProviderID)
SELECT EncounterID,PatientID,CONCAT('ACC',RIGHT('0000000000'+CAST(EncounterID AS varchar(10)),10)),
 CHOOSE(1+((EncounterID-1)%6),'CBC','BMP','CMP','TROP','A1C','TSH'),
 CHOOSE(1+((EncounterID-1)%6),N'Complete Blood Count',N'Basic Metabolic Panel',N'Comprehensive Metabolic Panel',N'Troponin',N'Hemoglobin A1C',N'Thyroid Stimulating Hormone'),
 CASE WHEN PatientClass='E' THEN 'STAT' ELSE 'ROUTINE' END,'FINAL',DATEADD(hour,1,AdmitDateTime),DATEADD(hour,2,AdmitDateTime),DATEADD(hour,5,AdmitDateTime),AttendingProviderID
FROM dbo.Encounter;

INSERT dbo.LabResult(LabOrderID,TestCode,TestName,ResultValue,ResultUnit,ReferenceRange,AbnormalFlag,ResultStatus,ObservationDateTime)
SELECT lo.LabOrderID,v.TestCode,v.TestName,v.ResultValue,v.ResultUnit,v.ReferenceRange,v.AbnormalFlag,'FINAL',DATEADD(minute,v.OffsetMinutes,lo.ResultedDateTime)
FROM dbo.LabOrder lo
CROSS APPLY(VALUES
 ('WBC',N'White Blood Cell Count',CONVERT(varchar(20),CAST(4.0+(lo.LabOrderID%90)/10.0 AS decimal(5,1))),'10^9/L','4.0-11.0',CASE WHEN lo.LabOrderID%11=0 THEN 'H' ELSE 'N' END,0),
 ('HGB',N'Hemoglobin',CONVERT(varchar(20),CAST(100+lo.LabOrderID%70 AS decimal(5,1))),'g/L','120-170',CASE WHEN lo.LabOrderID%7=0 THEN 'L' ELSE 'N' END,1),
 ('NA',N'Sodium',CONVERT(varchar(20),CAST(130+lo.LabOrderID%16 AS int)),'mmol/L','135-145',CASE WHEN lo.LabOrderID%9=0 THEN 'L' ELSE 'N' END,2)
)v(TestCode,TestName,ResultValue,ResultUnit,ReferenceRange,AbnormalFlag,OffsetMinutes);
GO

INSERT dbo.InterfaceMessage(PatientID,EncounterID,ChannelName,MessageType,MessageControlID,SourceSystem,DestinationSystem,ReceivedDateTime,ProcessedDateTime,ProcessingStatus,RetryCount,PayloadFormat)
SELECT PatientID,EncounterID,
 CHOOSE(1+((EncounterID-1)%5),'PRD-EHR-MIRTH-ADT','PRD-EHR-MIRTH-LAB','PRD-EHR-MIRTH-PHARMACY','PRD-MIRTH-REPORTING','DEV-SQL-MIRTH-TRAINING'),
 CASE WHEN EncounterID%5=0 THEN 'ORU^R01' ELSE 'ADT^A01' END,CONCAT('INT-',EncounterID),
 CHOOSE(1+((EncounterID-1)%4),'Epic','Cerner','Meditech','MirthCareEHR'),
 CHOOSE(1+((EncounterID-1)%5),'Mirth Connect','SQL Server','Pyxis','PACS','Analytics'),AdmitDateTime,DATEADD(second,1+EncounterID%20,AdmitDateTime),
 CASE WHEN EncounterID%19=0 THEN 'ERROR' ELSE 'PROCESSED' END,CASE WHEN EncounterID%19=0 THEN 1+EncounterID%3 ELSE 0 END,'HL7'
FROM dbo.Encounter;

INSERT dbo.InterfaceError(InterfaceMessageID,ErrorDateTime,ErrorCode,ErrorCategory,ErrorMessage,ResolvedFlag,ResolutionNotes)
SELECT InterfaceMessageID,DATEADD(second,5,ReceivedDateTime),
 CHOOSE(1+((InterfaceMessageID-1)%5),'SQL_TIMEOUT','MLLP_RESET','INVALID_MRN','MISSING_FIELD','JDBC_ERROR'),
 CHOOSE(1+((InterfaceMessageID-1)%5),'Database','Network','Validation','HL7 Mapping','JDBC'),
 CHOOSE(1+((InterfaceMessageID-1)%5),N'Database command timed out during training scenario.',N'Downstream connection reset during MLLP send.',N'Patient MRN failed synthetic validation.',N'Required HL7 field was missing.',N'JDBC connection failed during training scenario.'),
 CASE WHEN InterfaceMessageID%2=0 THEN 1 ELSE 0 END,CASE WHEN InterfaceMessageID%2=0 THEN N'Resolved during synthetic training exercise.' END
FROM dbo.InterfaceMessage WHERE ProcessingStatus='ERROR';

INSERT dbo.AuditLog(EventDateTime,UserOrSystem,ActionType,EntityType,EntityID,PatientID,Description,SourceIP)
SELECT UpdatedAt,CASE WHEN PatientID%2=0 THEN 'Mirth Connect' ELSE 'RegistrationUser' END,
 CASE WHEN PatientID%3=0 THEN 'UPDATE' ELSE 'CREATE' END,'Patient',CAST(PatientID AS varchar(50)),PatientID,
 N'Synthetic patient record activity for SQL training.',CONCAT('10.10.',PatientID%20,'.',10+PatientID%200)
FROM dbo.Patient;
GO

/*
===============================================================================
ENRICHMENT / DATA-QUALITY PASS
Keeps the original deterministic data generation, then fills the enhanced
columns and makes commonly taught related fields more coherent.
===============================================================================
*/

-- Facility / department / location / provider enrichment
UPDATE dbo.Facility
SET FacilityType = CASE FacilityID WHEN 1 THEN 'Acute Care Hospital'
                                   WHEN 2 THEN 'Rehabilitation Hospital'
                                   ELSE 'Ambulatory Clinic' END,
    TimeZone = 'America/Toronto',
    ActiveFlag = 1;

UPDATE dbo.Department
SET CostCenterCode = CONCAT('CC-',RIGHT('0000'+CAST(DepartmentID AS varchar(4)),4)),
    DepartmentPhone = CONCAT('+1-416-555-',RIGHT('0000'+CAST(2000+DepartmentID AS varchar(4)),4)),
    ActiveFlag = 1;

UPDATE l
SET Building = CASE d.FacilityID WHEN 1 THEN N'Main Hospital'
                                 WHEN 2 THEN N'Rehabilitation Centre'
                                 ELSE N'Community Clinic' END,
    FloorNumber = 1 + ((l.LocationID-1)%8),
    ActiveFlag = 1
FROM dbo.Location l
JOIN dbo.Department d ON d.DepartmentID=l.DepartmentID;

UPDATE dbo.Provider
SET ProviderType = 'Physician',
    Credentials = 'MD',
    ActiveFlag = 1;

-- Accurate age as of the deterministic training reference date
DECLARE @TrainingAsOfDate date='2026-08-01';

UPDATE p
SET AgeYears =
    DATEDIFF(year,p.DateOfBirth,@TrainingAsOfDate)
    - CASE WHEN DATEADD(year,DATEDIFF(year,p.DateOfBirth,@TrainingAsOfDate),p.DateOfBirth) > @TrainingAsOfDate THEN 1 ELSE 0 END
FROM dbo.Patient p;

UPDATE dbo.Patient
SET AgeGroup = CASE WHEN AgeYears < 1 THEN 'Infant'
                    WHEN AgeYears < 13 THEN 'Child'
                    WHEN AgeYears < 18 THEN 'Adolescent'
                    WHEN AgeYears < 65 THEN 'Adult'
                    ELSE 'Older Adult' END;

-- Coherent residence location triplets for easier SQL/Excel demonstrations.
UPDATE p
SET City = x.City,
    ProvinceState = x.ProvinceState,
    Country = x.Country,
    PostalCode = x.PostalCode
FROM dbo.Patient p
CROSS APPLY (VALUES
    (1,N'Toronto',N'Ontario',N'Canada','M5V 2T6'),
    (2,N'Brampton',N'Ontario',N'Canada','L6Y 1N7'),
    (3,N'Mississauga',N'Ontario',N'Canada','L5B 3C1'),
    (4,N'Ottawa',N'Ontario',N'Canada','K1P 1J1'),
    (5,N'Vancouver',N'British Columbia',N'Canada','V6B 1A1'),
    (6,N'Calgary',N'Alberta',N'Canada','T2P 1J9'),
    (7,N'Montreal',N'Quebec',N'Canada','H3B 1A7'),
    (8,N'Hyderabad',N'Telangana',N'India','500001'),
    (9,N'Lisbon',N'Lisbon',N'Portugal','1000-001'),
    (10,N'Rio de Janeiro',N'Rio de Janeiro',N'Brazil','20000-000'),
    (11,N'Paris',N'Île-de-France',N'France','75001'),
    (12,N'Lagos',N'Lagos',N'Nigeria','100001'),
    (13,N'Tokyo',N'Tokyo',N'Japan','100-0001'),
    (14,N'Manila',N'Metro Manila',N'Philippines','1000'),
    (15,N'Mexico City',N'CDMX',N'Mexico','06000')
) x(Seq,City,ProvinceState,Country,PostalCode)
WHERE x.Seq = 1 + ((p.PatientID-1)%15);

-- Citizenship is usually related to country of birth but still includes
-- naturalized Canadian patients for useful WHERE/GROUP BY scenarios.
UPDATE p
SET Citizenship =
    CASE WHEN p.PatientID%5=0 THEN N'Canadian'
         ELSE CASE p.CountryOfBirth
            WHEN N'Canada' THEN N'Canadian'
            WHEN N'India' THEN N'Indian'
            WHEN N'Brazil' THEN N'Brazilian'
            WHEN N'Portugal' THEN N'Portuguese'
            WHEN N'Argentina' THEN N'Argentinian'
            WHEN N'France' THEN N'French'
            WHEN N'Nigeria' THEN N'Nigerian'
            WHEN N'China' THEN N'Chinese'
            WHEN N'Japan' THEN N'Japanese'
            WHEN N'South Korea' THEN N'South Korean'
            WHEN N'Egypt' THEN N'Egyptian'
            WHEN N'Pakistan' THEN N'Pakistani'
            WHEN N'Italy' THEN N'Italian'
            WHEN N'Germany' THEN N'German'
            WHEN N'Mexico' THEN N'Mexican'
            WHEN N'Philippines' THEN N'Filipino'
            WHEN N'United Kingdom' THEN N'British'
            WHEN N'Australia' THEN N'Australian'
            WHEN N'Kenya' THEN N'Kenyan'
            WHEN N'United States' THEN N'American'
            ELSE N'Other'
         END
    END
FROM dbo.Patient p;

-- Insurance enrichment
UPDATE dbo.InsurancePolicy
SET PayerCode = CONCAT('PAY',RIGHT('000'+CAST(1+((InsurancePolicyID-1)%8) AS varchar(3)),3)),
    GroupNumber = CONCAT('GRP',RIGHT('000000'+CAST(100000+(InsurancePolicyID%900000) AS varchar(6)),6)),
    RelationshipToSubscriber = CHOOSE(1+((InsurancePolicyID-1)%4),'Self','Spouse','Child','Other'),
    CoverageType = CHOOSE(1+((InsurancePolicyID-1)%4),'Provincial','Employer','Private','Self Pay');

-- Encounter enrichment
UPDATE dbo.Encounter
SET AccountNumber = CONCAT('ACCT',RIGHT('0000000000'+CAST(EncounterID AS varchar(10)),10)),
    AdmissionType = CHOOSE(1+((EncounterID-1)%4),'Emergency','Urgent','Elective','Newborn'),
    ReasonForVisit = CHOOSE(1+((EncounterID-1)%10),
        N'Chest pain',N'Shortness of breath',N'Fever',N'Abdominal pain',N'Fall / injury',
        N'Follow-up visit',N'Rehabilitation therapy',N'Diabetes management',N'Neurologic symptoms',N'Routine assessment'),
    ChiefComplaint = CONCAT(N'Synthetic training complaint: ',
        CHOOSE(1+((EncounterID-1)%10),
        N'chest discomfort',N'difficulty breathing',N'fever and fatigue',N'abdominal discomfort',N'fall-related pain',
        N'follow-up evaluation',N'mobility rehabilitation',N'glucose management',N'headache / weakness',N'routine assessment'));

-- ADT / HL7 enrichment
UPDATE dbo.ADTEvent
SET HL7Version = '2.5.1',
    SourceSystem = CHOOSE(1+((ADTEventID-1)%3),'Epic','Oracle Health/Cerner','MEDITECH'),
    DestinationSystem = 'Mirth Connect',
    EventReasonCode = CASE TriggerEvent WHEN 'A01' THEN 'ADMISSION'
                                       WHEN 'A02' THEN 'TRANSFER'
                                       WHEN 'A03' THEN 'DISCHARGE'
                                       WHEN 'A08' THEN 'UPDATE'
                                       ELSE 'OTHER' END;

-- Clinical terminology enrichment
UPDATE dbo.Diagnosis
SET CodeSystem = 'ICD-10-CA',
    DiagnosisRank = CASE WHEN DiagnosisType='Primary' THEN 1 ELSE 2 END;

UPDATE dbo.Allergy
SET AllergenCode = CONCAT('ALG',RIGHT('000000'+CAST(AllergyID AS varchar(6)),6)),
    CodeSystem = 'LOCAL',
    VerificationStatus = CASE WHEN Allergen=N'No Known Drug Allergy' THEN 'Unconfirmed' ELSE 'Confirmed' END;

UPDATE dbo.MedicationOrder
SET MedicationCodeSystem = 'LOCAL-MED',
    PRNFlag = CASE WHEN Frequency LIKE '%PRN%' THEN 1 ELSE 0 END,
    StartDateTime = OrderDateTime,
    EndDateTime = CASE WHEN OrderStatus='COMPLETED' THEN DATEADD(day,7,OrderDateTime) END;

UPDATE dbo.LabOrder
SET PlacerOrderNumber = CONCAT('PLC-',RIGHT('0000000000'+CAST(LabOrderID AS varchar(10)),10)),
    FillerOrderNumber = CONCAT('FIL-',RIGHT('0000000000'+CAST(LabOrderID AS varchar(10)),10)),
    SpecimenType = CASE OrderCode WHEN 'CBC' THEN 'Whole Blood'
                                  WHEN 'BMP' THEN 'Serum'
                                  WHEN 'CMP' THEN 'Serum'
                                  WHEN 'TROP' THEN 'Plasma'
                                  WHEN 'A1C' THEN 'Whole Blood'
                                  WHEN 'TSH' THEN 'Serum'
                                  ELSE 'Unknown' END;

UPDATE dbo.LabResult
SET LOINCCode = CASE TestCode WHEN 'WBC' THEN '6690-2'
                              WHEN 'HGB' THEN '718-7'
                              WHEN 'NA' THEN '2951-2'
                              ELSE NULL END,
    ValueType = 'NM';

-- Interface operations enrichment
UPDATE dbo.InterfaceMessage
SET TriggerEvent = CASE WHEN CHARINDEX('^',MessageType)>0
                        THEN SUBSTRING(MessageType,CHARINDEX('^',MessageType)+1,10)
                        ELSE NULL END,
    HL7Version = '2.5.1',
    Direction = 'Outbound',
    TransportProtocol = CASE WHEN ChannelName LIKE '%REPORTING%' OR ChannelName LIKE '%SQL%' THEN 'JDBC' ELSE 'MLLP' END,
    ProcessingTimeMs = CASE WHEN ProcessedDateTime IS NULL THEN NULL
                            ELSE DATEDIFF_BIG(millisecond,ReceivedDateTime,ProcessedDateTime) END,
    AckStatus = CASE WHEN ProcessingStatus='ERROR' THEN 'NACK' ELSE 'ACK' END;

UPDATE dbo.InterfaceError
SET Severity = 'ERROR',
    SegmentName = CASE ErrorCode WHEN 'INVALID_MRN' THEN 'PID'
                                 WHEN 'MISSING_FIELD' THEN 'PV1'
                                 WHEN 'MLLP_RESET' THEN 'MSH'
                                 ELSE NULL END,
    FieldPosition = CASE ErrorCode WHEN 'INVALID_MRN' THEN 'PID-3'
                                   WHEN 'MISSING_FIELD' THEN 'PV1-2'
                                   WHEN 'MLLP_RESET' THEN 'MSH-10'
                                   ELSE NULL END;

UPDATE dbo.AuditLog
SET ApplicationName = CASE WHEN UserOrSystem='Mirth Connect' THEN 'Mirth Connect'
                           ELSE 'Registration Portal' END,
    WorkstationName = CASE WHEN UserOrSystem='Mirth Connect' THEN 'MIRTH-PRD-01'
                           ELSE CONCAT('REG-WS-',RIGHT('000'+CAST((AuditLogID%50)+1 AS varchar(3)),3)) END;
GO

CREATE INDEX IX_Patient_Name ON dbo.Patient(LastName,FirstName);
CREATE INDEX IX_Patient_DOB ON dbo.Patient(DateOfBirth);
CREATE INDEX IX_Patient_Country ON dbo.Patient(Country);
CREATE INDEX IX_Encounter_Patient_Admit ON dbo.Encounter(PatientID,AdmitDateTime DESC);
CREATE INDEX IX_Encounter_Status ON dbo.Encounter(EncounterStatus,PatientClass,ServiceCode);
CREATE INDEX IX_ADT_Patient_Event ON dbo.ADTEvent(PatientID,EventDateTime DESC);
CREATE INDEX IX_Diagnosis_Patient ON dbo.Diagnosis(PatientID,DiagnosisCode);
CREATE INDEX IX_Interface_Status ON dbo.InterfaceMessage(ProcessingStatus,ReceivedDateTime);
CREATE INDEX IX_Patient_CountryOfBirth ON dbo.Patient(CountryOfBirth);
CREATE INDEX IX_Patient_Citizenship ON dbo.Patient(Citizenship);
CREATE INDEX IX_Patient_AgeYears ON dbo.Patient(AgeYears);
CREATE INDEX IX_Encounter_VisitNumber ON dbo.Encounter(VisitNumber);
CREATE UNIQUE INDEX UX_Encounter_AccountNumber ON dbo.Encounter(AccountNumber) WHERE AccountNumber IS NOT NULL;
CREATE INDEX IX_ADT_MessageType ON dbo.ADTEvent(MessageType,EventDateTime DESC);
CREATE INDEX IX_LabOrder_Patient ON dbo.LabOrder(PatientID,OrderDateTime DESC);
CREATE INDEX IX_Interface_MessageType ON dbo.InterfaceMessage(MessageType,ReceivedDateTime DESC);
GO

/*
===============================================================================
TEACHING VIEWS
===============================================================================
*/

CREATE OR ALTER VIEW dbo.vw_PatientTeaching AS
SELECT
    PatientID,
    EnterpriseMRN,
    FacilityMRN,
    FirstName,
    MiddleName,
    LastName,
    FullName,
    DateOfBirth,
    AgeYears,
    AgeGroup,
    SexAtBirth,
    GenderIdentity,
    CountryOfBirth,
    Citizenship,
    Country,
    ProvinceState,
    City,
    PostalCode,
    PrimaryLanguage,
    InterpreterRequired,
    MobilePhone,
    EmailAddress,
    PatientStatus,
    RegistrationSource,
    LastSeenAt
FROM dbo.Patient;
GO

CREATE OR ALTER VIEW dbo.vw_PatientEncounterTeaching AS
SELECT
    p.PatientID,
    p.EnterpriseMRN,
    p.FullName,
    p.AgeYears,
    p.Country,
    e.EncounterID,
    e.VisitNumber,
    e.AccountNumber,
    e.PatientClass,
    e.EncounterType,
    e.EncounterStatus,
    e.ServiceCode,
    e.ReasonForVisit,
    e.AdmitDateTime,
    e.DischargeDateTime,
    f.FacilityName,
    d.DepartmentName,
    CONCAT(pr.FirstName,' ',pr.LastName) AS AttendingProvider
FROM dbo.Patient p
JOIN dbo.Encounter e ON e.PatientID=p.PatientID
JOIN dbo.Facility f ON f.FacilityID=e.FacilityID
JOIN dbo.Department d ON d.DepartmentID=e.DepartmentID
JOIN dbo.Provider pr ON pr.ProviderID=e.AttendingProviderID;
GO

CREATE OR ALTER VIEW dbo.vw_HL7InterfaceTeaching AS
SELECT
    im.InterfaceMessageID,
    im.MessageControlID,
    im.ChannelName,
    im.MessageType,
    im.TriggerEvent,
    im.HL7Version,
    im.SourceSystem,
    im.DestinationSystem,
    im.Direction,
    im.TransportProtocol,
    im.ReceivedDateTime,
    im.ProcessingTimeMs,
    im.ProcessingStatus,
    im.AckStatus,
    p.PatientID,
    p.EnterpriseMRN,
    p.FullName,
    e.VisitNumber
FROM dbo.InterfaceMessage im
LEFT JOIN dbo.Patient p ON p.PatientID=im.PatientID
LEFT JOIN dbo.Encounter e ON e.EncounterID=im.EncounterID;
GO

CREATE OR ALTER VIEW dbo.vw_CurrentCensus AS
SELECT e.EncounterID,e.VisitNumber,e.AccountNumber,p.PatientID,p.EnterpriseMRN,p.FullName,p.FirstName,p.LastName,p.DateOfBirth,p.AgeYears,p.AgeGroup,p.GenderIdentity,p.Country,
 e.PatientClass,e.ServiceCode,e.AssignedUnit,e.AssignedRoom,e.AssignedBed,e.AdmitDateTime,f.FacilityName,d.DepartmentName,
 CONCAT(pr.FirstName,' ',pr.LastName) AttendingProvider,e.FinancialClass
FROM dbo.Encounter e
JOIN dbo.Patient p ON p.PatientID=e.PatientID
JOIN dbo.Facility f ON f.FacilityID=e.FacilityID
JOIN dbo.Department d ON d.DepartmentID=e.DepartmentID
JOIN dbo.Provider pr ON pr.ProviderID=e.AttendingProviderID
WHERE e.EncounterStatus='Active' AND e.DischargeDateTime IS NULL;
GO

CREATE OR ALTER VIEW dbo.vw_InterfaceRetryQueue AS
SELECT im.InterfaceMessageID,im.MessageControlID,im.ChannelName,im.MessageType,im.SourceSystem,im.DestinationSystem,
 im.ReceivedDateTime,im.RetryCount,ie.ErrorCode,ie.ErrorCategory,ie.ErrorMessage,ie.ResolvedFlag
FROM dbo.InterfaceMessage im JOIN dbo.InterfaceError ie ON ie.InterfaceMessageID=im.InterfaceMessageID
WHERE im.ProcessingStatus='ERROR' AND ie.ResolvedFlag=0;
GO

CREATE OR ALTER PROCEDURE dbo.usp_FindPatient @Search nvarchar(100) AS
BEGIN
 SET NOCOUNT ON;
 SELECT TOP(100)
    PatientID,EnterpriseMRN,FacilityMRN,FirstName,MiddleName,LastName,FullName,
    DateOfBirth,AgeYears,GenderIdentity,CountryOfBirth,Citizenship,Country,City,
    PrimaryLanguage,MobilePhone,EmailAddress,PatientStatus
 FROM dbo.Patient
 WHERE EnterpriseMRN=@Search
    OR FacilityMRN=@Search
    OR FirstName LIKE '%'+@Search+'%'
    OR LastName LIKE '%'+@Search+'%'
    OR FullName LIKE '%'+@Search+'%'
    OR Country LIKE '%'+@Search+'%'
    OR CountryOfBirth LIKE '%'+@Search+'%'
 ORDER BY LastName,FirstName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CurrentCensus @ServiceCode varchar(20)=NULL AS
BEGIN
 SET NOCOUNT ON;
 SELECT * FROM dbo.vw_CurrentCensus WHERE @ServiceCode IS NULL OR ServiceCode=@ServiceCode
 ORDER BY AssignedUnit,AssignedRoom,AssignedBed;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdmitPatient @PatientID int,@ServiceCode varchar(20),@PatientClass varchar(10)='I' AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  IF NOT EXISTS(SELECT 1 FROM dbo.Patient WHERE PatientID=@PatientID AND DeceasedFlag=0)
   THROW 51001,'Patient does not exist or is deceased.',1;
  IF EXISTS(SELECT 1 FROM dbo.Encounter WHERE PatientID=@PatientID AND EncounterStatus='Active' AND DischargeDateTime IS NULL)
   THROW 51002,'Patient already has an active encounter.',1;
  DECLARE @VisitNumber varchar(25)=CONCAT('LIVE',FORMAT(SYSDATETIME(),'yyyyMMddHHmmss'),RIGHT('0000'+CAST(@PatientID AS varchar(4)),4));
  DECLARE @EncounterID bigint;
  INSERT dbo.Encounter(VisitNumber,PatientID,FacilityID,DepartmentID,LocationID,PatientClass,EncounterType,EncounterStatus,ServiceCode,
   AdmitDateTime,DischargeDateTime,AttendingProviderID,AdmittingProviderID,ReferringProviderID,AdmissionSource,DischargeDisposition,
   AssignedUnit,AssignedRoom,AssignedBed,PriorUnit,PriorRoom,PriorBed,FinancialClass,CreatedAt,UpdatedAt)
  VALUES(@VisitNumber,@PatientID,1,8,1,@PatientClass,CASE WHEN @PatientClass='I' THEN 'Inpatient' ELSE 'Outpatient' END,'Active',@ServiceCode,
   SYSDATETIME(),NULL,1,2,3,'Interview Practice',NULL,'U08','R101','B1',NULL,NULL,NULL,'PROV',SYSDATETIME(),SYSDATETIME());
  SET @EncounterID=SCOPE_IDENTITY();
  INSERT dbo.ADTEvent(EncounterID,PatientID,TriggerEvent,MessageType,EventDateTime,ToUnit,ToRoom,ToBed,MessageControlID,ProcessingStatus)
  VALUES(@EncounterID,@PatientID,'A01','ADT^A01',SYSDATETIME(),'U08','R101','B1',CONCAT('LIVE-A01-',@EncounterID),'READY');
  COMMIT TRANSACTION;
  SELECT @EncounterID EncounterID,@VisitNumber VisitNumber,'ADMITTED' Status;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DischargeEncounter @EncounterID bigint,@Disposition varchar(60)='Home' AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @PatientID int,@Unit varchar(20),@Room varchar(20),@Bed varchar(20);
  SELECT @PatientID=PatientID,@Unit=AssignedUnit,@Room=AssignedRoom,@Bed=AssignedBed FROM dbo.Encounter
  WHERE EncounterID=@EncounterID AND EncounterStatus='Active' AND DischargeDateTime IS NULL;
  IF @PatientID IS NULL THROW 51003,'Active encounter not found.',1;
  UPDATE dbo.Encounter SET EncounterStatus='Discharged',DischargeDateTime=SYSDATETIME(),DischargeDisposition=@Disposition,UpdatedAt=SYSDATETIME()
  WHERE EncounterID=@EncounterID;
  INSERT dbo.ADTEvent(EncounterID,PatientID,TriggerEvent,MessageType,EventDateTime,FromUnit,FromRoom,FromBed,MessageControlID,ProcessingStatus)
  VALUES(@EncounterID,@PatientID,'A03','ADT^A03',SYSDATETIME(),@Unit,@Room,@Bed,CONCAT('LIVE-A03-',@EncounterID),'READY');
  COMMIT TRANSACTION;
  SELECT @EncounterID EncounterID,'DISCHARGED' Status;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH
END;
GO

PRINT 'HealtchareDatabse BUILD COMPLETE';
PRINT 'All data is synthetic training data only - NO REAL PHI.';

SELECT DB_NAME() AS CurrentDatabase;
SELECT COUNT(*) AS PatientCount FROM dbo.Patient;
SELECT COUNT(*) AS ActiveCensus FROM dbo.vw_CurrentCensus;
SELECT COUNT(*) AS EncounterCount FROM dbo.Encounter;
SELECT COUNT(*) AS ADTEventCount FROM dbo.ADTEvent;
SELECT COUNT(*) AS DiagnosisCount FROM dbo.Diagnosis;
SELECT COUNT(*) AS LabResultCount FROM dbo.LabResult;
SELECT COUNT(*) AS InterfaceErrorCount FROM dbo.InterfaceError;

-- Beginner-friendly verification queries
SELECT TOP(10)
    PatientID,EnterpriseMRN,FacilityMRN,FirstName,LastName,FullName,
    DateOfBirth,AgeYears,CountryOfBirth,Citizenship,Country,City
FROM dbo.Patient
ORDER BY PatientID;

SELECT Country,COUNT(*) AS Patients
FROM dbo.Patient
GROUP BY Country
ORDER BY Patients DESC;

SELECT AgeGroup,COUNT(*) AS Patients
FROM dbo.Patient
GROUP BY AgeGroup
ORDER BY Patients DESC;

SELECT TOP(20) *
FROM dbo.vw_HL7InterfaceTeaching
ORDER BY ReceivedDateTime DESC;
GO