export function companyDate(now = new Date()) {
 return new Intl.DateTimeFormat('en-CA', {timeZone:'Asia/Muscat', year:'numeric', month:'2-digit', day:'2-digit'}).format(now);
}
export const transitions: Record<string, string[]> = {
 REPORTED:['ACKNOWLEDGED'], ACKNOWLEDGED:['UNDER_REVIEW','UNDER_MAINTENANCE'],
 UNDER_REVIEW:['UNDER_MAINTENANCE','RESOLVED'], UNDER_MAINTENANCE:['RESOLVED'],
 RESOLVED:['VERIFIED_AND_CLOSED'], VERIFIED_AND_CLOSED:[]
};
export function validateResponses(items: {id:string; isRequired:boolean; allowedResponses:string[]}[], responses:{checklistItemId:string; response:string}[]) {
 const ids = new Set(responses.map(r=>r.checklistItemId));
 if(ids.size !== responses.length) throw new Error('Duplicate checklist responses');
 if(responses.some(r=>!items.some(i=>i.id===r.checklistItemId && i.allowedResponses.includes(r.response)))) throw new Error('Invalid checklist response');
 if(items.some(i=>i.isRequired && !ids.has(i.id))) throw new Error('Complete all required checklist items');
}
