# Nestora PG Management

A mobile-first Flutter platform for PG owners, administrators, and tenants. It ships in a zero-setup local mode backed by Hive, with realistic seeded data and working CRUD/status workflows.

## Included

- Role-based sign-in and sign-up for Owner, Tenant, and Admin
- PG listings, amenities, property photos entry point, rooms, floors, and bed occupancy
- Tenant onboarding, KYC capture, and rental agreement/e-sign flow
- Rent dues, a working demo checkout that marks rent paid, receipts, and owner-side payment recording
- Maintenance requests with priorities, technician assignment, and status timeline
- Visitor pre-approvals with approve/decline, check-in, and check-out
- Announcements and push-notification preference
- Tenant attendance with live check-in/check-out and history
- Electricity meter readings and per-bed split billing derived from room occupancy
- Notification centre fed by real in-app actions, tenant search, and a role-aware analytics dashboard
- Adaptive Material 3 UI with bottom navigation on phones and a navigation rail on larger screens

## Run locally

Flutter 3.35+ and Dart 3.3+ are recommended.

```bash
flutter pub get
flutter create --platforms=android,ios,web .
flutter run
```

`flutter create` adds the native runner projects when cloning this source-only workspace; it preserves the existing `lib/`, `web/`, and package configuration. Select any role on the sign-in screen and use the prefilled demo credentials. Data is stored in the local Hive box `nestora_local` and survives app restarts.

## Firebase production upgrade

The included build deliberately defaults to local mode so it starts without cloud credentials. For a Firebase deployment:

1. Add `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, and `firebase_messaging`.
2. Run `flutterfire configure` and place the generated platform configuration files in their normal Android/iOS locations.
3. Move each list in `AppState` behind repository interfaces and implement Firestore-backed repositories with per-property document paths.
4. Use Firebase Auth custom claims (`owner`, `tenant`, `admin`) for server-enforced RBAC; never rely only on hidden UI.
5. Store property/KYC images in Cloud Storage and keep only their URLs in Firestore.
6. Keep service-account credentials on a trusted server or Cloud Functions only—never bundle an Admin SDK key in the Flutter app.

The local entities and IDs are already shaped to map cleanly to Firestore collections.

## Safety notes

The payment screen is a Razorpay-style demo UI; connect the official SDK and verify signatures on a server before accepting real money. Document upload and e-sign buttons model their complete user flows but require your chosen storage and e-sign providers for legally binding production use.
