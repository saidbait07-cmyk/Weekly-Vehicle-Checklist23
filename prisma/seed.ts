import {PrismaClient} from '@prisma/client';
import bcrypt from 'bcryptjs';
import {randomBytes} from 'node:crypto';
import {checklist} from './checklist';
const db=new PrismaClient();
async function main(){
 const password=process.env.SEED_ADMIN_PASSWORD;
 if(!password || password.length<12 || Buffer.byteLength(password)>72)throw new Error('Set SEED_ADMIN_PASSWORD to 12–72 bytes; never use a production password for demonstrations');
 const department=await db.department.upsert({where:{code:'FLEET'},update:{},create:{code:'FLEET',nameEn:'Fleet',nameAr:'النقل',nameHi:'Fleet',nameUr:'Fleet'}});
 for(const code of ['ADMIN','SUPERVISOR','DRIVER'])await db.role.upsert({where:{code},update:{},create:{code,nameEn:code,nameAr:code,nameHi:code,nameUr:code}});
 const role=await db.role.findUniqueOrThrow({where:{code:'ADMIN'}});
 await db.user.upsert({where:{employeeId:process.env.SEED_ADMIN_ID||'ADMIN001'},update:{},create:{employeeId:process.env.SEED_ADMIN_ID||'ADMIN001',fullName:'System Administrator',passwordHash:await bcrypt.hash(password,12),departmentId:department.id,userRoles:{create:{roleId:role.id,assignedBy:'bootstrap'}}}});
 const template=await db.checklistTemplate.upsert({where:{code:'AL_GHALBI_WEEKLY_STD'},update:{},create:{code:'AL_GHALBI_WEEKLY_STD',titleEn:'Weekly vehicle checklist',titleAr:'قائمة الفحص الأسبوعي للمركبة',titleHi:'Weekly vehicle checklist',titleUr:'Weekly vehicle checklist'}});
 const existing=await db.checklistVersion.findUnique({where:{templateId_versionNumber:{templateId:template.id,versionNumber:1}}});
 if(!existing) await db.checklistVersion.create({data:{templateId:template.id,versionNumber:1,isPublished:true,publishedAt:new Date(),items:{create:checklist.map(([en,ar],i)=>({serialNumber:i+1,sortOrder:i+1,categoryCode:'ITEM_'+(i+1),allowedResponses:['PASS','FAIL','NA'],isSafetyCritical:[1,2,3,6,10,11,15,17,19].includes(i+1),translations:{create:[{languageCode:'en',label:en},{languageCode:'ar',label:ar}]}}))}}});
 if(process.env.SEED_DEMO==='true')await db.vehicle.upsert({where:{vehicleCode:'V001'},update:{},create:{vehicleCode:'V001',registrationNumber:'DEMO-001',plateNumber:'DEMO-001',vehicleCategory:'Light',manufacturer:'Toyota',model:'Hilux',manufacturingYear:2024,departmentId:department.id,registrationExpiryDate:new Date('2028-01-01'),insuranceExpiryDate:new Date('2028-01-01'),qrToken:randomBytes(32).toString('hex')}});
 console.log('Seed complete. Existing accounts and passwords were preserved.');
}
main().catch(e=>{console.error(e);process.exitCode=1}).finally(()=>db.$disconnect());
