import {
  COPY,
  accessGate,
  bucketLabel,
  chartIsEmpty,
  controlShare,
  crashChartEmpty,
  crashFreeText,
  sortControls,
  emptyReports,
  fixtureName,
  formatToronto,
  pageLabel,
  parseControls,
  preview,
  rangeFor,
  retentionNote,
  serializeControls,
  torontoDay
} from "./logic.js";

const root = document.querySelector("#app");
const today = () => torontoDay(new Date());
const state = {
  screen: "signin",
  notice: "",
  email: "",
  session: null,
  controls: parseControls(location.search, today()),
  summary: null,
  active: null,
  crashes: null,
  clicks: null,
  reports: null,
  reportFilter: "all",
  expanded: null,
  confirm: null,
  toast: "",
  fullFailure: false,
  sections: {
    summary: "loading",
    active: "loading",
    crashes: "loading",
    clicks: "loading",
    reports: "loading"
  }
};

function config() {
  const value = window.PAPER_GLIDE_DASHBOARD;
  if (!value || !value.supabaseUrl || !value.supabaseAnonKey) return null;
  if (/service_role/i.test(value.supabaseAnonKey)) return { rejected: true };
  return value;
}

function writeURL() {
  const params = new URLSearchParams(serializeControls(state.controls));
  const fixture = new URLSearchParams(location.search).get("fixture");
  if (fixture) params.set("fixture", fixture);
  const next = `${location.pathname}?${params.toString()}`;
  if (`${location.pathname}${location.search}` !== next) {
    history.replaceState(null, "", next);
  }
}

function liveData() {
  return state.screen === "dashboard" && !fixtureName(location.hostname, location.search);
}

function loadSession() {
  try {
    return JSON.parse(sessionStorage.getItem("paper-glide-dashboard-session") || "null");
  } catch {
    return null;
  }
}

function saveSession(session) {
  state.session = session;
  if (session) sessionStorage.setItem("paper-glide-dashboard-session", JSON.stringify(session));
  else sessionStorage.removeItem("paper-glide-dashboard-session");
}

async function api(path, options = {}) {
  const cfg = config();
  const headers = {
    apikey: cfg.supabaseAnonKey,
    Authorization: `Bearer ${options.token || cfg.supabaseAnonKey}`,
    "Content-Type": "application/json"
  };
  const response = await fetch(`${cfg.supabaseUrl}${path}`, { ...options, headers });
  const text = await response.text();
  let body = null;
  if (text) {
    try { body = JSON.parse(text); } catch { body = { raw: text }; }
  }
  if (!response.ok) {
    const error = new Error("request failed");
    error.status = response.status;
    error.body = body;
    throw error;
  }
  return body;
}

function applyControls(next) {
  const todayKey = today();
  const span = rangeFor(next.range, todayKey, next);
  state.controls = {
    range: next.range,
    group: next.group,
    start: span.start,
    end: span.end
  };
  writeURL();
}

function render() {
  if (state.screen === "signin") {
    root.innerHTML = signinHTML();
    return;
  }
  if (state.screen === "denied") {
    root.innerHTML = deniedHTML();
    return;
  }
  root.innerHTML = dashboardHTML();
}

function signinHTML() {
  const cfg = config();
  const setup = !cfg
    ? `<p>Copy config.example.js to config.js and set the project URL and anon key.</p>`
    : cfg.rejected
      ? `<p>Use the anon key in config.js.</p>`
      : "";
  return `<main class="signin">
    <h1>${COPY.title}</h1>
    ${setup}
    ${state.notice ? `<p class="notice">${escapeHTML(state.notice)}</p>` : ""}
    <form id="sign-in">
      <label>${COPY.emailLabel}
        <input name="email" type="email" autocomplete="email" required ${cfg && !cfg.rejected ? "" : "disabled"}>
      </label>
      <button class="primary" type="submit" ${cfg && !cfg.rejected ? "" : "disabled"}>${COPY.sendLink}</button>
    </form>
  </main>`;
}

function deniedHTML() {
  return `<main class="denied">
    <h1>${COPY.title}</h1>
    <p>${COPY.denied}</p>
    <button class="ghost" type="button" data-action="sign-out">${COPY.signOut}</button>
  </main>`;
}

function dashboardHTML() {
  if (state.fullFailure) {
    return `<main class="failure">
      <h1>${COPY.title}</h1>
      <p>${COPY.fullFailure.replace("Retry", "")}<button type="button" data-action="retry-all">Retry</button></p>
    </main>`;
  }
  return `<div class="wrap">
    <header class="top">
      <div>
        <h1>${COPY.title}</h1>
        <p class="who">${escapeHTML(COPY.signedInAs(state.email))}</p>
      </div>
      <button class="ghost" type="button" data-action="sign-out">${COPY.signOut}</button>
    </header>
    ${controlsHTML()}
    ${cardsHTML()}
    ${chartPanel("active", COPY.activeTitle, state.active)}
    ${crashesPanel()}
    ${clicksPanel()}
    ${reportsPanel()}
    ${state.confirm ? confirmHTML() : ""}
    ${state.toast ? `<div class="toast" role="status">${escapeHTML(state.toast)}</div>` : ""}
  </div>`;
}

function controlsHTML() {
  const presets = COPY.ranges.map(([key, label]) =>
    `<button type="button" data-range="${key}" aria-pressed="${state.controls.range === key}">${label}</button>`
  ).join("");
  const groups = COPY.groups.map(([key, label]) =>
    `<button type="button" data-group="${key}" aria-pressed="${state.controls.group === key}">${label}</button>`
  ).join("");
  const custom = state.controls.range === "custom"
    ? `<label>start <input type="date" data-custom="start" value="${state.controls.start}"></label>
       <label>end <input type="date" data-custom="end" value="${state.controls.end}"></label>`
    : "";
  const options = COPY.ranges.map(([key, label]) =>
    `<option value="${key}" ${state.controls.range === key ? "selected" : ""}>${label}</option>`
  ).join("");
  return `<section class="controls">
    <div class="row desktop-controls presets">${presets}${custom}</div>
    <div class="row desktop-controls"><div class="segmented">${groups}</div></div>
    <div class="row phone-controls">
      <select data-range-select aria-label="range">${options}</select>
      <div class="segmented">${groups}</div>
    </div>
    ${state.controls.range === "custom" ? `<div class="row phone-controls">${custom}</div>` : ""}
    <p class="caption">${COPY.caption}</p>
  </section>`;
}

function cardsHTML() {
  const loading = state.sections.summary === "loading";
  const failed = state.sections.summary === "error";
  if (failed) return `<section class="panel">${sectionError("summary")}</section>`;
  const data = state.summary || {};
  const value = (number) => loading ? COPY.dash : String(number ?? 0);
  return `<section class="cards">
    ${card(COPY.cards.dau, COPY.cards.dauNote, value(data.dau))}
    ${card(COPY.cards.wau, COPY.cards.wauNote, value(data.wau))}
    ${card(COPY.cards.mau, COPY.cards.mauNote, value(data.mau))}
    ${card(COPY.cards.crashes, COPY.cards.crashesNote, value(data.crashes))}
    ${card(COPY.cards.crashFree, COPY.cards.crashFreeNote, loading ? COPY.dash : crashFreeText(data.crash_free), "crash-free")}
  </section>`;
}

function card(title, note, value, extra = "") {
  return `<article class="card ${extra}"><h3>${title}</h3><p class="value">${value}</p><p class="note">${note}</p></article>`;
}

function chartPanel(key, title, buckets) {
  let body;
  if (state.sections[key] === "loading") body = `<div class="skeleton"></div><div class="skeleton"></div>`;
  else if (state.sections[key] === "error") body = sectionError(key);
  else if (chartIsEmpty(buckets)) body = `<div class="chart flat"><p>${COPY.noData}</p></div>`;
  else {
    const max = Math.max(...buckets.map((bucket) => Number(bucket.count)), 1);
    const bars = buckets.map((bucket) => {
      const height = Math.max(2, Math.round((Number(bucket.count) / max) * 120));
      const label = bucketLabel(bucket.start, state.controls.group, Boolean(bucket.so_far));
      return `<div class="bar ${bucket.so_far ? "so-far" : ""}">
        <strong>${bucket.count}</strong>
        <div class="fill" style="height:${height}px"></div>
        <span>${label}</span>
      </div>`;
    }).join("");
    body = `<div class="chart-scroll"><div class="chart ${buckets.length > 10 ? "long" : ""}" style="--n:${buckets.length}">${bars}</div></div>`;
  }
  return `<section class="panel"><h2>${title}</h2>${body}</section>`;
}

function crashesPanel() {
  let body;
  if (state.sections.crashes === "loading") body = `<div class="skeleton"></div><div class="skeleton"></div>`;
  else if (state.sections.crashes === "error") body = sectionError("crashes");
  else if (crashChartEmpty(state.crashes)) body = `<div class="chart flat"><p>${COPY.noData}</p></div>`;
  else body = bucketChart(state.crashes, true);
  const summary = state.summary;
  const totals = state.sections.summary === "loading"
    ? `<p class="note">${COPY.cards.crashes} ${COPY.dash} · ${COPY.cards.crashFree} ${COPY.dash}</p>`
    : `<p class="note">${COPY.cards.crashes} ${summary?.crashes ?? 0} · ${COPY.cards.crashFree} ${crashFreeText(summary?.crash_free)}</p>`;
  return `<section class="panel"><h2>${COPY.crashesTitle}</h2>${totals}${body}</section>`;
}

function bucketChart(buckets, withFree) {
  const max = Math.max(...buckets.map((bucket) => Number(bucket.count) || 0), 1);
  const bars = buckets.map((bucket) => {
    const height = Math.max(2, Math.round(((Number(bucket.count) || 0) / max) * 120));
    const label = bucketLabel(bucket.start, state.controls.group, Boolean(bucket.so_far));
    const free = withFree
      ? `<span class="free">${bucket.crash_free === null || bucket.crash_free === undefined ? COPY.dash : `${bucket.crash_free}%`}</span>`
      : "";
    return `<div class="bar ${bucket.so_far ? "so-far" : ""}">
      <strong>${bucket.count}</strong>
      <div class="fill" style="height:${height}px"></div>
      ${free}
      <span>${label}</span>
    </div>`;
  }).join("");
  return `<div class="chart-scroll"><div class="chart ${buckets.length > 10 ? "long" : ""}" style="--n:${buckets.length}">${bars}</div></div>`;
}

function clicksPanel() {
  let body;
  if (state.sections.clicks === "loading") body = `<div class="skeleton"></div>`;
  else if (state.sections.clicks === "error") body = sectionError("clicks");
  else {
    const pages = state.clicks || [];
    body = pages.map((page) => {
      const controls = sortControls(page.controls || []);
      const chart = Number(page.total) === 0 || chartIsEmpty(page.buckets)
        ? `<div class="chart flat"><p>${COPY.noData}</p></div>`
        : bucketChart(page.buckets, false);
      const rows = controls.map((control) => {
        const share = control.share === undefined ? controlShare(control.count, page.total) : control.share;
        return `<tr><td>${escapeHTML(control.control)}</td><td>${control.count}</td><td>${share}%</td></tr>`;
      }).join("");
      return `<div class="click-page">
        <h3>${pageLabel(page.page)} ${page.total}</h3>
        ${chart}
        <table>
          <thead><tr><th>control</th><th>clicks</th><th>% of page</th></tr></thead>
          <tbody>${rows}</tbody>
        </table>
      </div>`;
    }).join("");
  }
  return `<section class="panel"><h2>${COPY.clicksTitle}</h2>${body}</section>`;
}

function reportsPanel() {
  let body;
  if (state.sections.reports === "loading") body = `<div class="skeleton"></div>`;
  else if (state.sections.reports === "error") body = sectionError("reports");
  else {
    const data = state.reports || { counts: { all: 0, crash: 0, player: 0 }, reports: [], has_more: false, retention_note: false };
    const filters = COPY.filters.map(([key, label]) => {
      const count = data.counts?.[key] ?? 0;
      return `<button type="button" data-filter="${key}" aria-pressed="${state.reportFilter === key}">${label} ${count}</button>`;
    }).join("");
    const note = data.retention_note ? `<p class="note">${COPY.retention}</p>` : "";
    const rows = data.reports || [];
    const list = rows.length === 0
      ? `<p>${emptyReports(state.reportFilter)}</p>`
      : rows.map(reportRow).join("");
    const more = data.has_more ? `<button class="ghost" type="button" data-action="more">${COPY.loadMore}</button>` : "";
    body = `<div class="filters">${filters}</div>${note}${list}${more}`;
  }
  return `<section class="panel"><h2>${COPY.reportsTitle}</h2>${body}</section>`;
}

function reportRow(report) {
  const open = state.expanded === report.id;
  const badge = report.kind === "crash" ? COPY.badgeCrash : COPY.badgePlayer;
  const headline = report.kind === "crash" ? (report.summary || "") : (report.category || "");
  const text = report.kind === "crash" ? (report.summary || "") : preview(report.text || "");
  const username = report.username ? escapeHTML(report.username) : "";
  const meta = [report.app_version, report.ios_version, report.device_model, username].filter(Boolean).join(" · ");
  const full = report.kind === "crash" ? (report.details || report.summary || "") : (report.text || "");
  return `<article class="report">
    <button class="report-main" type="button" data-expand="${report.id}">
      <span><span class="badge">${badge}</span> ${escapeHTML(formatToronto(report.happened_at))}</span>
      <span><strong>${escapeHTML(headline)}</strong><br>${escapeHTML(text)}<br><span class="meta">${escapeHTML(meta)}</span></span>
      <span class="row-delete" data-delete="${report.id}" data-kind="${report.kind}">${COPY.delete}</span>
    </button>
    ${open ? `<div class="expanded">
      <p>${escapeHTML(full)}</p>
      <p class="meta">${escapeHTML(report.account_id || "")}</p>
      <button class="ghost report-delete-expanded" type="button" data-delete="${report.id}" data-kind="${report.kind}">${COPY.delete}</button>
    </div>` : ""}
  </article>`;
}

function sectionError(key) {
  return `<p class="section-error">couldn't load this section. <button type="button" data-retry="${key}">Retry</button></p>`;
}

function confirmHTML() {
  return `<div class="dialog-back">
    <div class="dialog" role="dialog" aria-modal="true">
      <p>${COPY.deleteConfirm}</p>
      <div class="row">
        <button class="ghost" type="button" data-action="cancel-delete">${COPY.cancel}</button>
        <button class="primary" type="button" data-action="confirm-delete">${COPY.delete}</button>
      </div>
    </div>
  </div>`;
}

function escapeHTML(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
  }[char]));
}

async function sendLink(email) {
  const cfg = config();
  const redirect = `${location.origin}${location.pathname}?${serializeControls(state.controls)}`;
  try {
    await fetch(`${cfg.supabaseUrl}/auth/v1/otp?redirect_to=${encodeURIComponent(redirect)}`, {
      method: "POST",
      headers: {
        apikey: cfg.supabaseAnonKey,
        Authorization: `Bearer ${cfg.supabaseAnonKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ email, create_user: true })
    });
  } catch {
    state.notice = COPY.fullFailure;
    render();
    return;
  }
  state.notice = COPY.linkSent;
  render();
}

async function establish(session) {
  saveSession(session);
  try {
    const user = await api("/auth/v1/user", { token: session.access_token });
    state.email = user.email || "";
    const who = await api("/rest/v1/rpc/analytics_who", {
      method: "POST",
      token: session.access_token,
      body: "{}"
    });
    const gate = accessGate(Boolean(who && who.admin));
    if (gate.mode === "denied") {
      state.screen = "denied";
      render();
      return;
    }
    state.screen = "dashboard";
    render();
    await loadAll();
  } catch (error) {
    if (error.status === 401) {
      const refreshed = await refresh(session);
      if (refreshed) return establish(refreshed);
      saveSession(null);
      state.screen = "signin";
      state.notice = COPY.signedOut;
      render();
      return;
    }
    state.screen = "dashboard";
    state.fullFailure = true;
    render();
  }
}

async function refresh(session) {
  try {
    const body = await api(`/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      body: JSON.stringify({ refresh_token: session.refresh_token })
    });
    return {
      access_token: body.access_token,
      refresh_token: body.refresh_token,
      expires_at: Date.now() + (body.expires_in || 3600) * 1000
    };
  } catch {
    return null;
  }
}

async function loadAll() {
  state.fullFailure = false;
  for (const key of Object.keys(state.sections)) state.sections[key] = "loading";
  render();
  const jobs = [
    ["summary", () => rpc("analytics_summary", { start_day: state.controls.start, end_day: state.controls.end })],
    ["active", () => rpc("analytics_series", { start_day: state.controls.start, end_day: state.controls.end, group_by: state.controls.group, metric: "active" })],
    ["crashes", () => rpc("analytics_series", { start_day: state.controls.start, end_day: state.controls.end, group_by: state.controls.group, metric: "crashes" })],
    ["clicks", () => rpc("analytics_clicks", { start_day: state.controls.start, end_day: state.controls.end, group_by: state.controls.group })],
    ["reports", () => loadReports(false)]
  ];
  const results = await Promise.allSettled(jobs.map(([, run]) => run()));
  if (results.some((result) => result.status === "rejected" && result.reason?.status === 401)) return;
  if (results.every((result) => result.status === "rejected")) {
    state.fullFailure = true;
    render();
    return;
  }
  jobs.forEach(([key], index) => {
    const result = results[index];
    if (result.status === "rejected") {
      state.sections[key] = "error";
      return;
    }
    accept(key, result.value);
  });
  render();
}

function accept(key, value) {
  if (!value || value.ok === false) {
    if (value && value.error === "forbidden") {
      state.screen = "denied";
      return;
    }
    state.sections[key] = "error";
    return;
  }
  state.sections[key] = "ready";
  if (key === "summary") state.summary = value;
  if (key === "active") state.active = value.buckets || [];
  if (key === "crashes") state.crashes = value.buckets || [];
  if (key === "clicks") state.clicks = value.pages || [];
  if (key === "reports") state.reports = value;
}

async function loadReports(append) {
  const cursor = append && state.reports?.reports?.length
    ? state.reports.reports[state.reports.reports.length - 1]
    : null;
  const value = await rpc("analytics_reports", {
    start_day: state.controls.start,
    end_day: state.controls.end,
    report_filter: state.reportFilter,
    before_at: cursor ? cursor.happened_at : null,
    before_id: cursor ? cursor.id : null
  });
  if (append && state.reports && value && value.ok !== false) {
    value.reports = state.reports.reports.concat(value.reports || []);
  }
  return value;
}

function noteSignedOut() {
  saveSession(null);
  state.screen = "signin";
  state.notice = COPY.signedOut;
  state.fullFailure = false;
  state.confirm = null;
  render();
}

async function rpc(name, args) {
  try {
    return await api(`/rest/v1/rpc/${name}`, {
      method: "POST",
      token: state.session.access_token,
      body: JSON.stringify(args)
    });
  } catch (error) {
    if (error.status === 401) noteSignedOut();
    throw error;
  }
}

async function reloadSection(key) {
  state.sections[key] = "loading";
  render();
  try {
    if (key === "summary") accept(key, await rpc("analytics_summary", { start_day: state.controls.start, end_day: state.controls.end }));
    if (key === "active") accept(key, await rpc("analytics_series", { start_day: state.controls.start, end_day: state.controls.end, group_by: state.controls.group, metric: "active" }));
    if (key === "crashes") accept(key, await rpc("analytics_series", { start_day: state.controls.start, end_day: state.controls.end, group_by: state.controls.group, metric: "crashes" }));
    if (key === "clicks") accept(key, await rpc("analytics_clicks", { start_day: state.controls.start, end_day: state.controls.end, group_by: state.controls.group }));
    if (key === "reports") accept(key, await loadReports(false));
  } catch (error) {
    if (error.status === 401) return;
    state.sections[key] = "error";
  }
  render();
}

async function reloadCharts() {
  await Promise.all([reloadSection("active"), reloadSection("crashes"), reloadSection("clicks")]);
}

function showToast(text) {
  state.toast = text;
  render();
  setTimeout(() => {
    if (state.toast === text) {
      state.toast = "";
      render();
    }
  }, 2500);
}

async function confirmDelete() {
  const target = state.confirm;
  state.confirm = null;
  if (!target || !state.reports) return;
  const previous = state.reports.reports;
  state.reports = {
    ...state.reports,
    reports: previous.filter((report) => report.id !== target.id)
  };
  showToast(COPY.reportDeleted);
  try {
    const result = await rpc("analytics_delete_report", { report_id: target.id, report_kind: target.kind });
    if (!result || result.ok === false || result.result === "missing") throw new Error("delete");
  } catch (error) {
    if (error.status === 401) return;
    state.reports = { ...state.reports, reports: previous };
    showToast(COPY.deleteFailed);
  }
}

function useFixture(name) {
  const day = today();
  state.email = "owen@example.com";
  state.screen = "dashboard";
  if (name === "denied") {
    state.screen = "denied";
    render();
    return;
  }
  if (name === "signin") {
    state.screen = "signin";
    state.notice = COPY.linkSent;
    render();
    return;
  }
  if (name === "expired") {
    state.screen = "signin";
    state.notice = COPY.linkExpired;
    render();
    return;
  }
  if (name === "failure") {
    state.fullFailure = true;
    render();
    return;
  }
  if (name === "loading") {
    render();
    return;
  }
  if (name === "error") {
    state.sections = { summary: "ready", active: "error", crashes: "ready", clicks: "ready", reports: "ready" };
    state.summary = { dau: 2, wau: 4, mau: 6, crashes: 1, sessions: 8, crash_free: 88 };
    state.active = null;
    state.crashes = [{ start: day, count: 1, so_far: true }];
    state.clicks = zeroClicks();
    state.reports = { counts: { all: 0, crash: 0, player: 0 }, reports: [], has_more: false, retention_note: false };
    render();
    return;
  }
  const empty = name === "empty";
  state.sections = { summary: "ready", active: "ready", crashes: "ready", clicks: "ready", reports: "ready" };
  state.summary = empty
    ? { dau: 0, wau: 0, mau: 0, crashes: 0, sessions: 0, crash_free: null }
    : { dau: 3, wau: 8, mau: 12, crashes: 1, sessions: 10, crash_free: 90 };
  state.active = empty
    ? [{ start: day, count: 0, so_far: true }]
    : [{ start: addDaysSafe(day, -1), count: 2, so_far: false }, { start: day, count: 3, so_far: true }];
  state.crashes = empty
    ? [{ start: day, count: 0, sessions: 0, crash_free: null, so_far: true }]
    : [{ start: addDaysSafe(day, -1), count: 0, sessions: 4, crash_free: 100, so_far: false }, { start: day, count: 1, sessions: 6, crash_free: 83, so_far: true }];
  state.clicks = empty ? zeroClicks() : sampleClicks();
  state.reports = empty
    ? { counts: { all: 0, crash: 0, player: 0 }, reports: [], has_more: false, retention_note: retentionNote(state.controls.start, day) }
    : {
        counts: { all: 2, crash: 1, player: 1 },
        has_more: false,
        retention_note: retentionNote(state.controls.start, day),
        reports: fixtureReports()
      };
  state.allReports = state.reports.reports.slice();
  render();
}

function fixtureReports() {
  return [
          {
            id: "r1",
            happened_at: "2026-07-16T03:30:00Z",
            kind: "player",
            category: "Something looks wrong",
            text: "the sky flickered near the second window and then settled",
            app_version: "1.0 (1)",
            ios_version: "18.0",
            device_model: "iPhone16,1",
            account_id: "11111111-1111-4111-8111-111111111111",
            username: "pilot"
          },
          {
            id: "c1",
            happened_at: "2026-07-15T18:00:00Z",
            kind: "crash",
            summary: "signal 11 exception 1/0",
            details: "call stack",
            app_version: "1.0 (1)",
            ios_version: "18.0",
            device_model: "iPhone16,1",
            account_id: "11111111-1111-4111-8111-111111111111",
            username: null
          }
  ];
}

function addDaysSafe(iso, days) {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

function zeroClicks() {
  return sampleClicks().map((page) => ({
    ...page,
    total: 0,
    controls: page.controls.map((control) => ({ ...control, count: 0, share: 0 })),
    buckets: (page.buckets || []).map((bucket) => ({ ...bucket, count: 0 }))
  }));
}

function sampleClicks() {
  const day = today();
  const buckets = (counts) => [
    { start: addDaysSafe(day, -1), count: counts[0], so_far: false },
    { start: day, count: counts[1], so_far: true }
  ];
  return [
    { page: "start", total: 6, buckets: buckets([2, 4]), controls: [
      { control: "play", count: 3, share: 50 },
      { control: "leaderboard", count: 1, share: 17 },
      { control: "report", count: 1, share: 17 },
      { control: "other", count: 1, share: 17 }
    ] },
    { page: "playing", total: 40, buckets: buckets([15, 25]), controls: [{ control: "flap", count: 40, share: 100 }] },
    { page: "leaderboard", total: 5, buckets: buckets([1, 4]), controls: [
      { control: "Today", count: 2, share: 40 },
      { control: "This week", count: 1, share: 20 },
      { control: "All time", count: 0, share: 0 },
      { control: "back", count: 1, share: 20 },
      { control: "other", count: 0, share: 0 },
      { control: "scroll", count: 1, share: 20 }
    ] }
  ];
}

root.addEventListener("click", (event) => {
  const deleter = event.target.closest("[data-delete]");
  if (deleter) {
    event.preventDefault();
    state.confirm = { id: deleter.dataset.delete, kind: deleter.dataset.kind };
    render();
    return;
  }
  const target = event.target.closest("button");
  if (!target) return;
  if (target.dataset.range) {
    applyControls({ ...state.controls, range: target.dataset.range });
    if (liveData()) loadAll();
    else render();
  } else if (target.dataset.group) {
    state.controls.group = target.dataset.group;
    writeURL();
    if (liveData()) reloadCharts();
    else render();
  } else if (target.dataset.filter) {
    state.reportFilter = target.dataset.filter;
    state.expanded = null;
    if (fixtureName(location.hostname, location.search)) {
      const all = state.allReports || [];
      state.reports.reports = all.filter((report) => state.reportFilter === "all" || report.kind === state.reportFilter);
      render();
    } else reloadSection("reports");
  } else if (target.dataset.expand) {
    state.expanded = state.expanded === target.dataset.expand ? null : target.dataset.expand;
    render();
  } else if (target.dataset.retry) {
    reloadSection(target.dataset.retry);
  } else if (target.dataset.action === "retry-all") {
    loadAll();
  } else if (target.dataset.action === "sign-out") {
    signOut();
  } else if (target.dataset.action === "cancel-delete") {
    state.confirm = null;
    render();
  } else if (target.dataset.action === "confirm-delete") {
    if (fixtureName(location.hostname, location.search)) {
      const id = state.confirm.id;
      state.confirm = null;
      state.reports.reports = state.reports.reports.filter((report) => report.id !== id);
      showToast(COPY.reportDeleted);
    } else {
      confirmDelete();
    }
  } else if (target.dataset.action === "more") {
    loadReports(true).then((value) => {
      accept("reports", value);
      render();
    }).catch((error) => {
      if (error.status === 401) return;
      state.sections.reports = "error";
      render();
    });
  }
});

root.addEventListener("change", (event) => {
  const target = event.target;
  if (target.dataset.rangeSelect) {
    applyControls({ ...state.controls, range: target.value });
    if (liveData()) loadAll();
    else render();
  }
  if (target.dataset.custom) {
    const custom = {
      start: target.dataset.custom === "start" ? target.value : state.controls.start,
      end: target.dataset.custom === "end" ? target.value : state.controls.end
    };
    applyControls({ range: "custom", group: state.controls.group, ...custom });
    if (liveData()) loadAll();
    else render();
  }
});

root.addEventListener("submit", (event) => {
  if (event.target.id !== "sign-in") return;
  event.preventDefault();
  const email = new FormData(event.target).get("email");
  sendLink(String(email || "").trim());
});

async function signOut() {
  const session = state.session;
  saveSession(null);
  state.screen = "signin";
  state.notice = "";
  state.summary = null;
  render();
  if (session && config() && !config().rejected) {
    try {
      await api("/auth/v1/logout", { method: "POST", token: session.access_token, body: "{}" });
    } catch {
      // The local session is already gone.
    }
  }
}

function readHash() {
  const hash = new URLSearchParams(location.hash.replace(/^#/, ""));
  if (hash.get("error")) {
    history.replaceState(null, "", `${location.pathname}?${serializeControls(state.controls)}`);
    state.screen = "signin";
    state.notice = COPY.linkExpired;
    render();
    return true;
  }
  if (hash.get("access_token")) {
    const session = {
      access_token: hash.get("access_token"),
      refresh_token: hash.get("refresh_token"),
      expires_at: Date.now() + Number(hash.get("expires_in") || 3600) * 1000
    };
    history.replaceState(null, "", `${location.pathname}?${serializeControls(state.controls)}`);
    establish(session);
    return true;
  }
  return false;
}

function boot() {
  writeURL();
  const fixture = fixtureName(location.hostname, location.search);
  if (fixture) {
    useFixture(fixture);
    return;
  }
  if (readHash()) return;
  const session = loadSession();
  if (!session) {
    render();
    return;
  }
  if (session.expires_at && session.expires_at < Date.now()) {
    refresh(session).then((next) => {
      if (!next) {
        saveSession(null);
        state.notice = COPY.signedOut;
        render();
        return;
      }
      establish(next);
    });
    return;
  }
  establish(session);
}

boot();
