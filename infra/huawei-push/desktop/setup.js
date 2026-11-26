const byId = (id) => document.getElementById(id);
const pair = byId("pair");
const login = byId("login");
const logout = byId("logout");
const startup = byId("startup");
const authorization = byId("authorization");
const message = byId("message");

async function request(route, body) {
  const response = await fetch(
    route,
    body === undefined
      ? undefined
      : {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        },
  );
  const data = await response.json();
  if (!response.ok) throw new Error(data.error);
  return data;
}

function render(state) {
  byId("t3-status").textContent = state.paired ? "已获得只读访问权限" : "等待连接";
  byId("huawei-status").textContent = state.signedIn ? "已登录" : "等待登录";
  pair.textContent = state.paired ? "重新连接" : "连接 T3 Code";
  pair.disabled = false;
  login.hidden = state.signedIn;
  login.disabled = false;
  logout.hidden = !state.signedIn;
  startup.hidden = !(state.paired && state.signedIn && !state.startupActive);
  message.textContent =
    state.paired && state.signedIn && state.startupActive
      ? "设置完成。增强工具会随系统登录启动，可以关闭此页。"
      : "";
}

function showFailure(error) {
  message.textContent = error.message || "操作失败，请重试。";
}

function action(button, route) {
  button.addEventListener("click", async () => {
    button.disabled = true;
    message.textContent = "";
    try {
      render(await request(route, {}));
    } catch (error) {
      showFailure(error);
    } finally {
      button.disabled = false;
    }
  });
}

action(pair, "pair");
action(logout, "logout");
action(startup, "startup");

login.addEventListener("click", async () => {
  login.disabled = true;
  message.textContent = "正在获取授权二维码";
  try {
    const grant = await request("login", {});
    byId("qr").src = grant.qrImage;
    byId("verification").href = grant.verificationUrl;
    authorization.hidden = false;
    message.textContent = "正在等待手机授权";
    const until = Date.now() + grant.expiresIn * 1000;
    let interval = grant.intervalSeconds * 1000;
    while (Date.now() < until) {
      await new Promise((resolve) => setTimeout(resolve, interval));
      const result = await request("login/poll", { flowToken: grant.flowToken });
      if (result.status === "signed_in") {
        render(result);
        return;
      }
      if (result.status === "slow_down") interval += 5000;
      if (result.status === "expired") break;
      if (result.status !== "pending" && result.status !== "slow_down")
        throw new Error("华为授权失败，请重试。");
    }
    message.textContent = "二维码已过期，请重新扫码。";
  } catch (error) {
    showFailure(error);
  } finally {
    authorization.hidden = true;
    login.disabled = false;
  }
});

request("state").then(render).catch(showFailure);
