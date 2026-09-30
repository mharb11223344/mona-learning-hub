# English Garden · Mrs. Mona Harb

[Open the learning portal](https://mharb11223344.github.io/mona-learning-hub/)

An English learning portal for Grade 3 and Grade 4 girls at Al Andalus Private Schools. Students create an account with their name, grade, email address, and password. After login, each student sees only the two learning sites for her grade.

| Grade | Learning sites |
| --- | --- |
| 3 | [English Primary 3](https://mharb11223344.github.io/english3-1termapp/) and [Connect Plus 3](https://mharb11223344.github.io/connectplus3-term1app/) |
| 4 | [English Primary 4](https://mharb11223344.github.io/connectplus4-term1app/) and [Connect Plus 4](https://mharb11223344.github.io/Plus4app-term1/) |

The portal opens each site in its learning player. Because all four sites use the same GitHub Pages origin, the player reads their existing local progress keys and synchronizes snapshots to the `app_progress` table in Supabase. **Students open lessons through the portal for cloud saving.** Direct visits to each site's home page now route to the portal; inside the portal the site stays embedded and synchronizes progress. The portal also offers an explicit import of prior progress from the same device when the student's account has no cloud record for that site.

## Source and deployment

The source is available in [`mona-learning-hub-source.zip`](./mona-learning-hub-source.zip), including `src/`, `public/`, `schema.sql`, and the Vite configuration. The repository root contains the compiled site for GitHub Pages. Run `pnpm install --frozen-lockfile` and `pnpm build` to rebuild it; publish the contents of `dist/` to the root of `main`.

`schema.sql` describes the Supabase database tables, student profile trigger, and row level security policies. Passwords are handled by Supabase Auth. The browser key in `src/main.js` is a publishable key; never add a database password or service role key to the site.

Email confirmation is temporarily off until a custom SMTP service is configured.

## Verification

Open the portal, create a student account, select Grade 3 or 4, and confirm the dashboard shows only the two sites for that grade. Open a lesson, make progress, wait for “Progress saved ✓”, refresh, and resume the lesson. Repeat with a separate account to check account isolation.
