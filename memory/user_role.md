---
name: User role
description: User is building Pargig — a gig-economy platform (Job giver / Job taker marketplace) with Flutter app, Node.js backend, React admin panel
type: user
---

User is the developer/owner of "Pargig" — a gig-economy marketplace similar to TaskRabbit/Urban Company. Email: akash@marioxsoftware.com (Mariox Software).

Stack chosen:
- Backend: Node.js (Express 5) + MongoDB (mongoose) at e:\node\pargig\backend (port 5014)
- Admin web panel: React (Vite) at e:\node\pargig\frontend
- Mobile: Flutter for Android + iOS (Flutter installed at E:\flutter)

Domain has 10 modules: User Profile, Job Posting (giver), Job Discovery (taker), Chat & Negotiation, Job Management (OTP-based start/complete), Payment (with hold/release/refund), Ratings & Reviews, Notifications, Disputes, Admin Panel.

Business rules to remember:
- Mobile + OTP login
- Two roles, switchable: Job Giver, Job Taker
- Professional document verification by admin
- Job taker first job under Rs 1000 free, jobs 1–3 require Rs 20 wallet deposit
- OTP-based job start: taker arrives → "Reached" → OTP sent to giver → taker enters → job starts
- Payment held in escrow, released after completion OTP
- Platform fee: free for first 3 jobs after launch, then ₹10 or 5% (whichever higher) per transaction
