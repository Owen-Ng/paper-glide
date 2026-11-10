export const COPY = {
  title: "Paper Glide dashboard",
  emailLabel: "email",
  sendLink: "Send sign-in link",
  linkSent: "if this email has access, a sign-in link is on its way. check your inbox.",
  linkExpired: "that link has expired. send a new one.",
  signedOut: "you've been signed out. sign in again.",
  denied: "this account doesn't have access.",
  signOut: "Sign out",
  caption: "all times in toronto time. weeks start monday.",
  cards: {
    dau: "DAU",
    dauNote: "today so far",
    wau: "WAU",
    wauNote: "this week so far",
    mau: "MAU",
    mauNote: "this month so far",
    crashes: "Crashes",
    crashesNote: "in range",
    crashFree: "Crash-free sessions",
    crashFreeNote: "in range"
  },
  activeTitle: "Active users",
  crashesTitle: "Crashes",
  clicksTitle: "Clicks",
  reportsTitle: "Reports",
  pages: [
    ["start", "Start"],
    ["playing", "Playing"],
    ["leaderboard", "Leaderboard"]
  ],
  ranges: [
    ["7d", "Last 7 days"],
    ["30d", "Last 30 days"],
    ["90d", "Last 90 days"],
    ["this-month", "This month"],
    ["last-month", "Last month"],
    ["custom", "Custom"]
  ],
  groups: [
    ["day", "Day"],
    ["week", "Week"],
    ["month", "Month"]
  ],
  filters: [
    ["all", "All"],
    ["crash", "Crashes"],
    ["player", "Player reports"]
  ],
  noData: "no data for this range",
  noReports: "no reports in this range",
  noCrashes: "no crashes in this range",
  noPlayerReports: "no player reports in this range",
  sectionError: "couldn't load this section. Retry",
  fullFailure: "couldn't reach the data. check your connection and Retry",
  deleteFailed: "couldn't delete. try again",
  deleteConfirm: "delete this report? this can't be undone.",
  delete: "Delete",
  cancel: "Cancel",
  reportDeleted: "report deleted",
  badgeCrash: "crash",
  badgePlayer: "player",
  retention: "crash details older than 90 days are removed. player reports are kept until deleted.",
  loadMore: "Load more",
  soFar: "so far",
  dash: "—",
  signedInAs: (email) => `signed in as ${email}`
};

const RANGE_KEYS = new Set(COPY.ranges.map(([key]) => key));
const GROUP_KEYS = new Set(COPY.groups.map(([key]) => key));

export function torontoDay(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto",
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).format(date);
}

export function addDays(iso, days) {
  const [year, month, day] = iso.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return date.toISOString().slice(0, 10);
}

export function weekStart(iso) {
  const weekday = new Intl.DateTimeFormat("en-US", {
    timeZone: "UTC",
    weekday: "short"
  }).format(new Date(`${iso}T12:00:00Z`));
  const index = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }[weekday];
  return addDays(iso, -((index + 6) % 7));
}

export function monthStart(iso) {
  return `${iso.slice(0, 7)}-01`;
}

export function monthEnd(iso) {
  const [year, month] = iso.split("-").map(Number);
  const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return `${iso.slice(0, 7)}-${String(last).padStart(2, "0")}`;
}

export function previousMonth(iso) {
  const [year, month] = iso.split("-").map(Number);
  if (month === 1) return `${year - 1}-12-01`;
  return `${year}-${String(month - 1).padStart(2, "0")}-01`;
}

export function rangeFor(preset, today, custom = {}) {
  if (preset === "30d") return { start: addDays(today, -29), end: today };
  if (preset === "90d") return { start: addDays(today, -89), end: today };
  if (preset === "this-month") return { start: monthStart(today), end: today };
  if (preset === "last-month") {
    const start = previousMonth(today);
    return { start, end: monthEnd(start) };
  }
  if (preset === "custom") {
    let start = custom.start || today;
    let end = custom.end || today;
    if (end < start) {
      const swap = start;
      start = end;
      end = swap;
    }
    return { start, end };
  }
  return { start: addDays(today, -6), end: today };
}

export function parseControls(search, today) {
  const params = new URLSearchParams(search.startsWith("?") ? search.slice(1) : search);
  const range = RANGE_KEYS.has(params.get("range")) ? params.get("range") : "7d";
  const group = GROUP_KEYS.has(params.get("group")) ? params.get("group") : "day";
  const span = rangeFor(range, today, { start: params.get("from"), end: params.get("to") });
  return {
    range,
    group,
    start: span.start,
    end: span.end,
    canonical: serializeControls({ range, group, start: span.start, end: span.end })
  };
}

export function serializeControls(controls) {
  const params = new URLSearchParams();
  params.set("range", controls.range || "7d");
  params.set("group", controls.group || "day");
  if ((controls.range || "7d") === "custom") {
    params.set("from", controls.start);
    params.set("to", controls.end);
  }
  return params.toString();
}

export function formatDay(iso) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC"
  }).format(new Date(`${iso}T12:00:00Z`));
}

export function formatMonth(iso) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    year: "numeric",
    timeZone: "UTC"
  }).format(new Date(`${monthStart(iso)}T12:00:00Z`));
}

export function bucketLabel(start, group, soFar) {
  const base = group === "month" ? formatMonth(start) : formatDay(start);
  return soFar ? `${base} ${COPY.soFar}` : base;
}

export function retentionNote(start, today) {
  return start <= addDays(today, -90);
}

export function crashFreeText(value) {
  if (value === null || value === undefined) return COPY.dash;
  return `${value}%`;
}

export function preview(text, limit = 80) {
  const value = text || "";
  if (value.length <= limit) return value;
  return value.slice(0, limit);
}

export function chartIsEmpty(buckets) {
  return !buckets || buckets.length === 0 || buckets.every((bucket) => Number(bucket.count) === 0);
}

export function emptyReports(filter) {
  if (filter === "crash") return COPY.noCrashes;
  if (filter === "player") return COPY.noPlayerReports;
  return COPY.noReports;
}

export function accessGate(admin) {
  if (admin) return { mode: "dashboard" };
  return { mode: "denied", message: COPY.denied };
}

export function fixtureName(host, search) {
  const local = host === "localhost" || host === "127.0.0.1";
  if (!local) return null;
  const name = new URLSearchParams(search).get("fixture");
  if (!name) return null;
  return name;
}

export function formatToronto(iso) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Toronto",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  }).format(new Date(iso));
}

export function pageLabel(page) {
  const found = COPY.pages.find(([key]) => key === page);
  return found ? found[1] : page;
}

export function controlShare(count, total) {
  const whole = Number(total) || 0;
  if (whole <= 0) return 0;
  return Math.round((Number(count) * 100) / whole);
}

export function sortControls(controls) {
  return controls.map((control, index) => ({ control, index }))
    .sort((a, b) => Number(b.control.count) - Number(a.control.count) || a.index - b.index)
    .map((item) => item.control);
}

export function crashChartEmpty(buckets) {
  if (!buckets || buckets.length === 0) return true;
  return buckets.every((bucket) => {
    const crashes = Number(bucket.count) || 0;
    const sessions = Number(bucket.sessions) || 0;
    return crashes === 0 && sessions === 0 && (bucket.crash_free === null || bucket.crash_free === undefined);
  });
}
