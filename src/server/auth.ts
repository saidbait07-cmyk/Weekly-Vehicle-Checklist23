import { createHash, randomBytes } from 'node:crypto';
import { cookies } from 'next/headers';
import { db } from './db';
import { companyDate } from './policy';
export class HttpError extends Error { constructor(public status:number, message:string) { super(message); } }
export const hashToken = (token:string) => createHash('sha256').update(token).digest('hex');
export const newToken = () => randomBytes(32).toString('hex');
export async function currentUser() {
 const token = (await cookies()).get('svifms_session')?.value;
 if(!token) throw new HttpError(401,'Sign in required');
 const session = await db.session.findUnique({where:{tokenHash:hashToken(token)},include:{user:{include:{userRoles:{include:{role:true}}}}}});
 if(!session || session.expiresAt < new Date() || session.user.status !== 'ACTIVE' || session.user.deletedAt) throw new HttpError(401,'Session expired');
 return {...session.user, roles:session.user.userRoles.map(r=>r.role.code)};
}
export type Actor = Awaited<ReturnType<typeof currentUser>>;
export function requireRole(user:Actor, roles:string[]) { if(!user.roles.some(r=>roles.includes(r))) throw new HttpError(403,'Permission denied'); }
export function vehicleScope(user:Actor) {
 if(user.roles.includes('ADMIN')) return {};
 if(user.roles.includes('SUPERVISOR')) return {supervisorAssignments:{some:{supervisorId:user.id,isActive:true}}};
 return {driverAssignments:{some:{driverId:user.id,isActive:true,assignmentDate:new Date(companyDate()+'T00:00:00Z')}}};
}
export async function requireVehicle(user:Actor,id:string) {
 const vehicle=await db.vehicle.findFirst({where:{id,archivedAt:null,...vehicleScope(user)}});
 if(!vehicle) throw new HttpError(404,'Vehicle unavailable or outside your scope');
 return vehicle;
}
export function publicUser(user:Actor) { return {id:user.id,employeeId:user.employeeId,fullName:user.fullName,roles:user.roles,mustChangePassword:user.mustChangePassword,departmentId:user.departmentId}; }
