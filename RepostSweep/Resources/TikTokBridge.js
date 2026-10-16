// Repost Sweep page bridge.
// Runs only inside the signed-in TikTok WKWebView. It never reads password
// fields and never returns cookies to the app. Listing uses the same repost
// endpoint the website calls. Removal uses TikTok's unrepost calls only
// (/tiktok/v1/upvote/delete/ and, if that path is gone, /api/repost/item/delete/).
// It does not call video-delete endpoints.
(function () {
  "use strict";

  var LIST_PATH = "/api/repost/item_list/";
  var UNREPOST_PATHS = ["/tiktok/v1/upvote/delete/", "/api/repost/item/delete/"];

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

  function avatarOf(user) {
    if (!user) return "";
    if (typeof user.avatarThumb === "string") return user.avatarThumb;
    if (user.avatarThumb && user.avatarThumb.url_list && user.avatarThumb.url_list[0]) {
      return String(user.avatarThumb.url_list[0]);
    }
    if (typeof user.avatarUri === "string") return user.avatarUri;
    return "";
  }

  function mapUser(user) {
    if (!user || typeof user !== "object") return null;
    var uniqueId = user.uniqueId || user.unique_id || "";
    if (!uniqueId) return null;
    return {
      uniqueId: String(uniqueId),
      nickname: String(user.nickname || user.nickName || ""),
      secUid: String(user.secUid || user.sec_uid || ""),
      avatarURL: avatarOf(user)
    };
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
      return { uniqueId: decoded, nickname: "", secUid: "", avatarURL: "" };
    }
    return null;
  }

  function profileUser() {
    var hydration = readHydration();
    var scope = hydration && hydration.__DEFAULT_SCOPE__;
    var detail = scope && scope["webapp.user-detail"];
    var user = detail && detail.userInfo && detail.userInfo.user;
    return mapUser(user);
  }

  function mergeAccount() {
    var session = sessionUser();
    var profile = profileUser();
    if (!session && profile) {
      var path = location.pathname || "";
      if (profile.uniqueId && path.indexOf("/@" + profile.uniqueId) !== -1) return profile;
      return null;
    }
    if (session && profile && session.uniqueId === profile.uniqueId && !session.secUid && profile.secUid) {
      session.secUid = profile.secUid;
      if (!session.nickname) session.nickname = profile.nickname;
      if (!session.avatarURL) session.avatarURL = profile.avatarURL;
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
    if (data && data.data && typeof data.data === "object") data = data.data;
    if (data && data.userInfo && data.userInfo.user) data = data.userInfo.user;
    else if (data && data.user && typeof data.user === "object") data = data.user;
    if (!data || typeof data !== "object") return null;
    var uniqueId = String(data.uniqueId || data.unique_id || data.username || "");
    if (!uniqueId || /^\d+$/.test(uniqueId)) return null;
    var avatar = data.avatar_url || data.avatarUrl || "";
    if (!avatar) avatar = avatarOf(data);
    return {
      uniqueId: uniqueId,
      nickname: String(data.screen_name || data.nickname || data.nickName || ""),
      secUid: String(data.sec_user_id || data.secUid || data.sec_uid || ""),
      avatarURL: String(avatar || "")
    };
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

  function fillAccount(base, extra) {
    if (!extra) return base;
    if (!base) return extra;
    if (!base.uniqueId) base.uniqueId = extra.uniqueId;
    if (!base.nickname) base.nickname = extra.nickname;
    if (!base.secUid) base.secUid = extra.secUid;
    if (!base.avatarURL) base.avatarURL = extra.avatarURL;
    return base;
  }

  async function detect() {
    if (!onTikTok()) return fail("NOT_ON_TIKTOK", "Sign-in happens on TikTok’s website.");
    var account = mergeAccount();
    if (!account || !account.uniqueId || !account.secUid || !account.avatarURL) {
      account = fillAccount(account, await fetchSelf());
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
        account = { uniqueId: "", nickname: "", secUid: supplied, avatarURL: "" };
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

  async function postUnrepost(path, itemId) {
    var params = new URLSearchParams();
    params.set("aid", "1988");
    params.set("app_name", "tiktok_web");
    var token = cookieValue("msToken");
    if (token) params.set("msToken", token);
    var body = new URLSearchParams();
    body.set("item_id", itemId);
    body.set("aweme_id", itemId);
    var response = await fetch(path + "?" + params.toString(), {
      method: "POST",
      credentials: "include",
      headers: csrfHeaders(),
      body: body.toString()
    });
    var text = await response.text();
    return { response: response, text: text };
  }

  async function remove(payload) {
    var input = payload || {};
    var itemId = String(input.itemId || "");
    if (!/^\d{6,}$/.test(itemId)) return fail("PARSE", "That repost id doesn’t look usable.");
    if (!onTikTok()) return fail("NOT_ON_TIKTOK", "Open TikTok and sign in.");

    var last = "no attempt";
    for (var i = 0; i < UNREPOST_PATHS.length; i += 1) {
      var outcome;
      try {
        outcome = await postUnrepost(UNREPOST_PATHS[i], itemId);
      } catch (error) {
        return fail("NETWORK", "The unrepost request didn’t finish.");
      }
      var text = outcome.text || "";
      var httpStatus = outcome.response.status;
      if (httpStatus === 404 || httpStatus === 405) {
        last = "http " + httpStatus;
        continue;
      }
      if (!text) {
        if (httpStatus >= 200 && httpStatus < 300) return succeed({});
        last = "empty http " + httpStatus;
        continue;
      }
      var json;
      try {
        json = JSON.parse(text);
      } catch (error) {
        return fail("ENDPOINT_CHANGED", "Unrepost response was not JSON (http " + httpStatus + ").");
      }
      var status = statusOf(json);
      var kind = classify(httpStatus, status === null ? -1 : status);
      if (kind === "OK") return succeed({});
      if (kind === "RATE_LIMITED") return fail("RATE_LIMITED", "status " + status);
      if (kind === "NOT_LOGGED_IN") return fail("NOT_LOGGED_IN", "status " + status);
      last = "status " + status + " http " + httpStatus;
    }
    return fail("ENDPOINT_CHANGED", "Unrepost " + last + ".");
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

  window.__repostSweep = {
    version: 1,
    detect: detect,
    list: list,
    remove: remove,
    focusReposts: focusReposts,
    scrollPage: scrollPage,
    thumbnail: thumbnail
  };
})();
