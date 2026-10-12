import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

// Kakao channel skill + PC relay mailbox (2026-10-12).
// - POST .../kakao-skill               Kakao chatbot skill (x-api-key = KAKAO_SKILL_TOKEN). Always on.
// - POST .../kakao-skill/relay/{claim|ack|publish}   PC automation service (x-relay-token = AUTOMATION_RELAY_TOKEN).
// Requests are stored until the PC pulls them. Agents never run here; status text is rendered by the PC.
// Secrets: KAKAO_SKILL_TOKEN, AUTOMATION_RELAY_TOKEN, KAKAO_BOT_IDS, KAKAO_USER_KEYS, KAKAO_DISCOVERY.

const HEADERS = { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };
const ALIASES: Record<string, string> = {
  "도움말": "/help", "내정보": "/whoami", "메모": "/memo", "실행": "/run",
  "상태": "/status", "중지": "/cancel", "재시도": "/retry",
};
const KEY = /^[A-Za-z0-9_-]{1,64}$/;
const SECRET = /^[A-Za-z0-9_-]{32,128}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HELP = [
  "일반 메시지 / 메모 내용: 메모 저장",
  "실행 요청키 내용: 자동 작업",
  "상태 [작업ID]: 결과 조회",
  "중지 작업ID",
  "재시도 요청키 작업ID",
  "요청키는 영문·숫자·_·-로 1~64자입니다. 새 작업은 새 키를 쓰세요.",
  "PC가 꺼져 있어도 접수되고, PC 작업기가 켜지면 순서대로 처리됩니다.",
].join("\n");

class Rejected extends Error {
  status: number;
  constructor(status: number) { super("rejected"); this.status = status; }
}

const json = (status: number, value: unknown) => new Response(JSON.stringify(value), { status, headers: HEADERS });

function kakao(text: string, status = 200, quick = false) {
  const template: Record<string, unknown> = { outputs: [{ simpleText: { text: text.slice(0, 1000) } }] };
  if (quick) template.quickReplies = [{ label: "상태 확인", action: "message", messageText: "상태" }];
  return json(status, { version: "2.0", template });
}

async function same(supplied: string, expected: string) {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(supplied)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const a = new Uint8Array(left), b = new Uint8Array(right);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

function list(name: string) {
  return (Deno.env.get(name) ?? "").split(",").map((value) => value.trim()).filter(Boolean);
}

function identifier(value: unknown, maximum = 100) {
  if (typeof value !== "string" || !value.trim() || value.length > maximum || value !== value.trim() || /[\x00-\x1f]/.test(value)) {
    throw new Rejected(400);
  }
  return value;
}

async function readJson(request: Request, limit: number) {
  if (request.headers.get("Origin")) throw new Rejected(403);
  const type = (request.headers.get("Content-Type") ?? "").split(";")[0].trim().toLowerCase();
  if (type !== "application/json") throw new Rejected(400);
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (declared > limit) throw new Rejected(413);
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (!bytes.length || bytes.length > limit) throw new Rejected(bytes.length ? 413 : 400);
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new Rejected(400);
  }
}

function when(value: string) {
  return new Date(value).toLocaleString("ko-KR", { timeZone: "Asia/Seoul", month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
}

type Db = { rpc: (name: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }> };

async function rpc(db: Db, name: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(name, args);
  if (error) throw new Rejected(503);
  return data;
}

async function status(db: Db, bot: string, user: string, task: string | null) {
  const view = await rpc(db, "automation_kakao_status", { p_bot: bot, p_user: user, p_task: task }) as {
    tasks: { id: string; text: string; updated: string }[]; waitingCount: number;
    waiting: { received: string; preview: string }[]; replies: { processed: string; text: string }[];
  };
  if (task) {
    const found = view.tasks[0];
    return found ? `${found.text}\n(PC 기준 ${when(found.updated)})` : "해당 작업을 찾을 수 없습니다. PC가 아직 처리하지 않았다면 잠시 후 다시 확인하세요.";
  }
  const parts: string[] = [];
  if (view.waitingCount > 0) {
    parts.push(`PC 처리 대기 ${view.waitingCount}건\n` + view.waiting.map((item) => `· ${when(item.received)} ${item.preview}`).join("\n"));
  }
  for (const reply of view.replies) parts.push(`처리 결과 (${when(reply.processed)})\n${reply.text}`);
  for (const item of view.tasks) parts.push(`${item.text}\n(PC 기준 ${when(item.updated)})`);
  return parts.length ? parts.join("\n\n") : "등록한 작업이 없습니다.";
}

async function skill(request: Request, db: Db) {
  const expected = Deno.env.get("KAKAO_SKILL_TOKEN") ?? "";
  const supplied = request.headers.get("x-api-key") ?? "";
  if (!SECRET.test(expected) || !(await same(supplied, expected))) return kakao("스킬 인증이 필요합니다.", 401);
  const payload = await readJson(request, 32768);
  let bot: string, user: string, text: string;
  try {
    bot = identifier(payload.bot.id);
    const requester = payload.userRequest.user;
    user = identifier(requester.id);
    if (requester.type !== "botUserKey") throw new Rejected(400);
    text = payload.userRequest.utterance;
    if (typeof text !== "string" || !text.trim() || text.length > 8200 || text.includes("\x00")) throw new Rejected(400);
  } catch (error) {
    if (error instanceof Rejected) throw error;
    throw new Rejected(400);
  }
  const forbidden = () => kakao("허용된 봇과 사용자만 이용할 수 있습니다.", 403);
  if (!list("KAKAO_BOT_IDS").includes(bot)) return forbidden();
  const trimmed = text.trim();
  const match = trimmed.match(/^(\S+)(?:\s+([\s\S]*))?$/)!;
  const command = ALIASES[match[1]] ?? match[1];
  const body = (match[2] ?? "").trim();
  if (command === "/whoami" && Deno.env.get("KAKAO_DISCOVERY") === "true") {
    return kakao(`연결 식별자\nbot.id: ${bot}\nbotUserKey: ${user}\nSupabase 함수 비밀값과 PC 로컬 설정의 허용 목록에 등록하세요.`);
  }
  if (!list("KAKAO_USER_KEYS").includes(user)) return forbidden();
  if (command === "/help" || command === "/start") return kakao(HELP);
  if (command === "/whoami") return kakao("연결 식별자 확인은 발견 모드(KAKAO_DISCOVERY=true)를 켠 동안만 가능합니다.");
  if (command === "/status") return kakao(await status(db, bot, user, body ? identifier(body) : null), 200, !body);
  let accepted: string;
  if (command === "/run") {
    const parts = body.match(/^(\S+)\s+([\s\S]+)$/);
    if (!parts) return kakao("실행 요청키 내용 형식으로 입력하세요. 예: 실행 test-1 문서에 연결 확인 문장 추가");
    if (!KEY.test(parts[1])) return kakao("요청키는 영문·숫자·_·-로 1~64자입니다.");
    accepted = `실행 요청을 받았습니다 (요청키 ${parts[1]}).\nPC 작업기가 켜져 있으면 순서대로 처리합니다. PC에서 자동 실행이 꺼져 있으면 실행하지 않고 결과에 안내를 남깁니다.`;
  } else if (command === "/retry") {
    const parts = body.split(/\s+/);
    if (parts.length !== 2 || !KEY.test(parts[0])) return kakao("재시도 요청키 작업ID 형식으로 입력하세요.");
    accepted = "재시도 요청을 받았습니다. PC가 처리하면 상태에 반영됩니다.";
  } else if (command === "/cancel") {
    if (!body || /\s/.test(body)) return kakao("중지 작업ID 형식으로 입력하세요.");
    accepted = "중지 요청을 받았습니다. PC가 처리하면 상태에 반영됩니다.";
  } else if (command.startsWith("/") && command !== "/memo") {
    return kakao("지원하지 않는 명령입니다. 도움말을 입력하세요.");
  } else {
    if (command === "/memo" && !body) return kakao("메모 내용을 함께 입력하세요.");
    accepted = "메모를 받았습니다. PC 작업함으로 옮겨지면 상태에서 확인할 수 있습니다.";
  }
  const stored = await rpc(db, "automation_kakao_receive", { p_bot: bot, p_user: user, p_utterance: trimmed });
  if (!stored) return kakao("PC 처리 대기 요청이 100건에 도달했습니다. PC 작업기를 켠 뒤 다시 보내세요.");
  return kakao(accepted, 200, true);
}

async function relay(request: Request, db: Db, action: string) {
  const expected = Deno.env.get("AUTOMATION_RELAY_TOKEN") ?? "";
  const supplied = request.headers.get("x-relay-token") ?? "";
  if (!SECRET.test(expected) || !(await same(supplied, expected))) return json(401, { error: "unauthorized" });
  const data = await readJson(request, 262144);
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Rejected(400);
  if (action === "claim") {
    const limit = data.limit ?? 10;
    if (!Number.isInteger(limit) || limit < 1 || limit > 20) throw new Rejected(400);
    const rows = await rpc(db, "automation_kakao_claim", { p_limit: limit }) as Record<string, string>[];
    return json(200, { items: (rows ?? []).map((row) => ({
      id: row.item_id, claim: row.item_claim, bot: row.item_bot, user: row.item_user,
      utterance: row.item_utterance, received: row.item_received,
    })) });
  }
  if (action === "ack") {
    if (typeof data.id !== "string" || !UUID.test(data.id) || typeof data.claim !== "string" || !UUID.test(data.claim)) throw new Rejected(400);
    const task = data.taskId === null || data.taskId === undefined ? null : identifier(data.taskId);
    if (typeof data.reply !== "string" || !data.reply || data.reply.length > 1000) throw new Rejected(400);
    const ok = await rpc(db, "automation_kakao_ack", { p_id: data.id, p_claim: data.claim, p_task: task, p_reply: data.reply });
    return json(200, { ok: ok === true });
  }
  if (action === "publish") {
    const tasks = data.tasks;
    if (!Array.isArray(tasks) || tasks.length > 200) throw new Rejected(400);
    const seen = new Set<string>();
    for (const task of tasks) {
      if (!task || typeof task !== "object") throw new Rejected(400);
      identifier(task.id);
      identifier(task.actor, 200);
      if (!task.actor.startsWith("kakao:") || seen.has(task.id)) throw new Rejected(400);
      seen.add(task.id);
      if (typeof task.statusText !== "string" || !task.statusText || task.statusText.length > 1000) throw new Rejected(400);
      if (typeof task.created !== "string" || Number.isNaN(Date.parse(task.created))) throw new Rejected(400);
    }
    const count = tasks.length ? await rpc(db, "automation_kakao_publish", { p_tasks: tasks }) : 0;
    return json(200, { count });
  }
  return json(404, { error: "not found" });
}

Deno.serve(async (request: Request) => {
  const path = new URL(request.url).pathname.replace(/\/+$/, "");
  const at = path.lastIndexOf("/kakao-skill");
  if (at < 0) return json(404, { error: "not found" });
  const route = path.slice(at + "/kakao-skill".length);
  const isRelay = route.startsWith("/relay/");
  if (route !== "" && !isRelay) return json(404, { error: "not found" });
  if (request.method !== "POST") return isRelay ? json(405, { error: "method" }) : kakao("등록된 스킬 경로가 아닙니다.", 405);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json(503, { error: "unavailable" });
  const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } }) as unknown as Db;
  try {
    return isRelay ? await relay(request, db, route.slice("/relay/".length)) : await skill(request, db);
  } catch (error) {
    // Never echo utterances, identifiers, tokens or database errors.
    const status = error instanceof Rejected ? error.status : 500;
    if (isRelay) return json(status, { error: "rejected" });
    return kakao(status === 503 ? "잠시 후 다시 보내 주세요." : "입력 형식을 확인하세요.", status);
  }
});
