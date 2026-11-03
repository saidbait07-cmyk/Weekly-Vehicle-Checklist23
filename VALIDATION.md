# Validation record

Validated against an isolated PostgreSQL 16 database and Node.js 24.19.0.

- Prisma schema validation passed.
- The full SQL migration applied successfully to an empty PostgreSQL database.
- Seed completed and preserves existing account passwords on repeat execution.
- TypeScript `npm run typecheck` passed.
- All four policy tests passed.
- Production `npm run build` passed (Next.js 15.5.29).
- HTTP/database integration passed: session login/logout, account lockout, Origin enforcement, role isolation, vehicle scoping, QR access checks, multiple historical assignments, complete checklist validation, rollback on invalid input, idempotent replay, duplicate daily inspection rejection, automatic faults, legal workflow transitions, maintenance, supervisor signoff, protected photos, invalid-image rejection, ten-sheet XLSX, session revocation, assignment uniqueness and audit update/delete/truncate prevention.
- Chromium mobile smoke test at 390×844 passed with no page errors or horizontal overflow.
- Chromium offline flow passed: a full 27-item inspection was queued without network access, was absent from PostgreSQL while offline, and was saved exactly once after explicit synchronization.

Run the optional browser check on a machine with Chromium installed:

```bash
BROWSER_EXECUTABLE=/usr/bin/chromium npm run test:integration
```

Integration tests create persistent test records. Use a dedicated database. External hosting, Supabase/Neon connectivity, production HTTPS configuration, cloud storage, disaster recovery and background synchronization were not tested or provisioned. See README for scope limitations.
