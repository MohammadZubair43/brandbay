# BrandBay

**Live site: [brandbay.vercel.app](https://brandbay.vercel.app)**

BrandBay is one platform for a brand's whole marketing. A business (a restaurant, gym, salon or shop) posts what it needs. Social media managers create the content, influencers are booked to shoot at the business, and the BrandBay team keeps everything on track. All of it happens in one portal, with one login per person.

> "BrandBay" is a working name. The final name (for example Collavya) and domain are still being decided. The name is set in one place in the build, so renaming the site takes a few minutes.

---

## Contents

1. [Who uses it](#who-uses-it)
2. [Features by role](#features-by-role)
3. [How a campaign works](#how-a-campaign-works)
4. [How an influencer shoot works](#how-an-influencer-shoot-works)
5. [How it's built](#how-its-built)
6. [What's in this repo](#whats-in-this-repo)
7. [Database updates](#database-updates)
8. [Security: who can see what](#security-who-can-see-what)
9. [Testing guide](#testing-guide)
10. [Updating the site](#updating-the-site)
11. [Setting up from scratch](#setting-up-from-scratch)
12. [Not built yet and roadmap](#not-built-yet-and-roadmap)
13. [Decisions waiting](#decisions-waiting)

---

## Who uses it

| Role | Who they are | How they log in |
|---|---|---|
| **Business** | A restaurant, gym, shop or any brand that wants marketing done | Register on the main site |
| **Social Media Manager** | Freelancers who create content and run campaigns | Register on the main site, then the team verifies them |
| **Influencer** | Creators who get booked to shoot at a business | Register on the main site, then the team verifies them |
| **BrandBay Team** | Employees who run the platform | **Team login** link at the bottom of the site. Nobody can register as an employee; an admin upgrades the account (see [Setting up from scratch](#setting-up-from-scratch)). |

Everyone uses the same portal and the same data, but each role sees its own dashboard and only the information it's allowed to see.

---

## Features by role

### Business
- **Overview:** active campaigns, posts waiting for approval, amount due, upcoming posts
- **Social accounts:** add Instagram, Facebook, YouTube, LinkedIn, X and Google Business with follower counts (entered by hand until the platform connection is built)
- **Post planner:** write and schedule its own posts; each platform shows only its own post types (for example YouTube: Video, Short)
- **New request:** choose its industry, pick one of that industry's packages or **Custom**, set goal, audience, platforms, services, budget (minimum $100) and target date
- **My campaigns:** progress of every campaign through Submitted → Research → Content → Live
- **Approvals:** approve the manager's drafts, or ask for changes with feedback
- **Influencers:** find influencers by category and city, book a shoot (date, time, address, fee, brief), review the uploaded video, then approve it or ask for changes
- **Content calendar:** manager posts, its own posts and influencer shoots on one calendar
- **Messages:** one chat per campaign with the manager and the team; attach files up to **50 MB**
- **Billing:** invoices with Due, Paid and Overdue status
- **Brand kit:** voice, colours, hashtags, do's and don'ts, plus **brand files** (logo, guidelines, photos, fonts, up to 25 MB each) shared with its managers and booked influencers
- **Review** the manager after a campaign goes live
- **Pop-up alerts** on laptop and phone (see below)

### Social Media Manager
- **Find campaigns:** open campaigns with a match score and estimated payout, filters by platform and budget
- **My campaigns:** accept a campaign, move it through the stages, submit drafts (post types per platform), resubmit after changes
- **Influencers:** book influencers for the campaigns they manage
- **Caption helper:** writes 3 captions with hashtags from brand, topic, tone and platform (template-based, no AI yet)
- **Content calendar, messages, earnings** (60% of each campaign budget), **profile and reviews**

### Influencer
- **Shoot requests** with date, time, address, fee and brief, plus a notification the moment they're booked
- **Accept or decline**, then **upload** the video (file or link) after the shoot
- **Brand files** of the business that booked them, right on the shoot card
- **Shoot calendar, earnings, profile**
- New influencers see a "being verified" notice until the team approves them

### BrandBay Team (team login)
- **Operations desk:** unassigned requests, people waiting for verification, uploads waiting for review, activity feed
- **All requests:** search, filter, assign a manager, change the stage
- **Packages:** add, edit, hide or delete packages per industry. They appear on the home page and in new requests straight away.
- **Influencer bookings:** every shoot on the platform; send reminders
- **Manager matching:** ranks managers for each open request
- **Users:** verify, suspend or reactivate any account
- **Research briefs** on any campaign (audience, competitors, hashtags)
- **Revenue:** billed, collected, outstanding, margin; mark invoices as paid and send payment reminders
- **Activity log** of everything that happens

### Everyone
- Notifications bell (live), global search, dark mode, works on phone
- **Pop-up alerts:** after clicking "Turn on alerts" once, new notifications pop up on that laptop or phone even when the site is closed. On iPhone this needs the site added to the Home Screen first (Share → Add to Home Screen).
- Forgot password by email
- Terms of Use and Privacy Policy pages (drafts, see [Decisions waiting](#decisions-waiting))
- All prices in **US dollars**

---

## How a campaign works

1. **Business** submits a request → an invoice is created automatically and the team and managers are notified
2. **Team** assigns a manager (or a manager accepts it from Find campaigns) → stage moves to **Research**
3. **Team** writes the research brief
4. **Manager** submits drafts → stage moves to **Content**; the business is notified
5. **Business** approves each draft or asks for changes
6. Stage moves to **Live**; the business can review the manager
7. **Team** marks the invoice as paid when payment arrives

## How an influencer shoot works

1. **Business** (or its manager, or the team) books an influencer with date, time, address, fee and brief
2. **Influencer** gets a notification (and a pop-up if alerts are on): *"New shoot from Sunny Cafe (Instagram Reel): please come on Fri, 20 Nov at 16:00. 📍 5th Ave, Austin. Fee $1,200."*
3. Influencer **accepts** or declines
4. After the shoot, the influencer **uploads** the video or a link
5. **Business** approves it, or asks for a reshoot with feedback

---

## How it's built

| Part | Service | What it does |
|---|---|---|
| Website | One page, `index.html` (HTML, CSS, JavaScript) | All screens for all roles |
| Hosting | **Vercel** | Serves the site; every push to `main` goes live in about a minute |
| Database, logins, files | **Supabase** (Postgres) | Accounts, all data, file storage, live updates |
| Security | Supabase row-level security | The database itself decides what each person can see or change, so the rules can't be bypassed from the browser |
| Notifications | Database triggers | Created automatically on every important event |
| Pop-up alerts | Web Push + a Supabase Edge Function (`send-push`) + `sw.js` in the browser | Sends each notification to the user's devices |

The Supabase **publishable** key inside `index.html` is meant to be public. Never commit the service-role or secret key, the database password, the push secret or the VAPID private key.

---

## What's in this repo

```
index.html                 the whole website
sw.js                      background helper for pop-up alerts
manifest.webmanifest       app name and icons for "Add to Home Screen"
icon-192.png, icon-512.png, apple-touch-icon.png
supabase/
  schema.sql               the complete database (all updates combined), for a brand-new project
  003_post_types.sql       ... individual updates, in order (see below)
  004_file_uploads.sql
  005_push_notifications.sql
  006_chat_50mb.sql
  007_usd_packages.sql
  functions/send-push/index.ts   the pop-up alerts sender (Supabase Edge Function)
```

---

## Database updates

Each update was run once in **Supabase → SQL Editor**, in this order. A new project only needs `schema.sql`, which contains all of them.

| File | What it adds | Status on the live project |
|---|---|---|
| `schema.sql` (original part) | Accounts and roles, campaigns, drafts, chat, invoices, reviews, brand kits, social accounts, posts, influencer bookings, notifications, activity log, security rules, private video storage | ✅ Applied |
| 002 (inside schema.sql) | Team can send payment reminders | ✅ Applied |
| `003_post_types.sql` | Post types per platform (YouTube Video/Short, X Thread, and so on) | ✅ Applied |
| `004_file_uploads.sql` | Files in chat and brand kit, with storage rules; fix so admin changes are logged correctly | ✅ Applied |
| `005_push_notifications.sql` | Pop-up alerts: saved devices, private settings, trigger that calls `send-push` | ✅ Applied |
| `006_chat_50mb.sql` | Chat file limit 10 MB → 50 MB | ✅ Applied |
| `007_usd_packages.sql` | Packages per industry (team-managed), $100 minimum budget, notifications in $ | ✅ Applied |

---

## Security: who can see what

These rules are enforced by the database and were tested with simulated users:

- A business sees only its own campaigns, invoices, posts, social accounts and files. It can't see other businesses.
- Managers see open campaigns, and full details only for campaigns they manage.
- Influencers see only their own bookings, and can upload only into their own booking.
- Chat files can be opened only by people on that campaign. Brand files only by the business, its managers, influencers it booked and the team.
- Nobody can sign up as an employee or change their own role or status.
- Only the business can approve a manager's draft or an influencer's upload. Nobody can change a fee after booking.
- Emails and phone numbers are hidden from other users.
- Only the team can manage packages; visitors see only packages marked visible.

---

## Testing guide

Use **different emails for different roles**, or one normal window plus one incognito window, so you can be two people at once.

**Business**
- [ ] Register as Business → Overview loads
- [ ] Social accounts → add Instagram → Post planner → schedule a post (try YouTube: only Video and Short should appear)
- [ ] Brand kit → save details → upload a logo under Brand files
- [ ] New request → your industry is preselected → pick a package or Custom → submit
- [ ] Messages → send text, and attach a file (try one over 50 MB: it should be refused)
- [ ] Turn on alerts on the Overview page

**Team** (needs an account upgraded by the admin)
- [ ] Team login → Packages → add a package → check it shows on the home page and in New request
- [ ] Users → verify a new manager and influencer
- [ ] Manager matching → assign a manager
- [ ] Revenue → mark an invoice paid → the business gets a "Payment received" notification

**Manager**
- [ ] Find campaigns → accept → submit a draft
- [ ] Business approves or asks for changes → manager sees the result

**Influencer**
- [ ] Business books a shoot → influencer sees the notification with the address
- [ ] Accept → upload a video or link → business approves
- [ ] Brand files show on the shoot card

**Everywhere**
- [ ] Pop-up appears on the laptop or phone when another account sends a message (alerts must be on)
- [ ] Works on phone (Chrome and Safari), no sideways scrolling
- [ ] All prices show in $

Report issues with a **screenshot and the steps to repeat them**.

---

## Updating the site

Every push to `main` deploys to [brandbay.vercel.app](https://brandbay.vercel.app) automatically.

```bash
cd ~/brandbay
cp ~/Downloads/index.html .
git add . && git commit -m "Describe the change" && git push
```

If an update comes with a new `.sql` file, run it in **Supabase → SQL Editor** before or right after pushing.

---

## Setting up from scratch

Only needed for a brand-new Supabase project.

1. **Database:** SQL Editor → paste `supabase/schema.sql` → Run.
2. **Logins:** Authentication → URL Configuration → Site URL = the live link; add `https://<live-link>/**` to Redirect URLs.
3. **Make a team member:** they register on the site first, then run:
   ```sql
   update profiles set role = 'employee', status = 'Active', dept = 'Operations'
   where email = 'name@example.com';
   ```
4. **Pop-up alerts:**
   - Make keys with `npx web-push generate-vapid-keys` and a secret with `openssl rand -hex 24`
   - Put the public key into `index.html` (`VAPID_PUBLIC_KEY`)
   - Edge Functions → create `send-push` from `supabase/functions/send-push/index.ts`, turn **off** "Verify JWT"
   - Edge Functions → Secrets: `PUSH_SECRET`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `SITE_URL`
   - SQL Editor: save the function address and push secret in `private.config` (`push_url`, `push_secret`)

---

## Not built yet and roadmap

| Item | Status |
|---|---|
| Live version: logins, database, all roles, uploads, alerts, packages, US dollars | ✅ Done |
| **Posting to Instagram, Facebook, YouTube, TikTok, LinkedIn, X + live analytics** | ⏳ Plan: use **Postproxy**, which already has the platforms' approvals (about $49/month for 20 brands). About 1–2 weeks to build once approved. |
| **Online payments (Stripe)** | ⏳ Needs a Stripe account with US business details |
| **Email delivery from our own address** (signup confirmation, password reset) | ⏳ Needs the domain and a business email. Until then Supabase's built-in sender is used, which is limited to a few emails per hour. |
| **Bigger uploads for raw videos** (several GB) | ⏳ Needs the Supabase Pro plan |
| **Automatic deletion of old chat files** | ⏳ Waiting for the deletion rule |
| AI captions and hashtags (Gemini or GPT) | Later |
| Canva integration | Later |
| WhatsApp alerts | Later |
| Mobile app | Later |

**Things that are placeholders today:** social account follower counts are entered by hand; "Mark as posted" in the post planner doesn't post anywhere yet; the caption helper uses templates, not AI.

---

## Decisions waiting

| Decision | Why it matters |
|---|---|
| **Final name and domain** (Collavya?) | Needed for the business email, email setup and platform approvals. "BrandBay" is already used by other companies in this field. |
| **Postproxy: go ahead?** | Unlocks real posting and analytics without waiting weeks for approvals |
| **Supabase Pro** ($25/month) | Bigger uploads, daily backups, no pausing after 7 idle days |
| **Chat file deletion rule** | 30 days, after the campaign ends, or none |
| **Stripe account** (US business) | Online payments |
| **Packages and prices** per industry | Can be added directly in the team portal |
| **Terms and Privacy details** | Company legal name, support email, refund policy, and which US state's law applies. The pages are written for the US (FTC ad labels, CCPA) and stay marked as drafts until a lawyer checks them. |
