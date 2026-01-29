import type { MoltbotPluginApi } from "clawdbot/plugin-sdk";
import { emptyPluginConfigSchema } from "clawdbot/plugin-sdk";

import { feishuDock, feishuPlugin } from "./src/channel.js";
import { handleFeishuWebhookRequest } from "./src/monitor.js";
import { setFeishuRuntime } from "./src/runtime.js";

const plugin = {
  id: "feishu",
  name: "Feishu",
  description: "Feishu (Lark / 飞书) channel plugin",
  configSchema: emptyPluginConfigSchema(),
  register(api: MoltbotPluginApi) {
    setFeishuRuntime(api.runtime);
    api.registerChannel({ plugin: feishuPlugin, dock: feishuDock });
    api.registerHttpHandler(handleFeishuWebhookRequest);
  },
};

export default plugin;
