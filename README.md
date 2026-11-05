# BrandBay

**Live site: [brandbay.vercel.app](https://brandbay.vercel.app)**

BrandBay is one portal for a brand's marketing. Businesses post what they need, social media managers create the content, influencers are booked for shoots, and the BrandBay team keeps everything on track.

## Who uses it

| Role | What they do |
|---|---|
| **Business** | Post campaign requests, approve content, manage social accounts and scheduled posts, book influencers, chat, and see invoices |
| **Social Media Manager** | Find and accept campaigns, submit drafts for approval, book influencers, use the caption helper, and track earnings |
| **Influencer** | Get shoot requests with date, time and address, accept or decline, upload the video, and track earnings |
| **BrandBay Team** | Log in at the separate team page, verify new users, assign managers, write research briefs, mark invoices paid, and see all activity |

Team members log in from **Team login** at the bottom of the site.

## How it's built

- **Website:** a single `index.html` page (HTML, CSS and JavaScript), hosted on **Vercel**
- **Database, login and file storage:** **Supabase**
- **Security:** database rules make sure each person sees only their own data. A business can't see another business's campaigns, and only the business can approve content.
- **Notifications** (new requests, shoot bookings, approvals, messages) are created automatically by the database.

## Updating the site

Every push to `main` deploys to [brandbay.vercel.app](https://brandbay.vercel.app) automatically.

```bash
cp ~/Downloads/index.html ~/brandbay/
cd ~/brandbay
git add .
git commit -m "Describe the change"
git push
```

## Database setup (only for a new Supabase project)

1. In Supabase, open **SQL Editor → New query**, paste `supabase/schema.sql`, and click **Run**.
2. Set **Authentication → URL Configuration → Site URL** to the live link, and add `https://brandbay.vercel.app/**` to **Redirect URLs**.
3. To make someone a team member, run:

```sql
update profiles set role = 'employee', status = 'Active', dept = 'Operations'
where email = 'name@example.com';
```

The Supabase "publishable" key in `index.html` is meant to be public. Never commit the `service_role` / secret key, the database password, or email passwords.

## Roadmap

- [x] Live version with real login, shared database and file uploads
- [x] Forgot password, Terms of Use and Privacy Policy (drafts)
- [ ] Email delivery through our own email service
- [ ] Online payments with Razorpay
- [ ] WhatsApp and email alerts for shoots and approvals
- [ ] Instagram, Facebook and YouTube connection for auto-posting and live stats
- [ ] Mobile app
