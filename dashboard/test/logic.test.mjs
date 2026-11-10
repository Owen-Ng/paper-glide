import assert from "node:assert/strict";
import test from "node:test";
import {
  COPY,
  accessGate,
  addDays,
  bucketLabel,
  chartIsEmpty,
  crashFreeText,
  emptyReports,
  fixtureName,
  formatToronto,
  monthStart,
  parseControls,
  preview,
  rangeFor,
  retentionNote,
  serializeControls,
  torontoDay,
  weekStart
} from "../logic.js";

test("sign-in and dashboard copy match the spec", () => {
  assert.equal(COPY.title, "Paper Glide dashboard");
  assert.equal(COPY.sendLink, "Send sign-in link");
  assert.equal(COPY.linkSent, "if this email has access, a sign-in link is on its way. check your inbox.");
  assert.equal(COPY.linkExpired, "that link has expired. send a new one.");
  assert.equal(COPY.signedOut, "you've been signed out. sign in again.");
  assert.equal(COPY.denied, "this account doesn't have access.");
  assert.equal(COPY.signOut, "Sign out");
  assert.equal(COPY.signedInAs("owen@example.com"), "signed in as owen@example.com");
  assert.equal(COPY.caption, "all times in toronto time. weeks start monday.");
  assert.equal(COPY.cards.dauNote, "today so far");
  assert.equal(COPY.cards.wauNote, "this week so far");
  assert.equal(COPY.cards.mauNote, "this month so far");
  assert.equal(COPY.cards.crashFree, "Crash-free sessions");
  assert.equal(COPY.noData, "no data for this range");
  assert.equal(COPY.noReports, "no reports in this range");
  assert.equal(COPY.noCrashes, "no crashes in this range");
  assert.equal(COPY.noPlayerReports, "no player reports in this range");
  assert.equal(COPY.sectionError, "couldn't load this section. Retry");
  assert.equal(COPY.fullFailure, "couldn't reach the data. check your connection and Retry");
  assert.equal(COPY.deleteFailed, "couldn't delete. try again");
  assert.equal(COPY.deleteConfirm, "delete this report? this can't be undone.");
  assert.equal(COPY.reportDeleted, "report deleted");
  assert.equal(COPY.retention, "crash details older than 90 days are removed. player reports are kept until deleted.");
  assert.equal(COPY.loadMore, "Load more");
  assert.equal(COPY.badgeCrash, "crash");
  assert.equal(COPY.badgePlayer, "player");
  assert.deepEqual(COPY.ranges.map(([, label]) => label), [
    "Last 7 days", "Last 30 days", "Last 90 days", "This month", "Last month", "Custom"
  ]);
  assert.deepEqual(COPY.groups.map(([, label]) => label), ["Day", "Week", "Month"]);
  assert.deepEqual(COPY.filters.map(([, label]) => label), ["All", "Crashes", "Player reports"]);
});

test("the confirmation copy does not depend on the allowlist", () => {
  assert.equal(accessGate(true).mode, "dashboard");
  const denied = accessGate(false);
  assert.equal(denied.mode, "denied");
  assert.equal(denied.message, COPY.denied);
  assert.equal(COPY.linkSent, COPY.linkSent);
});

test("a 23:30 Toronto session stays on that civil day, week, and month", () => {
  const july = new Date("2026-07-16T03:30:00Z");
  assert.equal(torontoDay(july), "2026-07-15");
  assert.equal(weekStart("2026-07-15"), "2026-07-13");
  assert.equal(monthStart("2026-07-15"), "2026-07-01");

  const november = new Date("2026-11-02T04:30:00Z");
  assert.equal(torontoDay(november), "2026-11-01");
  assert.equal(weekStart("2026-11-01"), "2026-10-26");
  assert.equal(monthStart("2026-11-01"), "2026-11-01");

  const firstFold = new Date("2026-11-01T05:30:00Z");
  const secondFold = new Date("2026-11-01T06:30:00Z");
  assert.equal(torontoDay(firstFold), "2026-11-01");
  assert.equal(torontoDay(secondFold), "2026-11-01");
  assert.equal(weekStart(torontoDay(secondFold)), "2026-10-26");

  const beforeGap = new Date("2026-03-08T06:30:00Z");
  const afterGap = new Date("2026-03-08T07:30:00Z");
  assert.equal(torontoDay(beforeGap), "2026-03-08");
  assert.equal(torontoDay(afterGap), "2026-03-08");
  assert.equal(weekStart("2026-03-08"), "2026-03-02");
  assert.equal(monthStart("2026-03-08"), "2026-03-01");
});

test("default range is last 7 days grouped by day and round-trips through the url", () => {
  const today = "2026-07-15";
  const parsed = parseControls("", today);
  assert.equal(parsed.range, "7d");
  assert.equal(parsed.group, "day");
  assert.equal(parsed.start, "2026-07-09");
  assert.equal(parsed.end, "2026-07-15");
  assert.equal(parsed.canonical, "range=7d&group=day");
  assert.deepEqual(parseControls(`?${parsed.canonical}`, today).canonical, parsed.canonical);

  const custom = parseControls("?range=custom&group=month&from=2026-05-02&to=2026-06-01", today);
  assert.equal(custom.canonical, "range=custom&group=month&from=2026-05-02&to=2026-06-01");
  assert.equal(serializeControls(custom), custom.canonical);

  const swapped = rangeFor("custom", today, { start: "2026-06-01", end: "2026-05-02" });
  assert.equal(swapped.start, "2026-05-02");
  assert.equal(swapped.end, "2026-06-01");
  assert.equal(rangeFor("this-month", "2026-03-08").start, "2026-03-01");
  assert.deepEqual(rangeFor("last-month", "2026-03-01"), { start: "2026-02-01", end: "2026-02-28" });
  assert.equal(addDays("2026-11-01", -6), "2026-10-26");
});

test("the current bucket is marked so far and an empty chart uses the empty copy", () => {
  assert.equal(bucketLabel("2026-07-15", "day", true), "Jul 15 so far");
  assert.equal(bucketLabel("2026-07-01", "month", false).includes("so far"), false);
  assert.equal(chartIsEmpty([{ count: 0 }, { count: 0 }]), true);
  assert.equal(chartIsEmpty([{ count: 2 }]), false);
  assert.equal(COPY.noData, "no data for this range");
});

test("crash-free, retention, reports, and the local fixture gate", () => {
  assert.equal(crashFreeText(null), "—");
  assert.equal(crashFreeText(undefined), "—");
  assert.equal(crashFreeText(98), "98%");
  assert.equal(retentionNote("2026-04-12", "2026-07-15"), true);
  assert.equal(retentionNote(addDays("2026-07-15", -89), "2026-07-15"), false);
  assert.equal(emptyReports("all"), COPY.noReports);
  assert.equal(emptyReports("crash"), COPY.noCrashes);
  assert.equal(emptyReports("player"), COPY.noPlayerReports);
  const long = "a".repeat(90);
  assert.equal(preview(long).length, 80);
  assert.equal(preview("short"), "short");
  assert.equal(fixtureName("example.com", "?fixture=empty"), null);
  assert.equal(fixtureName("localhost", "?fixture=empty"), "empty");
  const evening = formatToronto("2026-07-16T03:30:00Z");
  assert.match(evening, /Jul 15/);
  assert.match(evening, /11:30/);
});
