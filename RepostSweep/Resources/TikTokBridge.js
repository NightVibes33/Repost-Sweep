// Repost Sweep page bridge.
// Runs inside the hidden TikTok WKWebView. It never reads password fields and
// never returns cookies to the app.
//
// Removal attribution (see THIRD_PARTY_NOTICES.md):
// - The upvote/delete request (POST, empty body, aid + item_id on the query,
//   tt-csrf-token from webapp.app-context) and the “re-list and confirm the
//   id is gone” check follow gabireze/tiktok-all-reposted-videos-remover (MIT).
// - The share-sheet selectors follow BrittAbdula/tiktokrepostremover (MIT, ClearTok).
//   A control is tapped only when data-e2e contains remove-repost or aria-pressed is true.
//   Fill color is not used, and captured signed URLs are not replayed.
(function () {
  "use strict";

  var LIST_PATH = "/api/repost/item_list/";
  var UNREPOST_PATHS = ["/tiktok/v1/upvote/delete/", "/api/repost/item/delete/"];
  var APP_LABELS = [
    "log in with tiktok app",
    "login with tiktok app",
    "continue with tiktok app",
    "open tiktok app",
    "open the tiktok app",
    "log in with app",
    "use tiktok app",
    "continue in the tiktok app",
    "continue in tiktok"
  ];

  function installNetHook() {
    var hook = window.__repostSweepNetHook;
    if (!hook) {
      hook = { lastDelete: null, nativeFetch: null };
      window.__repostSweepNetHook = hook;
    }
    if (typeof window.fetch === "function" && !window.fetch.__rs) {
      var previous = window.fetch;
      if (!hook.nativeFetch) {
        var native = previous;
        while (native && native.__rsPrev) native = native.__rsPrev;
        hook.nativeFetch = native;
      }
      var wrapped = function (input, init) {
        try {
          recordDelete(input, init);
        } catch (error) {
          /* capture is best-effort */
        }
        return previous.apply(this, arguments);
      };
      wrapped.__rs = true;
      wrapped.__rsPrev = previous;
      window.fetch = wrapped;
    }
    if (!XMLHttpRequest.prototype.__rsSend) {
      var originalOpen = XMLHttpRequest.prototype.open;
      var originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__rsMethod = method;
        this.__rsURL = typeof url === "string" ? url : String(url || "");
        return originalOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function (body) {
        try {
          var url = String(this.__rsURL || "");
          if (!window.__repostSweepReplay && isDeleteURL(url)) {
              window.__repostSweepNetHook.lastDelete = {
                url: url,
                method: String(this.__rsMethod || "POST"),
                body: bodyToString(body)
              };
              window.__repostSweepNetHook.lastDeleteAt = Date.now();
          }
        } catch (error) {
          /* capture is best-effort */
        }
        return originalSend.apply(this, arguments);
      };
      XMLHttpRequest.prototype.__rsSend = true;
    }
  }

  if (window.__repostSweep && window.__repostSweep.version >= 4) {
    installNetHook();
    return;
  }

  function onTikTok() {
    return /(^|\.)tiktok\.com$/i.test(location.hostname || "");
  }

  function fail(code, message) {
    return {
      ok: false,
      code: code,
      message: message || "",
      items: [],
      cursor: "",
      hasMore: false,
      account: null,
      dataURL: ""
    };
  }

  function succeed(extra) {
    var result = {
      ok: true,
      code: "",
      message: "",
      items: [],
      cursor: "",
      hasMore: false,
      account: null,
      dataURL: ""
    };
    if (extra) {
      Object.keys(extra).forEach(function (key) {
        result[key] = extra[key];
      });
    }
    return result;
  }

  function delay(ms) {
    return new Promise(function (resolve) {
      setTimeout(resolve, ms);
    });
  }

  function cookieValue(name) {
    var parts = (document.cookie || "").split("; ");
    for (var i = 0; i < parts.length; i += 1) {
      var eq = parts[i].indexOf("=");
      if (eq === -1) continue;
      if (parts[i].slice(0, eq) === name) {
        try {
          return decodeURIComponent(parts[i].slice(eq + 1));
        } catch (error) {
          return parts[i].slice(eq + 1);
        }
      }
    }
    return "";
  }

  function isDeleteURL(url) {
    return url.indexOf("/upvote/delete") !== -1 || url.indexOf("/repost/item/delete") !== -1;
  }

  function bodyToString(body) {
    if (body == null) return "";
    if (typeof body === "string") return body;
    if (typeof URLSearchParams !== "undefined" && body instanceof URLSearchParams) return body.toString();
    return "";
  }

  function recordDelete(input, init) {
    if (window.__repostSweepReplay) return;
    var url = "";
    var method = "GET";
    if (typeof input === "string") {
      url = input;
    } else if (input && typeof input.url === "string") {
      url = input.url;
      method = input.method || method;
    }
    if (init && init.method) method = init.method;
    if (!isDeleteURL(String(url))) return;
    var body = "";
    if (init && init.body != null) body = bodyToString(init.body);
    window.__repostSweepNetHook.lastDelete = {
      url: String(url),
      method: String(method),
      body: body
    };
    window.__repostSweepNetHook.lastDeleteAt = Date.now();
  }

  function readHydration() {
    if (window.__UNIVERSAL_DATA_FOR_REHYDRATION__) {
      return window.__UNIVERSAL_DATA_FOR_REHYDRATION__;
    }
    var element = document.getElementById("__UNIVERSAL_DATA_FOR_REHYDRATION__");
    if (!element || !element.textContent) return null;
    try {
      return JSON.parse(element.textContent);
    } catch (error) {
      return null;
    }
  }

  function isForeignAvatar(url) {
    var lower = String(url || "").toLowerCase();
    return (
      lower.indexOf("googleusercontent") !== -1 ||
      lower.indexOf("ggpht") !== -1 ||
      lower.indexOf("google.com") !== -1 ||
      lower.indexOf("gstatic") !== -1 ||
      lower.indexOf("fbcdn") !== -1
    );
  }

  function prefersTikTokCDN(url) {
    return /tiktokcdn|byteimg|tiktokv|ibyteimg|muscdn/i.test(String(url || ""));
  }

  function pushAvatar(list, value) {
    if (!value) return;
    if (typeof value === "string" && value) {
      list.push(value);
      return;
    }
    if (value.url_list && value.url_list[0]) list.push(String(value.url_list[0]));
    if (value.urlList && value.urlList[0]) list.push(String(value.urlList[0]));
  }

  function avatarOf(user) {
    if (!user) return "";
    var found = [];
    pushAvatar(found, user.avatarThumb);
    pushAvatar(found, user.avatarMedium);
    pushAvatar(found, user.avatarLarger);
    pushAvatar(found, user.avatar_thumb);
    pushAvatar(found, user.avatar_medium);
    pushAvatar(found, user.avatar_larger);
    pushAvatar(found, user.avatarUri);
    pushAvatar(found, user.avatar_url);
    pushAvatar(found, user.avatarUrl);
    var clean = [];
    for (var i = 0; i < found.length; i += 1) {
      if (!isForeignAvatar(found[i])) clean.push(found[i]);
    }
    for (var j = 0; j < clean.length; j += 1) {
      if (prefersTikTokCDN(clean[j])) return clean[j];
    }
    return clean[0] || "";
  }

  function countOf(source, keys) {
    if (!source || typeof source !== "object") return 0;
    for (var i = 0; i < keys.length; i += 1) {
      if (source[keys[i]] === undefined || source[keys[i]] === null || source[keys[i]] === "") continue;
      var number = Number(source[keys[i]]);
      if (isFinite(number) && number >= 0) return Math.round(number);
    }
    return 0;
  }

  function applyStats(account, source) {
    if (!account || !source) return account;
    var followers = countOf(source, ["followerCount", "follower_count", "fans"]);
    var following = countOf(source, ["followingCount", "following_count", "following"]);
    if (!account.followerCount && followers) account.followerCount = followers;
    if (!account.followingCount && following) account.followingCount = following;
    return account;
  }

  function mapUser(user) {
    if (!user || typeof user !== "object") return null;
    var uniqueId = user.uniqueId || user.unique_id || "";
    if (!uniqueId) return null;
    var account = {
      uniqueId: String(uniqueId),
      nickname: String(user.nickname || user.nickName || user.screen_name || ""),
      secUid: String(user.secUid || user.sec_uid || user.sec_user_id || ""),
      avatarURL: avatarOf(user),
      followerCount: 0,
      followingCount: 0
    };
    applyStats(account, user);
    applyStats(account, user.stats);
    return account;
  }

  function sessionUser() {
    var hydration = readHydration();
    var scope = hydration && hydration.__DEFAULT_SCOPE__;
    var appUser = scope && scope["webapp.app-context"] && scope["webapp.app-context"].user;
    var mapped = mapUser(appUser);
    if (mapped) return mapped;

    var sigi = window.SIGI_STATE &&
      window.SIGI_STATE.AppContext &&
      window.SIGI_STATE.AppContext.appContext &&
      window.SIGI_STATE.AppContext.appContext.user;
    mapped = mapUser(sigi);
    if (mapped) return mapped;

    var nav = document.querySelector('[data-e2e="nav-profile"]');
    var href = (nav && nav.getAttribute("href")) || "";
    var match = href.match(/@([^/?#]+)/);
    if (match && match[1]) {
      var decoded = match[1];
      try {
        decoded = decodeURIComponent(match[1]);
      } catch (error) {
        decoded = match[1];
      }
      return { uniqueId: decoded, nickname: "", secUid: "", avatarURL: "", followerCount: 0, followingCount: 0 };
    }
    return null;
  }

  function profileUser() {
    var hydration = readHydration();
    var scope = hydration && hydration.__DEFAULT_SCOPE__;
    var detail = scope && scope["webapp.user-detail"];
    var user = detail && detail.userInfo && detail.userInfo.user;
    var mapped = mapUser(user);
    if (mapped && detail.userInfo.stats) applyStats(mapped, detail.userInfo.stats);
    return mapped;
  }

  function mergeAccount() {
    var session = sessionUser();
    var profile = profileUser();
    if (!session && profile) {
      var path = location.pathname || "";
      if (profile.uniqueId && path.indexOf("/@" + profile.uniqueId) !== -1) return profile;
      return null;
    }
    if (session && profile && session.uniqueId === profile.uniqueId) {
      if (!session.secUid && profile.secUid) session.secUid = profile.secUid;
      if (!session.nickname) session.nickname = profile.nickname;
      if (!session.avatarURL) session.avatarURL = profile.avatarURL;
      if (!session.followerCount) session.followerCount = profile.followerCount;
      if (!session.followingCount) session.followingCount = profile.followingCount;
    }
    return session;
  }

  function coverOf(video) {
    if (!video || typeof video !== "object") return "";
    var candidates = [video.cover, video.originCover, video.dynamicCover, video.coverUrl, video.origin_cover];
    for (var i = 0; i < candidates.length; i += 1) {
      var value = candidates[i];
      if (typeof value === "string" && value) return value;
      if (value && value.url_list && value.url_list.length) return String(value.url_list[0]);
      if (value && value.urlList && value.urlList.length) return String(value.urlList[0]);
    }
    return "";
  }

  function mapItem(raw) {
    if (!raw || typeof raw !== "object") return null;
    var id = String(raw.id || raw.aweme_id || raw.awemeId || raw.item_id || raw.itemId || "");
    if (!/^\d{6,}$/.test(id)) return null;
    var author = "";
    if (raw.author && typeof raw.author === "object") {
      author = raw.author.uniqueId || raw.author.nickname || "";
    } else if (typeof raw.author === "string") {
      author = raw.author;
    }
    return {
      id: id,
      author: String(author).slice(0, 80),
      caption: String(raw.desc || raw.title || "").slice(0, 180),
      coverURL: coverOf(raw.video)
    };
  }

  function statusOf(json) {
    if (!json || typeof json !== "object") return null;
    if (json.statusCode !== undefined && json.statusCode !== null) return json.statusCode;
    if (json.status_code !== undefined && json.status_code !== null) return json.status_code;
    return null;
  }

  function classify(httpStatus, status) {
    var numeric = Number(status);
    if (httpStatus === 429 || numeric === 2483 || numeric === 2484) return "RATE_LIMITED";
    if (numeric === 0 && httpStatus >= 200 && httpStatus < 300) return "OK";
    if (httpStatus === 401 || httpStatus === 403 || numeric === 10101) return "NOT_LOGGED_IN";
    return "ENDPOINT_CHANGED";
  }

  function listParams(secUid, cursor) {
    var params = new URLSearchParams();
    params.set("aid", "1988");
    params.set("app_name", "tiktok_web");
    params.set("channel", "tiktok_web");
    params.set("device_platform", "web_mobile");
    params.set("os", "ios");
    params.set("count", "20");
    params.set("cursor", String(cursor || "0"));
    params.set("secUid", secUid);
    params.set("from_page", "user");
    params.set("coverFormat", "2");
    params.set("cookie_enabled", navigator.cookieEnabled ? "true" : "false");
    params.set("browser_language", navigator.language || "en");
    params.set("app_language", navigator.language || "en");
    params.set("webcast_language", navigator.language || "en");
    params.set("browser_online", "true");
    params.set("browser_platform", navigator.platform || "iPhone");
    params.set("focus_state", "true");
    params.set("is_fullscreen", "false");
    params.set("is_page_visible", document.visibilityState === "visible" ? "true" : "false");
    params.set("history_len", String((history && history.length) || 1));
    params.set("screen_width", String((window.screen && screen.width) || 390));
    params.set("screen_height", String((window.screen && screen.height) || 844));
    try {
      params.set("tz_name", Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC");
    } catch (error) {
      params.set("tz_name", "UTC");
    }
    var token = cookieValue("msToken");
    if (token) params.set("msToken", token);
    return params;
  }

  function looksLikeList(json) {
    return Boolean(
      json &&
      (Object.prototype.hasOwnProperty.call(json, "itemList") ||
        Object.prototype.hasOwnProperty.call(json, "item_list") ||
        Object.prototype.hasOwnProperty.call(json, "hasMore") ||
        Object.prototype.hasOwnProperty.call(json, "has_more") ||
        Object.prototype.hasOwnProperty.call(json, "cursor") ||
        Object.prototype.hasOwnProperty.call(json, "statusCode") ||
        Object.prototype.hasOwnProperty.call(json, "status_code"))
    );
  }

  function remoteAccount(json) {
    var data = json;
    if (data && data.data && typeof data.data === "object" && !data.uniqueId && !data.unique_id) data = data.data;
    var userInfo = data && data.userInfo;
    if (userInfo && userInfo.user) {
      var fromInfo = mapUser(userInfo.user);
      if (fromInfo) applyStats(fromInfo, userInfo.stats);
      return fromInfo;
    }
    if (data && data.user && typeof data.user === "object") data = data.user;
    if (!data || typeof data !== "object") return null;
    var mapped = mapUser(data);
    if (mapped) return mapped;
    var uniqueId = String(data.username || "");
    if (!uniqueId || /^\d+$/.test(uniqueId)) return null;
    var account = {
      uniqueId: uniqueId,
      nickname: String(data.screen_name || data.nickname || ""),
      secUid: String(data.sec_user_id || data.secUid || data.sec_uid || ""),
      avatarURL: avatarOf(data),
      followerCount: 0,
      followingCount: 0
    };
    applyStats(account, data);
    return account;
  }

  function fillAccount(base, extra) {
    if (!extra) return base;
    if (!base) return extra;
    if (extra.uniqueId && base.uniqueId && extra.uniqueId !== base.uniqueId) return base;
    if (!base.uniqueId) base.uniqueId = extra.uniqueId;
    if (!base.nickname) base.nickname = extra.nickname;
    if (!base.secUid) base.secUid = extra.secUid;
    if (!base.avatarURL) base.avatarURL = extra.avatarURL;
    if (!base.followerCount) base.followerCount = extra.followerCount || 0;
    if (!base.followingCount) base.followingCount = extra.followingCount || 0;
    return base;
  }

  async function fetchSelf() {
    try {
      var response = await fetch("/passport/web/account/info/?aid=1988&account_sdk_source=web", {
        method: "GET",
        credentials: "include",
        headers: { accept: "application/json, text/plain, */*" }
      });
      if (!response.ok) return null;
      var json = await response.json();
      return remoteAccount(json);
    } catch (error) {
      return null;
    }
  }

  async function fetchUserDetail(uniqueId) {
    if (!uniqueId) return null;
    try {
      var response = await fetch("/api/user/detail/?aid=1988&uniqueId=" + encodeURIComponent(uniqueId), {
        method: "GET",
        credentials: "include",
        headers: { accept: "application/json, text/plain, */*" }
      });
      if (!response.ok) return null;
      var json = await response.json();
      return remoteAccount(json);
    } catch (error) {
      return null;
    }
  }

  async function detect() {
    if (!onTikTok()) return fail("NOT_ON_TIKTOK", "Sign-in happens on TikTok’s website.");
    var account = mergeAccount();
    if (!account || !account.uniqueId || !account.secUid || !account.avatarURL) {
      account = fillAccount(account, await fetchSelf());
    }
    if (account && account.uniqueId && (!account.secUid || !account.avatarURL || !account.followerCount || !account.followingCount)) {
      account = fillAccount(account, await fetchUserDetail(account.uniqueId));
    }
    if (!account || !account.uniqueId) return fail("NOT_LOGGED_IN", "TikTok doesn’t show a signed-in account yet.");
    return succeed({ account: account });
  }

  async function list(payload) {
    var input = payload || {};
    if (!onTikTok()) return fail("NOT_ON_TIKTOK", "Open TikTok and sign in.");
    if (input.mode === "dom") return listFromDom();

    var account = mergeAccount();
    var supplied = String(input.secUid || "");
    if (supplied && (!account || !account.secUid)) {
      if (!account) {
        account = { uniqueId: "", nickname: "", secUid: supplied, avatarURL: "", followerCount: 0, followingCount: 0 };
      } else {
        account.secUid = supplied;
      }
    }
    if (!account && !supplied) return fail("NOT_LOGGED_IN", "TikTok doesn’t show a signed-in account yet.");
    if (!account || !account.secUid) return fail("NO_SEC_UID", "TikTok didn’t include the account id on this page.");

    var url = LIST_PATH + "?" + listParams(account.secUid, input.cursor || "0").toString();
    var response;
    try {
      response = await fetch(url, {
        method: "GET",
        credentials: "include",
        headers: { accept: "application/json, text/plain, */*" }
      });
    } catch (error) {
      return fail("NETWORK", "The repost list request didn’t finish.");
    }

    var text = "";
    try {
      text = await response.text();
    } catch (error) {
      return fail("NETWORK", "The repost list response couldn’t be read.");
    }
    if (response.status === 429) return fail("RATE_LIMITED", "http 429");

    var json;
    try {
      json = JSON.parse(text);
    } catch (error) {
      return fail("ENDPOINT_CHANGED", "Repost list was not JSON (http " + response.status + ").");
    }
    if (!looksLikeList(json)) {
      return fail("ENDPOINT_CHANGED", "Repost list JSON didn’t look like TikTok’s (http " + response.status + ").");
    }

    var status = statusOf(json);
    var kind = classify(response.status, status === null ? 0 : status);
    if (kind === "RATE_LIMITED") return fail("RATE_LIMITED", "status " + status);
    if (kind === "NOT_LOGGED_IN") return fail("NOT_LOGGED_IN", "status " + status);
    if (kind !== "OK") return fail("ENDPOINT_CHANGED", "Repost list status " + status + " http " + response.status + ".");

    var rawItems = json.itemList || json.item_list || [];
    if (!Array.isArray(rawItems)) return fail("ENDPOINT_CHANGED", "Repost list is missing itemList.");
    var items = [];
    for (var i = 0; i < rawItems.length; i += 1) {
      var mapped = mapItem(rawItems[i]);
      if (mapped) items.push(mapped);
    }
    return succeed({
      items: items,
      cursor: json.cursor !== undefined && json.cursor !== null ? String(json.cursor) : "",
      hasMore: Boolean(json.hasMore || json.has_more),
      account: account
    });
  }

  function csrfHeaders() {
    var headers = {
      accept: "application/json, text/plain, */*",
      "content-type": "application/x-www-form-urlencoded"
    };
    var csrf = cookieValue("tt_csrf_token") || cookieValue("csrf_session_id");
    if (csrf) headers["tt-csrf-token"] = csrf;
    return headers;
  }

  function snippet(text) {
    return String(text || "").replace(/\s+/g, " ").trim().slice(0, 500);
  }

  function cleanDeleteURL(raw) {
    var parsed = new URL(raw, location.origin);
    ["X-Bogus", "x-bogus", "X-Gnarly", "x-gnarly", "_signature"].forEach(function (key) {
      parsed.searchParams.delete(key);
    });
    var token = cookieValue("msToken");
    if (token) parsed.searchParams.set("msToken", token);
    return parsed.pathname + parsed.search;
  }

  function bodyForItem(body, itemId) {
    var text = body == null ? "" : String(body);
    if (!text) {
      var fresh = new URLSearchParams();
      fresh.set("item_id", itemId);
      fresh.set("aweme_id", itemId);
      return fresh.toString();
    }
    if (text.charAt(0) === "{") {
      try {
        var json = JSON.parse(text);
        ["item_id", "aweme_id", "itemId", "awemeId"].forEach(function (key) {
          if (Object.prototype.hasOwnProperty.call(json, key)) json[key] = itemId;
        });
        return JSON.stringify(json);
      } catch (error) {
        /* fall through to form encoding */
      }
    }
    var params = new URLSearchParams(text);
    var touched = false;
    ["item_id", "aweme_id", "itemId", "awemeId"].forEach(function (key) {
      if (params.has(key)) {
        params.set(key, itemId);
        touched = true;
      }
    });
    if (!touched) {
      params.set("item_id", itemId);
      params.set("aweme_id", itemId);
    }
    return params.toString();
  }

  async function signURL(raw) {
    var crawler = window.byted_acrawler;
    if (!crawler) return "";
    var absolute = raw;
    try {
      absolute = new URL(raw, location.origin).toString();
    } catch (error) {
      absolute = raw;
    }
    var signed = null;
    try {
      if (typeof crawler.frontierSign === "function") {
        signed = await crawler.frontierSign({ url: absolute });
      }
      if (!signed && typeof crawler.sign === "function") {
        try {
          signed = await crawler.sign({ url: absolute });
        } catch (error) {
          signed = null;
        }
        if (!signed) signed = await crawler.sign(absolute);
      }
    } catch (error) {
      return "";
    }
    if (!signed) return "";
    if (typeof signed === "string") return signed;
    if (typeof signed.url === "string") return signed.url;
    var bogus = signed["X-Bogus"] || signed["x-bogus"];
    var gnarly = signed["X-Gnarly"] || signed["x-gnarly"];
    if (!bogus && !gnarly) return "";
    try {
      var parsed = new URL(absolute);
      if (bogus) parsed.searchParams.set("X-Bogus", String(bogus));
      if (gnarly) parsed.searchParams.set("X-Gnarly", String(gnarly));
      return parsed.toString();
    } catch (error) {
      return "";
    }
  }

  async function sendDelete(url, body) {
    var signed = await signURL(url);
    var finalURL = signed || url;
    var hook = window.__repostSweepNetHook;
    var useNative = Boolean(signed && hook && typeof hook.nativeFetch === "function");
    var fetcher = useNative ? hook.nativeFetch : window.fetch;
    window.__repostSweepReplay = true;
    try {
      var response = await fetcher.call(window, finalURL, {
        method: "POST",
        credentials: "include",
        headers: csrfHeaders(),
        body: body
      });
      var text = "";
      try {
        text = await response.text();
      } catch (error) {
        text = "";
      }
      return { status: response.status, text: text };
    } finally {
      window.__repostSweepReplay = false;
    }
  }

  function interpretUnrepost(httpStatus, text) {
    if (httpStatus === 404 || httpStatus === 405) {
      return { kind: "next", message: "http " + httpStatus };
    }
    if (!text) {
      return { kind: "fallback", message: "Unrepost response was empty (http " + httpStatus + ")." };
    }
    var json;
    try {
      json = JSON.parse(text);
    } catch (error) {
      return {
        kind: "fallback",
        message: "Unrepost response was not JSON (http " + httpStatus + "). " + snippet(text)
      };
    }
    var status = statusOf(json);
    var kind = classify(httpStatus, status === null ? -1 : status);
    if (kind === "OK") return { kind: "ok", message: "" };
    if (kind === "RATE_LIMITED") return { kind: "rate", message: "status " + status };
    if (kind === "NOT_LOGGED_IN") return { kind: "auth", message: "status " + status };
    return {
      kind: "fallback",
      message: "Unrepost status " + status + " http " + httpStatus + ". " + snippet(text)
    };
  }

  function contextCsrf() {
    var hydration = readHydration();
    var scope = hydration && hydration.__DEFAULT_SCOPE__;
    var context = scope && scope["webapp.app-context"];
    return (context && (context.csrfToken || context.csrf_token)) || "";
  }

  function attemptLog(method, url, status, text) {
    var clean = String(url || "").replace(/([?&])(msToken|X-Bogus|X-Gnarly|_signature)=[^&]*/gi, "$1$2=…");
    return method + " " + clean.slice(0, 240) + " → http " + status + " " + snippet(text);
  }

  async function postUpvoteDelete(url, body) {
    var signed = await signURL(url);
    var finalURL = signed || url;
    var hook = window.__repostSweepNetHook;
    var useNative = Boolean(signed && hook && typeof hook.nativeFetch === "function");
    var fetcher = useNative ? hook.nativeFetch : window.fetch;
    var headers = {
      accept: "*/*",
      "content-type": "application/x-www-form-urlencoded"
    };
    var csrf = contextCsrf() || cookieValue("tt_csrf_token") || cookieValue("csrf_session_id");
    if (csrf) headers["tt-csrf-token"] = csrf;
    window.__repostSweepReplay = true;
    try {
      var response = await fetcher.call(window, finalURL, {
        method: "POST",
        credentials: "include",
        headers: headers,
        body: body == null ? "" : body
      });
      var text = "";
      try {
        text = await response.text();
      } catch (error) {
        text = "";
      }
      var read = interpretUnrepost(response.status, text);
      return {
        kind: read.kind,
        message: read.message,
        log: attemptLog("POST", finalURL, response.status, text)
      };
    } finally {
      window.__repostSweepReplay = false;
    }
  }

  async function remove(payload) {
    installNetHook();
    var input = payload || {};
    var itemId = String(input.itemId || "");
    if (!/^\d{6,}$/.test(itemId)) return fail("PARSE", "That repost id doesn’t look usable.");
    if (!onTikTok()) return fail("NOT_ON_TIKTOK", "Open TikTok and sign in.");

    var plain = new URLSearchParams();
    plain.set("aid", "1988");
    plain.set("item_id", itemId);
    var result;
    try {
      result = await postUpvoteDelete("/tiktok/v1/upvote/delete/?" + plain.toString(), "");
    } catch (error) {
      return fail("ATTEMPTED", "The unrepost request didn’t finish.");
    }
    if (result && result.kind === "rate") return fail("RATE_LIMITED", "TikTok asked for a pause.");
    if (result && result.kind === "auth") return fail("NOT_LOGGED_IN", "TikTok doesn’t see the sign-in.");
    if (result && result.kind === "ok") return fail("OK", "Delete request accepted.");
    return fail("ATTEMPTED", "Delete request sent.");
  }

  async function confirmRemoved(payload) {
    var input = payload || {};
    var itemId = String(input.itemId || "");
    if (!/^\d{6,}$/.test(itemId)) return fail("PARSE", "That repost id doesn’t look usable.");
    await delay(1200);
    var maxPages = Number(input.maxPages);
    if (!isFinite(maxPages) || maxPages < 1) maxPages = 2;
    if (maxPages > 2) maxPages = 2;
    var cursor = "0";
    var seen = 0;
    for (var page = 0; page < maxPages; page += 1) {
      var result = await list({ cursor: cursor, secUid: String(input.secUid || ""), mode: "api" });
      if (!result.ok) {
        return fail(result.code || "UNVERIFIED", "Couldn’t verify against the repost list.");
      }
      for (var i = 0; i < result.items.length; i += 1) {
        seen += 1;
        if (String(result.items[i].id) === itemId) {
          return fail("STILL_THERE", "That repost is still on the list.");
        }
      }
      if (!result.hasMore || !result.cursor || result.cursor === cursor) {
        return succeed({ message: "Not on the first pages of the repost list." });
      }
      cursor = result.cursor;
    }
    return fail("UNVERIFIED", "Not on the first pages. The sweep checks the full list at the end.");
  }

  function listFromDom() {
    var root = document.querySelector('[data-e2e="user-post-item-list"]') || document.querySelector("main") || document.body;
    var anchors = root.querySelectorAll('a[href*="/video/"]');
    var seen = {};
    var items = [];
    for (var i = 0; i < anchors.length; i += 1) {
      var href = anchors[i].getAttribute("href") || "";
      var match = href.match(/\/video\/(\d+)/);
      if (!match || seen[match[1]]) continue;
      seen[match[1]] = true;
      var image = anchors[i].querySelector("img");
      items.push({
        id: match[1],
        author: "",
        caption: image ? String(image.getAttribute("alt") || "").slice(0, 180) : "",
        coverURL: image && image.src ? String(image.src) : ""
      });
    }
    if (!items.length) return fail("EMPTY", "No repost tiles were visible on the profile.");
    return succeed({ items: items, hasMore: false, account: mergeAccount() });
  }

  async function focusReposts() {
    if (!onTikTok()) return fail("NOT_ON_TIKTOK", "Open TikTok and sign in.");
    var selectors = ['[data-e2e="profile-repost-tab"]', 'a[href*="tab=repost"]', '[class*="PRepost"]'];
    for (var i = 0; i < selectors.length; i += 1) {
      var element = document.querySelector(selectors[i]);
      if (element) {
        element.click();
        return succeed({ message: "clicked selector" });
      }
    }
    var nodes = document.querySelectorAll('a, button, div[role="tab"]');
    for (var j = 0; j < nodes.length; j += 1) {
      var text = (nodes[j].innerText || nodes[j].textContent || "").replace(/\s+/g, " ").trim().toLowerCase();
      if (text === "reposts" || text === "repost") {
        nodes[j].click();
        return succeed({ message: "clicked label" });
      }
    }
    return fail("UI_CHANGED", "The Reposts tab wasn’t on the profile page.");
  }

  function scrollPage() {
    var height = Math.max(
      document.body ? document.body.scrollHeight : 0,
      document.documentElement ? document.documentElement.scrollHeight : 0
    );
    window.scrollTo(0, height);
    return succeed({});
  }

  function isVisible(el) {
    if (!el || !el.getBoundingClientRect) return false;
    var rect = el.getBoundingClientRect();
    if (rect.width < 2 || rect.height < 2) return false;
    var style = window.getComputedStyle ? window.getComputedStyle(el) : null;
    if (!style) return true;
    if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
    return true;
  }

  function controlText(el) {
    if (!el) return "";
    var aria = el.getAttribute("aria-label") || "";
    var text = el.innerText || el.textContent || "";
    return (aria + " " + text).replace(/\s+/g, " ").trim();
  }

  function handoffHref(el) {
    if (!el || !el.getAttribute) return "";
    var href = (el.getAttribute("href") || el.getAttribute("data-href") || "").trim();
    var lower = href.toLowerCase();
    if (lower.indexOf("tiktok://") === 0 || lower.indexOf("snssdk1233://") === 0 || lower.indexOf("snssdk1128://") === 0) {
      return href;
    }
    return "";
  }

  function isForeignLogin(text) {
    return /google|facebook|apple|e-?mail|phone|qr code|username/.test(text);
  }

  function appLoginScore(text) {
    var lower = String(text || "").toLowerCase();
    if (!lower || isForeignLogin(lower)) return 0;
    var best = 0;
    for (var i = 0; i < APP_LABELS.length; i += 1) {
      if (lower.indexOf(APP_LABELS[i]) !== -1) best = Math.max(best, APP_LABELS[i].length);
    }
    return best;
  }

  function scanLogin() {
    var nodes = document.querySelectorAll("a, button, div[role='button'], span[role='button'], [data-e2e]");
    var labels = [];
    var seen = {};
    var visibleHref = null;
    var hiddenHref = null;
    var labelEl = null;
    var labelScore = 0;
    for (var i = 0; i < nodes.length; i += 1) {
      var el = nodes[i];
      var href = handoffHref(el);
      var visible = isVisible(el);
      if (href && visible && !visibleHref) visibleHref = href;
      if (href && !visible && !hiddenHref) hiddenHref = href;
      if (!visible) continue;
      var text = controlText(el).slice(0, 80);
      if (text && !seen[text]) {
        seen[text] = true;
        labels.push(text);
      }
      var score = appLoginScore(text);
      if (score > labelScore) {
        labelScore = score;
        labelEl = el;
      }
    }
    return {
      visibleHref: visibleHref,
      hiddenHref: hiddenHref,
      labelEl: labelEl,
      labels: labels.slice(0, 12)
    };
  }

  function activate(el) {
    var target = el.closest ? (el.closest("a, button") || el) : el;
    if (typeof target.click === "function") target.click();
  }

  async function openAppLogin() {
    if (!onTikTok()) return fail("NOT_ON_TIKTOK", "TikTok’s login page didn’t load.");
    var deadline = Date.now() + 12000;
    var lastLabels = [];
    while (Date.now() < deadline) {
      var found = scanLogin();
      lastLabels = found.labels;
      if (found.visibleHref) {
        location.href = found.visibleHref;
        return succeed({ message: "Opened " + found.visibleHref });
      }
      if (found.labelEl) {
        var label = controlText(found.labelEl).slice(0, 80);
        activate(found.labelEl);
        var until = Date.now() + 1800;
        while (Date.now() < until) {
          await delay(200);
          var again = scanLogin();
          var nextHref = again.visibleHref || again.hiddenHref;
          if (nextHref) {
            location.href = nextHref;
            return succeed({ message: "Opened " + nextHref });
          }
        }
        return succeed({ message: "Tapped “" + label + "”." });
      }
      if (found.hiddenHref) {
        location.href = found.hiddenHref;
        return succeed({ message: "Opened " + found.hiddenHref });
      }
      await delay(350);
    }
    var listed = lastLabels.length ? lastLabels.join(" | ") : "(none)";
    return fail(
      "NO_APP_LOGIN",
      "TikTok’s login page didn’t show Log in with TikTok app. Visible labels: " + listed
    );
  }

  function isRemoveRepost(el) {
    var e2e = (el.getAttribute("data-e2e") || "").toLowerCase();
    return e2e.indexOf("remove-repost") !== -1;
  }

  function isPressedRepost(el) {
    return el.getAttribute("aria-pressed") === "true";
  }

  function findPressedRepost() {
    var nodes = document.querySelectorAll("button, a, div[role='button'], [aria-pressed='true']");
    for (var i = 0; i < nodes.length; i += 1) {
      if (!isVisible(nodes[i])) continue;
      if (isPressedRepost(nodes[i])) return nodes[i];
    }
    return null;
  }

  function findRemoveControl() {
    var nodes = document.querySelectorAll("button, a, div[role='button'], [data-e2e]");
    for (var i = 0; i < nodes.length; i += 1) {
      if (!isVisible(nodes[i])) continue;
      if (isRemoveRepost(nodes[i])) return nodes[i];
    }
    return null;
  }

  function findShare() {
    var selectors = [
      '[data-e2e="browse-share"]',
      '[data-e2e="share-icon"]',
      '[data-e2e="video-share-icon"]',
      'button[aria-label="Share"]',
      '[aria-label="Share"]',
      '[aria-label="Share video"]'
    ];
    for (var i = 0; i < selectors.length; i += 1) {
      var el = document.querySelector(selectors[i]);
      if (el && isVisible(el)) return el;
    }
    var nodes = document.querySelectorAll("button, a, div[role='button']");
    for (var j = 0; j < nodes.length; j += 1) {
      if (!isVisible(nodes[j])) continue;
      var text = controlText(nodes[j]).toLowerCase();
      if (text === "share" || text.indexOf("share video") !== -1) return nodes[j];
    }
    return null;
  }

  function removedToast() {
    var nodes = document.querySelectorAll('[role="alert"], [role="status"], [class*="Toast"], [class*="toast"]');
    for (var i = 0; i < nodes.length; i += 1) {
      var text = controlText(nodes[i]).toLowerCase();
      if (text.indexOf("removed") !== -1 || text.indexOf("unreposted") !== -1) return true;
    }
    return false;
  }

  async function unrepostTap() {
    if (!onTikTok()) return fail("NOT_ON_TIKTOK", "The video page isn’t on TikTok.");
    var control = findRemoveControl() || findPressedRepost();
    if (!control) {
      var share = findShare();
      if (share) {
        activate(share);
        await delay(700);
        control = findRemoveControl() || findPressedRepost();
      }
    }
    if (!control) {
      return fail("UI_CHANGED", "Couldn’t find Remove repost.");
    }
    var hook = window.__repostSweepNetHook || {};
    var before = hook.lastDeleteAt || 0;
    var label = controlText(control).slice(0, 80);
    activate(control);
    var deadline = Date.now() + 8000;
    while (Date.now() < deadline) {
      await delay(350);
      var stamp = (window.__repostSweepNetHook && window.__repostSweepNetHook.lastDeleteAt) || 0;
      if (stamp > before) {
        var logged = window.__repostSweepNetHook.lastDelete && window.__repostSweepNetHook.lastDelete.url;
        return succeed({ message: "Tapped “" + label + "”. Delete request: " + String(logged || "").slice(0, 180) });
      }
      if (removedToast()) return succeed({ message: "Tapped “" + label + "”. Removal confirmation appeared." });
    }
    return fail("UI_CHANGED", "Tapped “" + label + "”, but no unrepost request or confirmation appeared.");
  }

  async function thumbnail(payload) {
    var input = payload || {};
    var url = String(input.coverURL || "");
    if (!url) return succeed({ dataURL: "" });
    if (url.indexOf("data:image/") === 0) return succeed({ dataURL: url });
    try {
      var response = await fetch(url, {
        credentials: "omit",
        referrer: "https://www.tiktok.com/",
        referrerPolicy: "origin"
      });
      if (!response.ok) return succeed({ dataURL: "" });
      var blob = await response.blob();
      var bitmap = await createImageBitmap(blob);
      var maxEdge = 240;
      var scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
      var width = Math.max(1, Math.round(bitmap.width * scale));
      var height = Math.max(1, Math.round(bitmap.height * scale));
      var canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;
      var context = canvas.getContext("2d");
      if (!context) return succeed({ dataURL: "" });
      context.drawImage(bitmap, 0, 0, width, height);
      if (bitmap.close) bitmap.close();
      return succeed({ dataURL: canvas.toDataURL("image/jpeg", 0.72) });
    } catch (error) {
      return succeed({ dataURL: "" });
    }
  }

  installNetHook();
  window.__repostSweep = {
    version: 4,
    detect: detect,
    list: list,
    remove: remove,
    confirmRemoved: confirmRemoved,
    focusReposts: focusReposts,
    scrollPage: scrollPage,
    thumbnail: thumbnail,
    openAppLogin: openAppLogin,
    unrepostTap: unrepostTap
  };
})();
