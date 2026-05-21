const http = require("http");
const querystring = require("querystring");
const { URL } = require("url");

const jars = {
  kong: {},
  keycloak: {},
};

function decodeHtml(value) {
  return String(value || "")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function attr(tag, name) {
  const re = new RegExp(`${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, "i");
  const match = tag.match(re);
  return match ? decodeHtml(match[1] || match[2] || match[3] || "") : undefined;
}

function storeCookies(jarName, setCookie) {
  if (!setCookie) {
    return;
  }

  const lines = Array.isArray(setCookie) ? setCookie : [setCookie];
  for (const line of lines) {
    const first = line.split(";", 1)[0];
    const index = first.indexOf("=");
    if (index > 0) {
      jars[jarName][first.slice(0, index)] = first.slice(index + 1);
    }
  }
}

function cookieHeader(jarName) {
  const parts = Object.entries(jars[jarName] || {}).map(([name, value]) => `${name}=${value}`);
  return parts.length ? parts.join("; ") : undefined;
}

function request({ connectHost, port, hostHeader, path, method = "GET", jarName, headers = {}, body }) {
  return new Promise((resolve, reject) => {
    const requestHeaders = {
      Host: hostHeader,
      Connection: "close",
      ...headers,
    };
    const cookies = cookieHeader(jarName);
    if (cookies) {
      requestHeaders.Cookie = cookies;
    }
    if (body !== undefined) {
      requestHeaders["Content-Length"] = Buffer.byteLength(body);
    }

    const req = http.request(
      {
        hostname: connectHost,
        port,
        path,
        method,
        headers: requestHeaders,
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          storeCookies(jarName, res.headers["set-cookie"]);
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks).toString("utf8"),
          });
        });
      },
    );
    req.on("error", reject);
    if (body !== undefined) {
      req.write(body);
    }
    req.end();
  });
}

function keycloakPathFrom(location) {
  const url = new URL(location, "http://localhost:18080");
  return url.pathname + url.search;
}

function kongPathFrom(location) {
  const url = new URL(location, "http://localhost:8000");
  return url.pathname + url.search;
}

function parseInputs(html) {
  const params = {};
  for (const match of html.matchAll(/<input\b[^>]*>/gi)) {
    const tag = match[0];
    const name = attr(tag, "name");
    if (name) {
      params[name] = attr(tag, "value") || "";
    }
  }
  return params;
}

function parseFormAction(html, containing) {
  const forms = [...html.matchAll(/<form\b[^>]*>/gi)].map((match) => match[0]);
  if (!forms.length) {
    throw new Error("No form found in HTML");
  }

  const selected = containing ? forms.find((form) => form.includes(containing)) || forms[0] : forms[0];
  const action = attr(selected, "action");
  if (!action) {
    throw new Error(`Form did not contain action: ${selected.slice(0, 250)}`);
  }
  return action;
}

async function keycloakGet(location) {
  return request({
    connectHost: "keycloak",
    port: 8080,
    hostHeader: "localhost:18080",
    path: keycloakPathFrom(location),
    jarName: "keycloak",
    headers: {
      Referer: "http://localhost:18080/",
    },
  });
}

async function followKeycloak(location, limit = 5) {
  let current = location;
  let response;
  for (let i = 0; i < limit; i++) {
    response = await keycloakGet(current);
    if (![301, 302, 303, 307, 308].includes(response.status)) {
      return response;
    }
    current = response.headers.location;
  }
  return response;
}

async function main() {
  const first = await request({
    connectHost: "kong",
    port: 8000,
    hostHeader: "localhost:8000",
    path: "/saml-demo",
    jarName: "kong",
  });

  if (first.status !== 302 || !first.headers.location) {
    throw new Error(`Expected Kong to start SAML with 302, got ${first.status}: ${first.body.slice(0, 300)}`);
  }
  console.log("start_login=302");

  const loginPage = await followKeycloak(first.headers.location);
  if (loginPage.status !== 200 || !/name=["']username["']/.test(loginPage.body)) {
    throw new Error(`Expected Keycloak login page, got ${loginPage.status}: ${loginPage.body.slice(0, 300)}`);
  }
  console.log("keycloak_login_page=200");

  const loginAction = parseFormAction(loginPage.body);
  const loginParams = parseInputs(loginPage.body);
  loginParams.username = "alice";
  loginParams.password = "alice-password";

  let samlPage = await request({
    connectHost: "keycloak",
    port: 8080,
    hostHeader: "localhost:18080",
    path: keycloakPathFrom(loginAction),
    method: "POST",
    jarName: "keycloak",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Origin: "http://localhost:18080",
      Referer: "http://localhost:18080" + keycloakPathFrom(first.headers.location),
    },
    body: querystring.stringify(loginParams),
  });

  for (let i = 0; [301, 302, 303, 307, 308].includes(samlPage.status) && i < 5; i++) {
    samlPage = await keycloakGet(samlPage.headers.location);
  }

  if (samlPage.status !== 200 || !samlPage.body.includes("SAMLResponse")) {
    throw new Error(`Expected Keycloak SAMLResponse form, got ${samlPage.status}: ${samlPage.body.slice(0, 700)}`);
  }
  console.log("keycloak_saml_response_form=200");

  const samlAction = parseFormAction(samlPage.body, "SAMLResponse");
  const samlParams = parseInputs(samlPage.body);
  if (!samlParams.SAMLResponse || !samlParams.RelayState) {
    throw new Error("SAML form missing SAMLResponse or RelayState");
  }

  const acs = await request({
    connectHost: "kong",
    port: 8000,
    hostHeader: "localhost:8000",
    path: kongPathFrom(samlAction),
    method: "POST",
    jarName: "kong",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Origin: "http://localhost:18080",
      Referer: "http://localhost:18080/",
    },
    body: querystring.stringify(samlParams),
  });

  if (acs.status !== 302 || !acs.headers["set-cookie"] || !acs.headers.location) {
    throw new Error(`Expected Kong ACS 302 with session cookie, got ${acs.status}: ${acs.body.slice(0, 700)}`);
  }
  console.log("kong_acs=302");

  const final = await request({
    connectHost: "kong",
    port: 8000,
    hostHeader: "localhost:8000",
    path: kongPathFrom(acs.headers.location),
    jarName: "kong",
  });

  if (final.status !== 200) {
    throw new Error(`Expected final protected route 200, got ${final.status}: ${final.body.slice(0, 700)}`);
  }

  const payload = JSON.parse(final.body);
  const headers = payload.headers || {};
  if (headers["X-Authenticated-User"] !== "alice" || headers["X-Authenticated-Email"] !== "alice@example.test") {
    throw new Error(`Expected alice identity headers, got ${JSON.stringify(headers).slice(0, 1000)}`);
  }

  console.log("final_saml_demo=200");
  console.log(`authenticated_user=${headers["X-Authenticated-User"]}`);
  console.log(`authenticated_email=${headers["X-Authenticated-Email"]}`);
}

main().catch((err) => {
  console.error(err.stack || err.message || err);
  process.exit(1);
});
