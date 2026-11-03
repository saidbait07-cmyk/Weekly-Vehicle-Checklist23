import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {loadEnvFile} from 'node:process';
import {randomUUID} from 'node:crypto';
import {PrismaClient} from '@prisma/client';
import bcrypt from 'bcryptjs';
import {companyDate} from '../src/server/policy';
try{loadEnvFile('.env')}catch{}
const db=new PrismaClient();const port=3217;const origin=`http://localhost:${port}`;
const server=spawn('node',['node_modules/next/dist/bin/next','start','-p',String(port)],{env:{...process.env,NODE_ENV:'test'},stdio:['ignore','pipe','pipe']});
let logs='';server.stdout.on('data',d=>logs+=d);server.stderr.on('data',d=>logs+=d);
class Client {
 cookie='';
 async call(path:string,method='GET',body?:unknown,expected=200,extra:Record<string,string>={}){
 const r=await fetch(origin+'/api/'+path,{method,headers:{Origin:origin,Cookie:this.cookie,...(body?{'Content-Type':'application/json'}:{}),...extra},body:body?JSON.stringify(body):undefined});
 const set=r.headers.get('set-cookie');if(set)this.cookie=set.split(';')[0];
 let value:any;if(r.headers.get('content-type')?.includes('json'))value=await r.json();else value=await r.arrayBuffer();
 assert.equal(r.status,expected,`${method} ${path}: ${JSON.stringify(value)}`);return value;
 }
}
async function main(){
 for(let i=0;i<100;i++){try{await fetch(origin);break}catch{if(i===99)throw new Error(logs);await new Promise(r=>setTimeout(r,200));}}
 assert.equal((await new Client().call('health')).status,'ok');
 const suffix=randomUUID().slice(0,8);const dept=await db.department.findUniqueOrThrow({where:{code:'FLEET'}});const password='integration-test-password';
 async function account(role:string){const r=await db.role.findUniqueOrThrow({where:{code:role}});return db.user.create({data:{employeeId:role+'-'+randomUUID().slice(0,12),fullName:role+' Test',departmentId:dept.id,passwordHash:await bcrypt.hash(password,4),mustChangePassword:false,userRoles:{create:{roleId:r.id,assignedBy:'integration-test'}}}})}
 const [admin,driver,outsider,supervisor]=await Promise.all([account('ADMIN'),account('DRIVER'),account('DRIVER'),account('SUPERVISOR')]);
 const a=new Client(),d=new Client(),s=new Client(),o=new Client();
 await new Client().call('vehicles','GET',undefined,401);
 for(const [c,u] of [[a,admin],[d,driver],[s,supervisor],[o,outsider]] as const)await c.call('auth/login','POST',{employeeId:u.employeeId,password});
 await a.call('vehicles','POST',{},403,{Origin:'https://evil.example'});
 await d.call('users','GET',undefined,403);
 const vehicle=await a.call('vehicles','POST',{vehicleCode:'TEST-'+suffix,registrationNumber:'REG-'+suffix,plateNumber:'PLT-'+suffix,vehicleCategory:'Light',manufacturer:'Toyota',model:'Hilux',manufacturingYear:2024,departmentId:dept.id,currentOdometerKm:100,registrationExpiryDate:'2028-01-01',insuranceExpiryDate:'2028-01-01'},201);
 assert.equal((await d.call('vehicles')).length,0);
 const date=companyDate();
 for(const [kind,userId] of [['DRIVER',driver.id],['SUPERVISOR',supervisor.id]])await a.call('assignments','POST',{vehicleId:vehicle.id,userId,kind,date,reason:'Integration assignment'},201);
 // Multiple previous assignments must coexist; only active assignment is unique.
 for(let i=0;i<2;i++)await a.call('assignments','POST',{vehicleId:vehicle.id,userId:driver.id,kind:'DRIVER',date,reason:'Reassignment test'},201);
 assert.equal((await d.call('vehicles')).length,1);assert.equal((await s.call('vehicles')).length,1);assert.equal((await o.call('vehicles')).length,0);
 assert.equal((await d.call('qr?token='+vehicle.qrToken)).id,vehicle.id);
 await o.call('qr?token='+vehicle.qrToken,'GET',undefined,404);
 const version=await d.call('checklist');assert.equal(version.items.length,27);
 const base={idempotencyKey:randomUUID(),vehicleId:vehicle.id,checklistVersionId:version.id,inspectionDate:date,startingKm:100,closingKm:110,driverSignature:'Driver Test',ropExpiryDate:'2028-01-01',responses:version.items.map((item:any)=>({checklistItemId:item.id,response:item.serialNumber===17?'FAIL':'PASS',remarks:item.serialNumber===17?'Brake issue':''}))};
 await o.call('inspections','POST',{...base,idempotencyKey:randomUUID()},403);
 await d.call('inspections','POST',{...base,responses:base.responses.slice(1)},400);
 assert.equal(await db.inspection.count({where:{vehicleId:vehicle.id}}),0);
 const inspection=await d.call('inspections','POST',base,201);assert.equal(inspection.status,'FLAGGED_UNSAFE');
 assert.equal((await d.call('inspections','POST',base)).id,inspection.id);
 await d.call('inspections','POST',{...base,idempotencyKey:randomUUID()},409);
 const faults=await s.call('faults');const fault=faults.find((f:any)=>f.inspectionId===inspection.id);assert(fault);assert.equal((await o.call('faults')).length,0);
 await d.call('faults/'+fault.id,'PATCH',{status:'ACKNOWLEDGED',notes:'Unauthorized'},403);
 await s.call('faults/'+fault.id,'PATCH',{status:'VERIFIED_AND_CLOSED',notes:'Skip stages'},409);
 for(const status of ['ACKNOWLEDGED','UNDER_MAINTENANCE'])await s.call('faults/'+fault.id,'PATCH',{status,notes:'Reviewed by test supervisor'});
 await s.call('maintenance','POST',{vehicleId:vehicle.id,faultReportId:fault.id,technicianName:'Test Technician',workDescription:'Replace brake pads',odometerAtService:110,costOmr:25},201);
 for(const status of ['RESOLVED','VERIFIED_AND_CLOSED'])await s.call('faults/'+fault.id,'PATCH',{status,notes:'Repair verified'});
 assert.equal((await db.vehicle.findUniqueOrThrow({where:{id:vehicle.id}})).safetyState,'SAFE');
 await s.call('inspections/'+inspection.id,'PATCH',{supervisorSign:'Supervisor Test'});
 const upload=new FormData();upload.set('file',new File([Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64')],'test.png',{type:'image/png'}));
 const uploaded=await fetch(origin+'/api/faults/'+fault.id+'/photos',{method:'POST',headers:{Origin:origin,Cookie:s.cookie},body:upload});assert.equal(uploaded.status,201);const photo=await uploaded.json();
 await s.call('photos/'+photo.id);await o.call('photos/'+photo.id,'GET',undefined,404);
 const invalid=new FormData();invalid.set('file',new File(['not a real image file'],'fake.png',{type:'image/png'}));
 assert.equal((await fetch(origin+'/api/faults/'+fault.id+'/photos',{method:'POST',headers:{Origin:origin,Cookie:s.cookie},body:invalid})).status,400);
 const bytes=await s.call('export');assert(bytes.byteLength>1000);
 const {default:ExcelJS}=await import('exceljs');const book=new ExcelJS.Workbook();await book.xlsx.load(bytes);assert.equal(book.worksheets.length,10);
 if(process.env.BROWSER_EXECUTABLE){
  const {chromium}=await import('@playwright/test');const browser=await chromium.launch({executablePath:process.env.BROWSER_EXECUTABLE,headless:true,args:['--no-sandbox']});
  try {const page=await browser.newPage({viewport:{width:390,height:844}});const pageErrors:string[]=[];page.on('pageerror',e=>pageErrors.push(e.message));await page.goto(origin);await page.locator('input[name="employeeId"]').fill(admin.employeeId);await page.locator('input[name="password"]').fill(password);await page.getByRole('button',{name:'دخول / Sign in',exact:true}).click();await page.getByRole('heading',{name:'مرحباً، ADMIN Test'}).waitFor();await page.getByRole('button',{name:'المركبات',exact:true}).click();await page.getByRole('heading',{name:'المركبات ضمن صلاحياتك'}).waitFor();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth),false,'mobile horizontal overflow');await page.screenshot({path:'/tmp/svifms-mobile.png',fullPage:true});assert.deepEqual(pageErrors,[]);
   const offlineVehicle=await a.call('vehicles','POST',{vehicleCode:'OFF-'+suffix,registrationNumber:'OFF-'+suffix,plateNumber:'OFF-'+suffix,vehicleCategory:'Light',manufacturer:'Toyota',model:'Hilux',manufacturingYear:2024,departmentId:dept.id,currentOdometerKm:0,registrationExpiryDate:'2028-01-01',insuranceExpiryDate:'2028-01-01'},201);
   await a.call('assignments','POST',{vehicleId:offlineVehicle.id,userId:driver.id,kind:'DRIVER',date,reason:'Offline inspection test'},201);
   const context=await browser.newContext({viewport:{width:390,height:844}});const driverPage=await context.newPage();await driverPage.goto(origin);await driverPage.locator('input[name="employeeId"]').fill(driver.employeeId);await driverPage.locator('input[name="password"]').fill(password);await driverPage.getByRole('button',{name:'دخول / Sign in',exact:true}).click();await driverPage.getByRole('heading',{name:'مرحباً، DRIVER Test'}).waitFor();await driverPage.getByRole('button',{name:'فحص جديد',exact:true}).click();await driverPage.locator('form select').first().selectOption(offlineVehicle.id);
   const selects=driverPage.locator('.check select');assert.equal(await selects.count(),27);for(let i=0;i<27;i++)await selects.nth(i).selectOption('PASS');await driverPage.locator('[name="closingKm"]').fill('5');await driverPage.locator('[name="driverSignature"]').fill('Driver Test');await driverPage.locator('[name="ropExpiryDate"]').fill('2028-01-01');
   await context.setOffline(true);await driverPage.getByRole('button',{name:'إرسال الفحص',exact:true}).click();await driverPage.getByRole('button',{name:'مزامنة الفحوصات',exact:true}).waitFor();assert.equal(await db.inspection.count({where:{vehicleId:offlineVehicle.id}}),0);
   await context.setOffline(false);await driverPage.getByRole('button',{name:'مزامنة الفحوصات',exact:true}).click();await driverPage.getByRole('status').filter({hasText:'اكتملت المزامنة'}).waitFor();assert.equal(await db.inspection.count({where:{vehicleId:offlineVehicle.id}}),1);await context.close();

  }finally{await browser.close()}
 }

 const audit=await db.auditLog.findFirstOrThrow({where:{affectedRecord:inspection.id}});
 await assert.rejects(db.auditLog.update({where:{id:audit.id},data:{result:'TAMPER'}}),/append-only/);
 await assert.rejects(db.auditLog.delete({where:{id:audit.id}}),/append-only/);
 await assert.rejects(db.$executeRawUnsafe('TRUNCATE TABLE "AuditLog"'),/append-only/);
 await assert.rejects(db.vehicleAssignment.create({data:{vehicleId:vehicle.id,driverId:outsider.id,assignmentDate:new Date(date+'T00:00:00Z'),startDate:new Date(),assignedById:admin.id}}));
 await a.call('users/'+driver.id,'PATCH',{status:'INACTIVE'});await d.call('vehicles','GET',undefined,401);
 const locked=await account('DRIVER');for(let i=0;i<5;i++)await new Client().call('auth/login','POST',{employeeId:locked.employeeId,password:'wrong'},401);await new Client().call('auth/login','POST',{employeeId:locked.employeeId,password},401);
 await a.call('auth/logout','POST',{});await a.call('vehicles','GET',undefined,401);
 console.log('Integration passed: login, lockout, CSRF, role/vehicle isolation, reassignment, 27 checks, atomic rollback, idempotency, faults, maintenance, signoff, protected photos, 10-sheet Excel, audit immutability, database uniqueness, session revocation.');
}
main().catch(e=>{console.error(e);console.error(logs.slice(-3000));process.exitCode=1}).finally(async()=>{server.kill('SIGTERM');await db.$disconnect()});
