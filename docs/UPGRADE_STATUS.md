# FleetGuard upgrade — interrupted work status

This draft currently preserves the guarded additive Supabase installer only. It is not the completed application release and must not be deployed as one.

The existing application's last full source revision, 9570fc914b37bd3e9d3170b2ae673b5bb1d06fcb, was restored and incrementally upgraded in /workspace/fleetguard. The current main branch had removed those files. Main has not been changed by this draft.

Implemented in the working copy: Supabase server-side authentication, English/Arabic interface, role-specific employee/vehicle/inspection/review workflows, private photo evidence, RLS, scoped transactional RPCs, immutable answers and reviews, real statistics, Excel weekly records, printable PDF, local drafts, setup scripts and deployment documentation.

Verified locally before the execution environment became unavailable: production build; six unit/translation/checklist tests; actual Supabase Auth, PostgreSQL/PostgREST and Storage integration; employee-ID login; real invitation email and activation; password selection; language persistence; employee editing; role/vehicle isolation and attempted escalation; inspection persistence and idempotency; private evidence; approval/rejection history; account deactivation; logout/session checks; database immutability. The final guarded installer was also checked in a fresh database (zero seeded employees, 27 checks, RLS on every new model table, no privileged implementation in public) and rejects an existing conflicting model.

Still pending: uploading the rest of the working copy, final mobile/offline/PDF smoke tests on the latest revision, running GitHub CI, owner configuration of SMTP/redirects/signup restrictions and hosting secrets, linking or provisioning the explicitly intended administrator, and verifying the actual hosted release. No production-ready claim is made.

The connected Supabase project is sojdtprszwucmudhmdid. It already has a separate lowercase model and a real employee profile; these must be preserved. The installer creates only the inherited case-sensitive model and refuses collisions. It does not automatically import, reset or invite existing employees.

No cloud migration has been applied in this flow. Automatic approval review rejected the first combined upgrade because it contained column/data removal and privilege changes with too broad a potential blast radius. The replacement additive installer removes those data-removal operations and was locally verified; its native confirmation expired before application. Review and explicit approval are still required before trying that cloud installation again.

Resume from the existing working copy when the managed execution environment is available. Do not rebuild from scratch or overwrite the existing company branding. Never upload .env files, .fleetguard-test/, node_modules, generated test credentials or company records.
