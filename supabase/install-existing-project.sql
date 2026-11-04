SET LOCAL search_path=public,extensions;
-- ADDITIVE INSTALL ONLY: abort before any write if the model or its bucket already exists.
-- Existing lowercase application tables, records and their privileges are not migrated.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename=ANY(ARRAY['Department','Role','Permission','User','UserRole','Vehicle','VehicleAssignment','SupervisorVehicleAssignment','ChecklistTemplate','ChecklistVersion','ChecklistItem','ChecklistItemTranslation','Inspection','InspectionResponse','FaultReport','FaultImage','MaintenanceRecord','Complaint','Notification','AuditLog','ExportJob','BackupRecord','SynchronizationJob','Session','_RolePermissions','RoleConfiguration','SupervisorApproval','InspectionEvidence','LoginRateLimit'] ))
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND (p.proname LIKE 'fg_%' OR p.proname='prevent_audit_log_modification')) OR n.nspname='fleetguard_private')
 OR EXISTS(SELECT 1 FROM storage.buckets WHERE id='inspection-evidence') THEN
 RAISE EXCEPTION 'Model collision: use the reviewed populated-database migration instead';
 END IF;
END $$;

-- CreateEnum
CREATE TYPE "AccountStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'LOCKED');

-- CreateEnum
CREATE TYPE "VehicleStatus" AS ENUM ('ACTIVE', 'UNDER_MAINTENANCE', 'OUT_OF_SERVICE', 'INACTIVE');

-- CreateEnum
CREATE TYPE "VehicleSafetyState" AS ENUM ('SAFE', 'NEEDS_REVIEW', 'OUT_OF_SERVICE');

-- CreateEnum
CREATE TYPE "InspectionStatus" AS ENUM ('DRAFT', 'SUBMITTED', 'AMENDED', 'FLAGGED_UNSAFE');

-- CreateEnum
CREATE TYPE "SyncStatus" AS ENUM ('SYNCED', 'PENDING_SYNC', 'CONFLICT', 'FAILED');

-- CreateEnum
CREATE TYPE "ItemResponseValue" AS ENUM ('PASS', 'FAIL', 'NA', 'NOT_CHECKED');

-- CreateEnum
CREATE TYPE "FaultSeverity" AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');

-- CreateEnum
CREATE TYPE "FaultWorkflowStatus" AS ENUM ('REPORTED', 'ACKNOWLEDGED', 'UNDER_REVIEW', 'UNDER_MAINTENANCE', 'RESOLVED', 'VERIFIED_AND_CLOSED');

-- CreateTable
CREATE TABLE "Department" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "nameEn" TEXT NOT NULL,
    "nameAr" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Department_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Role" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "nameEn" TEXT NOT NULL,
    "nameAr" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Role_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Permission" (
    "id" TEXT NOT NULL,
    "flag" TEXT NOT NULL,
    "description" TEXT NOT NULL,

    CONSTRAINT "Permission_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "fullName" TEXT NOT NULL,
    "passwordHash" TEXT,
    "mustChangePassword" BOOLEAN NOT NULL DEFAULT true,
    "failedLoginAttempts" INTEGER NOT NULL DEFAULT 0,
    "lockedUntil" TIMESTAMP(3),
    "phone" TEXT,
    "ropLicenseExpiry" TIMESTAMP(3),
    "preferredLanguage" TEXT NOT NULL DEFAULT 'en',
    "status" "AccountStatus" NOT NULL DEFAULT 'ACTIVE',
    "departmentId" TEXT NOT NULL,
    "assignedSupervisorId" TEXT,
    "customPermissions" JSONB,
    "lastLoginAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UserRole" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "roleId" TEXT NOT NULL,
    "assignedBy" TEXT NOT NULL,
    "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserRole_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Vehicle" (
    "id" TEXT NOT NULL,
    "vehicleCode" TEXT NOT NULL,
    "registrationNumber" TEXT NOT NULL,
    "plateNumber" TEXT NOT NULL,
    "vehicleCategory" TEXT NOT NULL,
    "manufacturer" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "manufacturingYear" INTEGER NOT NULL,
    "departmentId" TEXT NOT NULL,
    "currentOdometerKm" INTEGER NOT NULL DEFAULT 0,
    "registrationExpiryDate" TIMESTAMP(3) NOT NULL,
    "insuranceExpiryDate" TIMESTAMP(3) NOT NULL,
    "opalStickerExpiryDate" TIMESTAMP(3),
    "status" "VehicleStatus" NOT NULL DEFAULT 'ACTIVE',
    "safetyState" "VehicleSafetyState" NOT NULL DEFAULT 'SAFE',
    "qrToken" TEXT NOT NULL,
    "photoStorageKey" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "archivedAt" TIMESTAMP(3),

    CONSTRAINT "Vehicle_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "VehicleAssignment" (
    "id" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "assignmentDate" DATE NOT NULL,
    "startDate" TIMESTAMP(3) NOT NULL,
    "endDate" TIMESTAMP(3),
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "isEmergency" BOOLEAN NOT NULL DEFAULT false,
    "changeReason" TEXT,
    "assignedById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "VehicleAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SupervisorVehicleAssignment" (
    "id" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "supervisorId" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "assignedById" TEXT NOT NULL,
    "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMP(3),

    CONSTRAINT "SupervisorVehicleAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ChecklistTemplate" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "titleEn" TEXT NOT NULL,
    "titleAr" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ChecklistTemplate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ChecklistVersion" (
    "id" TEXT NOT NULL,
    "templateId" TEXT NOT NULL,
    "versionNumber" INTEGER NOT NULL,
    "isPublished" BOOLEAN NOT NULL DEFAULT false,
    "publishedById" TEXT,
    "publishedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ChecklistVersion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ChecklistItem" (
    "id" TEXT NOT NULL,
    "versionId" TEXT NOT NULL,
    "serialNumber" INTEGER NOT NULL,
    "categoryCode" TEXT NOT NULL,
    "allowedResponses" TEXT[],
    "isRequired" BOOLEAN NOT NULL DEFAULT true,
    "requirePhotoOnFail" BOOLEAN NOT NULL DEFAULT false,
    "isSafetyCritical" BOOLEAN NOT NULL DEFAULT false,
    "iconName" TEXT,
    "instructionImgKey" TEXT,
    "sortOrder" INTEGER NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "needsAdminVerify" BOOLEAN NOT NULL DEFAULT false,
    "archivedAt" TIMESTAMP(3),

    CONSTRAINT "ChecklistItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ChecklistItemTranslation" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "languageCode" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "description" TEXT,
    "verifiedByAdmin" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "ChecklistItemTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Inspection" (
    "id" TEXT NOT NULL,
    "inspectionCode" TEXT NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "checklistVersionId" TEXT NOT NULL,
    "inspectionDate" DATE NOT NULL,
    "dayOfWeek" TEXT NOT NULL,
    "startingKm" INTEGER NOT NULL,
    "closingKm" INTEGER,
    "odometerKm" INTEGER NOT NULL,
    "ropExpiryDate" TIMESTAMP(3),
    "driverSignature" TEXT,
    "supervisorSign" TEXT,
    "generalRemarks" TEXT,
    "defectDescription" TEXT,
    "actionTaken" TEXT,
    "status" "InspectionStatus" NOT NULL DEFAULT 'SUBMITTED',
    "syncStatus" "SyncStatus" NOT NULL DEFAULT 'SYNCED',
    "submittedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "amendedAt" TIMESTAMP(3),
    "amendmentReason" TEXT,

    CONSTRAINT "Inspection_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InspectionResponse" (
    "id" TEXT NOT NULL,
    "inspectionId" TEXT NOT NULL,
    "checklistItemId" TEXT NOT NULL,
    "response" "ItemResponseValue" NOT NULL,
    "remarks" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InspectionResponse_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FaultReport" (
    "id" TEXT NOT NULL,
    "faultCode" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "inspectionId" TEXT,
    "checklistItemSn" INTEGER,
    "reportedById" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "severity" "FaultSeverity" NOT NULL,
    "status" "FaultWorkflowStatus" NOT NULL DEFAULT 'REPORTED',
    "isConfirmed" BOOLEAN NOT NULL DEFAULT false,
    "assignedSupervisorId" TEXT,
    "assignedMaintenanceTo" TEXT,
    "correctiveAction" TEXT,
    "resolutionNotes" TEXT,
    "reportedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),
    "closedAt" TIMESTAMP(3),

    CONSTRAINT "FaultReport_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FaultImage" (
    "id" TEXT NOT NULL,
    "faultReportId" TEXT NOT NULL,
    "storageKey" TEXT NOT NULL,
    "mimeType" TEXT NOT NULL,
    "fileSizeBytes" INTEGER NOT NULL,
    "uploadedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FaultImage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MaintenanceRecord" (
    "id" TEXT NOT NULL,
    "maintenanceCode" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "faultReportId" TEXT,
    "technicianName" TEXT NOT NULL,
    "workshopName" TEXT,
    "workDescription" TEXT NOT NULL,
    "partsReplaced" TEXT,
    "costOmr" DECIMAL(10,3),
    "odometerAtService" INTEGER NOT NULL,
    "status" TEXT NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "verifiedById" TEXT,

    CONSTRAINT "MaintenanceRecord_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Complaint" (
    "id" TEXT NOT NULL,
    "complaintNo" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'OPEN',
    "supervisorNotes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),

    CONSTRAINT "Complaint_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Notification" (
    "id" TEXT NOT NULL,
    "recipientUserId" TEXT NOT NULL,
    "vehicleId" TEXT,
    "type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Notification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditLog" (
    "id" TEXT NOT NULL,
    "actorUserId" TEXT NOT NULL,
    "actorEmpId" TEXT NOT NULL,
    "actionType" TEXT NOT NULL,
    "affectedTable" TEXT NOT NULL,
    "affectedRecord" TEXT NOT NULL,
    "previousValue" JSONB,
    "newValue" JSONB,
    "result" TEXT NOT NULL DEFAULT 'SUCCESS',
    "sessionId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ExportJob" (
    "id" TEXT NOT NULL,
    "requestedBy" TEXT NOT NULL,
    "exportScope" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "storageKey" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'COMPLETED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ExportJob_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BackupRecord" (
    "id" TEXT NOT NULL,
    "backupType" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "checksumSha256" TEXT NOT NULL,
    "sizeBytes" BIGINT NOT NULL,
    "status" TEXT NOT NULL,
    "retentionDays" INTEGER NOT NULL DEFAULT 90,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastRestoreTest" TIMESTAMP(3),

    CONSTRAINT "BackupRecord_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SynchronizationJob" (
    "id" TEXT NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "payloadType" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "conflictNotes" TEXT,
    "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SynchronizationJob_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Session" (
    "id" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Session_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "_RolePermissions" (
    "A" TEXT NOT NULL,
    "B" TEXT NOT NULL
);

-- CreateIndex
CREATE UNIQUE INDEX "Department_code_key" ON "Department"("code");

-- CreateIndex
CREATE UNIQUE INDEX "Role_code_key" ON "Role"("code");

-- CreateIndex
CREATE UNIQUE INDEX "Permission_flag_key" ON "Permission"("flag");

-- CreateIndex
CREATE UNIQUE INDEX "User_employeeId_key" ON "User"("employeeId");

-- CreateIndex
CREATE UNIQUE INDEX "UserRole_userId_roleId_key" ON "UserRole"("userId", "roleId");

-- CreateIndex
CREATE UNIQUE INDEX "Vehicle_vehicleCode_key" ON "Vehicle"("vehicleCode");

-- CreateIndex
CREATE UNIQUE INDEX "Vehicle_registrationNumber_key" ON "Vehicle"("registrationNumber");

-- CreateIndex
CREATE UNIQUE INDEX "Vehicle_plateNumber_key" ON "Vehicle"("plateNumber");

-- CreateIndex
CREATE UNIQUE INDEX "Vehicle_qrToken_key" ON "Vehicle"("qrToken");

-- CreateIndex
CREATE INDEX "VehicleAssignment_vehicleId_assignmentDate_idx" ON "VehicleAssignment"("vehicleId", "assignmentDate");

-- CreateIndex
CREATE INDEX "VehicleAssignment_driverId_assignmentDate_idx" ON "VehicleAssignment"("driverId", "assignmentDate");

-- CreateIndex
CREATE INDEX "SupervisorVehicleAssignment_supervisorId_isActive_idx" ON "SupervisorVehicleAssignment"("supervisorId", "isActive");

-- CreateIndex
CREATE UNIQUE INDEX "ChecklistTemplate_code_key" ON "ChecklistTemplate"("code");

-- CreateIndex
CREATE UNIQUE INDEX "ChecklistVersion_templateId_versionNumber_key" ON "ChecklistVersion"("templateId", "versionNumber");

-- CreateIndex
CREATE UNIQUE INDEX "ChecklistItemTranslation_itemId_languageCode_key" ON "ChecklistItemTranslation"("itemId", "languageCode");

-- CreateIndex
CREATE UNIQUE INDEX "Inspection_inspectionCode_key" ON "Inspection"("inspectionCode");

-- CreateIndex
CREATE UNIQUE INDEX "Inspection_idempotencyKey_key" ON "Inspection"("idempotencyKey");

-- CreateIndex
CREATE INDEX "Inspection_vehicleId_inspectionDate_idx" ON "Inspection"("vehicleId", "inspectionDate");

-- CreateIndex
CREATE UNIQUE INDEX "Inspection_vehicleId_driverId_inspectionDate_key" ON "Inspection"("vehicleId", "driverId", "inspectionDate");

-- CreateIndex
CREATE UNIQUE INDEX "InspectionResponse_inspectionId_checklistItemId_key" ON "InspectionResponse"("inspectionId", "checklistItemId");

-- CreateIndex
CREATE UNIQUE INDEX "FaultReport_faultCode_key" ON "FaultReport"("faultCode");

-- CreateIndex
CREATE INDEX "FaultReport_vehicleId_category_reportedAt_idx" ON "FaultReport"("vehicleId", "category", "reportedAt");

-- CreateIndex
CREATE UNIQUE INDEX "MaintenanceRecord_maintenanceCode_key" ON "MaintenanceRecord"("maintenanceCode");

-- CreateIndex
CREATE UNIQUE INDEX "Complaint_complaintNo_key" ON "Complaint"("complaintNo");

-- CreateIndex
CREATE INDEX "Notification_recipientUserId_isRead_idx" ON "Notification"("recipientUserId", "isRead");

-- CreateIndex
CREATE INDEX "AuditLog_actorEmpId_createdAt_idx" ON "AuditLog"("actorEmpId", "createdAt");

-- CreateIndex
CREATE INDEX "AuditLog_affectedTable_affectedRecord_idx" ON "AuditLog"("affectedTable", "affectedRecord");

-- CreateIndex
CREATE UNIQUE INDEX "SynchronizationJob_idempotencyKey_key" ON "SynchronizationJob"("idempotencyKey");

-- CreateIndex
CREATE UNIQUE INDEX "Session_tokenHash_key" ON "Session"("tokenHash");

-- CreateIndex
CREATE INDEX "Session_expiresAt_idx" ON "Session"("expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "_RolePermissions_AB_unique" ON "_RolePermissions"("A", "B");

-- CreateIndex
CREATE INDEX "_RolePermissions_B_index" ON "_RolePermissions"("B");

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_departmentId_fkey" FOREIGN KEY ("departmentId") REFERENCES "Department"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_assignedSupervisorId_fkey" FOREIGN KEY ("assignedSupervisorId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserRole" ADD CONSTRAINT "UserRole_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserRole" ADD CONSTRAINT "UserRole_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES "Role"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Vehicle" ADD CONSTRAINT "Vehicle_departmentId_fkey" FOREIGN KEY ("departmentId") REFERENCES "Department"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleAssignment" ADD CONSTRAINT "VehicleAssignment_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VehicleAssignment" ADD CONSTRAINT "VehicleAssignment_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupervisorVehicleAssignment" ADD CONSTRAINT "SupervisorVehicleAssignment_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SupervisorVehicleAssignment" ADD CONSTRAINT "SupervisorVehicleAssignment_supervisorId_fkey" FOREIGN KEY ("supervisorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ChecklistVersion" ADD CONSTRAINT "ChecklistVersion_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "ChecklistTemplate"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ChecklistItem" ADD CONSTRAINT "ChecklistItem_versionId_fkey" FOREIGN KEY ("versionId") REFERENCES "ChecklistVersion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ChecklistItemTranslation" ADD CONSTRAINT "ChecklistItemTranslation_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "ChecklistItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Inspection" ADD CONSTRAINT "Inspection_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Inspection" ADD CONSTRAINT "Inspection_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Inspection" ADD CONSTRAINT "Inspection_checklistVersionId_fkey" FOREIGN KEY ("checklistVersionId") REFERENCES "ChecklistVersion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InspectionResponse" ADD CONSTRAINT "InspectionResponse_inspectionId_fkey" FOREIGN KEY ("inspectionId") REFERENCES "Inspection"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InspectionResponse" ADD CONSTRAINT "InspectionResponse_checklistItemId_fkey" FOREIGN KEY ("checklistItemId") REFERENCES "ChecklistItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FaultReport" ADD CONSTRAINT "FaultReport_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FaultReport" ADD CONSTRAINT "FaultReport_inspectionId_fkey" FOREIGN KEY ("inspectionId") REFERENCES "Inspection"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FaultReport" ADD CONSTRAINT "FaultReport_reportedById_fkey" FOREIGN KEY ("reportedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FaultImage" ADD CONSTRAINT "FaultImage_faultReportId_fkey" FOREIGN KEY ("faultReportId") REFERENCES "FaultReport"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MaintenanceRecord" ADD CONSTRAINT "MaintenanceRecord_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MaintenanceRecord" ADD CONSTRAINT "MaintenanceRecord_faultReportId_fkey" FOREIGN KEY ("faultReportId") REFERENCES "FaultReport"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Complaint" ADD CONSTRAINT "Complaint_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AuditLog" ADD CONSTRAINT "AuditLog_actorUserId_fkey" FOREIGN KEY ("actorUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Session" ADD CONSTRAINT "Session_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_RolePermissions" ADD CONSTRAINT "_RolePermissions_A_fkey" FOREIGN KEY ("A") REFERENCES "Permission"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_RolePermissions" ADD CONSTRAINT "_RolePermissions_B_fkey" FOREIGN KEY ("B") REFERENCES "Role"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- One active driver per vehicle and Muscat calendar date; retain all prior assignments.
CREATE UNIQUE INDEX "one_active_driver_per_vehicle_day"
ON "VehicleAssignment" ("vehicleId", "assignmentDate") WHERE "isActive" = TRUE;

CREATE FUNCTION prevent_audit_log_modification()
RETURNS TRIGGER AS $$
BEGIN
 RAISE EXCEPTION 'Audit logs are append-only';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER audit_log_immutable BEFORE UPDATE OR DELETE ON "AuditLog"
FOR EACH ROW EXECUTE FUNCTION prevent_audit_log_modification();
CREATE TRIGGER audit_log_no_truncate BEFORE TRUNCATE ON "AuditLog"
FOR EACH STATEMENT EXECUTE FUNCTION prevent_audit_log_modification();
ALTER TABLE "Inspection" ADD CONSTRAINT inspection_odometer_order CHECK ("startingKm" >= 0 AND "odometerKm" >= "startingKm" AND ("closingKm" IS NULL OR "closingKm" >= "startingKm"));

-- Incremental Supabase migration: retain the existing fleet data and identifiers.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
ALTER TABLE public."User" ADD COLUMN IF NOT EXISTS "authUserId" uuid UNIQUE REFERENCES auth.users(id);
ALTER TABLE public."User" ADD COLUMN IF NOT EXISTS email text UNIQUE;
ALTER TABLE public."User" ADD CONSTRAINT user_language_supported CHECK ("preferredLanguage" IN ('en','ar')) NOT VALID;
ALTER TABLE public."User" VALIDATE CONSTRAINT user_language_supported;
ALTER TABLE public."Inspection" ADD COLUMN IF NOT EXISTS "reviewStatus" text NOT NULL DEFAULT 'PENDING' CHECK ("reviewStatus" IN ('PENDING','APPROVED','REJECTED'));
ALTER TABLE public."Inspection" ADD COLUMN "driverNameSnapshot" text NOT NULL DEFAULT '';
ALTER TABLE public."Inspection" ADD COLUMN "employeeIdSnapshot" text NOT NULL DEFAULT '';
ALTER TABLE public."ChecklistItemTranslation" ADD CONSTRAINT translation_language_supported CHECK ("languageCode" IN ('en','ar'));
CREATE TABLE public."RoleConfiguration" (
 "roleCode" text PRIMARY KEY CHECK ("roleCode" IN ('ADMIN','SUPERVISOR','DRIVER')),
 permissions jsonb NOT NULL DEFAULT '{}', "updatedAt" timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public."RoleConfiguration" VALUES
 ('ADMIN','{"manageEmployees":true,"manageVehicles":true,"assignVehicles":true,"manageTemplates":true,"reviewInspections":true,"manageMaintenance":true,"exportReports":true,"viewAudit":true,"configurePermissions":true,"submitInspections":false}',now()),
 ('SUPERVISOR','{"reviewInspections":true,"manageMaintenance":true,"exportReports":true}',now()),
 ('DRIVER','{"submitInspections":true}',now());
CREATE TABLE public."SupervisorApproval" (
 id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
 "inspectionId" text NOT NULL REFERENCES public."Inspection"(id),
 "reviewerId" text NOT NULL REFERENCES public."User"(id),
 decision text NOT NULL CHECK(decision IN ('APPROVED','REJECTED')),
 comments text NOT NULL CHECK(length(comments) BETWEEN 1 AND 2000),
 signature text, "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON public."SupervisorApproval"("inspectionId","createdAt");
CREATE TABLE public."InspectionEvidence" (
 id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
 "vehicleId" text NOT NULL REFERENCES public."Vehicle"(id),
 "uploaderId" text NOT NULL REFERENCES public."User"(id),
 "checklistItemId" text REFERENCES public."ChecklistItem"(id),
 "inspectionId" text REFERENCES public."Inspection"(id),
 "storageKey" text NOT NULL UNIQUE, "mimeType" text NOT NULL CHECK("mimeType" IN ('image/jpeg','image/png','image/webp')),
 "fileSizeBytes" integer NOT NULL CHECK("fileSizeBytes" BETWEEN 12 AND 5000000),
 "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON public."InspectionEvidence"("inspectionId");
CREATE TABLE public."LoginRateLimit" (key text PRIMARY KEY, attempts int NOT NULL, "windowStart" timestamptz NOT NULL);
CREATE SEQUENCE public.employee_number_seq START 1;
SELECT setval('public.employee_number_seq',COALESCE((SELECT max(substring("employeeId" from '^EMP-([0-9]+)$')::bigint) FROM public."User" WHERE "employeeId" ~ '^EMP-[0-9]+$'),0)+1,false);
CREATE INDEX ON public."LoginRateLimit"("windowStart");
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['Department','Role','Permission','User','UserRole','Vehicle','VehicleAssignment','SupervisorVehicleAssignment','ChecklistTemplate','ChecklistVersion','ChecklistItem','ChecklistItemTranslation','Inspection','InspectionResponse','FaultReport','FaultImage','MaintenanceRecord','Complaint','Notification','AuditLog','ExportJob','BackupRecord','SynchronizationJob','Session'] LOOP
  EXECUTE format('ALTER TABLE public.%I ALTER COLUMN id SET DEFAULT gen_random_uuid()::text',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['Department','User','Vehicle'] LOOP
  EXECUTE format('ALTER TABLE public.%I ALTER COLUMN "updatedAt" SET DEFAULT now()',t);
 END LOOP;
END $$;
INSERT INTO public."Department"(code,"nameEn","nameAr") VALUES ('FLEET','Fleet','إدارة الأسطول') ON CONFLICT(code) DO NOTHING;
INSERT INTO public."Role"(code,"nameEn","nameAr") VALUES ('ADMIN','Administrator','مدير النظام'),('SUPERVISOR','Supervisor','المشرف'),('DRIVER','Driver','السائق') ON CONFLICT(code) DO NOTHING;

-- Helpers are SECURITY DEFINER to avoid recursive policies. Each uses a fixed search path.
CREATE FUNCTION public.fg_actor() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT id FROM public."User" WHERE "authUserId"=auth.uid() AND status='ACTIVE' AND "deletedAt" IS NULL
 AND EXISTS(SELECT 1 FROM auth.sessions s WHERE s.user_id=auth.uid() AND s.id::text=auth.jwt()->>'session_id')
$$;
CREATE FUNCTION public.fg_ready() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM public."User" WHERE id=public.fg_actor() AND NOT "mustChangePassword")
$$;
CREATE FUNCTION public.fg_has_role(code text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fg_ready() AND EXISTS(SELECT 1 FROM public."UserRole" ur JOIN public."Role" r ON r.id=ur."roleId" WHERE ur."userId"=public.fg_actor() AND r.code=$1)
$$;
CREATE FUNCTION public.fg_can(flag text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fg_ready() AND COALESCE((SELECT (u."customPermissions"->>$1)::boolean FROM public."User" u WHERE u.id=public.fg_actor() AND u."customPermissions" ? $1),
 (SELECT bool_or(COALESCE((rc.permissions->>$1)::boolean,false)) FROM public."UserRole" ur JOIN public."Role" r ON r.id=ur."roleId" JOIN public."RoleConfiguration" rc ON rc."roleCode"=r.code WHERE ur."userId"=public.fg_actor()),false)
$$;
CREATE FUNCTION public.fg_vehicle_scope(vehicle_id text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fg_has_role('ADMIN') OR (public.fg_has_role('SUPERVISOR') AND EXISTS(SELECT 1 FROM public."SupervisorVehicleAssignment" WHERE "vehicleId"=$1 AND "supervisorId"=public.fg_actor() AND "isActive")) OR
 (public.fg_has_role('DRIVER') AND EXISTS(SELECT 1 FROM public."VehicleAssignment" WHERE "vehicleId"=$1 AND "driverId"=public.fg_actor() AND "isActive" AND "assignmentDate"=(now() AT TIME ZONE 'Asia/Muscat')::date))
$$;
CREATE FUNCTION public.fg_inspection_scope(inspection_id text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fg_ready() AND EXISTS(SELECT 1 FROM public."Inspection" i LEFT JOIN public."User" d ON d.id=i."driverId" WHERE i.id=$1 AND
 (public.fg_has_role('ADMIN') OR i."driverId"=public.fg_actor() OR (public.fg_has_role('SUPERVISOR') AND (public.fg_vehicle_scope(i."vehicleId") OR d."assignedSupervisorId"=public.fg_actor()))))
$$;
CREATE FUNCTION public.fg_employee_scope(employee_id text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fg_has_role('ADMIN') OR $1=public.fg_actor() OR (public.fg_has_role('SUPERVISOR') AND EXISTS(SELECT 1 FROM public."User" u WHERE u.id=$1 AND (u."assignedSupervisorId"=public.fg_actor() OR EXISTS(SELECT 1 FROM public."VehicleAssignment" a WHERE a."driverId"=u.id AND public.fg_vehicle_scope(a."vehicleId")))))
$$;
CREATE FUNCTION public.fg_fault_scope(fault_id text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fg_ready() AND EXISTS(SELECT 1 FROM public."FaultReport" f WHERE f.id=$1 AND (f."reportedById"=public.fg_actor() OR public.fg_vehicle_scope(f."vehicleId") OR (f."inspectionId" IS NOT NULL AND public.fg_inspection_scope(f."inspectionId"))))
$$;
CREATE FUNCTION public.fg_audit(action text, table_name text, record_id text, before_value jsonb DEFAULT NULL, after_value jsonb DEFAULT NULL) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE actor public."User"; BEGIN
 SELECT * INTO actor FROM public."User" WHERE id=public.fg_actor();
 IF actor.id IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 INSERT INTO public."AuditLog"("actorUserId","actorEmpId","actionType","affectedTable","affectedRecord","previousValue","newValue") VALUES(actor.id,actor."employeeId",action,table_name,record_id,before_value,after_value);
END $$;
CREATE FUNCTION public.fg_me() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public."User"; BEGIN
 SELECT * INTO u FROM public."User" WHERE id=public.fg_actor();
 IF u.id IS NULL THEN RAISE EXCEPTION 'Account unavailable' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('id',u.id,'authUserId',u."authUserId",'employeeId',u."employeeId",'fullName',u."fullName",'email',u.email,'roles',(SELECT COALESCE(jsonb_agg(r.code),'[]') FROM public."UserRole" ur JOIN public."Role" r ON r.id=ur."roleId" WHERE ur."userId"=u.id),'mustChangePassword',u."mustChangePassword",'preferredLanguage',u."preferredLanguage",'departmentId',u."departmentId",'permissions',(SELECT COALESCE(jsonb_object_agg(k,public.fg_can(k)),'{}') FROM unnest(ARRAY['manageEmployees','manageVehicles','assignVehicles','manageTemplates','reviewInspections','manageMaintenance','exportReports','viewAudit','configurePermissions','submitInspections']) k));
END $$;

-- All tables are closed by default. Browser and server session clients have SELECT only.
DO $$ DECLARE t record; BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename=ANY(ARRAY['Department','Role','Permission','User','UserRole','Vehicle','VehicleAssignment','SupervisorVehicleAssignment','ChecklistTemplate','ChecklistVersion','ChecklistItem','ChecklistItemTranslation','Inspection','InspectionResponse','FaultReport','FaultImage','MaintenanceRecord','Complaint','Notification','AuditLog','ExportJob','BackupRecord','SynchronizationJob','Session','_RolePermissions','RoleConfiguration','SupervisorApproval','InspectionEvidence','LoginRateLimit']) LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t.tablename);
  EXECUTE format('REVOKE ALL ON public.%I FROM anon,authenticated',t.tablename);
  EXECUTE format('GRANT ALL ON public.%I TO service_role',t.tablename);
 END LOOP;
END $$;
GRANT USAGE ON SCHEMA public TO anon,authenticated,service_role;
GRANT USAGE,SELECT ON SEQUENCE public.employee_number_seq TO service_role;
GRANT SELECT ON public."Role",public."Department",public."RoleConfiguration",public."Vehicle",public."UserRole",public."VehicleAssignment",public."SupervisorVehicleAssignment",public."ChecklistTemplate",public."ChecklistVersion",public."ChecklistItem",public."ChecklistItemTranslation",public."Inspection",public."InspectionResponse",public."FaultReport",public."FaultImage",public."MaintenanceRecord",public."Notification",public."AuditLog",public."SupervisorApproval",public."InspectionEvidence" TO authenticated;
GRANT SELECT(id,"authUserId","employeeId","fullName",email,phone,"ropLicenseExpiry","preferredLanguage",status,"departmentId","assignedSupervisorId","mustChangePassword","lastLoginAt","createdAt","updatedAt","deletedAt") ON public."User" TO authenticated;
CREATE POLICY employee_read ON public."User" FOR SELECT TO authenticated USING(public.fg_employee_scope(id));
CREATE POLICY role_read ON public."Role" FOR SELECT TO authenticated USING(public.fg_ready());
CREATE POLICY department_read ON public."Department" FOR SELECT TO authenticated USING(public.fg_ready());
CREATE POLICY role_config_read ON public."RoleConfiguration" FOR SELECT TO authenticated USING(public.fg_has_role('ADMIN'));
CREATE POLICY membership_read ON public."UserRole" FOR SELECT TO authenticated USING(public.fg_employee_scope("userId"));
CREATE POLICY vehicle_read ON public."Vehicle" FOR SELECT TO authenticated USING(public.fg_vehicle_scope(id) OR EXISTS(SELECT 1 FROM public."Inspection" i WHERE i."vehicleId"="Vehicle".id AND public.fg_inspection_scope(i.id)));
CREATE POLICY assignment_read ON public."VehicleAssignment" FOR SELECT TO authenticated USING(public.fg_ready() AND ("driverId"=public.fg_actor() OR public.fg_vehicle_scope("vehicleId")));
CREATE POLICY supervisor_assignment_read ON public."SupervisorVehicleAssignment" FOR SELECT TO authenticated USING(public.fg_has_role('ADMIN') OR "supervisorId"=public.fg_actor());
CREATE POLICY template_read ON public."ChecklistTemplate" FOR SELECT TO authenticated USING(public.fg_ready());
CREATE POLICY version_read ON public."ChecklistVersion" FOR SELECT TO authenticated USING(public.fg_ready());
CREATE POLICY item_read ON public."ChecklistItem" FOR SELECT TO authenticated USING(public.fg_ready());
CREATE POLICY translation_read ON public."ChecklistItemTranslation" FOR SELECT TO authenticated USING(public.fg_ready());
CREATE POLICY inspection_read ON public."Inspection" FOR SELECT TO authenticated USING(public.fg_inspection_scope(id));
CREATE POLICY response_read ON public."InspectionResponse" FOR SELECT TO authenticated USING(public.fg_inspection_scope("inspectionId"));
CREATE POLICY approval_read ON public."SupervisorApproval" FOR SELECT TO authenticated USING(public.fg_inspection_scope("inspectionId"));
CREATE POLICY evidence_read ON public."InspectionEvidence" FOR SELECT TO authenticated USING(public.fg_ready() AND ("uploaderId"=public.fg_actor() OR ("inspectionId" IS NOT NULL AND public.fg_inspection_scope("inspectionId"))));
CREATE POLICY fault_read ON public."FaultReport" FOR SELECT TO authenticated USING(public.fg_fault_scope(id));
CREATE POLICY fault_image_read ON public."FaultImage" FOR SELECT TO authenticated USING(public.fg_fault_scope("faultReportId"));
CREATE POLICY maintenance_read ON public."MaintenanceRecord" FOR SELECT TO authenticated USING(public.fg_vehicle_scope("vehicleId") OR ("faultReportId" IS NOT NULL AND public.fg_fault_scope("faultReportId")));
CREATE POLICY notification_read ON public."Notification" FOR SELECT TO authenticated USING(public.fg_ready() AND "recipientUserId"=public.fg_actor());
CREATE POLICY audit_read ON public."AuditLog" FOR SELECT TO authenticated USING(public.fg_has_role('ADMIN') AND public.fg_can('viewAudit'));

CREATE FUNCTION public.fg_provision_employee(auth_id uuid, employee_email text, payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public."User"; rid text; eid text; BEGIN
 IF NOT(public.fg_has_role('ADMIN') AND public.fg_can('manageEmployees')) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 IF payload->>'role' NOT IN ('ADMIN','SUPERVISOR','DRIVER') OR length(trim(payload->>'fullName')) NOT BETWEEN 2 AND 150 OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=auth_id AND lower(email)=lower(employee_email)) THEN RAISE EXCEPTION 'Invalid employee'; END IF;
 IF payload->>'assignedSupervisorId' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public."UserRole" ur JOIN public."Role" r ON r.id=ur."roleId" JOIN public."User" s ON s.id=ur."userId" WHERE s.id=payload->>'assignedSupervisorId' AND r.code='SUPERVISOR' AND s.status='ACTIVE') THEN RAISE EXCEPTION 'Invalid supervisor'; END IF;
 eid='EMP-'||lpad(nextval('public.employee_number_seq')::text,6,'0');
 WHILE EXISTS(SELECT 1 FROM public."User" WHERE "employeeId"=eid) LOOP eid='EMP-'||lpad(nextval('public.employee_number_seq')::text,6,'0'); END LOOP;
 INSERT INTO public."User"("authUserId","employeeId","fullName",email,"departmentId","preferredLanguage","assignedSupervisorId",phone) VALUES(auth_id,eid,trim(payload->>'fullName'),lower(employee_email),payload->>'departmentId',COALESCE(payload->>'preferredLanguage','en'),payload->>'assignedSupervisorId',payload->>'phone') RETURNING * INTO u;
 SELECT id INTO rid FROM public."Role" WHERE code=payload->>'role';
 INSERT INTO public."UserRole"("userId","roleId","assignedBy") VALUES(u.id,rid,public.fg_actor());
 PERFORM public.fg_audit('EMPLOYEE_CREATE','User',u.id,NULL,jsonb_build_object('employeeId',eid,'role',payload->>'role'));
 RETURN jsonb_build_object('id',u.id,'employeeId',eid,'email',u.email);
END $$;
CREATE FUNCTION public.fg_bootstrap_admin(auth_id uuid, employee_email text, full_name text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public."User"; eid text; BEGIN
 PERFORM pg_advisory_xact_lock(hashtext('fleetguard-first-admin'));
 IF EXISTS(SELECT 1 FROM public."User" existing_user JOIN public."UserRole" ur ON ur."userId"=existing_user.id JOIN public."Role" r ON r.id=ur."roleId" WHERE r.code='ADMIN' AND existing_user."authUserId" IS NOT NULL) THEN RAISE EXCEPTION 'An administrator is already provisioned'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=auth_id AND lower(email)=lower(employee_email)) OR length(trim(full_name)) NOT BETWEEN 2 AND 150 THEN RAISE EXCEPTION 'Invalid bootstrap identity'; END IF;
 eid='EMP-'||lpad(nextval('public.employee_number_seq')::text,6,'0');
 INSERT INTO public."User"("authUserId","employeeId","fullName",email,"departmentId") VALUES(auth_id,eid,full_name,lower(employee_email),(SELECT id FROM public."Department" WHERE code='FLEET')) RETURNING * INTO u;
 INSERT INTO public."UserRole"("userId","roleId","assignedBy") VALUES(u.id,(SELECT id FROM public."Role" WHERE code='ADMIN'),'protected-bootstrap');
 INSERT INTO public."AuditLog"("actorUserId","actorEmpId","actionType","affectedTable","affectedRecord") VALUES(u.id,u."employeeId",'ADMIN_BOOTSTRAP','User',u.id);
 RETURN jsonb_build_object('id',u.id,'employeeId',eid);
END $$;
CREATE FUNCTION public.fg_password_changed(auth_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public."User"; BEGIN
 UPDATE public."User" SET "mustChangePassword"=false,"updatedAt"=now() WHERE "authUserId"=auth_id AND status='ACTIVE' RETURNING * INTO u;
 IF u.id IS NULL THEN RAISE EXCEPTION 'Account unavailable'; END IF;
 INSERT INTO public."AuditLog"("actorUserId","actorEmpId","actionType","affectedTable","affectedRecord") VALUES(u.id,u."employeeId",'PASSWORD_CHANGED','User',u.id);
END $$;
CREATE FUNCTION public.fg_rate_limit(bucket text, maximum int) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE n int; BEGIN
 IF maximum NOT BETWEEN 1 AND 100 OR length(bucket)>100 THEN RAISE EXCEPTION 'Invalid rate bucket'; END IF;
 INSERT INTO public."LoginRateLimit" VALUES(bucket,1,now()) ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN "LoginRateLimit"."windowStart"<now()-interval '15 minutes' THEN 1 ELSE "LoginRateLimit".attempts+1 END,"windowStart"=CASE WHEN "LoginRateLimit"."windowStart"<now()-interval '15 minutes' THEN now() ELSE "LoginRateLimit"."windowStart" END RETURNING attempts INTO n;
 RETURN n<=maximum;
END $$;
CREATE FUNCTION public.fg_update_employee(employee_id text, payload jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE before_row public."User"; rid text; BEGIN
 IF NOT(public.fg_has_role('ADMIN') AND public.fg_can('manageEmployees')) OR employee_id=public.fg_actor() THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO before_row FROM public."User" WHERE id=employee_id FOR UPDATE;
 IF before_row.id IS NULL THEN RAISE EXCEPTION 'Employee not found'; END IF;
 IF payload ? 'status' AND payload->>'status' NOT IN ('ACTIVE','INACTIVE','LOCKED') THEN RAISE EXCEPTION 'Invalid status'; END IF;
 IF payload ? 'role' AND payload->>'role' NOT IN ('ADMIN','SUPERVISOR','DRIVER') THEN RAISE EXCEPTION 'Invalid role'; END IF;
 IF payload ? 'fullName' AND length(trim(payload->>'fullName')) NOT BETWEEN 2 AND 150 THEN RAISE EXCEPTION 'Invalid name'; END IF;
 IF payload ? 'assignedSupervisorId' AND payload->>'assignedSupervisorId' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public."User" s JOIN public."UserRole" ur ON ur."userId"=s.id JOIN public."Role" r ON r.id=ur."roleId" WHERE s.id=payload->>'assignedSupervisorId' AND s.status='ACTIVE' AND r.code='SUPERVISOR') THEN RAISE EXCEPTION 'Invalid supervisor'; END IF;
 UPDATE public."User" SET "fullName"=COALESCE(payload->>'fullName',"fullName"),phone=CASE WHEN payload ? 'phone' THEN payload->>'phone' ELSE phone END,"departmentId"=COALESCE(payload->>'departmentId',"departmentId"),"assignedSupervisorId"=CASE WHEN payload ? 'assignedSupervisorId' THEN payload->>'assignedSupervisorId' ELSE "assignedSupervisorId" END,status=COALESCE(payload->>'status',status::text)::public."AccountStatus","preferredLanguage"=COALESCE(payload->>'preferredLanguage',"preferredLanguage"),"updatedAt"=now() WHERE id=employee_id;
 IF payload ? 'role' THEN
  SELECT id INTO rid FROM public."Role" WHERE code=payload->>'role';DELETE FROM public."UserRole" WHERE "userId"=employee_id;INSERT INTO public."UserRole"("userId","roleId","assignedBy") VALUES(employee_id,rid,public.fg_actor());
 END IF;
 PERFORM public.fg_audit('EMPLOYEE_UPDATE','User',employee_id,jsonb_build_object('status',before_row.status,'supervisor',before_row."assignedSupervisorId"),payload);
END $$;
CREATE FUNCTION public.fg_set_language(language text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF language NOT IN ('ar','en') OR public.fg_actor() IS NULL THEN RAISE EXCEPTION 'Unsupported language' USING ERRCODE='42501'; END IF;
 UPDATE public."User" SET "preferredLanguage"=language,"updatedAt"=now() WHERE id=public.fg_actor();
END $$;
CREATE FUNCTION public.fg_configure_role(role_code text, flags jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old jsonb; BEGIN
 IF NOT(public.fg_has_role('ADMIN') AND public.fg_can('configurePermissions')) OR role_code NOT IN ('SUPERVISOR','DRIVER') THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(flags) f WHERE f.key NOT IN ('reviewInspections','manageMaintenance','exportReports','submitInspections') OR jsonb_typeof(f.value)<>'boolean') THEN RAISE EXCEPTION 'Invalid permission'; END IF;
 IF role_code='DRIVER' AND EXISTS(SELECT 1 FROM jsonb_each(flags) f WHERE f.key<>'submitInspections' AND f.value='true') THEN RAISE EXCEPTION 'Drivers cannot receive management permissions'; END IF;
 SELECT permissions INTO old FROM public."RoleConfiguration" WHERE "roleCode"=role_code FOR UPDATE;
 UPDATE public."RoleConfiguration" SET permissions=flags,"updatedAt"=now() WHERE "roleCode"=role_code;
 PERFORM public.fg_audit('ROLE_PERMISSIONS','RoleConfiguration',role_code,old,flags);
END $$;
CREATE FUNCTION public.fg_create_vehicle(payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public."Vehicle"; BEGIN
 IF NOT(public.fg_has_role('ADMIN') AND public.fg_can('manageVehicles')) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 IF COALESCE((payload->>'currentOdometerKm')::int,0)<0 OR (payload->>'manufacturingYear')::int NOT BETWEEN 1950 AND 2100 OR length(trim(payload->>'vehicleCode')) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Invalid vehicle'; END IF;
 INSERT INTO public."Vehicle"("vehicleCode","registrationNumber","plateNumber","vehicleCategory",manufacturer,model,"manufacturingYear","departmentId","currentOdometerKm","registrationExpiryDate","insuranceExpiryDate","qrToken") VALUES(payload->>'vehicleCode',payload->>'registrationNumber',payload->>'plateNumber',payload->>'vehicleCategory',payload->>'manufacturer',payload->>'model',(payload->>'manufacturingYear')::int,payload->>'departmentId',COALESCE((payload->>'currentOdometerKm')::int,0),(payload->>'registrationExpiryDate')::date,(payload->>'insuranceExpiryDate')::date,encode(extensions.gen_random_bytes(32),'hex')) RETURNING * INTO v;
 PERFORM public.fg_audit('VEHICLE_CREATE','Vehicle',v.id,NULL,jsonb_build_object('vehicleCode',v."vehicleCode"));RETURN to_jsonb(v);
END $$;
CREATE FUNCTION public.fg_update_vehicle(vehicle_id text,payload jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public."Vehicle"; BEGIN
 IF NOT(public.fg_has_role('ADMIN') AND public.fg_can('manageVehicles')) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO v FROM public."Vehicle" WHERE id=vehicle_id FOR UPDATE;
 IF v.id IS NULL THEN RAISE EXCEPTION 'Vehicle not found'; END IF;
 UPDATE public."Vehicle" SET status=COALESCE(payload->>'status',status::text)::public."VehicleStatus","registrationExpiryDate"=COALESCE((payload->>'registrationExpiryDate')::date,"registrationExpiryDate"),"insuranceExpiryDate"=COALESCE((payload->>'insuranceExpiryDate')::date,"insuranceExpiryDate"),"updatedAt"=now() WHERE id=vehicle_id;
 PERFORM public.fg_audit('VEHICLE_UPDATE','Vehicle',vehicle_id,jsonb_build_object('status',v.status),payload);
END $$;
CREATE FUNCTION public.fg_assign(payload jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE d date=(payload->>'date')::date; BEGIN
 IF NOT(public.fg_has_role('ADMIN') AND public.fg_can('assignVehicles')) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 IF payload->>'kind' NOT IN ('DRIVER','SUPERVISOR') OR length(trim(payload->>'reason')) NOT BETWEEN 3 AND 500 OR d IS NULL THEN RAISE EXCEPTION 'Invalid assignment'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public."User" u JOIN public."UserRole" ur ON ur."userId"=u.id JOIN public."Role" r ON r.id=ur."roleId" WHERE u.id=payload->>'userId' AND u.status='ACTIVE' AND u."authUserId" IS NOT NULL AND r.code=payload->>'kind') OR NOT EXISTS(SELECT 1 FROM public."Vehicle" WHERE id=payload->>'vehicleId' AND "archivedAt" IS NULL) THEN RAISE EXCEPTION 'Invalid employee or vehicle'; END IF;
 PERFORM pg_advisory_xact_lock(hashtext(payload->>'vehicleId'));
 IF payload->>'kind'='DRIVER' THEN
  UPDATE public."VehicleAssignment" SET "isActive"=false,"endDate"=now() WHERE "vehicleId"=payload->>'vehicleId' AND "assignmentDate"=d AND "isActive";
  INSERT INTO public."VehicleAssignment"("vehicleId","driverId","assignmentDate","startDate","assignedById","changeReason") VALUES(payload->>'vehicleId',payload->>'userId',d,now(),public.fg_actor(),payload->>'reason');
 ELSE
  UPDATE public."SupervisorVehicleAssignment" SET "isActive"=false,"revokedAt"=now() WHERE "vehicleId"=payload->>'vehicleId' AND "supervisorId"=payload->>'userId' AND "isActive";
  INSERT INTO public."SupervisorVehicleAssignment"("vehicleId","supervisorId","assignedById") VALUES(payload->>'vehicleId',payload->>'userId',public.fg_actor());
 END IF;
 PERFORM public.fg_audit('VEHICLE_ASSIGN','Vehicle',payload->>'vehicleId',NULL,payload);
END $$;
CREATE FUNCTION public.fg_register_evidence(vehicle_id text,item_id text,object_key text,mime text,bytes int) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE e public."InspectionEvidence"; BEGIN
 IF NOT public.fg_ready() OR NOT public.fg_vehicle_scope(vehicle_id) OR split_part(object_key,'/',1)<>auth.uid()::text OR split_part(object_key,'/',2)<>vehicle_id THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='inspection-evidence' AND name=object_key) OR NOT EXISTS(SELECT 1 FROM public."ChecklistItem" WHERE id=item_id AND "isActive") THEN RAISE EXCEPTION 'Evidence upload is not present'; END IF;
 INSERT INTO public."InspectionEvidence"("vehicleId","uploaderId","checklistItemId","storageKey","mimeType","fileSizeBytes") VALUES(vehicle_id,public.fg_actor(),item_id,object_key,mime,bytes) RETURNING * INTO e;
 PERFORM public.fg_audit('EVIDENCE_UPLOAD','InspectionEvidence',e.id);RETURN jsonb_build_object('id',e.id);
END $$;
CREATE FUNCTION public.fg_submit_inspection(payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE actor text=public.fg_actor(); actor_row public."User"; v public."Vehicle"; version public."ChecklistVersion"; ins public."Inspection"; item public."ChecklistItem"; r jsonb; unsafe boolean=false; failed boolean=false; eid text; date_today date=(now() AT TIME ZONE 'Asia/Muscat')::date; recipient text; evidence_ids text[]='{}';
BEGIN
 IF NOT(public.fg_has_role('DRIVER') AND public.fg_can('submitInspections')) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO actor_row FROM public."User" WHERE id=actor;
 IF length(payload->>'idempotencyKey')<>36 THEN RAISE EXCEPTION 'Invalid idempotency key'; END IF;
 PERFORM pg_advisory_xact_lock(hashtext(payload->>'vehicleId'));
 SELECT * INTO ins FROM public."Inspection" WHERE "idempotencyKey"=payload->>'idempotencyKey';
 IF ins.id IS NOT NULL THEN
  IF ins."driverId"<>actor OR ins."vehicleId"<>payload->>'vehicleId' THEN RAISE EXCEPTION 'Idempotency conflict' USING ERRCODE='23505'; END IF;
  RETURN to_jsonb(ins);
 END IF;
 IF (payload->>'inspectionDate')::date<>date_today OR payload->>'inspectionDate' IS NULL THEN RAISE EXCEPTION 'Late offline inspection requires review; its date cannot be changed automatically'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public."VehicleAssignment" WHERE "vehicleId"=payload->>'vehicleId' AND "driverId"=actor AND "isActive" AND "assignmentDate"=date_today) THEN RAISE EXCEPTION 'No active driver assignment' USING ERRCODE='42501'; END IF;
 SELECT * INTO v FROM public."Vehicle" WHERE id=payload->>'vehicleId' FOR UPDATE;
 IF v.id IS NULL OR v.status<>'ACTIVE' OR v."archivedAt" IS NOT NULL THEN RAISE EXCEPTION 'Vehicle unavailable'; END IF;
 IF (payload->>'startingKm')::int<v."currentOdometerKm" OR (payload->>'closingKm')::int<(payload->>'startingKm')::int OR payload->>'startingKm' IS NULL OR payload->>'closingKm' IS NULL THEN RAISE EXCEPTION 'Invalid odometer'; END IF;
 IF length(trim(payload->>'driverSignature')) NOT BETWEEN 2 AND 500 OR payload->>'driverSignature' IS NULL OR payload->>'ropExpiryDate' IS NULL THEN RAISE EXCEPTION 'Driver signature and licence expiry are required'; END IF;
 SELECT * INTO version FROM public."ChecklistVersion" WHERE id=payload->>'checklistVersionId' AND "isPublished";
 IF version.id IS NULL THEN RAISE EXCEPTION 'Checklist version unavailable'; END IF;
 IF jsonb_typeof(payload->'responses')<>'array' OR jsonb_array_length(payload->'responses')<>27 OR (SELECT count(*) FROM public."ChecklistItem" WHERE "versionId"=version.id AND "isActive")<>27 THEN RAISE EXCEPTION 'Complete all 27 inspection checks and signoff fields'; END IF;
 IF (SELECT count(DISTINCT a->>'checklistItemId') FROM jsonb_array_elements(payload->'responses') a)<>27 THEN RAISE EXCEPTION 'Duplicate checklist answer'; END IF;
 FOR r IN SELECT * FROM jsonb_array_elements(payload->'responses') LOOP
  SELECT * INTO item FROM public."ChecklistItem" WHERE id=r->>'checklistItemId' AND "versionId"=version.id AND "isActive";
  IF item.id IS NULL OR r->>'response' NOT IN ('PASS','FAIL','NA') OR r->>'response' IS NULL OR NOT (r->>'response'=ANY(item."allowedResponses")) THEN RAISE EXCEPTION 'Invalid checklist answer'; END IF;
  IF length(COALESCE(r->>'remarks',''))>1000 THEN RAISE EXCEPTION 'Comment too long'; END IF;
  IF r->>'response'='FAIL' AND length(trim(COALESCE(r->>'remarks','')))<3 THEN RAISE EXCEPTION 'A comment is required for every failed item'; END IF;
  IF r->>'response'='FAIL' AND item."requirePhotoOnFail" AND NOT EXISTS(SELECT 1 FROM public."InspectionEvidence" e WHERE e.id IN (SELECT jsonb_array_elements_text(COALESCE(r->'evidenceIds','[]'))) AND e."uploaderId"=actor AND e."vehicleId"=v.id AND e."checklistItemId"=item.id AND e."inspectionId" IS NULL) THEN RAISE EXCEPTION 'Photo evidence is required for this failed item'; END IF;
  FOR eid IN SELECT jsonb_array_elements_text(COALESCE(r->'evidenceIds','[]')) LOOP
   IF eid=ANY(evidence_ids) OR NOT EXISTS(SELECT 1 FROM public."InspectionEvidence" WHERE id=eid AND "uploaderId"=actor AND "vehicleId"=v.id AND "checklistItemId"=item.id AND "inspectionId" IS NULL) THEN RAISE EXCEPTION 'Invalid or already used evidence'; END IF;
   evidence_ids=array_append(evidence_ids,eid);
  END LOOP;
  IF r->>'response'='FAIL' THEN failed=true;unsafe=unsafe OR item."isSafetyCritical"; END IF;
 END LOOP;
 INSERT INTO public."Inspection"("inspectionCode","idempotencyKey","vehicleId","driverId","driverNameSnapshot","employeeIdSnapshot","checklistVersionId","inspectionDate","dayOfWeek","startingKm","closingKm","odometerKm","ropExpiryDate","driverSignature","generalRemarks","defectDescription","actionTaken",status)
 VALUES('INS-'||gen_random_uuid(),payload->>'idempotencyKey',v.id,actor,actor_row."fullName",actor_row."employeeId",version.id,date_today,trim(to_char(date_today,'Day')),(payload->>'startingKm')::int,(payload->>'closingKm')::int,(payload->>'closingKm')::int,(payload->>'ropExpiryDate')::date,payload->>'driverSignature',payload->>'generalRemarks',payload->>'defectDescription',payload->>'actionTaken',CASE WHEN unsafe THEN 'FLAGGED_UNSAFE'::public."InspectionStatus" ELSE 'SUBMITTED'::public."InspectionStatus" END) RETURNING * INTO ins;
 FOR r IN SELECT * FROM jsonb_array_elements(payload->'responses') LOOP
  SELECT * INTO item FROM public."ChecklistItem" WHERE id=r->>'checklistItemId';
  INSERT INTO public."InspectionResponse"("inspectionId","checklistItemId",response,remarks) VALUES(ins.id,item.id,(r->>'response')::public."ItemResponseValue",r->>'remarks');
  IF r->>'response'='FAIL' THEN
   INSERT INTO public."FaultReport"("faultCode","vehicleId","inspectionId","checklistItemSn","reportedById",category,description,severity) VALUES('FLT-'||gen_random_uuid(),v.id,ins.id,item."serialNumber",actor,item."categoryCode",r->>'remarks',CASE WHEN item."isSafetyCritical" THEN 'CRITICAL'::public."FaultSeverity" ELSE 'MEDIUM'::public."FaultSeverity" END);
   IF (SELECT count(*) FROM public."FaultReport" WHERE "vehicleId"=v.id AND category=item."categoryCode" AND "reportedAt">=now()-interval '7 days')>1 THEN
    FOR recipient IN SELECT "supervisorId" FROM public."SupervisorVehicleAssignment" WHERE "vehicleId"=v.id AND "isActive" UNION SELECT "assignedSupervisorId" FROM public."User" WHERE id=actor AND "assignedSupervisorId" IS NOT NULL LOOP
     INSERT INTO public."Notification"("recipientUserId","vehicleId",type,title,message) VALUES(recipient,v.id,'REPEATED_FAILURE','Repeated failure','Item '||item."serialNumber"||' on '||v."vehicleCode");
    END LOOP;
   END IF;
  END IF;
 END LOOP;
 UPDATE public."InspectionEvidence" SET "inspectionId"=ins.id WHERE id=ANY(evidence_ids);
 UPDATE public."Vehicle" SET "currentOdometerKm"=ins."odometerKm","safetyState"=CASE WHEN unsafe THEN 'OUT_OF_SERVICE'::public."VehicleSafetyState" WHEN failed AND "safetyState"='SAFE' THEN 'NEEDS_REVIEW'::public."VehicleSafetyState" ELSE "safetyState" END,"updatedAt"=now() WHERE id=v.id;
 FOR recipient IN SELECT "supervisorId" FROM public."SupervisorVehicleAssignment" WHERE "vehicleId"=v.id AND "isActive" UNION SELECT "assignedSupervisorId" FROM public."User" WHERE id=actor AND "assignedSupervisorId" IS NOT NULL LOOP
  INSERT INTO public."Notification"("recipientUserId","vehicleId",type,title,message) VALUES(recipient,v.id,CASE WHEN unsafe THEN 'CRITICAL_FAULT' ELSE 'INSPECTION_REVIEW' END,'Inspection awaiting review',v."vehicleCode");
 END LOOP;
 PERFORM public.fg_audit('INSPECTION_SUBMIT','Inspection',ins.id,NULL,jsonb_build_object('unsafe',unsafe,'failed',failed));RETURN to_jsonb(ins);
END $$;
CREATE FUNCTION public.fg_review_inspection(inspection_id text,decision text,comments text,signature text DEFAULT NULL) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE ins public."Inspection"; BEGIN
 IF NOT(public.fg_can('reviewInspections') AND (public.fg_has_role('ADMIN') OR public.fg_has_role('SUPERVISOR')) AND public.fg_inspection_scope(inspection_id)) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO ins FROM public."Inspection" WHERE id=inspection_id FOR UPDATE;
 IF ins."driverId"=public.fg_actor() OR ins.id IS NULL THEN RAISE EXCEPTION 'Cannot review own report' USING ERRCODE='42501'; END IF;
 IF decision NOT IN ('APPROVED','REJECTED') OR length(trim(comments)) NOT BETWEEN 1 AND 2000 OR comments IS NULL OR (decision='APPROVED' AND (signature IS NULL OR length(trim(signature))<2)) THEN RAISE EXCEPTION 'A review comment and approval signature are required'; END IF;
 INSERT INTO public."SupervisorApproval"("inspectionId","reviewerId",decision,comments,signature) VALUES(ins.id,public.fg_actor(),decision,comments,signature);
 UPDATE public."Inspection" SET "reviewStatus"=decision,"supervisorSign"=CASE WHEN decision='APPROVED' THEN signature ELSE NULL END WHERE id=ins.id;
 PERFORM public.fg_audit('INSPECTION_REVIEW','Inspection',ins.id,jsonb_build_object('decision',ins."reviewStatus"),jsonb_build_object('decision',decision,'comments',comments,'signature',signature));
END $$;
CREATE FUNCTION public.fg_fault_status(fault_id text,next_status text,notes text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE f public."FaultReport"; valid boolean=false; BEGIN
 IF NOT(public.fg_can('manageMaintenance') AND (public.fg_has_role('ADMIN') OR public.fg_has_role('SUPERVISOR')) AND public.fg_fault_scope(fault_id)) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO f FROM public."FaultReport" WHERE id=fault_id FOR UPDATE;
 valid=CASE f.status WHEN 'REPORTED' THEN next_status='ACKNOWLEDGED' WHEN 'ACKNOWLEDGED' THEN next_status IN ('UNDER_REVIEW','UNDER_MAINTENANCE') WHEN 'UNDER_REVIEW' THEN next_status IN ('UNDER_MAINTENANCE','RESOLVED') WHEN 'UNDER_MAINTENANCE' THEN next_status='RESOLVED' WHEN 'RESOLVED' THEN next_status='VERIFIED_AND_CLOSED' ELSE false END;
 IF NOT valid OR length(trim(notes)) NOT BETWEEN 3 AND 2000 OR notes IS NULL THEN RAISE EXCEPTION 'Invalid fault transition or notes'; END IF;
 UPDATE public."FaultReport" SET status=next_status::public."FaultWorkflowStatus","resolutionNotes"=notes,"resolvedAt"=CASE WHEN next_status='RESOLVED' THEN now() ELSE "resolvedAt" END,"closedAt"=CASE WHEN next_status='VERIFIED_AND_CLOSED' THEN now() ELSE "closedAt" END WHERE id=fault_id;
 IF next_status='VERIFIED_AND_CLOSED' AND NOT EXISTS(SELECT 1 FROM public."FaultReport" WHERE "vehicleId"=f."vehicleId" AND status<>'VERIFIED_AND_CLOSED') THEN UPDATE public."Vehicle" SET "safetyState"='SAFE',"updatedAt"=now() WHERE id=f."vehicleId"; END IF;
 PERFORM public.fg_audit('FAULT_STATUS','FaultReport',f.id,jsonb_build_object('status',f.status),jsonb_build_object('status',next_status,'notes',notes));
END $$;
CREATE FUNCTION public.fg_add_maintenance(payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE m public."MaintenanceRecord"; BEGIN
 IF NOT(public.fg_can('manageMaintenance') AND (public.fg_has_role('ADMIN') OR public.fg_has_role('SUPERVISOR')) AND public.fg_vehicle_scope(payload->>'vehicleId')) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public."FaultReport" WHERE id=payload->>'faultReportId' AND "vehicleId"=payload->>'vehicleId' AND status='UNDER_MAINTENANCE') OR length(trim(payload->>'workDescription'))<3 OR (payload->>'costOmr')::numeric<0 OR (payload->>'odometerAtService')::int<0 THEN RAISE EXCEPTION 'Invalid maintenance record'; END IF;
 INSERT INTO public."MaintenanceRecord"("maintenanceCode","vehicleId","faultReportId","technicianName","workDescription","odometerAtService","costOmr",status,"completedAt") VALUES('MNT-'||gen_random_uuid(),payload->>'vehicleId',payload->>'faultReportId',payload->>'technicianName',payload->>'workDescription',(payload->>'odometerAtService')::int,(payload->>'costOmr')::numeric,'COMPLETED',now()) RETURNING * INTO m;
 PERFORM public.fg_audit('MAINTENANCE_CREATE','MaintenanceRecord',m.id);RETURN to_jsonb(m);
END $$;
CREATE FUNCTION public.fg_publish_template(items jsonb) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE template_id text; version_id text; r jsonb; item_id text; BEGIN
 IF NOT(public.fg_has_role('ADMIN') AND public.fg_can('manageTemplates')) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 IF jsonb_array_length(items)<>27 OR (SELECT count(DISTINCT (x->>'serialNumber')::int) FROM jsonb_array_elements(items) x WHERE (x->>'serialNumber')::int BETWEEN 1 AND 27)<>27 THEN RAISE EXCEPTION 'Keep all 27 numbered checks; rows 28–32 are signoff fields'; END IF;
 SELECT id INTO template_id FROM public."ChecklistTemplate" WHERE code='AL_GHALBI_WEEKLY_STD' FOR UPDATE;
 UPDATE public."ChecklistVersion" SET "isPublished"=false WHERE "templateId"=template_id;
 INSERT INTO public."ChecklistVersion"("templateId","versionNumber","isPublished","publishedById","publishedAt") VALUES(template_id,(SELECT COALESCE(max("versionNumber"),0)+1 FROM public."ChecklistVersion" WHERE "templateId"=template_id),true,public.fg_actor(),now()) RETURNING id INTO version_id;
 FOR r IN SELECT * FROM jsonb_array_elements(items) LOOP
  IF length(trim(r->>'labelEn')) NOT BETWEEN 1 AND 300 OR length(trim(r->>'labelAr')) NOT BETWEEN 1 AND 300 OR r->>'labelEn' IS NULL OR r->>'labelAr' IS NULL THEN RAISE EXCEPTION 'Arabic and English labels are required'; END IF;
  INSERT INTO public."ChecklistItem"("versionId","serialNumber","categoryCode","allowedResponses","sortOrder","isSafetyCritical","requirePhotoOnFail") VALUES(version_id,(r->>'serialNumber')::int,'ITEM_'||(r->>'serialNumber'),ARRAY['PASS','FAIL','NA'],(r->>'serialNumber')::int,COALESCE((r->>'isSafetyCritical')::boolean,false),COALESCE((r->>'requirePhotoOnFail')::boolean,false)) RETURNING id INTO item_id;
  INSERT INTO public."ChecklistItemTranslation"("itemId","languageCode",label) VALUES(item_id,'en',r->>'labelEn'),(item_id,'ar',r->>'labelAr');
 END LOOP;
 PERFORM public.fg_audit('TEMPLATE_PUBLISH','ChecklistVersion',version_id,NULL,jsonb_build_object('count',27));RETURN version_id;
END $$;
CREATE FUNCTION public.fg_dashboard() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,pg_temp AS $$
 SELECT jsonb_build_object(
 'employees',(SELECT count(*) FROM public."User" WHERE "authUserId" IS NOT NULL AND "deletedAt" IS NULL),
 'activeEmployees',(SELECT count(*) FROM public."User" WHERE "authUserId" IS NOT NULL AND status='ACTIVE' AND "deletedAt" IS NULL),
 'vehicles',(SELECT count(*) FROM public."Vehicle" WHERE "archivedAt" IS NULL),
 'inspectionsToday',(SELECT count(*) FROM public."Inspection" WHERE "inspectionDate"=(now() AT TIME ZONE 'Asia/Muscat')::date),
 'pendingInspections',(SELECT count(*) FROM public."VehicleAssignment" a WHERE a."isActive" AND a."assignmentDate"=(now() AT TIME ZONE 'Asia/Muscat')::date AND NOT EXISTS(SELECT 1 FROM public."Inspection" i WHERE i."vehicleId"=a."vehicleId" AND i."driverId"=a."driverId" AND i."inspectionDate"=a."assignmentDate")),
 'failedInspections',(SELECT count(*) FROM public."Inspection" i WHERE EXISTS(SELECT 1 FROM public."InspectionResponse" r WHERE r."inspectionId"=i.id AND r.response='FAIL')),
 'maintenanceVehicles',(SELECT count(*) FROM public."Vehicle" WHERE "safetyState"<>'SAFE' OR status='UNDER_MAINTENANCE'),
 'pendingApprovals',(SELECT count(*) FROM public."Inspection" WHERE "reviewStatus"='PENDING'),
 'openFaults',(SELECT count(*) FROM public."FaultReport" WHERE status<>'VERIFIED_AND_CLOSED'))
$$;
CREATE FUNCTION public.fg_record_export(format text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT public.fg_can('exportReports') OR format NOT IN ('PDF','XLSX') THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 PERFORM public.fg_audit('REPORT_EXPORT','Inspection',format);
END $$;
CREATE FUNCTION public.fg_schema_version() RETURNS text LANGUAGE sql STABLE SECURITY INVOKER AS $$ SELECT 'fleetguard-supabase-v2'::text $$;

-- Submitted answers and review decisions are append-only, even for direct SQL users.
CREATE FUNCTION public.fg_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN RAISE EXCEPTION 'Completed records are immutable'; END $$;
CREATE TRIGGER immutable_answers BEFORE UPDATE OR DELETE ON public."InspectionResponse" FOR EACH ROW EXECUTE FUNCTION public.fg_immutable();
CREATE TRIGGER immutable_approvals BEFORE UPDATE OR DELETE ON public."SupervisorApproval" FOR EACH ROW EXECUTE FUNCTION public.fg_immutable();
CREATE FUNCTION public.fg_protect_report() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN
 IF (to_jsonb(NEW)-ARRAY['supervisorSign','reviewStatus']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['supervisorSign','reviewStatus']) THEN RAISE EXCEPTION 'Submitted report content is immutable; review changes are audited'; END IF;RETURN NEW;
END $$;
CREATE TRIGGER immutable_report BEFORE UPDATE ON public."Inspection" FOR EACH ROW EXECUTE FUNCTION public.fg_protect_report();
CREATE TRIGGER no_delete_report BEFORE DELETE ON public."Inspection" FOR EACH ROW EXECUTE FUNCTION public.fg_immutable();

-- Private Supabase Storage bucket, with the same identity/vehicle rules as the database.
GRANT SELECT,INSERT ON storage.objects TO authenticated;
GRANT SELECT ON storage.buckets TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO service_role;
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES('inspection-evidence','inspection-evidence',false,5000000,ARRAY['image/jpeg','image/png','image/webp']);
CREATE POLICY evidence_upload ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='inspection-evidence' AND public.fg_ready() AND (storage.foldername(name))[1]=auth.uid()::text AND public.fg_vehicle_scope((storage.foldername(name))[2]));
CREATE FUNCTION public.fg_storage_read(object_key text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fg_ready() AND (split_part(object_key,'/',1)=auth.uid()::text OR EXISTS(SELECT 1 FROM public."InspectionEvidence" e WHERE e."storageKey"=$1 AND e."inspectionId" IS NOT NULL AND public.fg_inspection_scope(e."inspectionId")) OR EXISTS(SELECT 1 FROM public."FaultImage" f WHERE f."storageKey"=$1 AND public.fg_fault_scope(f."faultReportId")))
$$;
CREATE POLICY evidence_download ON storage.objects FOR SELECT TO authenticated USING(bucket_id='inspection-evidence' AND public.fg_storage_read(name));
-- Restrictive rules also protect this bucket if another application has broad permissive policies.
CREATE POLICY fg_evidence_read_guard ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated USING(bucket_id<>'inspection-evidence' OR public.fg_storage_read(name));
CREATE POLICY fg_evidence_insert_guard ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(bucket_id<>'inspection-evidence' OR (public.fg_ready() AND (storage.foldername(name))[1]=auth.uid()::text AND public.fg_vehicle_scope((storage.foldername(name))[2])));
CREATE POLICY fg_evidence_update_guard ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated USING(bucket_id<>'inspection-evidence') WITH CHECK(bucket_id<>'inspection-evidence');
CREATE POLICY fg_evidence_delete_guard ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated USING(bucket_id<>'inspection-evidence');
-- Users cannot overwrite or delete submitted evidence. Orphan cleanup is a separate service task.

CREATE FUNCTION public.fg_auth_event(event text,employee_id text DEFAULT NULL) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF public.fg_actor() IS NULL OR (event NOT IN ('LOGIN','LOGOUT') AND NOT(event='PASSWORD_RESET_REQUEST' AND public.fg_has_role('ADMIN') AND public.fg_can('manageEmployees'))) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF;
 IF event='LOGIN' THEN UPDATE public."User" SET "lastLoginAt"=now() WHERE id=public.fg_actor(); END IF;
 PERFORM public.fg_audit(event,'User',COALESCE(employee_id,public.fg_actor()));
END $$;

-- Operator-only account migration: retain an existing Auth identity and its password.
CREATE FUNCTION public.fg_link_legacy_employee(employee_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE source jsonb; linked public."User"; role_code text; BEGIN
 IF to_regclass('public.profiles') IS NULL THEN RAISE EXCEPTION 'No legacy profile model exists'; END IF;
 EXECUTE 'SELECT to_jsonb(p) FROM public.profiles p WHERE employee_id=$1' INTO source USING employee_id;
 IF source IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=(source->>'id')::uuid AND lower(email)=lower(source->>'email') AND email_confirmed_at IS NOT NULL) THEN RAISE EXCEPTION 'A verified matching legacy Auth identity is required'; END IF;
 IF EXISTS(SELECT 1 FROM public."User" WHERE "authUserId"=(source->>'id')::uuid) THEN RAISE EXCEPTION 'Identity is already linked'; END IF;
 role_code=CASE source->>'role' WHEN 'administrator' THEN 'ADMIN' WHEN 'supervisor' THEN 'SUPERVISOR' WHEN 'driver' THEN 'DRIVER' ELSE NULL END;
 IF role_code IS NULL OR source->>'language' NOT IN ('ar','en') THEN RAISE EXCEPTION 'Legacy role or language must be reviewed'; END IF;
 INSERT INTO public."User"(id,"authUserId","employeeId","fullName",email,"departmentId","preferredLanguage",status,"mustChangePassword") VALUES(source->>'id',(source->>'id')::uuid,source->>'employee_id',source->>'full_name',lower(source->>'email'),(SELECT id FROM public."Department" WHERE code='FLEET'),source->>'language',CASE WHEN (source->>'active')::boolean THEN 'ACTIVE'::public."AccountStatus" ELSE 'INACTIVE'::public."AccountStatus" END,false) RETURNING * INTO linked;
 INSERT INTO public."UserRole"("userId","roleId","assignedBy") VALUES(linked.id,(SELECT id FROM public."Role" WHERE code=role_code),'protected-legacy-link');
 INSERT INTO public."AuditLog"("actorUserId","actorEmpId","actionType","affectedTable","affectedRecord") VALUES(linked.id,linked."employeeId",'LEGACY_IDENTITY_LINK','User',linked.id);
 RETURN jsonb_build_object('employeeId',linked."employeeId",'id',linked.id);
END $$;

-- Supabase defaults give PUBLIC execute; explicitly close every custom function.
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'fg_%' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.signature);
  IF f.proname IN ('fg_bootstrap_admin','fg_password_changed','fg_rate_limit','fg_link_legacy_employee') THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',f.signature);
  ELSIF f.proname NOT IN ('fg_audit','fg_immutable','fg_protect_report') THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated,service_role',f.signature);
  END IF;
 END LOOP;
END $$;
REVOKE ALL ON SEQUENCE public.employee_number_seq FROM anon,authenticated;
-- Realtime changes are hints only; every refresh still fetches through RLS.
DO $$ DECLARE t text; BEGIN
 IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
  FOREACH t IN ARRAY ARRAY['Inspection','FaultReport','Notification'] LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename=t) THEN EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',t); END IF;
  END LOOP;
 END IF;
END $$;

-- Keep privileged implementations out of the exposed API schema. Public RPCs are
-- SECURITY INVOKER wrappers; private implementations keep their explicit actor checks.
CREATE SCHEMA IF NOT EXISTS fleetguard_private;
REVOKE ALL ON SCHEMA fleetguard_private FROM PUBLIC,anon;
GRANT USAGE ON SCHEMA fleetguard_private TO authenticated,service_role;
DO $$ DECLARE f record; args text; wrapper_sql text; volatility text; BEGIN
 FOR f IN SELECT p.proname,pg_get_function_arguments(p.oid) arguments,pg_get_function_identity_arguments(p.oid) identity_arguments,pg_get_function_result(p.oid) result_type,p.pronargs,p.provolatile FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'fg_%' AND p.prosecdef LOOP
  SELECT COALESCE(string_agg('$'||i,',' ORDER BY i),'') INTO args FROM generate_series(1,f.pronargs) i;
  volatility=CASE f.provolatile WHEN 's' THEN 'STABLE' WHEN 'i' THEN 'IMMUTABLE' ELSE 'VOLATILE' END;
  EXECUTE format('ALTER FUNCTION public.%I(%s) SET SCHEMA fleetguard_private',f.proname,f.identity_arguments);
  wrapper_sql=format('SELECT fleetguard_private.%I(%s)',f.proname,args);
  EXECUTE format('CREATE FUNCTION public.%I(%s) RETURNS %s LANGUAGE sql %s SECURITY INVOKER SET search_path='''' AS %L',f.proname,f.arguments,f.result_type,volatility,wrapper_sql);
  EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC,anon,authenticated,service_role',f.proname,f.identity_arguments);
  IF f.proname IN ('fg_bootstrap_admin','fg_password_changed','fg_rate_limit','fg_link_legacy_employee') THEN EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO service_role',f.proname,f.identity_arguments);
  ELSIF f.proname<>'fg_audit' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated,service_role',f.proname,f.identity_arguments);
  END IF;
 END LOOP;
END $$;

-- Reference checklist imported from the supplied workbook. Past versions remain intact.
DO $$ DECLARE tid text; vid text; iid text; r record; BEGIN
 INSERT INTO public."ChecklistTemplate"(code,"titleEn","titleAr") VALUES('AL_GHALBI_WEEKLY_STD','Weekly vehicle checklist','جدول الفحص الأسبوعي للمركبة') ON CONFLICT(code) DO NOTHING;
 SELECT id INTO tid FROM public."ChecklistTemplate" WHERE code='AL_GHALBI_WEEKLY_STD';
 INSERT INTO public."ChecklistVersion"("templateId","versionNumber","isPublished","publishedAt") VALUES(tid,(SELECT COALESCE(max("versionNumber"),0)+1 FROM public."ChecklistVersion" WHERE "templateId"=tid),true,now()) RETURNING id INTO vid;
 FOR r IN SELECT * FROM (VALUES
(1,'Light & Indicator','الأضواء والإشارات'),
(2,'Mirrors','المرايا'),
(3,'Blind spot mirror','مرآة النقطة العمياء'),
(4,'Horn','البوق'),
(5,'Fuel','الوقود'),
(6,'Seat Belt','حزام الأمان'),
(7,'Communication Radio / Tape','جهاز الاتصال اللاسلكي'),
(8,'A/C In Vehicle','مكيف الهواء'),
(9,'Body Damage','أضرار الهيكل'),
(10,'Tyres, nut & bolts','الإطارات والصواميل والبراغي'),
(11,'Load Restraint','تثبيت الحمولة'),
(12,'Battery','البطارية'),
(13,'Oil Level','مستوى الزيت'),
(14,'Water Level','مستوى الماء'),
(15,'Steering','المقود'),
(16,'Wipers & Wind Screen','المساحات والزجاج الأمامي'),
(17,'Brakes','الفرامل'),
(18,'First Aid Box','صندوق الإسعافات الأولية'),
(19,'Fire Extinguishers','طفايات الحريق'),
(20,'Jack, Tools, Tringle','الرافعة والأدوات ومثلث التحذير'),
(21,'Vehicle registration papers','أوراق تسجيل المركبة'),
(22,'Ladder condition','حالة السلم'),
(23,'IVMS','نظام مراقبة المركبة IVMS'),
(24,'Housekeeping','نظافة المركبة وترتيبها'),
(25,'360 degree Walk around','فحص محيط المركبة بزاوية 360 درجة'),
(26,'RAS Sticker OPAL','ملصق الفحص RAS الخاص بأوبال'),
(27,'Driver''s Mandatory Training Cards','بطاقات التدريب الإلزامي للسائق')
) AS x(sn,en,ar) LOOP
 INSERT INTO public."ChecklistItem"("versionId","serialNumber","categoryCode","allowedResponses","sortOrder","isSafetyCritical","requirePhotoOnFail") VALUES(vid,r.sn,'ITEM_'||r.sn,ARRAY['PASS','FAIL','NA'],r.sn,false,false) RETURNING id INTO iid;
 INSERT INTO public."ChecklistItemTranslation"("itemId","languageCode",label) VALUES(iid,'en',r.en),(iid,'ar',r.ar);
 END LOOP;
END $$;
