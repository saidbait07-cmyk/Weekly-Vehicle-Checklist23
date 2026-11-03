import { NextRequest, NextResponse } from 'next/server';
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import { randomUUID } from 'node:crypto';
import {mkdir,writeFile,readFile,unlink} from 'node:fs/promises';
import {join} from 'node:path';
import { cookies } from 'next/headers';
import { db } from '../../../server/db';
import { currentUser, hashToken, newToken, requireRole, requireVehicle, vehicleScope, publicUser, HttpError, type Actor } from '../../../server/auth';
import { companyDate, transitions, validateResponses } from '../../../server/policy';
export const runtime='nodejs';
export const dynamic='force-dynamic';
const string=z.string().trim().min(1).max(500);
const password=z.string().min(12).max(72);
const audit=(tx:Prisma.TransactionClient,u:Actor,actionType:string,affectedTable:string,affectedRecord:string,newValue?:Prisma.InputJsonValue)=>tx.auditLog.create({data:{actorUserId:u.id,actorEmpId:u.employeeId,actionType,affectedTable,affectedRecord,newValue}});
const transaction=<T,>(fn:(tx:Prisma.TransactionClient)=>Promise<T>)=>db.$transaction(fn,{isolationLevel:Prisma.TransactionIsolationLevel.Serializable});
async function handle(req:NextRequest, context:{params:Promise<{path:string[]}>}) {
 try {
 const path=(await context.params).path.join('/'); const method=req.method;
 if(method!=='GET') {
  const origin=req.headers.get('origin');
  if(origin!==req.nextUrl.origin) throw new HttpError(403,'Invalid request origin');
  if(Number(req.headers.get('content-length')||0)>6_000_000) throw new HttpError(413,'Request too large');
 }
 if(path==='auth/login' && method==='POST') {
  const input=z.object({employeeId:string,password:z.string().min(1).max(72)}).parse(await req.json());
  const user=await db.user.findUnique({where:{employeeId:input.employeeId}});
  const dummy='$2a$12$R9h/cIPz0gi.URNNX3kh2OPST9/PgBkqquzi.Ss7KIUgO2t0jWMUW';
  const valid=await bcrypt.compare(input.password,user?.passwordHash||dummy);
  if(!user || !valid || user.status!=='ACTIVE' || user.deletedAt || (user.lockedUntil && user.lockedUntil>new Date())) {
   if(user) await db.user.update({where:{id:user.id},data:{failedLoginAttempts:{increment:1},...((user.failedLoginAttempts+1)>=5?{lockedUntil:new Date(Date.now()+15*60_000)}:{})}});
   throw new HttpError(401,'Invalid credentials or account temporarily locked');
  }
  const token=newToken();
  await db.$transaction([db.user.update({where:{id:user.id},data:{failedLoginAttempts:0,lockedUntil:null,lastLoginAt:new Date()}}),db.session.create({data:{userId:user.id,tokenHash:hashToken(token),expiresAt:new Date(Date.now()+8*3600_000)}})]);
  (await cookies()).set('svifms_session',token,{httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'strict',path:'/',maxAge:8*3600});
  return NextResponse.json({ok:true});
 }
 if(path==='health' && method==='GET') {
  try {await db.$queryRaw`SELECT 1`;return NextResponse.json({status:'ok'},{headers:{'Cache-Control':'no-store'}});}
  catch {return NextResponse.json({status:'unavailable'},{status:503,headers:{'Cache-Control':'no-store'}});}
 }
 const u=await currentUser();
 if(path==='auth/me') return NextResponse.json(publicUser(u));
 if(path==='auth/logout' && method==='POST') {
  const jar=await cookies();const token=jar.get('svifms_session')?.value;
  if(token) await db.session.deleteMany({where:{tokenHash:hashToken(token)}});jar.delete('svifms_session');return NextResponse.json({ok:true});
 }
 if(path==='auth/password' && method==='POST') {
  const input=z.object({currentPassword:z.string().max(72),newPassword:password}).parse(await req.json());
  if(!await bcrypt.compare(input.currentPassword,u.passwordHash)) throw new HttpError(400,'Current password is incorrect');
  const passwordHash=await bcrypt.hash(input.newPassword,12);
  await transaction(async tx=>{await tx.user.update({where:{id:u.id},data:{passwordHash,mustChangePassword:false}});await tx.session.deleteMany({where:{userId:u.id}});await audit(tx,u,'PASSWORD_CHANGE','User',u.id);});
  (await cookies()).delete('svifms_session');return NextResponse.json({ok:true});
 }
 if(u.mustChangePassword) throw new HttpError(403,'Change your password before continuing');
 if(path==='departments' && method==='GET') {requireRole(u,['ADMIN']);return NextResponse.json(await db.department.findMany());}
 if(path==='vehicles' && method==='GET') return NextResponse.json(await db.vehicle.findMany({where:{archivedAt:null,...vehicleScope(u)},orderBy:{vehicleCode:'asc'}}));
 if(path==='vehicles' && method==='POST') {
  requireRole(u,['ADMIN']);const input=z.object({vehicleCode:string,registrationNumber:string,plateNumber:string,vehicleCategory:string,manufacturer:string,model:string,manufacturingYear:z.number().int().min(1950).max(2100),departmentId:string,currentOdometerKm:z.number().int().nonnegative(),registrationExpiryDate:z.coerce.date(),insuranceExpiryDate:z.coerce.date()}).parse(await req.json());
  const result=await transaction(async tx=>{const v=await tx.vehicle.create({data:{...input,qrToken:newToken()}});await audit(tx,u,'VEHICLE_CREATE','Vehicle',v.id);return v;});return NextResponse.json(result,{status:201});
 }
 if(path==='users' && method==='GET') {requireRole(u,['ADMIN']);return NextResponse.json(await db.user.findMany({where:{deletedAt:null},select:{id:true,employeeId:true,fullName:true,status:true,departmentId:true,userRoles:{select:{role:{select:{code:true}}}}}}));}
 if(path==='users' && method==='POST') {
  requireRole(u,['ADMIN']); const input=z.object({employeeId:string,fullName:string,password,departmentId:string,role:z.enum(['ADMIN','SUPERVISOR','DRIVER'])}).parse(await req.json());
  const hash=await bcrypt.hash(input.password,12);
  const result=await transaction(async tx=>{const role=await tx.role.findUniqueOrThrow({where:{code:input.role}});const user=await tx.user.create({data:{employeeId:input.employeeId,fullName:input.fullName,passwordHash:hash,departmentId:input.departmentId,userRoles:{create:{roleId:role.id,assignedBy:u.id}}},select:{id:true,employeeId:true}});await audit(tx,u,'USER_CREATE','User',user.id,{role:input.role});return user;});return NextResponse.json(result,{status:201});
 }
 if(path==='assignments' && method==='POST') {
  requireRole(u,['ADMIN']); const input=z.object({vehicleId:string,userId:string,date:z.string().date(),kind:z.enum(['DRIVER','SUPERVISOR']),reason:z.string().min(3).max(500)}).parse(await req.json());
  const target=await db.user.findFirst({where:{id:input.userId,status:'ACTIVE',deletedAt:null,userRoles:{some:{role:{code:input.kind}}}}});if(!target) throw new HttpError(400,'User does not have the required active role');
  const result=await transaction(async tx=>{let a;if(input.kind==='DRIVER') {const date=new Date(input.date+'T00:00:00Z');await tx.vehicleAssignment.updateMany({where:{vehicleId:input.vehicleId,assignmentDate:date,isActive:true},data:{isActive:false,endDate:new Date()}});a=await tx.vehicleAssignment.create({data:{vehicleId:input.vehicleId,driverId:input.userId,assignmentDate:date,startDate:new Date(),assignedById:u.id,changeReason:input.reason}});}else {await tx.supervisorVehicleAssignment.updateMany({where:{vehicleId:input.vehicleId,supervisorId:input.userId,isActive:true},data:{isActive:false,revokedAt:new Date()}});a=await tx.supervisorVehicleAssignment.create({data:{vehicleId:input.vehicleId,supervisorId:input.userId,assignedById:u.id}});}await audit(tx,u,'VEHICLE_ASSIGN','Vehicle',input.vehicleId,{...input});return a;});return NextResponse.json(result,{status:201});
 }
 if(path==='checklist' && method==='GET') return NextResponse.json(await db.checklistVersion.findFirst({where:{isPublished:true,template:{code:'AL_GHALBI_WEEKLY_STD'}},orderBy:{versionNumber:'desc'},include:{items:{where:{isActive:true},orderBy:{sortOrder:'asc'},include:{translations:true}}}}));
 if(path==='qr' && method==='GET') {
  const v=await db.vehicle.findFirst({where:{qrToken:req.nextUrl.searchParams.get('token')||'',...vehicleScope(u),archivedAt:null}});if(!v) throw new HttpError(404,'QR unavailable');return NextResponse.json(v);
 }
 if(path==='inspections' && method==='GET') return NextResponse.json(await db.inspection.findMany({where:{vehicle:vehicleScope(u),...(u.roles.includes('DRIVER')&&!u.roles.includes('ADMIN')&&!u.roles.includes('SUPERVISOR')?{driverId:u.id}:{})},include:{vehicle:true,driver:{select:{fullName:true}},responses:true},orderBy:{submittedAt:'desc'},take:200}));
 if(path==='inspections' && method==='POST') {
  requireRole(u,['DRIVER']); const input=z.object({idempotencyKey:z.string().uuid(),vehicleId:string,checklistVersionId:string,inspectionDate:z.string().date(),startingKm:z.number().int().nonnegative(),closingKm:z.number().int().nonnegative(),driverSignature:z.string().min(2).max(500),ropExpiryDate:z.coerce.date(),generalRemarks:z.string().max(2000).optional(),defectDescription:z.string().max(2000).optional(),actionTaken:z.string().max(2000).optional(),responses:z.array(z.object({checklistItemId:string,response:z.enum(['PASS','FAIL','NA']),remarks:z.string().max(1000).optional()})).max(100)}).parse(await req.json());
  const replay=await db.inspection.findUnique({where:{idempotencyKey:input.idempotencyKey}});if(replay){if(replay.driverId!==u.id || replay.vehicleId!==input.vehicleId)throw new HttpError(409,'Idempotency key conflict');return NextResponse.json(replay);}
  if(input.inspectionDate!==companyDate()) throw new HttpError(409,'Inspection requires an assignment for the current Muscat date; late offline submissions require review');
  if(input.closingKm<input.startingKm) throw new HttpError(400,'Closing odometer must be at least starting odometer');
  const result=await transaction(async tx=>{
   const assignment=await tx.vehicleAssignment.findFirst({where:{vehicleId:input.vehicleId,driverId:u.id,isActive:true,assignmentDate:new Date(input.inspectionDate+'T00:00:00Z')}});if(!assignment)throw new HttpError(403,'No active driver assignment');
   const vehicle=await tx.vehicle.findUniqueOrThrow({where:{id:input.vehicleId}});if(vehicle.archivedAt || vehicle.status!=='ACTIVE')throw new HttpError(409,'Vehicle is unavailable');if(input.startingKm<vehicle.currentOdometerKm)throw new HttpError(409,'Odometer cannot decrease');
   const version=await tx.checklistVersion.findFirst({where:{id:input.checklistVersionId,isPublished:true},include:{items:{where:{isActive:true}}}});if(!version)throw new HttpError(400,'Invalid checklist version');
   try{validateResponses(version.items,input.responses);}catch(e){throw new HttpError(400,(e as Error).message);}
   const unsafe=input.responses.some(r=>r.response==='FAIL'&&version.items.some(i=>i.id===r.checklistItemId&&i.isSafetyCritical));
   const {responses,idempotencyKey,inspectionDate,...data}=input;
   const ins=await tx.inspection.create({data:{...data,idempotencyKey,inspectionDate:new Date(inspectionDate+'T00:00:00Z'),inspectionCode:'INS-'+randomUUID(),driverId:u.id,odometerKm:input.closingKm,dayOfWeek:new Intl.DateTimeFormat('en',{weekday:'long',timeZone:'UTC'}).format(new Date(inspectionDate)),status:unsafe?'FLAGGED_UNSAFE':'SUBMITTED',responses:{create:responses}}});
   for(const r of responses.filter(r=>r.response==='FAIL')) {const item=version.items.find(i=>i.id===r.checklistItemId)!;await tx.faultReport.create({data:{faultCode:'FLT-'+randomUUID(),vehicleId:input.vehicleId,inspectionId:ins.id,reportedById:u.id,checklistItemSn:item.serialNumber,category:item.categoryCode,description:r.remarks||`Checklist item ${item.serialNumber} failed`,severity:item.isSafetyCritical?'CRITICAL':'MEDIUM'}});}
   await tx.vehicle.update({where:{id:input.vehicleId},data:{currentOdometerKm:input.closingKm,...(unsafe?{safetyState:'OUT_OF_SERVICE'}:responses.some(r=>r.response==='FAIL')&&vehicle.safetyState==='SAFE'?{safetyState:'NEEDS_REVIEW'}:{})}});
   if(unsafe){const supervisors=await tx.supervisorVehicleAssignment.findMany({where:{vehicleId:input.vehicleId,isActive:true}});for(const s of supervisors)await tx.notification.create({data:{recipientUserId:s.supervisorId,vehicleId:input.vehicleId,type:'CRITICAL_FAULT',title:'Critical inspection failure',message:vehicle.vehicleCode}});}
   const since=new Date(Date.now()-7*86400_000);
   for(const r of responses.filter(r=>r.response==='FAIL')){const item=version.items.find(i=>i.id===r.checklistItemId)!;if(await tx.faultReport.count({where:{vehicleId:input.vehicleId,category:item.categoryCode,reportedAt:{gte:since}}})>=2){const supervisors=await tx.supervisorVehicleAssignment.findMany({where:{vehicleId:input.vehicleId,isActive:true}});for(const supervisor of supervisors)await tx.notification.create({data:{recipientUserId:supervisor.supervisorId,vehicleId:input.vehicleId,type:'REPEATED_FAILURE',title:'Repeated failure in 7 days',message:`${vehicle.vehicleCode}: item ${item.serialNumber}`}});}}
   await audit(tx,u,'INSPECTION_SUBMIT','Inspection',ins.id,{unsafe});return ins;
  });return NextResponse.json(result,{status:201});
 }
 if(path.startsWith('inspections/') && method==='PATCH') {
  requireRole(u,['ADMIN','SUPERVISOR']);const id=path.split('/')[1];const input=z.object({supervisorSign:z.string().min(2).max(500)}).parse(await req.json());
  const result=await transaction(async tx=>{const inspection=await tx.inspection.findFirst({where:{id,vehicle:vehicleScope(u)}});if(!inspection)throw new HttpError(404,'Inspection unavailable');const updated=await tx.inspection.update({where:{id},data:{supervisorSign:input.supervisorSign}});await audit(tx,u,'INSPECTION_SIGNOFF','Inspection',id,{signature:input.supervisorSign});return updated;});return NextResponse.json(result);
 }
 if(path.startsWith('users/') && method==='PATCH') {
  requireRole(u,['ADMIN']);const id=path.split('/')[1];const input=z.object({status:z.enum(['ACTIVE','INACTIVE','LOCKED']).optional(),temporaryPassword:password.optional()}).refine(v=>v.status||v.temporaryPassword).parse(await req.json());
  if(id===u.id)throw new HttpError(400,'Use password settings for your own account');
  const passwordHash=input.temporaryPassword?await bcrypt.hash(input.temporaryPassword,12):undefined;
  await transaction(async tx=>{await tx.user.update({where:{id},data:{status:input.status,...(passwordHash?{passwordHash,mustChangePassword:true,failedLoginAttempts:0,lockedUntil:null}:{})}});await tx.session.deleteMany({where:{userId:id}});await audit(tx,u,'USER_UPDATE','User',id,{status:input.status||'UNCHANGED',passwordReset:!!passwordHash});});return NextResponse.json({ok:true});
 }
 if(path==='faults' && method==='GET') return NextResponse.json(await db.faultReport.findMany({where:{vehicle:vehicleScope(u)},include:{vehicle:true,maintenanceRecords:true,images:{select:{id:true}}},orderBy:{reportedAt:'desc'},take:200}));
 if(path.startsWith('faults/') && path.split('/').length===2 && method==='PATCH') {
  requireRole(u,['ADMIN','SUPERVISOR']);const id=path.split('/')[1];const input=z.object({status:z.enum(['ACKNOWLEDGED','UNDER_REVIEW','UNDER_MAINTENANCE','RESOLVED','VERIFIED_AND_CLOSED']),notes:z.string().min(3).max(2000)}).parse(await req.json());
  const fault=await db.faultReport.findUnique({where:{id}});if(!fault)throw new HttpError(404,'Fault not found');await requireVehicle(u,fault.vehicleId);
  const result=await transaction(async tx=>{const f=await tx.faultReport.findUniqueOrThrow({where:{id}});if(!transitions[f.status].includes(input.status))throw new HttpError(409,'Invalid fault transition');const updated=await tx.faultReport.update({where:{id},data:{status:input.status,resolutionNotes:input.notes,...(input.status==='RESOLVED'?{resolvedAt:new Date()}:{}),...(input.status==='VERIFIED_AND_CLOSED'?{closedAt:new Date()}: {})}});if(input.status==='VERIFIED_AND_CLOSED' && !await tx.faultReport.count({where:{vehicleId:f.vehicleId,status:{not:'VERIFIED_AND_CLOSED'}}}))await tx.vehicle.update({where:{id:f.vehicleId},data:{safetyState:'SAFE'}});await audit(tx,u,'FAULT_STATUS','FaultReport',id,input);return updated;});return NextResponse.json(result);
 }
 if(path==='maintenance' && method==='POST') {
  requireRole(u,['ADMIN','SUPERVISOR']);const input=z.object({vehicleId:string,faultReportId:string,technicianName:string,workDescription:string,odometerAtService:z.number().int().nonnegative(),costOmr:z.number().nonnegative().max(9999999).optional()}).parse(await req.json());await requireVehicle(u,input.vehicleId);
  const result=await transaction(async tx=>{const fault=await tx.faultReport.findFirst({where:{id:input.faultReportId,vehicleId:input.vehicleId,status:'UNDER_MAINTENANCE'}});if(!fault)throw new HttpError(409,'Fault must be under maintenance for this vehicle');const m=await tx.maintenanceRecord.create({data:{...input,maintenanceCode:'MNT-'+randomUUID(),status:'COMPLETED',completedAt:new Date()}});await audit(tx,u,'MAINTENANCE_CREATE','MaintenanceRecord',m.id);return m;});return NextResponse.json(result,{status:201});
 }
 if(path.startsWith('faults/') && path.endsWith('/photos') && method==='POST') {
  const fault=await db.faultReport.findUnique({where:{id:path.split('/')[1]}});if(!fault)throw new HttpError(404,'Fault not found');await requireVehicle(u,fault.vehicleId);
  if(!u.roles.some(r=>['ADMIN','SUPERVISOR'].includes(r))&&fault.reportedById!==u.id)throw new HttpError(403,'Only the reporter or supervisor may attach evidence');
  const form=await req.formData();const file=form.get('file');if(!(file instanceof File)||file.size>5_000_000||file.size<12)throw new HttpError(400,'Upload a JPG, PNG or WebP file up to 5 MB');
  const bytes=Buffer.from(await file.arrayBuffer());const mime=bytes.subarray(0,3).equals(Buffer.from([255,216,255]))?'image/jpeg':bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))?'image/png':bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WEBP'?'image/webp':null;
  if(!mime)throw new HttpError(400,'Unsupported image format');
  const storageKey=randomUUID();const directory=process.env.UPLOAD_DIR||join(process.cwd(),'uploads');await mkdir(directory,{recursive:true});await writeFile(join(directory,storageKey),bytes,{flag:'wx',mode:0o600});
  try {const result=await transaction(async tx=>{const image=await tx.faultImage.create({data:{faultReportId:fault.id,storageKey,mimeType:mime,fileSizeBytes:bytes.length}});await audit(tx,u,'FAULT_IMAGE_CREATE','FaultImage',image.id);return {id:image.id};});return NextResponse.json(result,{status:201});}catch(error){await unlink(join(directory,storageKey)).catch(()=>{});throw error;}
 }
 if(path.startsWith('photos/') && method==='GET') {
  const image=await db.faultImage.findUnique({where:{id:path.split('/')[1]},include:{faultReport:true}});if(!image)throw new HttpError(404,'Image not found');await requireVehicle(u,image.faultReport.vehicleId);
  if(!/^[a-f0-9-]{36}$/.test(image.storageKey))throw new HttpError(404,'Image unavailable');
  const bytes=await readFile(join(process.env.UPLOAD_DIR||join(process.cwd(),'uploads'),image.storageKey));return new NextResponse(bytes,{headers:{'Content-Type':image.mimeType,'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'}});
 }
 if(path==='notifications' && method==='GET') return NextResponse.json(await db.notification.findMany({where:{recipientUserId:u.id},orderBy:{createdAt:'desc'},take:100}));
 if(path==='audit' && method==='GET') {requireRole(u,['ADMIN']);return NextResponse.json(await db.auditLog.findMany({orderBy:{createdAt:'desc'},take:200}));}
 if(path==='export' && method==='GET') {
  requireRole(u,['ADMIN','SUPERVISOR']);const ExcelJS=await import('exceljs');const workbook=new ExcelJS.Workbook();
  const vehicles=await db.vehicle.findMany({where:vehicleScope(u)});const inspections=await db.inspection.findMany({where:{vehicle:vehicleScope(u)},include:{responses:true},take:10000});const faults=await db.faultReport.findMany({where:{vehicle:vehicleScope(u)},take:10000});
  const ids=vehicles.map(v=>v.id);
  const maintenance=await db.maintenanceRecord.findMany({where:{vehicleId:{in:ids}},take:10000});
  const assignments=await db.vehicleAssignment.findMany({where:{vehicleId:{in:ids}},take:10000});
  const users=await db.user.findMany({where:u.roles.includes('ADMIN')?{deletedAt:null}:{driverAssignments:{some:{vehicleId:{in:ids}}}},select:{employeeId:true,fullName:true,status:true,departmentId:true}});
  const items=await db.checklistItem.findMany({include:{translations:true,version:true}});
  const weekly=inspections.flatMap(i=>i.responses.map(r=>({date:i.inspectionDate.toISOString().slice(0,10),day:i.dayOfWeek,vehicle:vehicles.find(v=>v.id===i.vehicleId)?.vehicleCode,driverId:i.driverId,serialNumber:items.find(item=>item.id===r.checklistItemId)?.serialNumber,response:r.response,remarks:r.remarks,driverSignature:i.driverSignature,supervisorSign:i.supervisorSign,defectDescription:i.defectDescription,actionTaken:i.actionTaken})));
  const logs=await db.auditLog.findMany({where:u.roles.includes('ADMIN')?{}:{actorUserId:u.id},take:10000,orderBy:{createdAt:'desc'}});
  const notifications=await db.notification.findMany({where:{recipientUserId:u.id},take:10000});
  const sheets:[string,Record<string,unknown>[]][]=[['Vehicles',vehicles],['Inspections',inspections.map(({responses,...r})=>r)],['Responses',inspections.flatMap(i=>i.responses)],['Faults',faults],['Maintenance',maintenance],['Assignments',assignments],['Employees',users],['Weekly checklist',weekly],['Audit',logs],['Notifications',notifications]];
  for(const [name,rows] of sheets){const sheet=workbook.addWorksheet(name);if(rows.length){sheet.columns=Object.keys(rows[0]).map(key=>({header:key,key,width:22}));for(const row of rows)sheet.addRow(Object.fromEntries(Object.entries(row).map(([key,value])=>[key,value!==null&&typeof value==='object'&&!(value instanceof Date)?String(value):value])));sheet.views=[{state:'frozen',ySplit:1}];}}
  await audit(db,u,'EXCEL_EXPORT','Vehicle','scoped');const buffer=await workbook.xlsx.writeBuffer();return new NextResponse(new Uint8Array(buffer),{headers:{'Content-Type':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','Content-Disposition':'attachment; filename="svifms.xlsx"','Cache-Control':'no-store'}});
 }
 throw new HttpError(404,'Endpoint not found');
 }catch(error){if(error instanceof HttpError)return NextResponse.json({error:error.message},{status:error.status});if(error instanceof z.ZodError)return NextResponse.json({error:error.issues.map(i=>i.path.join('.')+': '+i.message).join('; ')},{status:400});if(error instanceof Prisma.PrismaClientKnownRequestError && ['P2002','P2034'].includes(error.code))return NextResponse.json({error:'Conflicting record or concurrent change. Refresh and retry.'},{status:409});console.error(error);return NextResponse.json({error:'Server error'},{status:500});}
}
export {handle as GET,handle as POST,handle as PATCH};
